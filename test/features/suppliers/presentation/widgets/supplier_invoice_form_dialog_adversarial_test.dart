import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:frontend_desktop/core/network/api_client.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/features/pos/presentation/providers/pos_provider.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/features/suppliers/presentation/widgets/supplier_invoice_form_dialog.dart';
import 'package:frontend_desktop/features/suppliers/providers/supplier_provider.dart';

class FakeSettingsProvider extends ChangeNotifier implements SettingsProvider {
  bool _isRI = true;
  @override
  bool get isResponsableInscripto => _isRI;

  void setIsRI(bool val) {
    _isRI = val;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSupplierProvider extends ChangeNotifier implements SupplierProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakePosProvider extends ChangeNotifier implements PosProvider {
  @override
  Future<List<Product>> search(String query) async => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeCatalogProvider extends ChangeNotifier implements CatalogProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeApiClient implements ApiClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSettingsProvider fakeSettings;
  late FakeSupplierProvider fakeSupplier;
  late FakePosProvider fakePos;
  late FakeCatalogProvider fakeCatalog;
  late FakeApiClient fakeApi;

  setUp(() {
    fakeSettings = FakeSettingsProvider();
    fakeSupplier = FakeSupplierProvider();
    fakePos = FakePosProvider();
    fakeCatalog = FakeCatalogProvider();
    fakeApi = FakeApiClient();
  });

  Widget buildTestDialog({Size size = const Size(1024, 768), Map<String, dynamic>? initialInvoice}) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsProvider>.value(value: fakeSettings),
        ChangeNotifierProvider<SupplierProvider>.value(value: fakeSupplier),
        ChangeNotifierProvider<PosProvider>.value(value: fakePos),
        ChangeNotifierProvider<CatalogProvider>.value(value: fakeCatalog),
        Provider<ApiClient>.value(value: fakeApi),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: SupplierInvoiceFormDialog(
              supplierId: 1,
              supplierName: 'Distribuidora Central S.A.',
              initialInvoice: initialInvoice,
            ),
          ),
        ),
      ),
    );
  }

  group('SupplierInvoiceFormDialog Adversarial Layout & Stress Tests', () {
    testWidgets('Resolution 1024x768 (Compact Desktop): Renders cleanly with zero RenderFlex overflow',
        (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestDialog(size: const Size(1024, 768)));
      await tester.pumpAndSettle();

      // Check for exceptions
      expect(tester.takeException(), isNull, reason: 'Must not throw any layout overflow exception at 1024x768');

      // Verify header and primary sections
      expect(find.text('Espejo de Ventas - Carga de Remito / Factura'), findsOneWidget);
      expect(find.text('Datos Fiscales (ARCA / AFIP)'), findsOneWidget);

      // Verify that the fiscal section is expanded by default
      expect(find.text('Letra'), findsOneWidget);
      expect(find.text('Pto. Venta'), findsOneWidget);
      expect(find.text('Nº Comprobante'), findsOneWidget);
    });

    testWidgets('Ultra-compact Resolution 800x600: SingleChildScrollView adapts with zero overflow',
        (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestDialog(size: const Size(800, 600)));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: 'Must not overflow in vertical stacked mode at 800x600');
      expect(find.text('Datos Generales'), findsOneWidget);
    });

    testWidgets('Structural Constraint Check: All Rows in Fiscal Section have at most 2 Expanded inputs',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestDialog());
      await tester.pumpAndSettle();

      // Find the fiscal section container by finding 'Datos Fiscales (ARCA / AFIP)' ancestor Container
      final fiscalHeader = find.text('Datos Fiscales (ARCA / AFIP)');
      expect(fiscalHeader, findsOneWidget);

      // Inspect every Row inside the dialog to verify that right panel inputs do not exceed 2 Expanded children
      final rows = find.byType(Row);
      int evaluatedFiscalRows = 0;

      for (final rowElement in rows.evaluate()) {
        final rowWidget = rowElement.widget as Row;
        // Count how many children are Expanded or Flexible
        final expandedCount = rowWidget.children.where((c) => c is Expanded || c is Flexible).length;

        // If the row contains TextFormFields, Dropdowns, or InkWells with InputDecorators
        final hasFormField = rowWidget.children.any((c) {
          final desc = c.toStringDeep();
          final childDesc = c is Expanded
              ? c.child.toStringDeep()
              : (c is Flexible ? c.child.toStringDeep() : '');
          return desc.contains('TextFormField') ||
              desc.contains('DropdownButtonFormField') ||
              desc.contains('InputDecorator') ||
              childDesc.contains('TextFormField') ||
              childDesc.contains('DropdownButtonFormField') ||
              childDesc.contains('InputDecorator');
        });

        if (hasFormField) {
          evaluatedFiscalRows++;
          expect(
            expandedCount,
            lessThanOrEqualTo(2),
            reason: 'Row with inputs has $expandedCount Expanded children, violating the maximum of 2 constraint: ${rowWidget.toStringShort()}',
          );
        }
      }

      expect(evaluatedFiscalRows, greaterThanOrEqualTo(5),
          reason: 'Must evaluate at least 5 input rows in the dialog');
    });

    testWidgets('Non-RI businesses: Fiscal Section is strictly hidden', (tester) async {
      fakeSettings.setIsRI(false);

      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestDialog());
      await tester.pumpAndSettle();

      expect(find.text('Datos Fiscales (ARCA / AFIP)'), findsNothing);
      expect(find.text('Pto. Venta'), findsNothing);
      expect(find.text('Neto 21% (\$)'), findsNothing);
    });

    testWidgets('Voucher Letter B/C: zeroes fiscal aliquots, displays B/C info banner and Non-Taxed allocation',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestDialog());
      await tester.pumpAndSettle();

      // Open Letter Dropdown and select 'B (No Computa)'
      await tester.ensureVisible(find.text('A (Discrimina IVA)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('A (Discrimina IVA)'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('B (No Computa)').last);
      await tester.pumpAndSettle();

      // Aliquots (21%, 10.5%, 27%) must be hidden for B/C
      expect(find.text('Neto 21% (\$)'), findsNothing);
      expect(find.text('IVA 21% (\$)'), findsNothing);
      expect(find.text('Distribuir Total en Neto 21%'), findsNothing);

      // Informative banner must be shown
      expect(
        find.textContaining('Comprobantes B/C no computan Crédito Fiscal. El total se asigna como No Gravado.'),
        findsOneWidget,
      );

      // No Gravado input must remain visible
      expect(find.text('No Gravado (\$)'), findsOneWidget);
    });

    testWidgets('Editing existing invoice: Loads 15 fiscal fields into controllers correctly',
        (tester) async {
      final existingInvoice = {
        'id': 42,
        'type': 'invoice',
        'voucher_letter': 'A',
        'point_of_sale': 4,
        'voucher_number': 12345,
        'affects_vat_book': true,
        'net_21': 100000.0,
        'iva_21': 21000.0,
        'net_105': 20000.0,
        'iva_105': 2100.0,
        'net_27': 10000.0,
        'iva_27': 2700.0,
        'non_taxed_amount': 5000.0,
        'exempt_amount': 2000.0,
        'iva_perception': 3000.0,
        'iibb_perception': 1500.0,
        'internal_taxes': 500.0,
        'total_amount': 167800.0,
        'items': [],
      };

      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestDialog(initialInvoice: existingInvoice));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Editar Comprobante de Proveedor #42'), findsOneWidget);
      expect(find.text('4'), findsOneWidget); // Point of sale
      expect(find.text('12345'), findsOneWidget); // Voucher number
    });

    testWidgets('Large Number Stress (\$100,000,000+): Auto-calculates without overflow or crash',
        (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestDialog(size: const Size(1024, 768)));
      await tester.pumpAndSettle();

      // Enter a massive net 21 amount: 150,000,000
      final net21Field = find.widgetWithText(TextFormField, 'Neto 21% (\$)');
      expect(net21Field, findsOneWidget);

      await tester.enterText(net21Field, '150000000');
      await tester.pumpAndSettle();

      // Verify no exception was thrown
      expect(tester.takeException(), isNull);

      // Verify auto-calculated 21% IVA = 31,500,000
      expect(find.textContaining('31.500.000'), findsWidgets);
    });

    testWidgets('Factura A zero-sum validation: blocks submission and shows snackbar when fSum is zero',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Provide an invoice with items totaling > 0 but with 0 fiscal amounts
      final invoiceWithItems = {
        'id': 99,
        'type': 'invoice',
        'invoice_number': '0001-00000123',
        'voucher_letter': 'A',
        'affects_vat_book': true,
        'point_of_sale': 1,
        'voucher_number': 123,
        'total_amount': 5000.0,
        'items': [
          {
            'product_id': 1,
            'product_name': 'Test Item',
            'quantity': 1,
            'unit_cost': 5000.0,
            'price': 6000.0,
          }
        ],
      };

      await tester.pumpWidget(buildTestDialog(initialInvoice: invoiceWithItems));
      await tester.pumpAndSettle();

      // Tap submit button
      final submitButton = find.text('GUARDAR CAMBIOS');
      await tester.ensureVisible(submitButton);
      await tester.pumpAndSettle();
      await tester.tap(submitButton);
      await tester.pumpAndSettle();

      // Expect the snackbar to appear
      expect(find.text('Debe ingresar el desglose fiscal para Factura A'), findsOneWidget);
    });

    testWidgets('Multi-digit typing in Pto. Venta and Nº Comprobante updates invoice_number continuously',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestDialog());
      await tester.pumpAndSettle();

      final pvField = find.widgetWithText(TextFormField, 'Pto. Venta');
      final nroField = find.widgetWithText(TextFormField, 'Nº Comprobante');

      await tester.enterText(pvField, '1');
      await tester.pump();
      await tester.enterText(nroField, '1');
      await tester.pump();
      expect(find.text('0001-00000001'), findsOneWidget);

      await tester.enterText(pvField, '12');
      await tester.pump();
      await tester.enterText(nroField, '12345');
      await tester.pump();
      expect(find.text('0012-00012345'), findsOneWidget);
    });

    testWidgets('Selecting Remito de Mercadería hides Fiscal Section', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestDialog());
      await tester.pumpAndSettle();

      expect(find.text('Datos Fiscales (ARCA / AFIP)'), findsOneWidget);

      await tester.tap(find.text('Factura de Compra'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remito de Mercadería').last);
      await tester.pumpAndSettle();

      expect(find.text('Datos Fiscales (ARCA / AFIP)'), findsNothing);
    });

    testWidgets('Editing historical invoice without voucher_letter defaults to S/D and does not block with Factura A error',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final historicalInvoice = {
        'id': 77,
        'type': 'invoice',
        'voucher_letter': null,
        'affects_vat_book': true,
        'total_amount': 410000.0,
        'items': [
          {
            'product_id': 1,
            'product_name': 'Insumo Histórico',
            'quantity': 1,
            'unit_cost': 410000.0,
            'price': 500000.0,
          }
        ],
      };

      await tester.pumpWidget(buildTestDialog(initialInvoice: historicalInvoice));
      await tester.pumpAndSettle();

      expect(find.text('S/D (Sin Desglose / Hist.)'), findsOneWidget);
      expect(find.text('Neto 21% (\$)'), findsNothing);
      final convertBtn = find.text('Convertir a Factura A y Calcular IVA 21%');
      expect(convertBtn, findsOneWidget);

      await tester.ensureVisible(convertBtn);
      await tester.pumpAndSettle();
      await tester.tap(convertBtn);
      await tester.pumpAndSettle();

      expect(find.text('A (Discrimina IVA)'), findsOneWidget);
      expect(find.text('Neto 21% (\$)'), findsOneWidget);
      expect(find.textContaining('Suma fiscal coincide'), findsOneWidget);

      // Verify per-product IVA badge is visible and switching to 10.5% recalculates Neto 10.5% and IVA 10.5%
      expect(find.text('IVA 21%'), findsOneWidget);
      await tester.tap(find.text('IVA 21%'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('IVA 10.5% (Reducido)'));
      await tester.pumpAndSettle();

      expect(find.text('IVA 10.5%'), findsOneWidget);
      expect(find.textContaining('Suma fiscal coincide'), findsOneWidget);
    });

    testWidgets('Resistencia -> Formosa Factura A Mayorista: Costos Netos (+IVA) + Percepción IIBB Rentas 2% s/Sub+IVA',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 860);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final resistInvoice = {
        'id': 88,
        'type': 'invoice',
        'voucher_letter': 'A',
        'affects_vat_book': true,
        'total_amount': 230159.02,
        'items': [
          {
            'product_id': 1,
            'product_name': 'Mercadería Mayorista Resistencia',
            'quantity': 1,
            'unit_cost': 230159.02,
            'price': 320000.0,
          }
        ],
      };

      await tester.pumpWidget(buildTestDialog(initialInvoice: resistInvoice));
      await tester.pumpAndSettle();

      // Switch to 'Costos Netos (+IVA)'
      final netModeBtn = find.text('Costos Netos (+IVA)');
      expect(netModeBtn, findsOneWidget);
      await tester.ensureVisible(netModeBtn);
      await tester.pumpAndSettle();
      await tester.tap(netModeBtn);
      await tester.pumpAndSettle();

      // Verify Net 21% is 230.159,02 and IVA 21% is 48.333,39
      expect(find.text('230.159,02'), findsWidgets);
      expect(find.text('48.333,39'), findsWidgets);

      // Open the % IIBB Rentas calculator menu and select '2% s/ Subtotal+IVA (2,42% s/Neto - Ej. Resistencia)'
      final iibbRateBtn = find.text('% ▾');
      expect(iibbRateBtn, findsOneWidget);
      await tester.ensureVisible(iibbRateBtn);
      await tester.pumpAndSettle();
      await tester.tap(iibbRateBtn);
      await tester.pumpAndSettle();

      await tester.tap(find.text('2% s/ Subtotal+IVA (2,42% s/Neto - Ej. Resistencia)'));
      await tester.pumpAndSettle();

      // Verify Percepción IIBB Formosa = 5.569,85, badge shows '2% c/IVA ▾', and Suma fiscal coincide
      expect(find.text('5.569,85'), findsOneWidget);
      expect(find.text('2% c/IVA ▾'), findsOneWidget);
      expect(find.textContaining('Suma fiscal coincide'), findsOneWidget);
    });
  });
}
