import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:frontend_desktop/core/presentation/widgets/app_modal_shell.dart';
import 'package:frontend_desktop/core/theme/app_theme.dart';
import 'package:frontend_desktop/core/utils/snack_bar_service.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

/// Convierte la preferencia de papel (`'a4'` / `'letter'`) al [PdfPageFormat].
PdfPageFormat pdfPageFormatFromPaperSize(String? paperSize) {
  final normalized = (paperSize ?? '').trim().toLowerCase();
  return normalized == 'letter' ? PdfPageFormat.letter : PdfPageFormat.a4;
}

/// Etiqueta legible del tamaño de papel (`'Carta'` o `'A4'`).
String pdfPaperSizeLabel(String? paperSize) {
  final normalized = (paperSize ?? '').trim().toLowerCase();
  return normalized == 'letter' ? 'Carta' : 'A4';
}

/// Limpia caracteres inválidos en nombres de archivo de Windows y garantiza extensión `.pdf`.
String sanitizePdfFileName(String rawName) {
  var cleaned = rawName.trim().replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
  cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (cleaned.isEmpty) {
    cleaned = 'Documento.pdf';
  }
  if (!cleaned.toLowerCase().endsWith('.pdf')) {
    cleaned = '$cleaned.pdf';
  }
  return cleaned;
}

/// Visor PDF unificado para Caja4U (A4, Carta y Etiquetas).
///
/// Características:
/// - Zoom fluido con `Ctrl + Rueda del mouse` anclado al cursor (y pinch en trackpad).
/// - Controles de zoom `-`, `100%`, `+`, "Ajustar al ancho" y atajos `Ctrl + +` / `Ctrl + -` / `Ctrl + 0`.
/// - Arrastrar con el mouse (pan) cuando el zoom supera 100%, más doble clic para alternar zoom.
/// - Barra superior limpia e integrada al sistema de diseño (Imprimir `Ctrl+P`, Guardar `Ctrl+S`, Compartir, Pág. X / Y).
/// - Rasterizado a 200 DPI por defecto para mantener máxima nitidez en textos y códigos de barras al hacer zoom.
class AppPdfPreview extends StatefulWidget {
  const AppPdfPreview({
    super.key,
    required this.build,
    this.initialPageFormat,
    this.pdfFileName = 'Documento.pdf',
    this.dpi = 200.0,
    this.showPrintAction = true,
    this.showSaveAction = true,
    this.showShareAction = true,
    this.compactToolbar = false,
    this.shouldRepaint = false,
    this.autofocus = true,
    this.loadingWidget,
    this.onPrinted,
    @visibleForTesting this.testPages,
    @visibleForTesting this.onPrintOverride,
    @visibleForTesting this.onSaveOverride,
    @visibleForTesting this.onShareOverride,
  });

  final LayoutCallback build;
  final PdfPageFormat? initialPageFormat;
  final String pdfFileName;
  final double dpi;
  final bool showPrintAction;
  final bool showSaveAction;
  final bool showShareAction;
  final bool compactToolbar;
  final bool shouldRepaint;
  final bool autofocus;
  final Widget? loadingWidget;
  final VoidCallback? onPrinted;

  @visibleForTesting
  final List<PdfPreviewPageData>? testPages;

  @visibleForTesting
  final Future<void> Function(
    Uint8List bytes,
    PdfPageFormat format,
    String jobName,
  )? onPrintOverride;

  @visibleForTesting
  final Future<void> Function(Uint8List bytes, String fileName)? onSaveOverride;

  @visibleForTesting
  final Future<void> Function(Uint8List bytes, String fileName)?
      onShareOverride;

  @override
  State<AppPdfPreview> createState() => _AppPdfPreviewState();
}

class _AppPdfPreviewState extends State<AppPdfPreview> {
  static const double _minZoom = 0.50;
  static const double _maxZoom = 3.00;
  static const double _defaultZoom = 1.00;
  static const double _zoomButtonStep = 0.25;
  static const double _doubleTapZoom = 1.75;
  static const double _horizontalPadding = 48.0;
  static const double _verticalPadding = 20.0;
  static const double _pageSpacing = 16.0;
  static const double _maxBasePageWidth = 860.0;

  final ScrollController _verticalScrollController = ScrollController();
  final ScrollController _horizontalScrollController = ScrollController();
  final FocusNode _focusNode = FocusNode(debugLabel: 'AppPdfPreviewFocus');
  final GlobalKey _viewportKey = GlobalKey();

  double _zoom = _defaultZoom;
  int _pageCount = 0;
  int _currentPage = 1;
  bool _isPanning = false;
  bool _isBusyAction = false;

