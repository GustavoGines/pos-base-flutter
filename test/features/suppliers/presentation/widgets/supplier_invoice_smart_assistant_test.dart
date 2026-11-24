import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend_desktop/core/network/api_client.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/brand.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/category.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/rubro.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/features/catalog/presentation/widgets/supplier_quick_grid_dialog.dart';
import 'package:frontend_desktop/features/pos/presentation/providers/pos_provider.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/features/suppliers/models/supplier_model.dart';
import 'package:frontend_desktop/features/suppliers/presentation/widgets/supplier_invoice_form_dialog.dart';
import 'package:frontend_desktop/features/suppliers/providers/supplier_provider.dart';

class _FakeSettingsProvider extends ChangeNotifier implements SettingsProvider {
  bool _isRI = false;
  bool _batchExpiration = false;

  @override
  bool get isResponsableInscripto => _isRI;

  @override
  FeatureFlags get features => FeatureFlags(
        suppliers: true,
        batchExpiration: _batchExpiration,
      );

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

class _FakeSupplierProvider extends ChangeNotifier implements SupplierProvider {
  Map<String, dynamic>? lastInvoicePayload;
  int? lastInvoiceSupplierId;
  final List<Supplier> _suppliers = [
    Supplier(
      id: 1,
      name: 'Ferretería Industrial S.A.',
      balance: 0,
      isActive: true,
    ),
    Supplier(
      id: 2,
      name: 'Pinturería Norte S.R.L.',
      balance: 0,
      isActive: true,
    ),
  ];

  @override
  String get baseUrl => 'http://localhost:8000/api';

  @override
  List<Supplier> get suppliers => _suppliers;

  @override
  bool get isLoading => false;

  @override
  Future<void> fetchSuppliers({String? search}) async {}

