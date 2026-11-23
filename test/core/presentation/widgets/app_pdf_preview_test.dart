import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_desktop/core/presentation/widgets/app_modal_shell.dart';
import 'package:frontend_desktop/core/presentation/widgets/app_pdf_preview.dart';
import 'package:frontend_desktop/core/theme/app_theme.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

/// PNG válido 1x1 transparente en memoria para pruebas determinísticas sin PDFium.
final Uint8List _kDummyPng1x1 = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

List<PdfPreviewPageData> _buildTestPages({
  int count = 1,
  int width = 595,
  int height = 842,
}) {
  return List.generate(
    count,
    (_) => PdfPreviewPageData(
      image: MemoryImage(_kDummyPng1x1),
      width: width,
      height: height,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Helpers de papel y nombre de archivo PDF', () {
    test('pdfPageFormatFromPaperSize y pdfPaperSizeLabel soportan A4 y Carta',
        () {
      expect(pdfPageFormatFromPaperSize('a4'), PdfPageFormat.a4);
      expect(pdfPageFormatFromPaperSize('A4'), PdfPageFormat.a4);
      expect(pdfPageFormatFromPaperSize(null), PdfPageFormat.a4);
      expect(pdfPageFormatFromPaperSize('letter'), PdfPageFormat.letter);
      expect(pdfPageFormatFromPaperSize('LETTER'), PdfPageFormat.letter);

      expect(pdfPaperSizeLabel('a4'), 'A4');
      expect(pdfPaperSizeLabel(null), 'A4');
      expect(pdfPaperSizeLabel('letter'), 'Carta');
      expect(pdfPaperSizeLabel('Letter'), 'Carta');
    });

    test('sanitizePdfFileName limpia caracteres inválidos de Windows', () {
      expect(
        sanitizePdfFileName('Factura:0001/0002*?"<>|'),
        'Factura_0001_0002______.pdf',
      );
      expect(sanitizePdfFileName('Presupuesto_01'), 'Presupuesto_01.pdf');
      expect(sanitizePdfFileName('  '), 'Documento.pdf');
    });
  });

  group('AppPdfPreview — Zoom, Ctrl + Rueda, Atajos y Navegación', () {
    testWidgets(
      'Ctrl + rueda arriba acerca, Ctrl + rueda abajo aleja sin scrollear verticalmente, y rueda sin Ctrl mantiene 100%',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 860);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final letterPages = _buildTestPages(count: 2, width: 612, height: 792);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: AppPdfPreview(
                build: (_) async => Uint8List.fromList([1, 2, 3]),
                initialPageFormat: PdfPageFormat.letter,
                pdfFileName: 'Presupuesto_Carta.pdf',
                testPages: letterPages,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('100%'), findsOneWidget);
        expect(find.text('Pág. 1 / 2'), findsOneWidget);

        final verticalScroll = tester.widget<SingleChildScrollView>(
          find.byType(SingleChildScrollView).first,
        );
        final vController = verticalScroll.controller!;
        expect(vController.offset, 0.0);

        final canvasRect = tester.getRect(find.byType(Image).first);
        final topFocal = Offset(canvasRect.center.dx, canvasRect.top + 8);
        final pointer = TestPointer(1, PointerDeviceKind.mouse);
        await tester.sendEventToBinding(pointer.hover(topFocal));

        // 1) Rueda abajo SIN Ctrl: scrollea la hoja y NO cambia zoom (100%)
        await tester.sendEventToBinding(pointer.scroll(const Offset(0, 120)));
        await tester.pumpAndSettle();
        expect(find.text('100%'), findsOneWidget);
        expect(vController.offset, greaterThan(0.0));

        // Volvemos arriba para aislar el zoom
        vController.jumpTo(0.0);
        await tester.pumpAndSettle();

        // 2) Ctrl + rueda abajo: aleja (< 100%) y NO dispara el scroll vertical del Scrollable
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendEventToBinding(pointer.scroll(const Offset(0, 120)));
        await tester.pumpAndSettle();
        expect(vController.offset, 0.0);

        final zoomOutText = tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(const ValueKey('pdf_zoom_reset_btn')),
                matching: find.byType(Text),
              ),
            )
            .data!;
        final zoomOutPct = int.parse(zoomOutText.replaceAll('%', ''));
        expect(zoomOutPct, lessThan(100));
        expect(zoomOutPct, greaterThanOrEqualTo(50));

        // 3) Ctrl + rueda arriba repetida: acerca (> 100%) y respeta tope 300%
        for (var i = 0; i < 15; i++) {
          await tester.sendEventToBinding(pointer.scroll(const Offset(0, -120)));
          await tester.pump();
        }
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();

        final zoomMaxText = tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(const ValueKey('pdf_zoom_reset_btn')),
                matching: find.byType(Text),
              ),
            )
            .data!;
        final zoomMaxPct = int.parse(zoomMaxText.replaceAll('%', ''));
        expect(zoomMaxPct, lessThanOrEqualTo(300));
        expect(zoomMaxPct, greaterThan(100));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Botones -, 100%, +, Ajustar al ancho y navegación de páginas funcionan correctamente',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 860);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final a4Pages = _buildTestPages(count: 2, width: 595, height: 842);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: AppPdfPreview(
                build: (_) async => Uint8List.fromList([1, 2, 3]),
                initialPageFormat: PdfPageFormat.a4,
                testPages: a4Pages,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Zoom + (100% -> 125%)
        await tester.tap(find.byKey(const ValueKey('pdf_zoom_in_btn')));
        await tester.pumpAndSettle();
        expect(find.text('125%'), findsOneWidget);

        // Zoom - (125% -> 100% -> 75%)
        await tester.tap(find.byKey(const ValueKey('pdf_zoom_out_btn')));
        await tester.pumpAndSettle();
        expect(find.text('100%'), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('pdf_zoom_out_btn')));
        await tester.pumpAndSettle();
        expect(find.text('75%'), findsOneWidget);

        // Reset a 100% tocando la píldora
        await tester.tap(find.byKey(const ValueKey('pdf_zoom_reset_btn')));
        await tester.pumpAndSettle();
        expect(find.text('100%'), findsOneWidget);

        // Ajustar al ancho (en 1280px, base=860, disponible=1232 -> ~143%)
        await tester.tap(find.byKey(const ValueKey('pdf_zoom_fit_btn')));
        await tester.pumpAndSettle();
        expect(find.text('100%'), findsNothing);

        // Volver a 100%
        await tester.tap(find.byKey(const ValueKey('pdf_zoom_reset_btn')));
        await tester.pumpAndSettle();
        expect(find.text('100%'), findsOneWidget);

        // Navegar a página 2 y volver a página 1
        expect(find.text('Pág. 1 / 2'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('pdf_next_page_btn')));
        await tester.pumpAndSettle();
        expect(find.text('Pág. 2 / 2'), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('pdf_prev_page_btn')));
        await tester.pumpAndSettle();
        expect(find.text('Pág. 1 / 2'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Atajos de teclado Ctrl++, Ctrl+-, Ctrl+0, Ctrl+P y Ctrl+S disparan zoom y acciones',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 860);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        PdfPageFormat? printedFormat;
        String? printedJob;
        String? savedFile;

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: AppPdfPreview(
                build: (_) async => Uint8List.fromList([9, 8, 7]),
                initialPageFormat: PdfPageFormat.letter,
                pdfFileName: 'Remito:000021.pdf',
                testPages: _buildTestPages(count: 1, width: 612, height: 792),
                onPrintOverride: (bytes, format, jobName) async {
                  printedFormat = format;
                  printedJob = jobName;
                },
                onSaveOverride: (bytes, fileName) async {
                  savedFile = fileName;
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Ctrl + Numpad +
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.numpadAdd);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
        expect(find.text('125%'), findsOneWidget);

        // Ctrl + -
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.minus);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
        expect(find.text('100%'), findsOneWidget);

        // Ctrl + + y luego Ctrl + 0
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.equal);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
        expect(find.text('125%'), findsOneWidget);

        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
        expect(find.text('100%'), findsOneWidget);

        // Ctrl + P
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
        expect(printedJob, 'Remito_000021.pdf');
        expect(printedFormat, isNotNull);

        // Ctrl + S
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
        expect(savedFile, 'Remito_000021.pdf');
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'No genera RenderFlex overflow en pantalla angosta (420x600)',
      (tester) async {
        tester.view.physicalSize = const Size(420, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: AppPdfPreview(
                build: (_) async => Uint8List.fromList([1, 2, 3]),
                testPages: _buildTestPages(count: 2),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('100%'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('AppPdfPreviewModal — Cabecera AppModalShell, Expandir y Esc', () {
    testWidgets(
      'Muestra AppModalShell sin Switch de debug, expande/restaura y cierra con Esc solo si canClose=true',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 860);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // 1) canClose = true: Esc cierra el modal
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => AppPdfPreviewModal(
                        title: 'Remito de Despacho N° 000021',
                        subtitle: 'Vista previa • Hoja A4',
                        build: (_) async => Uint8List.fromList([1, 2, 3]),
                        testPages: _buildTestPages(count: 1),
                      ),
                    );
                  },
                  child: const Text('Abrir'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Abrir'));
        await tester.pumpAndSettle();

        expect(find.byType(AppModalShell), findsOneWidget);
        expect(find.byType(Switch), findsNothing);
        expect(find.text('Remito de Despacho N° 000021'), findsOneWidget);

        // Expandir y restaurar tamaño
        final shellBefore =
            tester.widget<AppModalShell>(find.byType(AppModalShell));
        expect(shellBefore.maxWidth, 920.0);

        await tester.tap(find.byKey(const ValueKey('pdf_toggle_expand_btn')));
        await tester.pumpAndSettle();

        final shellExpanded =
            tester.widget<AppModalShell>(find.byType(AppModalShell));
        expect(shellExpanded.maxWidth, greaterThan(920.0));

        await tester.tap(find.byKey(const ValueKey('pdf_toggle_expand_btn')));
        await tester.pumpAndSettle();
        final shellRestored =
            tester.widget<AppModalShell>(find.byType(AppModalShell));
        expect(shellRestored.maxWidth, 920.0);

        // Esc cierra
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(AppPdfPreviewModal), findsNothing);

        // 2) canClose = false: Esc NO cierra el modal
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (ctx) => AppPdfPreviewModal(
                        title: 'Procesando anulación',
                        canClose: false,
                        build: (_) async => Uint8List.fromList([1, 2, 3]),
                        testPages: _buildTestPages(count: 1),
                      ),
                    );
                  },
                  child: const Text('Abrir Bloqueado'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Abrir Bloqueado'));
        await tester.pumpAndSettle();
        expect(find.byType(AppPdfPreviewModal), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(AppPdfPreviewModal), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
