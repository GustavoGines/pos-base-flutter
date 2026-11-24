import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend_desktop/core/network/api_client.dart';
import 'package:frontend_desktop/core/presentation/widgets/searchable_select_field.dart';
import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import 'package:frontend_desktop/features/auth/presentation/providers/auth_provider.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/brand.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/category.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/rubro.dart';
import 'package:frontend_desktop/features/catalog/domain/repositories/catalog_repository.dart';
import 'package:frontend_desktop/features/catalog/domain/usecases/get_products_usecase.dart';
import 'package:frontend_desktop/features/catalog/presentation/pages/catalog_screen.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/features/reports/presentation/providers/inventory_alerts_provider.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/features/suppliers/models/supplier_model.dart';
import 'package:frontend_desktop/features/suppliers/providers/supplier_provider.dart';

class _TestCatalogRepository implements CatalogRepository {
  List<Category> remoteCategories = [];
  List<Brand> remoteBrands = [];
  List<Rubro> remoteRubros = [];
  Map<String, dynamic>? lastSubmittedProductData;
  int? lastBulkPriceCategoryId;
  int? lastBulkPriceBrandId;
  int? lastBulkPriceSupplierId;
  double? lastBulkPricePercentage;
  int _nextId = 100;

  @override
  Future<List<Category>> getCategories() async => List.of(remoteCategories);

  @override
  Future<List<Brand>> getBrands() async => List.of(remoteBrands);

  @override
  Future<List<Rubro>> getRubros() async => List.of(remoteRubros);

  @override
  Future<Category> createCategory(String name, {String? description, int? rubroId}) async {
    return Category(id: _nextId++, name: name, description: description, rubroId: rubroId);
  }

  @override
  Future<Category> updateCategory(int id, String name, {String? description, int? rubroId}) async {
    return Category(id: id, name: name, description: description, rubroId: rubroId);
  }

  @override
  Future<Brand> createBrand(String name, {String? description}) async {
    return Brand(id: _nextId++, name: name, description: description);
  }

  @override
  Future<Brand> updateBrand(int id, String name, {String? description}) async {
    return Brand(id: id, name: name, description: description);
  }

  @override
  Future<Rubro> createRubro(String name, {String? description, String? verticalType}) async {
    return Rubro(
      id: _nextId++,
      name: name,
      description: description,
      verticalType: verticalType,
      isSystem: false,
    );
  }

  @override
  Future<Rubro> updateRubro(int id, String name, {String? description, String? verticalType}) async {
    return Rubro(
      id: id,
      name: name,
      description: description,
      verticalType: verticalType,
      isSystem: false,
    );
  }

  @override
  Future<Product> createProduct(Map<String, dynamic> productData) async {
    lastSubmittedProductData = Map<String, dynamic>.from(productData);
    return Product(
      id: 900,
      name: (productData['name'] ?? 'Item').toString(),
      internalCode: (productData['internal_code'] ?? '00900').toString(),
      costPrice: (productData['cost_price'] as num?)?.toDouble() ?? 0.0,
      sellingPrice: (productData['selling_price'] as num?)?.toDouble() ?? 100.0,
      stock: 0.0,
      active: true,
      isSoldByWeight: false,
      isService: productData['is_service'] == true,
      isCombo: productData['is_combo'] == true,
    );
  }