  Uint8List? _cachedPdfBytes;
  List<PdfPreviewPageData> _latestPages = const [];
  List<double> _lastPageHeights = const [];

  double _lastViewportWidth = 800.0;
  double _lastViewportHeight = 600.0;
  double _lastBasePageWidth = 752.0;

  double? _pendingScrollX;
  double? _pendingScrollY;
  bool _scrollSyncScheduled = false;
  Offset? _doubleTapLocalPosition;

  @override
  void initState() {
    super.initState();
    _verticalScrollController.addListener(_onVerticalScrollChanged);
    if (widget.testPages != null) {
      _latestPages = widget.testPages!;
      _pageCount = widget.testPages!.length;
    }
  }

  @override
  void didUpdateWidget(covariant AppPdfPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.build != widget.build ||
        widget.shouldRepaint ||
        oldWidget.initialPageFormat != widget.initialPageFormat) {
      _cachedPdfBytes = null;
    }
    if (widget.testPages != null && widget.testPages != oldWidget.testPages) {
      _latestPages = widget.testPages!;
      _pageCount = widget.testPages!.length;
      if (_currentPage > _pageCount && _pageCount > 0) {
        _currentPage = _pageCount;
      }
    }
  }

  @override
  void dispose() {
    _verticalScrollController.removeListener(_onVerticalScrollChanged);
    _verticalScrollController.dispose();
    _horizontalScrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool get _isZoomModifierPressed {
    final hw = HardwareKeyboard.instance;
    return hw.isControlPressed || hw.isMetaPressed;
  }

  PdfPageFormat _computeActualPageFormat() {
    final fallback = widget.initialPageFormat ?? PdfPageFormat.a4;
    if (_latestPages.isNotEmpty) {
      final first = _latestPages.first;
      if (first.width > 0 && first.height > 0 && widget.dpi > 0) {
        return PdfPageFormat(
          first.width * PdfPageFormat.inch / widget.dpi,
          first.height * PdfPageFormat.inch / widget.dpi,
          marginAll: 5 * PdfPageFormat.mm,
        );
      }
    }
    return fallback;
  }

  Future<Uint8List> _wrappedBuild(PdfPageFormat format) async {
    final bytes = await widget.build(format);
    _cachedPdfBytes = bytes;
    return bytes;
  }

  Future<Uint8List> _ensurePdfBytes() async {
    final existing = _cachedPdfBytes;
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final bytes = await widget.build(_computeActualPageFormat());
    _cachedPdfBytes = bytes;
    return bytes;
  }

  double _computeBasePageWidth(double viewportWidth) {
    return math
        .min(viewportWidth - _horizontalPadding, _maxBasePageWidth)
        .clamp(160.0, _maxBasePageWidth)
        .toDouble();
  }

  double _pageHeightFor(PdfPreviewPageData page, double displayWidth) {
    final ratio = (page.width > 0 && page.height > 0)
        ? (page.height / page.width)
        : (297.0 / 210.0);
    return displayWidth * ratio;
  }

  double _contentWidthFor(double viewportWidth, double baseWidth, double zoom) {
    return math.max(viewportWidth, (baseWidth * zoom) + _horizontalPadding);
  }

  void _onVerticalScrollChanged() {
    if (_latestPages.isEmpty || _lastPageHeights.isEmpty) return;
    if (!_verticalScrollController.hasClients) return;

    final viewportMid =
        _verticalScrollController.offset + (_lastViewportHeight * 0.35);
    var cursorY = _verticalPadding;
    var detectedPage = 1;

    for (var i = 0; i < _lastPageHeights.length; i++) {
      final pageBottom = cursorY + _lastPageHeights[i];
      if (viewportMid <= pageBottom + (_pageSpacing * 0.5) ||
          i == _lastPageHeights.length - 1) {
        detectedPage = i + 1;
        break;
      }
      cursorY = pageBottom + _pageSpacing;
    }

    if (detectedPage != _currentPage && mounted) {
      setState(() => _currentPage = detectedPage);
    }
  }

  void _goToPage(int targetPage) {
    if (_pageCount <= 0 || _lastPageHeights.isEmpty) return;
    final clampedPage = targetPage.clamp(1, _pageCount);
    if (!_verticalScrollController.hasClients) return;

    var targetOffset = 0.0;
    if (clampedPage > 1) {
      targetOffset = _verticalPadding;
      for (var i = 0; i < clampedPage - 1; i++) {
        final h = i < _lastPageHeights.length ? _lastPageHeights[i] : 0.0;
        targetOffset += h + _pageSpacing;
      }
      targetOffset = (targetOffset - 12.0).clamp(
        _verticalScrollController.position.minScrollExtent,
        _verticalScrollController.position.maxScrollExtent,
      );
    }

    _verticalScrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
    if (clampedPage != _currentPage) {
      setState(() => _currentPage = clampedPage);
    }
  }

  void _scheduleScrollJump(double targetX, double targetY) {
    _pendingScrollX = targetX;
    _pendingScrollY = targetY;
    if (_scrollSyncScheduled) return;
    _scrollSyncScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollSyncScheduled = false;
      if (!mounted) return;

      final x = _pendingScrollX;
      final y = _pendingScrollY;
      _pendingScrollX = null;
      _pendingScrollY = null;

      if (x != null && _horizontalScrollController.hasClients) {
        final pos = _horizontalScrollController.position;
        final clampedX = x.clamp(pos.minScrollExtent, pos.maxScrollExtent);
        if ((clampedX - pos.pixels).abs() > 0.5) {
          _horizontalScrollController.jumpTo(clampedX);
        }
      }
      if (y != null && _verticalScrollController.hasClients) {
        final pos = _verticalScrollController.position;
        final clampedY = y.clamp(pos.minScrollExtent, pos.maxScrollExtent);
        if ((clampedY - pos.pixels).abs() > 0.5) {
          _verticalScrollController.jumpTo(clampedY);
        }
      }
    });
  }

  /// Aplica un nuevo nivel de zoom manteniendo anclado el punto [focalInViewport].
  void _applyZoom(double targetZoom, {Offset? focalInViewport}) {
    final newZoom = targetZoom.clamp(_minZoom, _maxZoom).toDouble();
    final oldZoom = _zoom;
    if ((newZoom - oldZoom).abs() < 0.0005) return;

    final focal = focalInViewport ??
        Offset(_lastViewportWidth / 2.0, _lastViewportHeight / 2.0);
    final currentH = _pendingScrollX ??
        (_horizontalScrollController.hasClients
            ? _horizontalScrollController.offset
            : 0.0);
    final currentV = _pendingScrollY ??
        (_verticalScrollController.hasClients
            ? _verticalScrollController.offset
            : 0.0);

    final baseWidth = _lastBasePageWidth;
    final oldDisplayWidth = baseWidth * oldZoom;
    final newDisplayWidth = baseWidth * newZoom;

    final oldContentWidth =
        _contentWidthFor(_lastViewportWidth, baseWidth, oldZoom);
    final newContentWidth =
        _contentWidthFor(_lastViewportWidth, baseWidth, newZoom);

    final oldPageLeft = (oldContentWidth - oldDisplayWidth) / 2.0;
    final newPageLeft = (newContentWidth - newDisplayWidth) / 2.0;

    final oldContentX = currentH + focal.dx;
    final relX = oldDisplayWidth > 0
        ? (oldContentX - oldPageLeft) / oldDisplayWidth
        : 0.5;
    final newContentX = newPageLeft + (relX * newDisplayWidth);
    final targetScrollX = math.max(0.0, newContentX - focal.dx);

    final oldContentY = currentV + focal.dy;
    final newContentY = _mapVerticalContentY(
      oldContentY: oldContentY,
      oldDisplayWidth: oldDisplayWidth,
      newDisplayWidth: newDisplayWidth,
      fallbackScaleRatio: newZoom / oldZoom,
    );
    final targetScrollY = math.max(0.0, newContentY - focal.dy);

    setState(() => _zoom = newZoom);
    _scheduleScrollJump(targetScrollX, targetScrollY);
  }

  double _mapVerticalContentY({
    required double oldContentY,
    required double oldDisplayWidth,
    required double newDisplayWidth,
    required double fallbackScaleRatio,
  }) {
    if (_latestPages.isEmpty) {
      return oldContentY * fallbackScaleRatio;
    }

    final yRelativeOld = oldContentY - _verticalPadding;
    var oldTop = 0.0;
    var newTop = 0.0;

    for (var i = 0; i < _latestPages.length; i++) {
      final page = _latestPages[i];
      final oldH = _pageHeightFor(page, oldDisplayWidth);
      final newH = _pageHeightFor(page, newDisplayWidth);
      final oldBottom = oldTop + oldH;

      if (yRelativeOld <= oldBottom || i == _latestPages.length - 1) {
        final t = oldH > 0 ? (yRelativeOld - oldTop) / oldH : 0.0;
        return _verticalPadding + newTop + (t * newH);
      }

      oldTop = oldBottom + _pageSpacing;
      newTop += newH + _pageSpacing;
    }

    return oldContentY * fallbackScaleRatio;
  }

  void _zoomIn() {
    final next = ((_zoom / _zoomButtonStep).floor() + 1) * _zoomButtonStep;
    _applyZoom(next);
  }

  void _zoomOut() {
    final next = ((_zoom / _zoomButtonStep).ceil() - 1) * _zoomButtonStep;
    _applyZoom(next);
  }

  void _resetZoom() => _applyZoom(_defaultZoom);

  void _fitToWidth() {
    if (_lastBasePageWidth <= 0) {
      _resetZoom();
      return;
    }
    final availableWidth =
        math.max(160.0, _lastViewportWidth - _horizontalPadding);
    final fitZoom = (availableWidth / _lastBasePageWidth)
        .clamp(_minZoom, _maxZoom)
        .toDouble();
    _applyZoom(fitZoom);
  }

  Offset _globalToViewportLocal(Offset globalPosition) {
    final renderBox =
        _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null && renderBox.hasSize) {
      return renderBox.globalToLocal(globalPosition);
    }
    return Offset(_lastViewportWidth / 2.0, _lastViewportHeight / 2.0);
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent && _isZoomModifierPressed) {
      GestureBinding.instance.pointerSignalResolver.register(
        event,
        _resolveCtrlWheelZoom,
      );
      return;
    }

    if (event is PointerScaleEvent) {
      GestureBinding.instance.pointerSignalResolver.register(
        event,
        _resolveTrackpadScale,
      );
    }
  }

  void _resolveCtrlWheelZoom(PointerEvent event) {
    if (!mounted || event is! PointerScrollEvent) return;
    final deltaY = event.scrollDelta.dy;
    if (deltaY == 0.0) return;

    final factor = math.pow(1.0015, -deltaY).toDouble().clamp(0.80, 1.25);
    final focal = _globalToViewportLocal(event.position);
    _applyZoom(_zoom * factor, focalInViewport: focal);
    event.respond(allowPlatformDefault: false);
  }

  void _resolveTrackpadScale(PointerEvent event) {
    if (!mounted || event is! PointerScaleEvent) return;
    if (event.scale == 1.0) return;

    final focal = _globalToViewportLocal(event.position);
    _applyZoom(_zoom * event.scale, focalInViewport: focal);
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (!_focusNode.hasFocus) {
      _focusNode.requestFocus();
    }
    if (event.kind == PointerDeviceKind.mouse &&
        event.buttons == kPrimaryMouseButton &&
        _zoom > 1.001) {
      if (!_isPanning) {
        setState(() => _isPanning = true);
      }
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (!_isPanning) return;
    if (event.kind != PointerDeviceKind.mouse ||
        (event.buttons & kPrimaryMouseButton) == 0) {
      setState(() => _isPanning = false);
      return;
    }

    if (_horizontalScrollController.hasClients && event.delta.dx != 0.0) {
      final pos = _horizontalScrollController.position;
      final nextX = (pos.pixels - event.delta.dx)
          .clamp(pos.minScrollExtent, pos.maxScrollExtent);
      _horizontalScrollController.jumpTo(nextX);
    }
    if (_verticalScrollController.hasClients && event.delta.dy != 0.0) {
      final pos = _verticalScrollController.position;
      final nextY = (pos.pixels - event.delta.dy)
          .clamp(pos.minScrollExtent, pos.maxScrollExtent);
      _verticalScrollController.jumpTo(nextY);
    }
  }

  void _handlePointerUpOrCancel(PointerEvent _) {
    if (_isPanning && mounted) {
      setState(() => _isPanning = false);
    }
  }

  void _handleDoubleTap() {
    final focal = _doubleTapLocalPosition ??
        Offset(_lastViewportWidth / 2.0, _lastViewportHeight / 2.0);
    final target =
        (_zoom - _defaultZoom).abs() < 0.05 ? _doubleTapZoom : _defaultZoom;
    _applyZoom(target, focalInViewport: focal);
  }

  Future<void> _handlePrint() async {
    if (_isBusyAction) return;
    setState(() => _isBusyAction = true);
    try {
      final bytes = await _ensurePdfBytes();
      final format = _computeActualPageFormat();
      final jobName = sanitizePdfFileName(widget.pdfFileName);

      if (widget.onPrintOverride != null) {
        await widget.onPrintOverride!(bytes, format, jobName);
      } else {
        final printed = await Printing.layoutPdf(
          onLayout: (_) async => bytes,
          name: jobName,
          format: format,
        );
        if (printed) {
          widget.onPrinted?.call();
        }
      }
    } catch (e) {
      if (mounted) {
        SnackBarService.error(context, 'Error al imprimir PDF: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isBusyAction = false);
      }
    }
  }

  Future<void> _handleSavePdf() async {
    if (_isBusyAction) return;
    setState(() => _isBusyAction = true);
    try {
      final bytes = await _ensurePdfBytes();
      final fileName = sanitizePdfFileName(widget.pdfFileName);

      if (widget.onSaveOverride != null) {
        await widget.onSaveOverride!(bytes, fileName);
        return;
      }

      if (!kIsWeb &&
          (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        final outputPath = await FilePicker.platform.saveFile(
          dialogTitle: 'Guardar PDF',
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: const ['pdf'],
        );
        if (outputPath == null || outputPath.trim().isEmpty) {
          return;
        }
        final finalPath = outputPath.toLowerCase().endsWith('.pdf')
            ? outputPath
            : '$outputPath.pdf';
        await File(finalPath).writeAsBytes(bytes);
        if (mounted) {
          SnackBarService.success(context, 'PDF guardado correctamente');
        }
      } else {
        await Printing.sharePdf(bytes: bytes, filename: fileName);
      }
    } catch (e) {
      if (mounted) {
        SnackBarService.error(context, 'Error al guardar PDF: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isBusyAction = false);
      }
    }
  }

  Future<void> _handleSharePdf() async {
    if (_isBusyAction) return;
    setState(() => _isBusyAction = true);
    try {
      final bytes = await _ensurePdfBytes();
      final fileName = sanitizePdfFileName(widget.pdfFileName);

      if (widget.onShareOverride != null) {
        await widget.onShareOverride!(bytes, fileName);
      } else {
        await Printing.sharePdf(bytes: bytes, filename: fileName);
      }
    } catch (e) {
      if (mounted) {
        SnackBarService.error(context, 'Error al compartir PDF: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isBusyAction = false);
      }
    }
  }

  Map<ShortcutActivator, VoidCallback> _buildShortcuts() {
    return <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.equal, control: true): _zoomIn,
      const SingleActivator(LogicalKeyboardKey.equal,
          control: true, shift: true): _zoomIn,
      const SingleActivator(LogicalKeyboardKey.add, control: true): _zoomIn,
      const SingleActivator(LogicalKeyboardKey.numpadAdd, control: true):
          _zoomIn,
      const SingleActivator(LogicalKeyboardKey.equal, meta: true): _zoomIn,
      const SingleActivator(LogicalKeyboardKey.equal, meta: true, shift: true):
          _zoomIn,
      const SingleActivator(LogicalKeyboardKey.add, meta: true): _zoomIn,
      const SingleActivator(LogicalKeyboardKey.numpadAdd, meta: true): _zoomIn,
      const SingleActivator(LogicalKeyboardKey.minus, control: true): _zoomOut,
      const SingleActivator(LogicalKeyboardKey.numpadSubtract, control: true):
          _zoomOut,
      const SingleActivator(LogicalKeyboardKey.minus, meta: true): _zoomOut,
      const SingleActivator(LogicalKeyboardKey.numpadSubtract, meta: true):
          _zoomOut,
      const SingleActivator(LogicalKeyboardKey.digit0, control: true):
          _resetZoom,
      const SingleActivator(LogicalKeyboardKey.numpad0, control: true):
          _resetZoom,
      const SingleActivator(LogicalKeyboardKey.digit0, meta: true): _resetZoom,
      const SingleActivator(LogicalKeyboardKey.numpad0, meta: true):
          _resetZoom,
      if (widget.showPrintAction) ...{
        const SingleActivator(LogicalKeyboardKey.keyP, control: true):
            _handlePrint,
        const SingleActivator(LogicalKeyboardKey.keyP, meta: true):
            _handlePrint,
      },
      if (widget.showSaveAction) ...{
        const SingleActivator(LogicalKeyboardKey.keyS, control: true):
            _handleSavePdf,
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true):
            _handleSavePdf,
      },
    };
  }

  @override
  Widget build(BuildContext context) {
    final previewContent = widget.testPages != null
        ? Container(
            color: const Color(0xFFCBD5E1),
            width: double.infinity,
            height: double.infinity,
            child: _buildZoomablePages(context, widget.testPages!),
          )
        : PdfPreview.builder(
            build: _wrappedBuild,
            initialPageFormat: widget.initialPageFormat ?? PdfPageFormat.a4,
            dpi: widget.dpi,
            useActions: false,
            allowPrinting: false,
            allowSharing: false,
            canChangeOrientation: false,
            canChangePageFormat: false,
            canDebug: false,
            shouldRepaint: widget.shouldRepaint,
            loadingWidget: widget.loadingWidget,
            scrollViewDecoration: const BoxDecoration(
              color: Color(0xFFCBD5E1),
            ),
            pagesBuilder: _buildZoomablePages,
          );

    return CallbackShortcuts(
      bindings: _buildShortcuts(),
      child: Focus(
        focusNode: _focusNode,
        autofocus: widget.autofocus,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildToolbar(),
            Expanded(child: previewContent),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    final hasAnyRightAction =
        widget.showPrintAction || widget.showSaveAction || widget.showShareAction;
    final zoomPct = (_zoom * 100).round();

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surfaceMuted,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: widget.compactToolbar ? 10 : 14,
        vertical: widget.compactToolbar ? 6 : 8,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final showHint = width >= 760 && !widget.compactToolbar;
          final showSaveLabel = width >= 660;
          final showPrintLabel = width >= 480;

          final leftControls = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ToolbarIconButton(
                key: const ValueKey('pdf_zoom_out_btn'),
                icon: Icons.remove_rounded,
                tooltip: 'Alejar (Ctrl + -)',
                onPressed: _zoom > _minZoom + 0.001 ? _zoomOut : null,
              ),
              const SizedBox(width: 4),
              Tooltip(
                message: 'Restablecer zoom al 100% (Ctrl + 0)',
                child: InkWell(
                  key: const ValueKey('pdf_zoom_reset_btn'),
                  onTap: _resetZoom,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(
                      '$zoomPct%',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              _ToolbarIconButton(
                key: const ValueKey('pdf_zoom_in_btn'),
                icon: Icons.add_rounded,
                tooltip: 'Acercar (Ctrl + +)',
                onPressed: _zoom < _maxZoom - 0.001 ? _zoomIn : null,
              ),
              const SizedBox(width: 6),
              _ToolbarIconButton(
                key: const ValueKey('pdf_zoom_fit_btn'),
                icon: Icons.fit_screen_rounded,
                tooltip: 'Ajustar al ancho',
                onPressed: _fitToWidth,
              ),
              if (showHint) ...[
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.mouse_rounded,
                        size: 13,
                        color: AppColors.textMuted,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Ctrl + rueda',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          );

          final pageControls = _pageCount > 0
              ? Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ToolbarMiniIconButton(
                        key: const ValueKey('pdf_prev_page_btn'),
                        icon: Icons.chevron_left_rounded,
                        tooltip: 'Página anterior',
                        onPressed: _pageCount > 1 && _currentPage > 1
                            ? () => _goToPage(_currentPage - 1)
                            : null,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text(
                          'Pág. $_currentPage / $_pageCount',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      _ToolbarMiniIconButton(
                        key: const ValueKey('pdf_next_page_btn'),
                        icon: Icons.chevron_right_rounded,
                        tooltip: 'Página siguiente',
                        onPressed: _pageCount > 1 && _currentPage < _pageCount
                            ? () => _goToPage(_currentPage + 1)
                            : null,
                      ),
                    ],
                  ),
                )
              : null;

          final rightControls = hasAnyRightAction
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.showSaveAction) ...[
                      if (showSaveLabel)
                        OutlinedButton.icon(
                          key: const ValueKey('pdf_save_btn'),
                          onPressed: _isBusyAction ? null : _handleSavePdf,
                          icon: const Icon(Icons.download_rounded, size: 17),
                          label: const Text('Guardar'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textPrimary,
                            backgroundColor: Colors.white,
                            side: const BorderSide(color: AppColors.borderStrong),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 11,
                              vertical: 8,
                            ),
                            visualDensity: VisualDensity.compact,
                            textStyle: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )
                      else
                        _ToolbarIconButton(
                          key: const ValueKey('pdf_save_btn'),
                          icon: Icons.download_rounded,
                          tooltip: 'Guardar PDF (Ctrl + S)',
                          onPressed: _isBusyAction ? null : _handleSavePdf,
                        ),
                      const SizedBox(width: 6),
                    ],
                    if (widget.showShareAction) ...[
                      _ToolbarIconButton(
                        key: const ValueKey('pdf_share_btn'),
                        icon: Icons.share_rounded,
                        tooltip: 'Compartir PDF',
                        onPressed: _isBusyAction ? null : _handleSharePdf,
                      ),
                      const SizedBox(width: 6),
                    ],
                    if (widget.showPrintAction)
                      showPrintLabel
                          ? FilledButton.icon(
                              key: const ValueKey('pdf_print_btn'),
                              onPressed: _isBusyAction ? null : _handlePrint,
                              icon: const Icon(Icons.print_rounded, size: 17),
                              label: const Text('Imprimir'),
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                visualDensity: VisualDensity.compact,
                                textStyle: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            )
                          : Tooltip(
                              message: 'Imprimir (Ctrl + P)',
                              child: IconButton.filled(
                                key: const ValueKey('pdf_print_btn'),
                                onPressed: _isBusyAction ? null : _handlePrint,
                                icon: const Icon(Icons.print_rounded, size: 18),
                                style: IconButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.white,
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                            ),
                  ],
                )
              : null;

          final toolbarRow = Row(
            children: [
              leftControls,
              const Spacer(),
              if (pageControls != null) pageControls,
              if (rightControls != null) ...[
                if (pageControls != null) const SizedBox(width: 10),
                rightControls,
              ],
            ],
          );

          final minNeededWidth = hasAnyRightAction ? 430.0 : 280.0;
          if (width < minNeededWidth) {
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: minNeededWidth),
                child: IntrinsicWidth(child: toolbarRow),
              ),
            );
          }

          return toolbarRow;
        },
      ),
    );
  }

  Widget _buildZoomablePages(
    BuildContext context,
    List<PdfPreviewPageData> pages,
  ) {
    _latestPages = pages;
    if (pages.length != _pageCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _pageCount = pages.length;
          if (_pageCount == 0) {
            _currentPage = 1;
          } else if (_currentPage > _pageCount) {
            _currentPage = _pageCount;
          }
        });
      });
    }

    return SizedBox.expand(
      child: LayoutBuilder(
        key: _viewportKey,
        builder: (context, constraints) {
          final viewportWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : 800.0;
          final viewportHeight = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : 600.0;

          final baseWidth = _computeBasePageWidth(viewportWidth);
          _lastViewportWidth = viewportWidth;
          _lastViewportHeight = viewportHeight;
          _lastBasePageWidth = baseWidth;

          final displayPageWidth = baseWidth * _zoom;
          final contentWidth =
              _contentWidthFor(viewportWidth, baseWidth, _zoom);
          final needsHorizontalScroll = contentWidth > viewportWidth + 1.0;

          final computedHeights = <double>[
            for (final page in pages) _pageHeightFor(page, displayPageWidth),
          ];
          _lastPageHeights = computedHeights;

          final cursor = _isPanning
              ? SystemMouseCursors.grabbing
              : (_zoom > 1.001
                  ? SystemMouseCursors.grab
                  : SystemMouseCursors.basic);

          return Scrollbar(
            controller: _verticalScrollController,
            thumbVisibility: true,
            notificationPredicate: (n) => n.metrics.axis == Axis.vertical,
            child: Scrollbar(
              controller: _horizontalScrollController,
              thumbVisibility: needsHorizontalScroll,
              notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
              child: SingleChildScrollView(
                controller: _verticalScrollController,
                scrollDirection: Axis.vertical,
                physics: const ClampingScrollPhysics(),
                child: SingleChildScrollView(
                  controller: _horizontalScrollController,
                  scrollDirection: Axis.horizontal,
                  physics: const ClampingScrollPhysics(),
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerSignal: _handlePointerSignal,
                    onPointerDown: _handlePointerDown,
                    onPointerMove: _handlePointerMove,
                    onPointerUp: _handlePointerUpOrCancel,
                    onPointerCancel: _handlePointerUpOrCancel,
                    child: MouseRegion(
                      cursor: cursor,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onDoubleTapDown: (details) {
                          _doubleTapLocalPosition =
                              _globalToViewportLocal(details.globalPosition);
                        },
                        onDoubleTap: _handleDoubleTap,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minWidth: contentWidth,
                            minHeight: viewportHeight,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: _verticalPadding,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (var i = 0; i < pages.length; i++) ...[
                                  if (i > 0)
                                    const SizedBox(height: _pageSpacing),
                                  Container(
                                    width: displayPageWidth,
                                    height: computedHeights[i],
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      border: Border.all(
                                        color: Colors.black
                                            .withValues(alpha: 0.08),
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black
                                              .withValues(alpha: 0.16),
                                          blurRadius: 12,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: Image(
                                      image: pages[i].image,
                                      width: displayPageWidth,
                                      height: computedHeights[i],
                                      fit: BoxFit.contain,
                                      filterQuality: FilterQuality.medium,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ToolbarIconButton extends StatelessWidget {
  const _ToolbarIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: 17,
              color: onPressed == null
                  ? AppColors.textMuted.withValues(alpha: 0.45)
                  : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolbarMiniIconButton extends StatelessWidget {
  const _ToolbarMiniIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            icon,
            size: 17,
            color: onPressed == null
                ? AppColors.textMuted.withValues(alpha: 0.4)
                : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

/// Modal unificado con `AppModalShell` para todas las vistas previas PDF.
class AppPdfPreviewModal extends StatefulWidget {
  const AppPdfPreviewModal({
    super.key,
    required this.title,
    this.subtitle,
    this.icon = Icons.picture_as_pdf_rounded,
    this.accent = AppModalAccent.blue,
    required this.build,
    this.pdfFileName = 'Documento.pdf',
    this.initialPageFormat,
    this.dpi = 200.0,
    this.maxWidth = 920.0,
    this.headerTrailing,
    this.canClose = true,
    this.onClose,
    this.showPrintAction = true,
    this.showSaveAction = true,
    this.showShareAction = true,
    this.onPrinted,
    @visibleForTesting this.testPages,
    @visibleForTesting this.onPrintOverride,
    @visibleForTesting this.onSaveOverride,
    @visibleForTesting this.onShareOverride,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final AppModalAccent accent;
  final LayoutCallback build;
  final String pdfFileName;
  final PdfPageFormat? initialPageFormat;
  final double dpi;
  final double maxWidth;
  final Widget? headerTrailing;
  final bool canClose;
  final VoidCallback? onClose;
  final bool showPrintAction;
  final bool showSaveAction;
  final bool showShareAction;
  final VoidCallback? onPrinted;

  @visibleForTesting
  final List<PdfPreviewPageData>? testPages;

  @visibleForTesting
  final Future<void> Function(
    Uint8List bytes,
    PdfPageFormat format,
    String jobName,
  )? onPrintOverride;

  @visibleForTesting
  final Future<void> Function(Uint8List bytes, String fileName)? onSaveOverride;

  @visibleForTesting
  final Future<void> Function(Uint8List bytes, String fileName)?
      onShareOverride;

  @override
  State<AppPdfPreviewModal> createState() => _AppPdfPreviewModalState();
}

class _AppPdfPreviewModalState extends State<AppPdfPreviewModal> {
  bool _isExpanded = false;

  void _handleEscape() {
    if (!widget.canClose) return;
    if (widget.onClose != null) {
      widget.onClose!();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final resolvedWidth = _isExpanded
        ? (screenSize.width - 24).clamp(320.0, 2400.0).toDouble()
        : widget.maxWidth;
    final resolvedHeight =
        _isExpanded ? screenSize.height * 0.96 : screenSize.height * 0.90;

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): _handleEscape,
      },
      child: AppModalShell(
        title: widget.title,
        subtitle: widget.subtitle,
        icon: widget.icon,
        accent: widget.accent,
        maxWidth: resolvedWidth,
        maxHeight: resolvedHeight,
        expandBody: true,
        bodyPadding: EdgeInsets.zero,
        showCloseButton: widget.canClose,
        onClose: widget.canClose
            ? (widget.onClose ?? () => Navigator.of(context).pop())
            : null,
        headerTrailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.headerTrailing != null) ...[
              widget.headerTrailing!,
              const SizedBox(width: 6),
            ],
            IconButton(
              key: const ValueKey('pdf_toggle_expand_btn'),
              onPressed: () => setState(() => _isExpanded = !_isExpanded),
              icon: Icon(
                _isExpanded
                    ? Icons.close_fullscreen_rounded
                    : Icons.open_in_full_rounded,
                color: Colors.white70,
                size: 19,
              ),
              tooltip: _isExpanded
                  ? 'Restaurar tamaño'
                  : 'Expandir vista previa',
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        body: AppPdfPreview(
          build: widget.build,
          pdfFileName: widget.pdfFileName,
          initialPageFormat: widget.initialPageFormat,
          dpi: widget.dpi,
          showPrintAction: widget.showPrintAction,
          showSaveAction: widget.showSaveAction,
          showShareAction: widget.showShareAction,
          onPrinted: widget.onPrinted,
          testPages: widget.testPages,
          onPrintOverride: widget.onPrintOverride,
          onSaveOverride: widget.onSaveOverride,
          onShareOverride: widget.onShareOverride,
        ),
      ),
    );
  }
}

/// Abre el modal unificado [AppPdfPreviewModal] con soporte A4 / Carta y zoom `Ctrl + rueda`.
Future<T?> showAppPdfPreviewDialog<T>({
  required BuildContext context,
  required String title,
  String? subtitle,
  IconData icon = Icons.picture_as_pdf_rounded,
  AppModalAccent accent = AppModalAccent.blue,
  required LayoutCallback build,
  String pdfFileName = 'Documento.pdf',
  PdfPageFormat? initialPageFormat,
  double dpi = 200.0,
  double maxWidth = 920.0,
  bool barrierDismissible = true,
  bool showPrintAction = true,
  bool showSaveAction = true,
  bool showShareAction = true,
  VoidCallback? onPrinted,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (ctx) => AppPdfPreviewModal(
      title: title,
      subtitle: subtitle,
      icon: icon,
      accent: accent,
      build: build,
      pdfFileName: pdfFileName,
      initialPageFormat: initialPageFormat,
      dpi: dpi,
      maxWidth: maxWidth,
      showPrintAction: showPrintAction,
      showSaveAction: showSaveAction,
      showShareAction: showShareAction,
      onPrinted: onPrinted,
      onClose: () => Navigator.of(ctx).pop(),
    ),
  );
}