  @override
  Future<bool> createInvoice(int supplierId, Map<String, dynamic> data) async {
    lastInvoiceSupplierId = supplierId;
    lastInvoicePayload = Map<String, dynamic>.from(data);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePosProvider extends ChangeNotifier implements PosProvider {
  List<Product> catalog = [];
  final List<String> searchedQueries = [];

  @override
  Future<List<Product>> search(String query) async {
    searchedQueries.add(query);
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];
    return catalog.where((p) {
      return p.name.toLowerCase().contains(q) ||
          p.internalCode.toLowerCase().contains(q) ||
          (p.barcode?.toLowerCase().contains(q) ?? false) ||
          (p.supplierSku?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  @override
  void syncUpdatedCatalogProduct(Product product) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCatalogProvider extends ChangeNotifier implements CatalogProvider {
  List<Product> _products = [];
  List<Product> remoteCatalog = [];

  void setProducts(List<Product> items) {
    _products = items;
    remoteCatalog = items;
    notifyListeners();
  }

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
  Future<void> setSupplierFilter(
    int? supplierId, {
    bool reload = true,
    String? supplierName,
  }) async {}

  @override
  Future<void> loadProducts({
    int page = 1,
    String? search,
    String? sortBy,
    String? sortDirection,
    int? perPage,
  }) async {}

  @override
  Future<void> loadMetadata({bool force = false}) async {}

  @override
  Future<void> loadRubros() async {}

  @override
  Future<void> loadBrands() async {}

  @override
  Future<List<Product>> searchProductsRemote(
    String query, {
    int perPage = 25,
    bool activeOnly = true,
  }) async {
    final q = query.trim().toLowerCase();
    return remoteCatalog.where((p) {
      return p.name.toLowerCase().contains(q) ||
          p.internalCode.toLowerCase().contains(q) ||
          (p.barcode?.toLowerCase().contains(q) ?? false) ||
          (p.supplierSku?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeApiClient implements ApiClient {
  Map<int, Map<String, dynamic>> assistantResponsesBySupplier = {};

  @override
  Future<http.Response> get(Uri url, {Map<String, String>? headers}) async {
    final match = RegExp(r'/suppliers/(\d+)/purchase-assistant').firstMatch(
      url.path,
    );
    if (match != null) {
      final supplierId = int.parse(match.group(1)!);
      final body = assistantResponsesBySupplier[supplierId] ??
          {
            'low_stock_products': [],
            'frequent_products': [],
            'catalog_products': [],
            'last_invoice': null,
          };
      return http.Response(json.encode(body), 200);
    }
    return http.Response('{}', 404);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> _productJson({
  required int id,
  required String name,
  String internalCode = '00001',
  double costPrice = 1000,
  double sellingPrice = 1500,
  double stock = 10,
  double? minStock = 5,
  int? supplierId = 1,
  String? purchasePackageName,
  double? conversionFactor,
  String? supplierSku,
  double? lastUnitCost,
  double? lastQuantity,
  int timesBought = 0,
}) {
  return {
    'id': id,
    'name': name,
    'internal_code': internalCode,
    'cost_price': costPrice,
    'selling_price': sellingPrice,
    'stock': stock,
    'min_stock': minStock,
    'active': true,
    'is_sold_by_weight': false,
    'unit_type': 'un',
    'supplier_id': supplierId,
    'supplier_sku': supplierSku,
    'purchase_package_name': purchasePackageName,
    'conversion_factor': conversionFactor,
    'times_bought': timesBought,
    if (lastUnitCost != null) 'last_unit_cost': lastUnitCost,
    if (lastQuantity != null) 'last_quantity': lastQuantity,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeSettingsProvider fakeSettings;
  late _FakeSupplierProvider fakeSupplier;
  late _FakePosProvider fakePos;
  late _FakeCatalogProvider fakeCatalog;
  late _FakeApiClient fakeApi;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    fakeSettings = _FakeSettingsProvider();
    fakeSupplier = _FakeSupplierProvider();
    fakePos = _FakePosProvider();
    fakeCatalog = _FakeCatalogProvider();
    fakeApi = _FakeApiClient();
  });

  Widget buildDialog({
    Key? dialogKey,
    int supplierId = 1,
    String supplierName = 'Ferretería Industrial S.A.',
    Map<String, dynamic>? initialInvoice,
  }) {
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
              key: dialogKey,
              supplierId: supplierId,
              supplierName: supplierName,
              initialInvoice: initialInvoice,
            ),
          ),
        ),
      ),
    );
  }

  group('SupplierInvoiceFormDialog Smart Assistant Tests', () {
    testWidgets(
      'Historial de búsquedas queda aislado por proveedor, dispara búsqueda al tocar chip y permite eliminarlo',
      (tester) async {
        tester.view.physicalSize = const Size(1024, 768);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final prodA = Product(
          id: 10,
          name: 'Tornillo Fix 5x50',
          internalCode: '00010',
          costPrice: 100,
          sellingPrice: 180,
          stock: 100,
          active: true,
          isSoldByWeight: false,
        );
        final prodB = Product(
          id: 11,
          name: 'Tornillo Fix 6x80',
          internalCode: '00011',
          costPrice: 120,
          sellingPrice: 210,
          stock: 80,
          active: true,
          isSoldByWeight: false,
        );
        fakePos.catalog = [prodA, prodB];
        fakeCatalog.setProducts([prodA, prodB]);

        await tester.pumpWidget(buildDialog(supplierId: 1));
        await tester.pumpAndSettle();

        final searchField =
            find.byKey(const ValueKey('supplier_invoice_search_field'));
        await tester.enterText(searchField, 'Tornillo');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        // Quitar dropdown seleccionando el primer resultado para limpiar la caja de búsqueda
        await tester.tap(find.text('Tornillo Fix 5x50').first);
        await tester.pumpAndSettle();

        final chipFinder = find.byKey(const ValueKey('recent_search_chip_1_Tornillo'));
        expect(chipFinder, findsOneWidget);

        // Tocar el chip vuelve a disparar la búsqueda de 'Tornillo'
        fakePos.searchedQueries.clear();
        await tester.tap(chipFinder);
        await tester.pumpAndSettle();
        expect(fakePos.searchedQueries, contains('Tornillo'));

        // Limpiar búsqueda para volver a ver los chips y probar eliminación
        await tester.tap(find.text('Tornillo Fix 6x80').first);
        await tester.pumpAndSettle();
        final chipWidget = tester.widget<InputChip>(chipFinder);
        chipWidget.onDeleted?.call();
        await tester.pumpAndSettle();
        expect(chipFinder, findsNothing);

        // Grabar búsqueda para proveedor 1 y abrir proveedor 2: no debe filtrarse
        await tester.enterText(searchField, 'Amoladora');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();

        await tester.pumpWidget(
          buildDialog(supplierId: 2, supplierName: 'Pinturería Norte S.R.L.'),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('recent_search_chip_1_Amoladora')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('recent_search_chip_2_Amoladora')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Panel Asistente de Compras: 3 pestañas, Agregar todos los faltantes y Traer última compra',
      (tester) async {
        tester.view.physicalSize = const Size(1024, 768);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        fakeApi.assistantResponsesBySupplier[1] = {
          'low_stock_products': [
            _productJson(
              id: 21,
              name: 'Disco de Corte 115mm',
              internalCode: '00021',
              stock: 2,
              minStock: 10,
              costPrice: 900,
              sellingPrice: 1500,
            ),
            _productJson(
              id: 22,
              name: 'Electrodo 6013 2.5mm',
              internalCode: '00022',
              stock: 0,
              minStock: 5,
              costPrice: 3500,
              sellingPrice: 5200,
            ),
          ],
          'frequent_products': [
            _productJson(
              id: 23,
              name: 'Cinta Aisladora Negra',
              internalCode: '00023',
              stock: 25,
              minStock: 5,
              costPrice: 700,
              sellingPrice: 1200,
              timesBought: 7,
              lastUnitCost: 750,
            ),
          ],
          'catalog_products': [
            _productJson(
              id: 21,
              name: 'Disco de Corte 115mm',
              internalCode: '00021',
              stock: 2,
              minStock: 10,
            ),
            _productJson(
              id: 22,
              name: 'Electrodo 6013 2.5mm',
              internalCode: '00022',
              stock: 0,
              minStock: 5,
            ),
            _productJson(
              id: 23,
              name: 'Cinta Aisladora Negra',
              internalCode: '00023',
              stock: 25,
              minStock: 5,
            ),
          ],
          'last_invoice': {
            'id': 50,
            'invoice_number': 'FC-A-0001-00000123',
            'issue_date': '2026-11-20',
            'items': [
              {
                'quantity': 4,
                'unit_cost': 950,
                'product': _productJson(
                  id: 21,
                  name: 'Disco de Corte 115mm',
                  internalCode: '00021',
                  costPrice: 900,
                  sellingPrice: 1500,
                ),
              },
            ],
          },
        };

        await tester.pumpWidget(buildDialog(supplierId: 1));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('assistant_tab_low_stock')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('assistant_tab_frequent')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('assistant_tab_catalog')),
          findsOneWidget,
        );
        expect(find.text('Disco de Corte 115mm'), findsOneWidget);
        expect(find.text('Electrodo 6013 2.5mm'), findsOneWidget);

        // Cambiar a Comprados antes
        await tester.tap(find.byKey(const ValueKey('assistant_tab_frequent')));
        await tester.pumpAndSettle();
        expect(find.text('Cinta Aisladora Negra'), findsOneWidget);
        expect(find.textContaining('7x comprado'), findsOneWidget);

        // Volver a Faltantes y pulsar Agregar todos los faltantes
        await tester.tap(find.byKey(const ValueKey('assistant_tab_low_stock')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('assistant_add_all_low_stock_btn')),
        );
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 4));

        // Ambos productos agregados al comprobante y el panel colapsado puede reabrirse
        expect(find.textContaining('Disco de Corte 115mm'), findsWidgets);
        expect(find.textContaining('Electrodo 6013 2.5mm'), findsWidgets);
        expect(
          find.byKey(const ValueKey('toggle_supplier_assistant_btn')),
          findsOneWidget,
        );

        // Abrir el asistente y usar "Traer última compra" con diálogo de suma/reemplazo
        await tester.tap(
          find.byKey(const ValueKey('toggle_supplier_assistant_btn')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('assistant_clone_last_invoice_btn')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Reemplazar lista'));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 4));

        expect(find.textContaining('Disco de Corte 115mm'), findsWidgets);
        expect(find.textContaining('Electrodo 6013 2.5mm'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Onboarding de proveedor nuevo sin catálogo abre SupplierQuickGridDialog',
      (tester) async {
        tester.view.physicalSize = const Size(1024, 768);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(buildDialog(supplierId: 1));
        await tester.pumpAndSettle();

        final quickGridBtn =
            find.byKey(const ValueKey('assistant_open_quick_grid_btn'));
        final newProdBtn =
            find.byKey(const ValueKey('assistant_new_product_btn'));
        expect(quickGridBtn, findsOneWidget);
        expect(newProdBtn, findsOneWidget);

        await tester.tap(quickGridBtn);
        await tester.pumpAndSettle();

        expect(find.byType(SupplierQuickGridDialog), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Auto-Bulto en alta + Alerta +150% con botón "Pasar a Por Caja" calcula bien el subtotal (sin 256M) y conserva modo unidad al editar',
      (tester) async {
        tester.view.physicalSize = const Size(1024, 768);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final packageProduct = Product(
          id: 101,
          name: 'Tornillo Autoperforante 8x1',
          internalCode: '00101',
          costPrice: 6400,
          sellingPrice: 9800,
          stock: 320,
          active: true,
          isSoldByWeight: false,
          unitType: 'un',
          purchasePackageName: 'Caja',
          conversionFactor: 200,
          supplier: Supplier(
            id: 1,
            name: 'Ferretería Industrial S.A.',
            balance: 0,
            isActive: true,
          ),
        );

        fakePos.catalog = [packageProduct];
        fakeCatalog.setProducts([packageProduct]);

        await tester.pumpWidget(buildDialog(supplierId: 1));
        await tester.pumpAndSettle();

        final searchField =
            find.byKey(const ValueKey('supplier_invoice_search_field'));
        await tester.enterText(searchField, 'Tornillo Autoperforante');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        // Debe arrancar automáticamente en "Por Caja (x200 un.)" con 1 Caja y Costo x Caja $1.280.000
        final pkgChipFinder =
            find.byKey(const ValueKey('invoice_item_pkg_mode_101_0'));
        final unitChipFinder =
            find.byKey(const ValueKey('invoice_item_unit_mode_101_0'));
        expect(pkgChipFinder, findsOneWidget);
        expect(tester.widget<ChoiceChip>(pkgChipFinder).selected, isTrue);

        final qtyField = tester.widget<TextFormField>(
          find.byKey(const ValueKey('invoice_item_qty_101_0')),
        );
        final costField = tester.widget<TextFormField>(
          find.byKey(const ValueKey('invoice_item_cost_101_0')),
        );
        expect(qtyField.controller?.text, '1');
        expect(costField.controller?.text, '1.280.000');

        // Simular que el usuario cambia a "Por Unidad" y tipea 1 unidad a $1.280.000 por error
        await tester.tap(unitChipFinder);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('invoice_item_qty_101_0')),
          '1',
        );
        await tester.enterText(
          find.byKey(const ValueKey('invoice_item_cost_101_0')),
          '1280000',
        );
        await tester.pumpAndSettle();

        // Debe aparecer la alerta +150% con acción "Pasar a Por Caja"
        final warningFinder =
            find.byKey(const ValueKey('cost_spike_warning_101_0'));
        final convertBtnFinder =
            find.byKey(const ValueKey('switch_spike_to_pkg_101_0'));
        expect(warningFinder, findsOneWidget);
        expect(convertBtnFinder, findsOneWidget);

        await tester.tap(convertBtnFinder);
        await tester.pumpAndSettle();

        // Al pasar a Por Caja: entra 1 Caja (= 200 un.), costo bulto $1.280.000, costo unit. $6.400, subtotal $1.280.000
        expect(warningFinder, findsNothing);
        expect(tester.widget<ChoiceChip>(pkgChipFinder).selected, isTrue);
        expect(
          tester
              .widget<TextFormField>(
                find.byKey(const ValueKey('invoice_item_qty_101_0')),
              )
              .controller
              ?.text,
          '1',
        );
        expect(
          tester
              .widget<TextFormField>(
                find.byKey(const ValueKey('invoice_item_cost_101_0')),
              )
              .controller
              ?.text,
          '1.280.000',
        );
        expect(find.textContaining('Entran +200 un. al stock'), findsOneWidget);
        expect(find.text('\$1.280.000'), findsWidgets);

        // En modo edición (initialInvoice) no debe convertir automáticamente las unidades ya guardadas
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await tester.pumpWidget(
          buildDialog(
            dialogKey: const ValueKey('edit_mode_dialog'),
            supplierId: 1,
            initialInvoice: {
              'id': 77,
              'type': 'delivery_note',
              'voucher_letter': 'S/D',
              'affects_vat_book': false,
              'amount': 64000.0,
              'items': [
                {
                  'product_id': 101,
                  'product_name': 'Tornillo Autoperforante 8x1',
                  'quantity': 10,
                  'unit_cost': 6400.0,
                  'previous_cost': 6400.0,
                  'current_selling_price': 9800.0,
                  'purchase_package_name': 'Caja',
                  'conversion_factor': 200,
                },
              ],
            },
          ),
        );
        await tester.pumpAndSettle();

        expect(
          tester
              .widget<ChoiceChip>(
                find.byKey(const ValueKey('invoice_item_unit_mode_101_0')),
              )
              .selected,
          isTrue,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Chip controlado link_supplier en payload + Atajo F2 enfoca el buscador sin overflow en 800x600',
      (tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final orphanProduct = Product(
          id: 201,
          name: 'Llave Combinada 13mm',
          internalCode: '00201',
          costPrice: 4000,
          sellingPrice: 6500,
          stock: 5,
          active: true,
          isSoldByWeight: false,
          supplier: null,
        );
        final otherSupplierProduct = Product(
          id: 202,
          name: 'Pinza Universal 8"',
          internalCode: '00202',
          costPrice: 5500,
          sellingPrice: 8900,
          stock: 3,
          active: true,
          isSoldByWeight: false,
          supplier: Supplier(
            id: 99,
            name: 'Otro Proveedor',
            balance: 0,
            isActive: true,
          ),
        );

        fakePos.catalog = [orphanProduct, otherSupplierProduct];
        fakeCatalog.setProducts([orphanProduct, otherSupplierProduct]);

        await tester.pumpWidget(buildDialog(supplierId: 1));
        await tester.pumpAndSettle();

        // Foco en otro campo, luego presionar F2 debe devolver foco al buscador
        final conceptField = find.widgetWithText(TextFormField, 'Concepto');
        await tester.ensureVisible(conceptField.first);
        await tester.tap(conceptField.first);
        await tester.pumpAndSettle();

        await tester.sendKeyEvent(LogicalKeyboardKey.f2);
        await tester.pumpAndSettle();
        final searchFieldWidget = tester.widget<TextField>(
          find.byKey(const ValueKey('supplier_invoice_search_field')),
        );
        expect(searchFieldWidget.focusNode?.hasFocus, isTrue);

        // Agregar producto huérfano (entra en index 0) y producto de otro proveedor (entra arriba -> desplaza al huérfano a index 1)
        await tester.enterText(
          find.byKey(const ValueKey('supplier_invoice_search_field')),
          'Llave Combinada 13mm',
        );
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey('supplier_invoice_search_field')),
          'Pinza Universal 8"',
        );
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        final otherChip =
            find.byKey(const ValueKey('link_supplier_chip_202_0'));
        final orphanChip =
            find.byKey(const ValueKey('link_supplier_chip_201_1'));
        expect(otherChip, findsOneWidget);
        expect(orphanChip, findsOneWidget);
        expect(tester.widget<FilterChip>(orphanChip).selected, isTrue);
        expect(tester.widget<FilterChip>(otherChip).selected, isFalse);

        // Invertir ambos chips: no vincular el huérfano y reasignar el de otro proveedor
        await tester.ensureVisible(otherChip);
        await tester.tap(otherChip);
        await tester.pumpAndSettle();
        await tester.ensureVisible(orphanChip);
        await tester.tap(orphanChip);
        await tester.pumpAndSettle();

        // Desactivar "Abonar en el acto" para ir directo a guardar
        final payNowCheckbox = find.byType(CheckboxListTile);
        if (payNowCheckbox.evaluate().isNotEmpty) {
          await tester.ensureVisible(payNowCheckbox.first);
          await tester.tap(payNowCheckbox.first);
          await tester.pumpAndSettle();
        }

        final confirmBtn = find.text('CONFIRMAR CARGA');
        await tester.ensureVisible(confirmBtn);
        await tester.tap(confirmBtn);
        await tester.pumpAndSettle();

        expect(fakeSupplier.lastInvoicePayload, isNotNull);
        final submittedItems =
            List<Map<String, dynamic>>.from(fakeSupplier.lastInvoicePayload!['items'] as List);
        final pinzaItem =
            submittedItems.firstWhere((e) => e['product_id'] == 202);
        final llaveItem =
            submittedItems.firstWhere((e) => e['product_id'] == 201);
        expect(pinzaItem['link_supplier'], isTrue);
        expect(llaveItem['link_supplier'], isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