  @override
  Future<Map<String, dynamic>> bulkPricePreview({
    required double percentage,
    required String roundingRule,
    String? targetField,
    List<int>? productIds,
    int? categoryId,
    int? brandId,
    int? supplierId,
  }) async {
    return {
      'affected_count': 4,
      'examples': [
        {'name': 'Ejemplo A', 'old_price': 1000, 'new_price': 1150},
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> bulkPriceUpdate({
    required double percentage,
    required String roundingRule,
    String? targetField,
    List<int>? productIds,
    int? categoryId,
    int? brandId,
    int? supplierId,
  }) async {
    lastBulkPricePercentage = percentage;
    lastBulkPriceCategoryId = categoryId;
    lastBulkPriceBrandId = brandId;
    lastBulkPriceSupplierId = supplierId;
    return {'message': '4 productos actualizados.'};
  }

  @override
  Future<Map<String, dynamic>> getProducts({
    int page = 1,
    String? search,
    String? sortBy,
    String? sortDirection,
    int? perPage,
    int? categoryId,
    int? brandId,
    int? supplierId,
    bool? active,
  }) async {
    return {'data': <Product>[], 'current_page': 1, 'last_page': 1};
  }

  @override
  Future<List<Product>> fetchCriticalAlerts() async => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeApiClient extends http.BaseClient implements ApiClient {
  final http.Response Function(Uri url) onGet;

  _FakeApiClient({required this.onGet});

  @override
  Future<http.Response> get(Uri url, {Map<String, String>? headers}) async =>
      onGet(url);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    throw UnimplementedError();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestSettingsProvider extends ChangeNotifier implements SettingsProvider {
  final BusinessSettings _settings;

  _TestSettingsProvider({required BusinessSettings settings})
      : _settings = settings;

  @override
  BusinessSettings? get settings => _settings;

  @override
  String get currentPlan => _settings.licensePlanType ?? 'premium';

  @override
  FeatureFlags get features => _settings.features;

  @override
  bool hasFeature(String featureName) => _settings.hasFeature(featureName);

  @override
  int get assignedRegisterId => 1;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestSupplierProvider extends ChangeNotifier implements SupplierProvider {
  final List<Supplier> _list;

  _TestSupplierProvider(this._list);

  @override
  List<Supplier> get suppliers => _list;

  @override
  bool get isLoading => false;

  @override
  Future<void> fetchSuppliers({String? search}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestAuthProvider extends ChangeNotifier implements AuthProvider {
  @override
  Map<String, dynamic>? get currentUser =>
      {'id': 1, 'name': 'Admin', 'role': 'admin'};

  @override
  bool get isAdmin => true;

  @override
  bool hasPermission(String permission) => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestLocalTerminalProvider extends ChangeNotifier
    implements LocalTerminalProvider {
  @override
  String get scaleComPort => '';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestAlertsProvider extends ChangeNotifier
    implements InventoryAlertsProvider {
  @override
  List<dynamic> get alerts => [];

  @override
  Future<void> fetchAlerts({int threshold = 3}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'disable_pusher': true});
  });

  group('Ordenamiento alfabético defensivo A->Z en Providers', () {
    test('CatalogProvider ordena categorías, marcas y rubros A->Z ignorando tildes al cargar, crear y editar', () async {
      final repo = _TestCatalogRepository()
        ..remoteCategories = [
          Category(id: 1, name: 'Perfumería'),
          Category(id: 2, name: 'Árboles'),
          Category(id: 3, name: 'Almacén Seco'),
          Category(id: 4, name: 'Bebidas'),
        ]
        ..remoteBrands = [
          Brand(id: 1, name: 'Xiaomi'),
          Brand(id: 2, name: 'Bambu Lab'),
          Brand(id: 3, name: 'Stanley'),
        ]
        ..remoteRubros = [
          Rubro(id: 1, name: 'Tecnología'),
          Rubro(id: 2, name: 'Alimentos'),
        ];

      final provider = CatalogProvider(
        getProductsUseCase: GetProductsUseCase(repo),
        repository: repo,
      );

      await provider.loadMetadata();
      expect(
        provider.categories.map((c) => c.name).toList(),
        ['Almacén Seco', 'Árboles', 'Bebidas', 'Perfumería'],
      );
      expect(
        provider.brands.map((b) => b.name).toList(),
        ['Bambu Lab', 'Stanley', 'Xiaomi'],
      );
      expect(
        provider.rubros.map((r) => r.name).toList(),
        ['Alimentos', 'Tecnología'],
      );

      await provider.createCategory('Carnicería');
      expect(
        provider.categories.map((c) => c.name).toList(),
        ['Almacén Seco', 'Árboles', 'Bebidas', 'Carnicería', 'Perfumería'],
      );

      await provider.updateBrand(1, 'Arcor');
      expect(
        provider.brands.map((b) => b.name).toList(),
        ['Arcor', 'Bambu Lab', 'Stanley'],
      );
    });

    test('SupplierProvider ordena proveedores A->Z al obtener desde API', () async {
      final client = _FakeApiClient(
        onGet: (_) => http.Response(
          json.encode([
            {'id': 1, 'name': 'Stanley Importaciones', 'balance': 0, 'is_active': true},
            {'id': 2, 'name': 'Distribuidora Norte', 'balance': 0, 'is_active': true},
            {'id': 3, 'name': '180 Pastelería', 'balance': 0, 'is_active': true},
          ]),
          200,
        ),
      );
      final supplierProvider =
          SupplierProvider(baseUrl: 'http://localhost/api', client: client);

      await supplierProvider.fetchSuppliers();
      expect(
        supplierProvider.suppliers.map((s) => s.name).toList(),
        ['180 Pastelería', 'Distribuidora Norte', 'Stanley Importaciones'],
      );
    });
  });

  group('Widget SearchableSelectField', () {
    testWidgets('Ordena A->Z, busca sin tildes ni mayúsculas, busca por keyword de rubro, limpia con X y permite crear', (tester) async {
      int? selectedValue;
      String? createRequestedWith;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => Padding(
                padding: const EdgeInsets.all(16),
                child: SearchableSelectField<int?>(
                  value: selectedValue,
                  clearValue: null,
                  labelText: 'Categoría',
                  prefixIcon: Icons.category_outlined,
                  options: const [
                    SearchableSelectOption<int?>(
                      value: null,
                      label: '— Sin categoría —',
                      isResetOption: true,
                    ),
                    SearchableSelectOption<int?>(
                      value: 1,
                      label: 'Lácteos',
                      subtitle: 'Rubro: Alimentos',
                      searchKeywords: ['Alimentos'],
                    ),
                    SearchableSelectOption<int?>(
                      value: 2,
                      label: 'Bebidas',
                      subtitle: 'Rubro: Quiosco',
                      searchKeywords: ['Quiosco'],
                    ),
                  ],
                  onChanged: (v) => setState(() => selectedValue = v),
                  onCreateNew: (q) async {
                    createRequestedWith = q;
                  },
                ),
              ),
            ),
          ),
        ),
      );

      // Abrir picker
      await tester.tap(find.byType(SearchableSelectField<int?>));
      await tester.pumpAndSettle();

      // Orden A->Z (Bebidas antes que Lácteos) tras opción reset
      final bebidasY = tester.getTopLeft(find.text('Bebidas')).dy;
      final lacteosY = tester.getTopLeft(find.text('Lácteos')).dy;
      expect(bebidasY, lessThan(lacteosY));

      // Buscar sin tilde ("lacteos") -> filtra a Lácteos
      await tester.enterText(find.byType(TextField), 'lacteos');
      await tester.pumpAndSettle();
      expect(find.text('Lácteos'), findsOneWidget);
      expect(find.text('Bebidas'), findsNothing);

      // Buscar por rubro keyword ("alimentos") -> sigue encontrando Lácteos
      await tester.enterText(find.byType(TextField), 'alimentos');
      await tester.pumpAndSettle();
      expect(find.text('Lácteos'), findsOneWidget);

      // Tapping selecciona Lácteos
      await tester.tap(find.text('Lácteos'));
      await tester.pumpAndSettle();
      expect(selectedValue, 1);

      // Limpieza rápida con botón X (clear_rounded)
      await tester.tap(find.byIcon(Icons.clear_rounded));
      await tester.pumpAndSettle();
      expect(selectedValue, isNull);

      // Opción "+ Crear ..." cuando consulta no existe
      await tester.tap(find.byType(SearchableSelectField<int?>));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Pastelería');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Crear "Pastelería"'));
      await tester.pumpAndSettle();
      expect(createRequestedWith, 'Pastelería');
    });

    testWidgets('No produce overflow en viewport compacto 320x480 al abrir el buscador', (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SearchableSelectField<int?>(
              value: null,
              labelText: 'Categoría',
              options: List.generate(
                30,
                (i) => SearchableSelectOption<int?>(
                  value: i + 1,
                  label: 'Categoría Larga Número ${i + 1}',
                  subtitle: 'Rubro: Comercio General',
                ),
              ),
              onChanged: (_) {},
            ),
          ),
        ),
      );

      await tester.tap(find.byType(SearchableSelectField<int?>));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('ProductFormDialog y BulkPriceUpdateDialog con selectores buscables A->Z', () {
    Widget wrapCatalogDialog(
      Widget child, {
      required CatalogProvider catalogProvider,
      required SupplierProvider supplierProvider,
    }) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<CatalogProvider>.value(value: catalogProvider),
          ChangeNotifierProvider<SettingsProvider>.value(
            value: _TestSettingsProvider(
              settings: const BusinessSettings(
                licensePlanType: 'premium',
                features: FeatureFlags(multiRubro: true, suppliers: true),
              ),
            ),
          ),
          ChangeNotifierProvider<SupplierProvider>.value(value: supplierProvider),
          ChangeNotifierProvider<LocalTerminalProvider>.value(
              value: _TestLocalTerminalProvider()),
          ChangeNotifierProvider<AuthProvider>.value(value: _TestAuthProvider()),
          ChangeNotifierProvider<InventoryAlertsProvider>.value(
              value: _TestAlertsProvider()),
        ],
        child: MaterialApp(home: Scaffold(body: child)),
      );
    }

    testWidgets('Servicio/Honorario oculta Marca y Proveedor en desktop, mantiene Categoría y envía null en brand_id/supplier_id', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final repo = _TestCatalogRepository()
        ..remoteRubros = [Rubro(id: 10, name: 'Tecnología')]
        ..remoteCategories = [
          Category(id: 1, name: 'Perfumería'),
          Category(
            id: 2,
            name: 'Celulares Xiaomi',
            rubroId: 10,
            rubro: Rubro(id: 10, name: 'Tecnología'),
          ),
        ]
        ..remoteBrands = [
          Brand(id: 5, name: 'Stanley'),
          Brand(id: 6, name: 'Arcor'),
        ];

      final catalogProv = CatalogProvider(
        getProductsUseCase: GetProductsUseCase(repo),
        repository: repo,
      );
      await catalogProv.loadMetadata();
      final supplierProv = _TestSupplierProvider([
        Supplier(id: 3, name: 'Distribuidora Sur', balance: 0, isActive: true),
      ]);

      await tester.pumpWidget(
        wrapCatalogDialog(
          ProductFormDialog(provider: catalogProv),
          catalogProvider: catalogProv,
          supplierProvider: supplierProv,
        ),
      );
      await tester.pumpAndSettle();

      // Producto Físico: los 3 selectores están visibles
      expect(find.widgetWithText(SearchableSelectField<int?>, 'Categoría'), findsOneWidget);
      expect(find.widgetWithText(SearchableSelectField<int?>, 'Marca'), findsOneWidget);
      expect(find.widgetWithText(SearchableSelectField<int?>, 'Proveedor'), findsOneWidget);

      // Elegir Categoría buscando por nombre de Rubro ("tecnologia")
      await tester.tap(find.widgetWithText(SearchableSelectField<int?>, 'Categoría'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'tecnologia');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Celulares Xiaomi'));
      await tester.pumpAndSettle();

      // Elegir Marca
      await tester.tap(find.widgetWithText(SearchableSelectField<int?>, 'Marca'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Stanley'));
      await tester.pumpAndSettle();

      // Cambiar a Combo / Fracción -> Categoría, Marca y Proveedor permanecen visibles
      await tester.tap(find.text('Combo / Fracción'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(SearchableSelectField<int?>, 'Categoría'), findsOneWidget);
      expect(find.widgetWithText(SearchableSelectField<int?>, 'Marca'), findsOneWidget);
      expect(find.widgetWithText(SearchableSelectField<int?>, 'Proveedor'), findsOneWidget);

      // Cambiar a Servicio / Honorario -> oculta Marca y Proveedor incluso en desktop ancho
      await tester.tap(find.text('Servicio / Honorario'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(SearchableSelectField<int?>, 'Categoría'), findsOneWidget);
      expect(find.widgetWithText(SearchableSelectField<int?>, 'Marca'), findsNothing);
      expect(find.widgetWithText(SearchableSelectField<int?>, 'Proveedor'), findsNothing);

      // Completar nombre e importe y guardar Servicio
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nombre del Servicio / Honorario *'),
        'Instalación Técnica',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Importe / Honorario *'),
        '15000',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Crear Producto'));
      await tester.pumpAndSettle();

      expect(repo.lastSubmittedProductData?['is_service'], isTrue);
      expect(repo.lastSubmittedProductData?['category_id'], 2);
      expect(repo.lastSubmittedProductData?['brand_id'], isNull);
      expect(repo.lastSubmittedProductData?['supplier_id'], isNull);
    });

    testWidgets('BulkPriceUpdateDialog filtra con selectores buscables y pasa IDs sin overflow en 320x480', (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final repo = _TestCatalogRepository()
        ..remoteCategories = [Category(id: 7, name: 'Lácteos')]
        ..remoteBrands = [Brand(id: 8, name: 'La Serenísima')]
        ..remoteRubros = [];

      final catalogProv = CatalogProvider(
        getProductsUseCase: GetProductsUseCase(repo),
        repository: repo,
      );
      await catalogProv.loadMetadata();
      final supplierProv = _TestSupplierProvider([
        Supplier(
          id: 9,
          name: 'Lácteos y Alimentos La Campiña',
          cuit: '30-71234567-9',
          balance: 0,
          isActive: true,
        ),
      ]);

      await tester.pumpWidget(
        wrapCatalogDialog(
          BulkPriceUpdateDialog(provider: catalogProv),
          catalogProvider: catalogProv,
          supplierProvider: supplierProv,
        ),
      );
      await tester.pumpAndSettle();

      // Ingresar porcentaje
      await tester.enterText(
        find.widgetWithText(TextField, 'Porcentaje de variación (%)'),
        '15',
      );

      // Seleccionar Categoría con buscador sin tilde ("lacteos")
      final catFilter = find.widgetWithText(
          SearchableSelectField<int?>, 'Filtrar por Categoría');
      await tester.ensureVisible(catFilter);
      await tester.tap(catFilter);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'lacteos');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lácteos'));
      await tester.pumpAndSettle();

      // Seleccionar Marca
      final brandFilter =
          find.widgetWithText(SearchableSelectField<int?>, 'Filtrar por Marca');
      await tester.ensureVisible(brandFilter);
      await tester.tap(brandFilter);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'serenisima');
      await tester.pumpAndSettle();
      await tester.tap(find.text('La Serenísima'));
      await tester.pumpAndSettle();

      // Seleccionar Proveedor por CUIT
      final supFilter = find.widgetWithText(
          SearchableSelectField<int?>, 'Filtrar por Proveedor');
      await tester.ensureVisible(supFilter);
      await tester.tap(supFilter);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '71234567');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lácteos y Alimentos La Campiña'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Previsualizar Impacto'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Confirmar y Aplicar'));
      await tester.pumpAndSettle();

      expect(repo.lastBulkPricePercentage, 15.0);
      expect(repo.lastBulkPriceCategoryId, 7);
      expect(repo.lastBulkPriceBrandId, 8);
      expect(repo.lastBulkPriceSupplierId, 9);
      expect(tester.takeException(), isNull);
    });
  });
}
