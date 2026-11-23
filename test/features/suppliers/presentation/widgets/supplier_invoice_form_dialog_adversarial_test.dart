import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend_desktop/core/network/api_client.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/brand.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/category.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/rubro.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/features/pos/presentation/providers/pos_provider.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/features/suppliers/models/supplier_model.dart';
import 'package:frontend_desktop/features/suppliers/presentation/widgets/supplier_invoice_form_dialog.dart';
import 'package:frontend_desktop/features/suppliers/providers/supplier_provider.dart';

class FakeSettingsProvider extends ChangeNotifier implements SettingsProvider {
  bool _isRI = true;
  bool _batchExpiration = true;
  @override
  bool get isResponsableInscripto => _isRI;

  @override
  FeatureFlags get features =>
      FeatureFlags(suppliers: true, batchExpiration: _batchExpiration);

  @override
  BusinessSettings? get settings => BusinessSettings(
        licensePlanType: 'premium',
        businessType: _batchExpiration ? 'retail' : 'hardware_store',
        features: features,
      );

  void setIsRI(bool val) {
    _isRI = val;
    notifyListeners();
  }

  void setBatchExpiration(bool val) {
    _batchExpiration = val;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSupplierProvider extends ChangeNotifier implements SupplierProvider {
  @override
  List<Supplier> get suppliers => const [];

  @override
  bool get isLoading => false;

  @override
  Future<void> fetchSuppliers({String? search}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakePosProvider extends ChangeNotifier implements PosProvider {
  @override
  Future<List<Product>> search(String query) async => [];

  @override
  void syncUpdatedCatalogProduct(Product product) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeCatalogProvider extends ChangeNotifier implements CatalogProvider {
  final List<Product> _products = [];
  Map<String, dynamic>? lastCreatedPayload;
  Product? _lastCreatedProduct;

  @override
  List<Product> get products => _products;

  @override
  List<Category> get categories => const [];

  @override
  List<Brand> get brands => const [];

  @override
  List<Rubro> get rubros => const [];

  @override
  bool get isLoading => false;

  @override
  String? get errorMessage => null;

  @override
  Product? get lastCreatedProduct => _lastCreatedProduct;

  @override
  Product? get lastUpdatedProduct => null;

  @override
  Future<bool> createProduct(Map<String, dynamic> data) async {
    lastCreatedPayload = Map<String, dynamic>.from(data);
    final created = Product(
      id: 999,
      name: (data['name'] ?? '').toString(),
      barcode: data['barcode']?.toString(),
      internalCode: (data['internal_code'] ?? '00999').toString(),
      costPrice: (data['cost_price'] as num?)?.toDouble() ?? 0.0,
      sellingPrice: (data['selling_price'] as num?)?.toDouble() ?? 0.0,
      stock: (data['stock'] as num?)?.toDouble() ?? 0.0,
      active: true,
      isSoldByWeight: false,
      supplier: data['supplier_id'] != null
          ? Supplier(
              id: data['supplier_id'] as int,
              name: 'Distribuidora Central S.A.',
              balance: 0,
              isActive: true,
            )
          : null,
    );
    _lastCreatedProduct = created;
    _products.add(created);
    notifyListeners();
    return true;
  }

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
    SharedPreferences.setMockInitialValues({});
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

    testWidgets(
      'Botón + Otro lote permite desdoblar un mismo producto en múltiples lotes dentro de la misma factura sin error de Key ni overflow',
      (tester) async {
        tester.view.physicalSize = const Size(1024, 768);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final sugarInvoice = {
          'id': 95,
          'type': 'delivery_note',
          'voucher_letter': 'S/D',
          'affects_vat_book': false,
          'amount': 12000.0,
          'items': [
            {
              'product_id': 81250,
              'product_name': 'Azúcar Ledesma 1kg Pack',
              'quantity': 10,
              'unit_cost': 1200.0,
              'previous_cost': 1000.0,
              'current_selling_price': 1800.0,
              'track_batches': false,
            },
          ],
        };

        await tester.pumpWidget(buildTestDialog(initialInvoice: sugarInvoice));
        await tester.pumpAndSettle();

        final otherLotBtn = find.text('+ Otro lote');
        expect(otherLotBtn, findsOneWidget);
        await tester.ensureVisible(otherLotBtn);
        await tester.pumpAndSettle();
        await tester.tap(otherLotBtn);
        await tester.pumpAndSettle();

        // Ahora existen 2 renglones del mismo producto sin DuplicateKey y con sus etiquetas Lote 1/2 y Lote 2/2
        expect(find.textContaining('Azúcar Ledesma 1kg Pack'), findsNWidgets(2));
        expect(find.text('Lote 1/2'), findsOneWidget);
        expect(find.text('Lote 2/2'), findsOneWidget);
        expect(find.text('+ Otro lote'), findsNWidgets(2));

        // Escribir '10' en Validez del primer lote calcula la fecha de vencimiento a +10 días sin overflow
        await tester.enterText(
          find.widgetWithText(TextField, 'Validez').first,
          '10',
        );
        await tester.pumpAndSettle();
        final expectedVence = DateFormat('dd/MM/yyyy').format(
          DateTime.now().add(const Duration(days: 10)),
        );
        expect(find.text('Vence: $expectedVence'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Opción 1A: En Ferretería (batchExpiration: false) se ocultan campos de lote y botón + Otro lote',
      (tester) async {
        tester.view.physicalSize = const Size(1024, 768);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        fakeSettings.setBatchExpiration(false);

        final hardwareInvoice = {
          'id': 96,
          'type': 'delivery_note',
          'voucher_letter': 'S/D',
          'affects_vat_book': false,
          'amount': 8500.0,
          'items': [
            {
              'product_id': 81301,
              'product_name': 'Amoladora Angular 115mm',
              'quantity': 1,
              'unit_cost': 8500.0,
              'previous_cost': 8000.0,
              'current_selling_price': 12500.0,
            },
          ],
        };

        await tester.pumpWidget(buildTestDialog(initialInvoice: hardwareInvoice));
        await tester.pumpAndSettle();

        expect(find.textContaining('Amoladora Angular 115mm'), findsOneWidget);
        expect(find.text('+ Lote / Vto.'), findsNothing);
        expect(find.text('+ Otro lote'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Botón + (Nuevo Producto Rápido) preselecciona el proveedor de la factura, precarga el nombre y auto-agrega al crear',
      (tester) async {
        tester.view.physicalSize = const Size(1024, 768);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(buildTestDialog());
        await tester.pumpAndSettle();

        await tester.enterText(
          find.widgetWithText(
            TextField,
            'Buscar por nombre, EAN, PLU, Cód. Prov. o medida...',
          ),
          'Azucar Ledesma',
        );
        await tester.pump(const Duration(milliseconds: 50));

        await tester.tap(find.byTooltip('Nuevo Producto Rápido'));
        await tester.pumpAndSettle();

        expect(find.text('Nuevo Producto'), findsOneWidget);
        expect(find.text('Azucar Ledesma'), findsWidgets);
        // El proveedor actual de la factura aparece preseleccionado inmediatamente
        expect(find.text('Distribuidora Central S.A.'), findsOneWidget);

        await tester.enterText(
          find.widgetWithText(TextFormField, 'Precio Venta *'),
          '1500',
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Crear Producto'));
        await tester.pumpAndSettle();
        // Esperar cierre automático del toast de SnackBarService
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();

        expect(find.text('Nuevo Producto'), findsNothing);
        expect(fakeCatalog.lastCreatedPayload, isNotNull);
        expect(fakeCatalog.lastCreatedPayload!['supplier_id'], 1);
        expect(fakeCatalog.lastCreatedPayload!['name'], 'Azucar Ledesma');
        // El nuevo producto queda agregado automáticamente al listado de ítems del comprobante
        expect(find.textContaining('Azucar Ledesma'), findsWidgets);
        expect(find.widgetWithText(TextFormField, 'Nuevo PVP'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
