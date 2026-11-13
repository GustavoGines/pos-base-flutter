import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend_desktop/core/services/remote_scanner_service.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/pos/domain/entities/cart_item.dart';
import 'package:frontend_desktop/features/pos/presentation/widgets/pos_rename_cart_item_dialog.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'disable_pusher': true});
  });

  Product makeProduct({
    required int id,
    required String name,
    String internalCode = '10001',
    String? barcode,
    bool active = true,
  }) {
    return Product(
      id: id,
      name: name,
      internalCode: internalCode,
      barcode: barcode,
      sellingPrice: 1500.0,
      costPrice: 1000.0,
      stock: 10,
      active: active,
      isSoldByWeight: false,
    );
  }

  group('RemoteScannerService - Lógica pura & matching', () {
    test('findExactProductMatch prioriza barcode exacto y cae en internalCode',
        () {
      final pByInternal = makeProduct(
        id: 1,
        name: 'Por PLU',
        internalCode: '7790001',
        barcode: null,
      );
      final pByBarcode = makeProduct(
        id: 2,
        name: 'Por EAN',
        internalCode: '00002',
        barcode: ' 7790001 ',
      );
      final pInactive = makeProduct(
        id: 3,
        name: 'Inactivo',
        internalCode: '00003',
        barcode: '99999999',
        active: false,
      );

      final exactBarcode = RemoteScannerService.findExactProductMatch(
        [pByInternal, pByBarcode],
        '7790001',
      );
      expect(exactBarcode?.id, 2);

      final exactPlu = RemoteScannerService.findExactProductMatch(
        [pByInternal, pByBarcode],
        ' 7790001 ',
        includeInternalCode: true,
      );
      expect(exactPlu?.id, 2);

      final pluFallback = RemoteScannerService.findExactProductMatch(
        [pByInternal],
        '7790001',
      );
      expect(pluFallback?.id, 1);

      expect(
        RemoteScannerService.findExactProductMatch(
          [pInactive],
          '99999999',
          activeOnly: true,
        ),
        isNull,
      );
      expect(
        RemoteScannerService.findExactProductMatch(
          [pInactive],
          '99999999',
          activeOnly: false,
        )?.id,
        3,
      );
    });

    test('updateTerminalId normaliza valores vacíos e ignora escaneos vacíos o tras dispose',
        () {
      final service = RemoteScannerService(autoConnect: false);
      expect(service.terminalId, 'caja-1');

      service.updateTerminalId('  caja-2 ');
      expect(service.terminalId, 'caja-2');

      service.updateTerminalId('   ');
      expect(service.terminalId, 'caja-1');

      expect(service.handleIncomingBarcode('   '), isFalse);

      service.dispose();
      expect(service.handleIncomingBarcode('7790001112223'), isFalse);
    });

    test('ignora silenciosamente sin aviso de bloqueo cuando no hay consumidores (ej. LoginScreen)',
        () {
      final blockedEvents = <String>[];
      final service = RemoteScannerService(
        autoConnect: false,
        onBlockedScanHook: blockedEvents.add,
      );
      addTearDown(service.dispose);

      expect(service.handleIncomingBarcode('111111'), isFalse);
      expect(blockedEvents, isEmpty);
    });
  });

  group('RemoteScannerListener - Ruteo por ModalRoute activa', () {
    testWidgets(
      'un modal con RemoteScannerListener intercepta sin disparar atrás y al cerrarse devuelve el foco al POS',
      (tester) async {
        final service = RemoteScannerService(autoConnect: false);
        addTearDown(service.dispose);

        final posScans = <String>[];
        final modalScans = <String>[];

        await tester.pumpWidget(
          ChangeNotifierProvider<RemoteScannerService>.value(
            value: service,
            child: MaterialApp(
              home: RemoteScannerListener(
                debugLabel: 'BasePos',
                onBarcodeScanned: posScans.add,
                child: Scaffold(
                  body: Builder(
                    builder: (context) => ElevatedButton(
                      onPressed: () {
                        showDialog<void>(
                          context: context,
                          builder: (dialogCtx) => RemoteScannerListener(
                            debugLabel: 'TopModal',
                            onBarcodeScanned: modalScans.add,
                            child: AlertDialog(
                              title: const Text('Modal Lector'),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(dialogCtx).pop(),
                                  child: const Text('Cerrar Modal'),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                      child: const Text('Abrir Modal Lector'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        // 1. Sin modales encima: recibe BasePos
        expect(service.handleIncomingBarcode(' 779111 '), isTrue);
        expect(posScans, ['779111']);
        expect(modalScans, isEmpty);

        // 2. Abrimos modal superior con su propio RemoteScannerListener
        await tester.tap(find.text('Abrir Modal Lector'));
        await tester.pumpAndSettle();

        expect(service.handleIncomingBarcode('779222'), isTrue);
        expect(posScans, ['779111']); // No mutó detrás
        expect(modalScans, ['779222']);

        // 3. Cerramos modal: el siguiente escaneo vuelve a BasePos
        await tester.tap(find.text('Cerrar Modal'));
        await tester.pumpAndSettle();

        expect(service.handleIncomingBarcode('779333'), isTrue);
        expect(posScans, ['779111', '779333']);
        expect(modalScans, ['779222']);
      },
    );

    testWidgets(
      'modales bloqueantes sin lector (ej. Checkout/PIN) frenan el escaneo detrás y disparan aviso con anti-spam',
      (tester) async {
        DateTime fakeNow = DateTime(2026, 11, 12, 12, 0, 0);
        final blockedCodes = <String>[];
        final service = RemoteScannerService(
          autoConnect: false,
          blockedWarningCooldown: const Duration(seconds: 3),
          clock: () => fakeNow,
          onBlockedScanHook: blockedCodes.add,
        );
        addTearDown(service.dispose);

        final posScans = <String>[];

        await tester.pumpWidget(
          ChangeNotifierProvider<RemoteScannerService>.value(
            value: service,
            child: MaterialApp(
              home: RemoteScannerListener(
                debugLabel: 'PosBase',
                onBarcodeScanned: posScans.add,
                child: Scaffold(
                  body: Builder(
                    builder: (context) => ElevatedButton(
                      onPressed: () {
                        showDialog<void>(
                          context: context,
                          builder: (_) => const AlertDialog(
                            title: Text('Checkout Bloqueante'),
                          ),
                        );
                      },
                      child: const Text('Abrir Checkout'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Abrir Checkout'));
        await tester.pumpAndSettle();

        // Primer escaneo bloqueado: dispara aviso
        expect(service.handleIncomingBarcode('7790001'), isFalse);
        expect(posScans, isEmpty);
        expect(blockedCodes, ['7790001']);

        // Dentro de la ventana de 3s: sigue bloqueado pero no spamea hook
        fakeNow = fakeNow.add(const Duration(seconds: 1));
        expect(service.handleIncomingBarcode('7790002'), isFalse);
        expect(blockedCodes, ['7790001']);

        // Pasados los 3s: permite nuevo aviso
        fakeNow = fakeNow.add(const Duration(seconds: 3));
        expect(service.handleIncomingBarcode('7790003'), isFalse);
        expect(blockedCodes, ['7790001', '7790003']);
        expect(posScans, isEmpty);
      },
    );

    testWidgets(
      'PosRenameCartItemDialog (Ctrl+E) recibe escaneo Android en Zona 2 y expande editor EAN sin disparar el POS',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final service = RemoteScannerService(autoConnect: false);
        addTearDown(service.dispose);

        final posScans = <String>[];
        final product = makeProduct(
          id: 50,
          name: 'Torta Selva Negra',
          internalCode: '500',
          barcode: null,
        );
        final cartItem = CartItem(product: product, quantity: 1);
        PosRenameCartItemResult? result;

        await tester.pumpWidget(
          ChangeNotifierProvider<RemoteScannerService>.value(
            value: service,
            child: MaterialApp(
              home: RemoteScannerListener(
                debugLabel: 'PosBackground',
                onBarcodeScanned: posScans.add,
                child: Scaffold(
                  body: Builder(
                    builder: (context) => ElevatedButton(
                      onPressed: () async {
                        result = await PosRenameCartItemDialog.show(
                          context,
                          item: cartItem,
                        );
                      },
                      child: const Text('Editar Linea'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Editar Linea'));
        await tester.pumpAndSettle();

        // Simulamos escaneo enviado desde la app Android con Zona 2 aún colapsada
        expect(service.handleIncomingBarcode('7798887776665'), isTrue);
        await tester.pump();

        expect(posScans, isEmpty);
        expect(
          find.textContaining('7798887776665'),
          findsAtLeastNWidgets(1),
        );

        // Esperamos a que se autocierre el toast de SnackBarService antes de finalizar el test
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();

        final applyBtn = find.text('Aplicar y Guardar en BD (Enter)');
        await tester.ensureVisible(applyBtn);
        await tester.tap(applyBtn);
        await tester.pumpAndSettle();

        expect(result, isNotNull);
        expect(result!.barcodeChanged, isTrue);
        expect(result!.newBarcode, '7798887776665');
      },
    );

    testWidgets(
      'modal bloqueante muestra toast flotante de aviso cuando no hay onBlockedScanHook',
      (tester) async {
        final service = RemoteScannerService(autoConnect: false);
        addTearDown(service.dispose);

        await tester.pumpWidget(
          ChangeNotifierProvider<RemoteScannerService>.value(
            value: service,
            child: MaterialApp(
              home: RemoteScannerListener(
                debugLabel: 'CatalogBase',
                onBarcodeScanned: (_) {},
                child: Scaffold(
                  body: Builder(
                    builder: (context) => ElevatedButton(
                      onPressed: () {
                        showDialog<void>(
                          context: context,
                          builder: (_) => const AlertDialog(
                            title: Text('Confirmación'),
                          ),
                        );
                      },
                      child: const Text('Abrir Confirmacion'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Abrir Confirmacion'));
        await tester.pumpAndSettle();

        expect(service.handleIncomingBarcode('779444555'), isFalse);
        await tester.pump();
        expect(
          find.textContaining('Escaneo ignorado (779444555)'),
          findsOneWidget,
        );

        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
      },
    );
  });
}
