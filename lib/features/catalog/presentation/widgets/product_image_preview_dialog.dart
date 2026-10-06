import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:frontend_desktop/core/utils/image_url_resolver.dart';

/// Diálogo de vista previa ampliada/pantalla completa para la imagen de un producto.
/// Proporciona visualización interactiva con zoom táctil y doble toque, y acciones para "Cambiar Foto" y "Quitar Foto".
class ProductImagePreviewDialog extends StatefulWidget {
  final String? title;
  final String? imageUrl;
  final String? imagePath;
  final Uint8List? imageBytes;
  final VoidCallback? onChangeImage;
  final VoidCallback? onRemoveImage;

  const ProductImagePreviewDialog({
    super.key,
    this.title,
    this.imageUrl,
    this.imagePath,
    this.imageBytes,
    this.onChangeImage,
    this.onRemoveImage,
  });

  @override
  State<ProductImagePreviewDialog> createState() => _ProductImagePreviewDialogState();
}

class _ProductImagePreviewDialogState extends State<ProductImagePreviewDialog> {
  bool _isDismissing = false;
  late final TransformationController _transformationController;

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController();
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  void _handleDoubleTap() {
    if (_transformationController.value.isIdentity()) {
      _transformationController.value = Matrix4.diagonal3Values(2.0, 2.0, 1.0);
    } else {
      _transformationController.value = Matrix4.identity();
    }
  }

  void _safePop([VoidCallback? afterPop]) {
    if (_isDismissing || !mounted) return;
    setState(() => _isDismissing = true);
    final route = ModalRoute.of(context);
    bool didPop = false;
    if (route != null) {
      if (route.isCurrent) {
        Navigator.of(context).pop();
        didPop = true;
      }
    } else if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      didPop = true;
    }
    if (didPop) {
      afterPop?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenSize = MediaQuery.of(context).size;
    final isMobile = screenSize.width < 500;
    final maxPreviewWidth = isMobile ? screenSize.width * 0.9 : 480.0;
    final maxPreviewHeight = (screenSize.height * 0.55).clamp(80.0, 420.0);

    final resolvedUrl = resolveImageUrl(widget.imageUrl);

    final hasBytes = widget.imageBytes != null && widget.imageBytes!.isNotEmpty;
    bool pathFileExists = false;
    if (!kIsWeb && widget.imagePath != null && widget.imagePath!.isNotEmpty) {
      try {
        pathFileExists = File(widget.imagePath!).existsSync();
      } catch (_) {
        pathFileExists = false;
      }
    }
    final hasPath = !kIsWeb && widget.imagePath != null && widget.imagePath!.isNotEmpty;
    final hasUrl = resolvedUrl != null && resolvedUrl.isNotEmpty;
    final hasImage = hasBytes || hasPath || hasUrl;

    Widget buildImageErrorFallback([String message = 'No se pudo cargar la imagen']) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.broken_image, size: 56, color: Colors.grey),
            const SizedBox(height: 6),
            Text(
              message,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    Widget imageWidget;
    if (hasBytes) {
      imageWidget = Image.memory(
        widget.imageBytes!,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => buildImageErrorFallback(),
      );
    } else if (hasPath) {
      if (!pathFileExists) {
        imageWidget = buildImageErrorFallback();
      } else {
        imageWidget = Image.file(
          File(widget.imagePath!),
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => buildImageErrorFallback(),
        );
      }
    } else if (hasUrl) {
      imageWidget = Image.network(
        resolvedUrl,
        fit: BoxFit.contain,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return const Center(
            child: SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          );
        },
        errorBuilder: (_, __, ___) => buildImageErrorFallback(),
      );
    } else {
      imageWidget = const Center(
        child: Icon(Icons.image_not_supported_outlined, size: 64, color: Colors.grey),
      );
    }

    return Dialog(
      key: const Key('product_image_preview_dialog'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxPreviewWidth,
          maxHeight: screenSize.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Barra de título con botón de cerrar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Icon(Icons.image_outlined, size: 20, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        widget.title ?? 'Vista previa de imagen',
                        style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              overflow: TextOverflow.ellipsis,
                            ) ??
                            const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              overflow: TextOverflow.ellipsis,
                            ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Cerrar',
                    onPressed: _isDismissing ? null : () => _safePop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Contenedor de la imagen ampliada con zoom interactivo y doble toque
            Flexible(
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: maxPreviewHeight,
                ),
                color: theme.colorScheme.onSurface.withValues(alpha: 0.04),
                child: Center(
                  child: Semantics(
                    label: 'Vista ampliada de imagen de producto. Toque dos veces para alternar zoom.',
                    image: true,
                    child: GestureDetector(
                      key: const Key('preview_double_tap_detector'),
                      onDoubleTap: _handleDoubleTap,
                      child: InteractiveViewer(
                        transformationController: _transformationController,
                        panEnabled: true,
                        scaleEnabled: true,
                        minScale: 0.8,
                        maxScale: 4.0,
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: imageWidget,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            const Divider(height: 1),

            // Barra de acciones inferiores
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 12,
                runSpacing: 8,
                children: [
                  if (widget.onRemoveImage != null && hasImage)
                    OutlinedButton.icon(
                      key: const Key('preview_remove_image_button'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: theme.colorScheme.error,
                        side: BorderSide(color: theme.colorScheme.error.withValues(alpha: 0.5)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Quitar Foto'),
                      onPressed: _isDismissing
                          ? null
                          : () {
                              final callback = widget.onRemoveImage;
                              _safePop(callback);
                            },
                    ),
                  if (widget.onChangeImage != null)
                    FilledButton.icon(
                      key: const Key('preview_change_image_button'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                      icon: const Icon(Icons.photo_library_outlined, size: 18),
                      label: const Text('Cambiar Foto'),
                      onPressed: _isDismissing
                          ? null
                          : () {
                              final callback = widget.onChangeImage;
                              _safePop(callback);
                            },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
