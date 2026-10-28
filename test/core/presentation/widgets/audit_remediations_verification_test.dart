import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend_desktop/core/presentation/pages/license_lock_screen.dart';
import 'package:frontend_desktop/core/presentation/widgets/thermal_receipt_widget.dart';
import 'package:frontend_desktop/core/services/license_heartbeat_service.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/features/pos/domain/entities/cart_item.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';

class MockSettingsProvider extends ChangeNotifier implements SettingsProvider {
  @override
  bool get isLicenseActive => false;

  @override
  String get currentApiUrl => 'http://127.0.0.1:8000';

  @override
  bool hasFeature(String feature) => true;

  @override
  LicenseSecurityStatus get securityStatus => LicenseSecurityStatus.ok;

  @override
  String? get errorMessage => null;

  @override
  BusinessSettings? get settings => BusinessSettings(
        companyName: 'Ferretería El Progreso',
        taxId: '30-71234567-8',
        licenseStatus: 'BLOCKED_KEY',
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('Audit Remediations Verification Tests (Frontend)', () {
    final testSettings = BusinessSettings(
      companyName: 'Ferretería El Progreso',
      taxId: '30-71234567-8',
      address: 'Av. San Martín 1234',
      phone: '11-4455-6677',
    );

    final testItems = [
      CartItem(
        product: Product(
          id: 1,
          name: 'Taladro Percutor 750W',
          internalCode: 'TAL-750',
          costPrice: 50000.0,
          sellingPrice: 75000.0,
          stock: 10.0,
          active: true,
          isSoldByWeight: false,
        ),
        quantity: 1.0,
      ),
    ];

    final testPayments = [
      {'name': 'EFECTIVO', 'amount': 75000.0},
    ];

    testWidgets('FE-MED-01: LicenseLockScreen displays CERRAR CAJA / ARQUEO button and navigates to /close-shift',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final navKey = GlobalKey<NavigatorState>();
      final mockSettings = MockSettingsProvider();
      String? navigatedRoute;

      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsProvider>.value(
          value: mockSettings,
          child: MaterialApp(
            navigatorKey: navKey,
            onGenerateRoute: (settings) {
              navigatedRoute = settings.name;
              return MaterialPageRoute(
                builder: (ctx) => Scaffold(body: Text('Página: ${settings.name}')),
              );
            },
            home: Scaffold(
              body: LicenseLockScreen(navigatorKey: navKey),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verificar que el botón de cierre de caja de emergencia existe en pantalla
      final closeShiftBtn = find.text('CERRAR CAJA / ARQUEO DE TURNO');
      expect(closeShiftBtn, findsOneWidget);

      // Tocar el botón y verificar navegación a /close-shift
      await tester.tap(closeShiftBtn);
      await tester.pumpAndSettle();

      expect(navigatedRoute, equals('/close-shift'));
    });

    testWidgets('R3-AFIP-01: ThermalReceiptWidget renders COMP. ASOC for Nota de Credito',
        (tester) async {
      final creditNoteInvoice = {
        'voucher_type': 3, // Nota de Crédito A
        'voucher_letter': 'A',
        'point_of_sale': 1,
        'voucher_number': 15,
        'formatted_number': '00001-00000015',
        'cae': '74239847120394',
        'cae_expiration': '2026-11-10',
        'associated_voucher_label': 'Factura A Nro 00001-00000042',
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ThermalReceiptWidget(
              businessSettings: testSettings,
              items: testItems,
              payments: testPayments,
              total: 75000.0,
              paperWidth: ThermalPaperWidth.mm80,
              electronicInvoice: creditNoteInvoice,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('NOTA DE CREDITO A'), findsOneWidget);
      expect(find.textContaining('COMP. ASOC: Factura A Nro 00001-00000042'), findsOneWidget);
    });

    testWidgets('R3-AFIP-01 (Fallback): ThermalReceiptWidget formats COMP. ASOC from associated_formatted_number',
        (tester) async {
      final creditNoteInvoice = {
        'voucher_type': 8, // Nota de Crédito B
        'voucher_letter': 'B',
        'point_of_sale': 2,
        'voucher_number': 99,
        'formatted_number': '00002-00000099',
        'cae': '74239847120394',
        'cae_expiration': '2026-11-10',
        'associated_formatted_number': '00002-00000120',
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ThermalReceiptWidget(
              businessSettings: testSettings,
              items: testItems,
              payments: testPayments,
              total: 75000.0,
              paperWidth: ThermalPaperWidth.mm80,
              electronicInvoice: creditNoteInvoice,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('NOTA DE CREDITO B'), findsOneWidget);
      expect(find.textContaining('COMP. ASOC: Factura B Nro 00002-00000120'), findsOneWidget);
    });

    testWidgets('R3-AFIP-01: Standard Factura does NOT show COMP. ASOC line',
        (tester) async {
      final standardInvoice = {
        'voucher_type': 1, // Factura A
        'voucher_letter': 'A',
        'point_of_sale': 1,
        'voucher_number': 15,
        'formatted_number': '00001-00000015',
        'cae': '74239847120394',
        'cae_expiration': '2026-11-10',
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ThermalReceiptWidget(
              businessSettings: testSettings,
              items: testItems,
              payments: testPayments,
              total: 75000.0,
              paperWidth: ThermalPaperWidth.mm80,
              electronicInvoice: standardInvoice,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('FACTURA A'), findsOneWidget);
      expect(find.textContaining('COMP. ASOC:'), findsNothing);
    });
  });
}
