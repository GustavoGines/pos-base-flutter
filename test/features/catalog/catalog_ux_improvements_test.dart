import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
import 'package:frontend_desktop/features/catalog/presentation/widgets/supplier_quick_grid_dialog.dart';
import 'package:frontend_desktop/features/quotes/data/quote_repository.dart';
import 'package:frontend_desktop/features/quotes/presentation/providers/quote_provider.dart';
import 'package:frontend_desktop/features/reports/presentation/providers/inventory_alerts_provider.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/features/suppliers/models/supplier_model.dart';
import 'package:frontend_desktop/features/suppliers/providers/supplier_provider.dart';

class _UxCatalogRepository implements CatalogRepository {
  int _nextCategoryId = 50;
  int _nextBrandId = 80;

  final List<Category> categories = [
    Category(id: 1, name: 'Electricidad'),
    Category(id: 2, name: 'Pinturería'),
  ];

  final List<Brand> brands = [
    Brand(id: 10, name: 'Alba'),
  ];

  final List<Rubro> rubros = [
    Rubro(id: 1, name: 'Ferretería General'),
  ];

  List<Product> seededProducts = [
    Product(
      id: 1,
      name: 'Chapa Acanalada C27 3.00m',
      internalCode: 'HW001',
      costPrice: 12000,
      sellingPrice: 18500,
      stock: 40,
      active: true,
      isSoldByWeight: false,
      unitType: 'un',
    ),
    Product(
      id: 2,
      name: 'Cable Subterráneo 2x2.5mm',
      internalCode: 'HW002',
      costPrice: 1400,
      sellingPrice: 2300,
      stock: 150,
      active: true,
      isSoldByWeight: true,
      unitType: 'mt',
    ),
  ];

  List<int>? lastBulkIds;
  int? lastBulkCategoryId;
  int? lastBulkBrandId;
  int? lastBulkSupplierId;

  int? lastQueryCategoryId;
  int? lastQueryBrandId;
  int? lastQuerySupplierId;
  bool? lastQueryActive;

  int? lastUpdatedProductId;
  Map<String, dynamic>? lastUpdatedPayload;

  @override
  Future<Product> updateProduct(int id, Map<String, dynamic> data) async {
    lastUpdatedProductId = id;
    lastUpdatedPayload = Map<String, dynamic>.from(data);
    final idx = seededProducts.indexWhere((p) => p.id == id);
    final existing = seededProducts[idx];
    final nextCat = data['category_id'] == null
        ? null
        : categories.where((c) => c.id == data['category_id']).firstOrNull;
    final nextBrand = data['brand_id'] == null
        ? null
        : brands.where((b) => b.id == data['brand_id']).firstOrNull;
    final nextSupId = data['supplier_id'] as int?;
    final nextSup = nextSupId == null
        ? null
        : Supplier(
            id: nextSupId,
            name: 'Proveedor #$nextSupId',
            balance: 0,
            isActive: true,
          );
    final updated = Product(
      id: existing.id,
      name: existing.name,
      internalCode: existing.internalCode,
      costPrice: existing.costPrice,
      sellingPrice: existing.sellingPrice,
      stock: existing.stock,
      active: existing.active,
      isSoldByWeight: existing.isSoldByWeight,
      unitType: existing.unitType,
      technicalSpec: existing.technicalSpec,
      supplierSku: existing.supplierSku,
      storageLocation: data.containsKey('storage_location')
          ? data['storage_location'] as String?
          : existing.storageLocation,
      category: nextCat,
      brand: nextBrand,
      supplier: nextSup,
    );
    seededProducts[idx] = updated;
    return updated;
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
    lastQueryCategoryId = categoryId;
    lastQueryBrandId = brandId;
    lastQuerySupplierId = supplierId;
    lastQueryActive = active;
    final filtered = seededProducts.where((p) {
      if (categoryId != null && p.category?.id != categoryId) return false;
      if (brandId != null && p.brand?.id != brandId) return false;
      if (supplierId != null && p.supplier?.id != supplierId) return false;
      if (active != null && p.active != active) return false;
      return true;
    }).toList();
    return {
      'data': filtered,
      'current_page': 1,
      'last_page': 1,
      'total': filtered.length,
    };
  }

  @override
  Future<List<Category>> getCategories() async => List<Category>.from(categories);

  @override
  Future<List<Brand>> getBrands() async => List<Brand>.from(brands);

  @override
  Future<List<Rubro>> getRubros() async => List<Rubro>.from(rubros);

  @override
  Future<Category> createCategory(
    String name, {
    String? description,
    int? rubroId,
  }) async {
    final created = Category(
      id: _nextCategoryId++,
      name: name,
      description: description,
      rubroId: rubroId,
    );
    categories.add(created);
    return created;
  }

  @override
  Future<Brand> createBrand(String name, {String? description}) async {
    final created = Brand(
      id: _nextBrandId++,
      name: name,
      description: description,
    );
    brands.add(created);
    return created;
  }

  @override
  Future<Map<String, dynamic>> bulkUpdateProducts(
    List<int> ids, {
    int? categoryId,
    bool clearCategory = false,
    int? brandId,
    bool clearBrand = false,
    bool? active,
    int? supplierId,
    bool clearSupplier = false,
  }) async {
    lastBulkIds = ids;
    lastBulkCategoryId = categoryId;
    lastBulkBrandId = brandId;
    lastBulkSupplierId = supplierId;
    return {
      'message': 'Se actualizaron ${ids.length} productos.',
      'updated_count': ids.length,
      'affected_ids': ids,
    };
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
      'affected_count': productIds?.length ?? seededProducts.length,
      'examples': [
        {
          'name': seededProducts.first.name,
          'old_price': seededProducts.first.sellingPrice,
          'new_price': seededProducts.first.sellingPrice * (1 + percentage / 100),
        },
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
    return {
      'message': 'Se actualizaron ${productIds?.length ?? seededProducts.length} precios.',
      'affected_count': productIds?.length ?? seededProducts.length,
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UxFakeQuoteRepository extends Fake implements QuoteRepository {
  int _nextQuoteId = 900;

  @override
  Future<Quote> createQuote({
    required List<QuoteItem> items,
    String? customerName,
    String? customerPhone,
    String? notes,
    String? validUntil,
    int? userId,
    String? priceList,
  }) async {
    final id = _nextQuoteId++;
    final total = items.fold<double>(0, (sum, it) => sum + it.subtotal);
    return Quote(
      id: id,
      quoteNumber: 'P-000$id',
      status: 'draft',
      subtotal: total,
      total: total,
      customerName: customerName,
      customerPhone: customerPhone,
      notes: notes,
      validUntil: validUntil,
      items: items,
      createdAt: DateTime.now().toIso8601String(),
      priceList: priceList ?? 'base',
    );
  }
}

class _UxSettingsProvider extends ChangeNotifier implements SettingsProvider {
  final BusinessSettings _settings = const BusinessSettings(
    companyName: 'Ferretería UX Test',
    businessType: 'hardware_store',
    taxCondition: 'Responsable Inscripto',
    licensePlanType: 'premium',
    features: FeatureFlags(
      quotes: true,
      suppliers: true,
      multiRubro: true,
      batchExpiration: false,
      production: false,
    ),
  );

  @override
  BusinessSettings? get settings => _settings;

  @override
  bool get isHardwareStore => true;

  @override
  bool get isResponsableInscripto => true;

  @override
  FeatureFlags get features => _settings.features;

  @override
  int get assignedRegisterId => 1;

  @override
  String get currentPlan => 'premium';

  @override
  bool hasFeature(String featureName) => _settings.hasFeature(featureName);

  @override
  bool get isLicenseActive => true;

  @override
  bool get isLoading => false;

  @override
  String? get errorMessage => null;

  @override
  List<String> get allowedAddons => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UxSupplierProvider extends ChangeNotifier implements SupplierProvider {
  int _nextId = 300;
  final List<Supplier> _suppliers = [
    Supplier(
      id: 100,
      name: 'Corralón Norte SA',
      cuit: '30-70982314-5',
      balance: 0,
      isActive: true,
    ),
    Supplier(
      id: 200,
      name: 'Ferretería Industrial Sudamericana',
      cuit: '30-71458923-4',
      balance: 0,
      isActive: true,
    ),
  ];

  @override
  List<Supplier> get suppliers => List<Supplier>.unmodifiable(_suppliers);

  @override
  bool get isLoading => false;

  @override
  Future<void> fetchSuppliers({String? search}) async {}

  @override
  Future<int?> createSupplier(Map<String, dynamic> data) async {
    final newId = _nextId++;
    _suppliers.add(
      Supplier(
        id: newId,
        name: (data['name'] ?? '').toString(),
        cuit: data['cuit']?.toString(),
        balance: 0,
        isActive: true,
      ),
    );
    notifyListeners();
    return newId;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UxAuthProvider extends ChangeNotifier implements AuthProvider {
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

class _UxLocalTerminalProvider extends ChangeNotifier
    implements LocalTerminalProvider {
  @override
  bool get autoOpenCashDrawer => false;
  @override
  String get scaleComPort => '';
  @override
  String get printerFormat => 'thermal_80';
  @override
  String get printerConnection => 'none';
  @override
  String get pdfPaperSize => 'a4';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UxInventoryAlertsProvider extends ChangeNotifier
    implements InventoryAlertsProvider {
  @override
  List<dynamic> get alerts => const [];
  @override
  int get totalAlertsCount => 0;
  @override
  List<dynamic> get reactiveAlerts => const [];
  @override
  List<dynamic> get predictiveCriticalAlerts => const [];
  @override
  Future<void> fetchAlerts({int threshold = 3}) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  void setViewport(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget wrapWithProviders({
    required Widget child,
    required CatalogProvider catalogProv,
    required _UxSupplierProvider supplierProv,
    QuoteProvider? quoteProv,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<CatalogProvider>.value(value: catalogProv),
        ChangeNotifierProvider<SettingsProvider>.value(
          value: _UxSettingsProvider(),
        ),
        ChangeNotifierProvider<SupplierProvider>.value(value: supplierProv),
        ChangeNotifierProvider<AuthProvider>.value(value: _UxAuthProvider()),
        ChangeNotifierProvider<LocalTerminalProvider>.value(
          value: _UxLocalTerminalProvider(),
        ),
        ChangeNotifierProvider<InventoryAlertsProvider>.value(
          value: _UxInventoryAlertsProvider(),
        ),
        if (quoteProv != null)
          ChangeNotifierProvider<QuoteProvider>.value(value: quoteProv),
      ],
      child: MaterialApp(home: child),
    );
  }

  group('Mejoras UX Catálogo (alta rápida en lotes, grilla responsive y acciones compactas)', () {
    testWidgets(
      'CatalogScreen reemplaza iconos redundantes por botón compacto ⋮ que abre el menú contextual completo',
      (tester) async {
        setViewport(tester, const Size(1440, 900));

        final repo = _UxCatalogRepository();
        final catalogProv = CatalogProvider(
          getProductsUseCase: GetProductsUseCase(repo),
          repository: repo,
        );
        final supplierProv = _UxSupplierProvider();

        await tester.pumpWidget(
          wrapWithProviders(
            catalogProv: catalogProv,
            supplierProv: supplierProv,
            child: const CatalogScreen(),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('catalog_row_actions_1')), findsOneWidget);
        expect(find.byKey(const ValueKey('catalog_row_actions_2')), findsOneWidget);

        // No debe haber botones redundantes inline en las filas
        expect(find.byIcon(Icons.print_outlined), findsNothing);
        expect(find.byIcon(Icons.warehouse_outlined), findsNothing);
        expect(find.byIcon(Icons.edit_outlined), findsNothing);
        expect(find.byIcon(Icons.delete_outline), findsNothing);

        // Tocar el botón ⋮ abre el mismo menú contextual que el clic derecho
        await tester.tap(find.byKey(const ValueKey('catalog_row_actions_1')));
        await tester.pumpAndSettle();

        expect(find.text('Editar producto'), findsOneWidget);
        expect(find.text('Cambiar precio rápido'), findsOneWidget);
        expect(find.text('Ajustar stock'), findsOneWidget);
        expect(find.text('Imprimir etiqueta'), findsOneWidget);
        expect(find.text('Eliminar producto'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Asignación en lote permite crear Categoría, Marca y Proveedor inline y auto-seleccionarlos',
      (tester) async {
        setViewport(tester, const Size(1440, 900));

        final repo = _UxCatalogRepository();
        final catalogProv = CatalogProvider(
          getProductsUseCase: GetProductsUseCase(repo),
          repository: repo,
        );
        final supplierProv = _UxSupplierProvider();

        await tester.pumpWidget(
          wrapWithProviders(
            catalogProv: catalogProv,
            supplierProv: supplierProv,
            child: const CatalogScreen(),
          ),
        );
        await tester.pumpAndSettle();

        Future<void> selectAllProducts() async {
          await tester.tap(find.byType(Checkbox).first);
          await tester.pumpAndSettle();
        }

        // 1) Categoría en lote con botón "+" inline
        await selectAllProducts();
        await tester.tap(find.byKey(const ValueKey('catalog_row_actions_1')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Asignar Categoría'));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('bulk_create_category_btn')));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey('quick_create_category_name_field')),
          'Techos y Zinguería',
        );
        await tester.tap(
          find.byKey(const ValueKey('quick_create_category_submit_btn')),
        );
        await tester.pumpAndSettle();

        expect(find.text('Techos y Zinguería'), findsOneWidget);
        await tester.tap(find.text('Asignar'));
        await tester.pumpAndSettle();

        expect(repo.lastBulkCategoryId, 50);
        expect(repo.lastBulkIds, containsAll([1, 2]));

        // 2) Marca en lote creando desde el buscador del picker (onCreateNew)
        await selectAllProducts();
        await tester.tap(find.byKey(const ValueKey('catalog_row_actions_1')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Asignar Marca'));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('bulk_brand_select_field')));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField).last, 'Makita Pro');
        await tester.pumpAndSettle();

        await tester.tap(find.text('Crear marca "Makita Pro"'));
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey('quick_create_brand_submit_btn')),
        );
        await tester.pumpAndSettle();

        expect(find.text('Makita Pro'), findsOneWidget);
        await tester.tap(find.text('Asignar'));
        await tester.pumpAndSettle();

        expect(repo.lastBulkBrandId, 80);

        // 3) Proveedor en lote con botón "+" inline
        await selectAllProducts();
        await tester.tap(find.byKey(const ValueKey('catalog_row_actions_1')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Asignar Proveedor'));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('bulk_create_supplier_btn')));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.widgetWithText(TextFormField, 'Razón Social / Nombre *'),
          'Distribuidora del Sur SA',
        );
        await tester.tap(find.text('Guardar'));
        await tester.pumpAndSettle();

        expect(find.text('Distribuidora del Sur SA'), findsOneWidget);
        await tester.tap(find.text('Asignar'));
        await tester.pumpAndSettle();

        expect(repo.lastBulkSupplierId, 300);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'SupplierQuickGridDialog entra completo sin scroll horizontal en 1366x768 y permite crear categoría inline',
      (tester) async {
        setViewport(tester, const Size(1366, 768));

        final repo = _UxCatalogRepository();
        final catalogProv = CatalogProvider(
          getProductsUseCase: GetProductsUseCase(repo),
          repository: repo,
        );
        final supplierProv = _UxSupplierProvider();

        await tester.pumpWidget(
          wrapWithProviders(
            catalogProv: catalogProv,
            supplierProv: supplierProv,
            child: Scaffold(
              body: SupplierQuickGridDialog(
                provider: catalogProv,
                alreadyAuthorized: true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);

        // Verificar que no requiere scroll horizontal en 1366px
        final hScroll = tester.widget<SingleChildScrollView>(
          find.byKey(const ValueKey('quick_grid_horizontal_scroll')),
        );
        expect(hScroll.controller!.position.maxScrollExtent, equals(0.0));

        // Verificar que el botón de eliminar fila es completamente visible dentro del viewport
        final deleteRect = tester.getRect(
          find.byKey(const ValueKey('quick_grid_delete_row_0')),
        );
        expect(deleteRect.right, lessThanOrEqualTo(1366.0));

        // Verificar que el alta rápida inline en la cabecera funciona y auto-selecciona
        await tester.tap(
          find.byKey(const ValueKey('quick_grid_create_category_btn')),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey('quick_create_category_name_field')),
          'Bulonería Fina',
        );
        await tester.tap(
          find.byKey(const ValueKey('quick_create_category_submit_btn')),
        );
        await tester.pumpAndSettle();

        expect(find.text('Bulonería Fina'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'SupplierQuickGridDialog activa scroll horizontal de respaldo sin desbordes en pantalla angosta (900x700)',
      (tester) async {
        setViewport(tester, const Size(900, 700));

        final repo = _UxCatalogRepository();
        final catalogProv = CatalogProvider(
          getProductsUseCase: GetProductsUseCase(repo),
          repository: repo,
        );
        final supplierProv = _UxSupplierProvider();

        await tester.pumpWidget(
          wrapWithProviders(
            catalogProv: catalogProv,
            supplierProv: supplierProv,
            child: Scaffold(
              body: SupplierQuickGridDialog(
                provider: catalogProv,
                alreadyAuthorized: true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);

        final hScroll = tester.widget<SingleChildScrollView>(
          find.byKey(const ValueKey('quick_grid_horizontal_scroll')),
        );
        expect(hScroll.controller!.position.maxScrollExtent, greaterThan(0.0));
      },
    );

    testWidgets(
      'Actualizar Precios en lote conserva la selección al cerrar sin aplicar y la limpia solo al confirmar',
      (tester) async {
        setViewport(tester, const Size(1440, 900));

        final repo = _UxCatalogRepository();
        final catalogProv = CatalogProvider(
          getProductsUseCase: GetProductsUseCase(repo),
          repository: repo,
        );
        final supplierProv = _UxSupplierProvider();

        await tester.pumpWidget(
          wrapWithProviders(
            catalogProv: catalogProv,
            supplierProv: supplierProv,
            child: const CatalogScreen(),
          ),
        );
        await tester.pumpAndSettle();

        // Seleccionar los 2 productos
        await tester.tap(find.byType(Checkbox).first);
        await tester.pumpAndSettle();
        expect(find.text('Lote (2)'), findsOneWidget);

        // 1) Abrir Actualizar Precios desde menú superior de Lote y cerrar con Cancelar
        await tester.tap(find.text('Lote (2)'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Actualizar Precios'));
        await tester.pumpAndSettle();

        expect(find.text('Aumento Masivo de Precios'), findsOneWidget);
        await tester.tap(find.text('Cancelar'));
        await tester.pumpAndSettle();

        // La selección debe seguir intacta
        expect(find.text('Lote (2)'), findsOneWidget);

        // 2) Abrir Actualizar Precios desde el menú ⋮ y cerrar tocando fuera (barrier)
        await tester.tap(find.byKey(const ValueKey('catalog_row_actions_1')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Actualizar Precios'));
        await tester.pumpAndSettle();

        expect(find.text('Aumento Masivo de Precios'), findsOneWidget);
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();

        expect(find.text('Lote (2)'), findsOneWidget);

        // 3) Confirmar y aplicar aumento -> debe limpiar la selección
        await tester.tap(find.byKey(const ValueKey('catalog_row_actions_1')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Actualizar Precios'));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.widgetWithText(TextField, 'Porcentaje de variación (%)'),
          '10',
        );
        await tester.tap(find.text('Previsualizar Impacto'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Confirmar y Aplicar'));
        await tester.pumpAndSettle();

        expect(find.text('Lote (2)'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Generar Presupuesto conserva la selección si volvés atrás sin emitir y la limpia si se emitió el presupuesto',
      (tester) async {
        setViewport(tester, const Size(1440, 900));

        final repo = _UxCatalogRepository();
        final catalogProv = CatalogProvider(
          getProductsUseCase: GetProductsUseCase(repo),
          repository: repo,
        );
        final supplierProv = _UxSupplierProvider();
        final quoteProv = QuoteProvider(repository: _UxFakeQuoteRepository());

        await tester.pumpWidget(
          wrapWithProviders(
            catalogProv: catalogProv,
            supplierProv: supplierProv,
            quoteProv: quoteProv,
            child: const CatalogScreen(),
          ),
        );
        await tester.pumpAndSettle();

        // Seleccionar los 2 productos
        await tester.tap(find.byType(Checkbox).first);
        await tester.pumpAndSettle();
        expect(find.text('Lote (2)'), findsOneWidget);

        // 1) Ir a Generar Presupuesto y volver con la flecha atrás SIN emitir
        await tester.tap(find.byKey(const ValueKey('catalog_row_actions_1')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Generar Presupuesto'));
        await tester.pumpAndSettle();

        expect(quoteProv.cart.length, 2);
        await tester.tap(find.byIcon(Icons.arrow_back_rounded));
        await tester.pumpAndSettle();

        // Deben seguir seleccionados en Catálogo
        expect(find.text('Lote (2)'), findsOneWidget);

        // 2) Volver a entrar a Presupuestos, emitir el presupuesto y volver atrás
        await tester.tap(find.byKey(const ValueKey('catalog_row_actions_1')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Generar Presupuesto'));
        await tester.pumpAndSettle();

        await quoteProv.generateQuote(customerName: 'Cliente Mostrador');
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.arrow_back_rounded));
        await tester.pumpAndSettle();

        // Ahora sí se emitió el presupuesto -> la selección se limpia
        expect(find.text('Lote (2)'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Botón Filtros permite filtrar por Proveedor, Categoría, Marca y Estado, y cambiar de proveedor desde el banner',
      (tester) async {
        setViewport(tester, const Size(1440, 900));

        final repo = _UxCatalogRepository();
        final catalogProv = CatalogProvider(
          getProductsUseCase: GetProductsUseCase(repo),
          repository: repo,
        );
        final supplierProv = _UxSupplierProvider();

        await tester.pumpWidget(
          wrapWithProviders(
            catalogProv: catalogProv,
            supplierProv: supplierProv,
            child: const CatalogScreen(),
          ),
        );
        await tester.pumpAndSettle();

        // 1) Abrir barra plegable de filtros
        expect(find.byKey(const ValueKey('catalog_filters_bar')), findsNothing);
        await tester.tap(find.byKey(const ValueKey('catalog_toggle_filters_btn')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('catalog_filters_bar')), findsOneWidget);

        // 2) Filtrar por Proveedor desde Catálogo -> activa banner y consulta API con supplierId
        await tester.tap(find.byKey(const ValueKey('catalog_filter_supplier_field')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Corralón Norte SA').last);
        await tester.pumpAndSettle();

        expect(repo.lastQuerySupplierId, 100);
        expect(find.byKey(const ValueKey('catalog_banner_switch_supplier_btn')), findsOneWidget);
        expect(find.text('Filtros (1)'), findsOneWidget);

        // 3) Cambiar de proveedor directamente desde el pill del banner sin volver atrás
        await tester.tap(find.byKey(const ValueKey('catalog_banner_switch_supplier_btn')));
        await tester.pumpAndSettle();
        expect(find.text('Cambiar Proveedor'), findsOneWidget);

        await tester.tap(find.text('Ferretería Industrial Sudamericana').last);
        await tester.pumpAndSettle();

        expect(repo.lastQuerySupplierId, 200);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('catalog_banner_switch_supplier_btn')),
            matching: find.text('Ferretería Industrial Sudamericana'),
          ),
          findsOneWidget,
        );

        // 4) Combinar con Categoría, Marca y Estado POS
        await tester.tap(find.byKey(const ValueKey('catalog_filter_category_field')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Electricidad').last);
        await tester.pumpAndSettle();
        expect(repo.lastQueryCategoryId, 1);

        await tester.tap(find.byKey(const ValueKey('catalog_filter_brand_field')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Alba').last);
        await tester.pumpAndSettle();
        expect(repo.lastQueryBrandId, 10);

        await tester.tap(find.byKey(const ValueKey('catalog_filter_active_dropdown')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Activos').last);
        await tester.pumpAndSettle();
        expect(repo.lastQueryActive, isTrue);

        expect(find.text('Filtros (4)'), findsOneWidget);

        // 5) Limpiar todos los filtros en un clic
        await tester.tap(find.byKey(const ValueKey('catalog_clear_all_filters_btn')));
        await tester.pumpAndSettle();

        expect(repo.lastQuerySupplierId, isNull);
        expect(repo.lastQueryCategoryId, isNull);
        expect(repo.lastQueryBrandId, isNull);
        expect(repo.lastQueryActive, isNull);
        expect(find.byKey(const ValueKey('catalog_banner_switch_supplier_btn')), findsNothing);
        expect(find.text('Filtros'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Tabla expone tooltips completos en celdas y menú ⋮ individual ofrece Clasificación rápida y Ver productos de este proveedor',
      (tester) async {
        setViewport(tester, const Size(1440, 900));

        final repo = _UxCatalogRepository()
          ..seededProducts = [
            Product(
              id: 1,
              name: 'Madera Lapacho Cepillada Premium',
              internalCode: 'HW001',
              supplierSku: 'LAP-400',
              technicalSpec: '1" / 4m',
              storageLocation: 'Estante 2',
              costPrice: 15000,
              sellingPrice: 36930,
              stock: 20,
              active: true,
              isSoldByWeight: false,
              unitType: 'un',
              category: Category(id: 1, name: 'Electricidad'),
              brand: Brand(id: 10, name: 'Alba'),
              supplier: Supplier(
                id: 100,
                name: 'Corralón Norte SA',
                cuit: '30-70982314-5',
                balance: 0,
                isActive: true,
              ),
            ),
          ];
        final catalogProv = CatalogProvider(
          getProductsUseCase: GetProductsUseCase(repo),
          repository: repo,
        );
        final supplierProv = _UxSupplierProvider();

        await tester.pumpWidget(
          wrapWithProviders(
            catalogProv: catalogProv,
            supplierProv: supplierProv,
            child: const CatalogScreen(),
          ),
        );
        await tester.pumpAndSettle();

        // 1) Tooltips completos en celdas
        expect(
          find.byTooltip('Madera Lapacho Cepillada Premium • 1" / 4m'),
          findsOneWidget,
        );
        expect(
          find.byTooltip('Corralón Norte SA • CUIT: 30-70982314-5'),
          findsOneWidget,
        );
        expect(find.byTooltip('Cód. Prov.: LAP-400'), findsOneWidget);
        expect(find.byTooltip('Estante 2'), findsOneWidget);

        // 2) Menú ⋮ individual -> "Ver productos de este proveedor"
        await tester.tap(find.byKey(const ValueKey('catalog_row_actions_1')));
        await tester.pumpAndSettle();
        expect(find.text('Ver productos de este proveedor'), findsOneWidget);
        await tester.tap(find.text('Ver productos de este proveedor'));
        await tester.pumpAndSettle();

        expect(repo.lastQuerySupplierId, 100);
        expect(
          find.byKey(const ValueKey('catalog_banner_switch_supplier_btn')),
          findsOneWidget,
        );

        // Quitar filtro para continuar probando sobre la tabla completa
        await tester.tap(
          find.byKey(const ValueKey('catalog_clear_supplier_filter_btn')),
        );
        await tester.pumpAndSettle();

        // 3) Menú ⋮ individual -> "Clasificación rápida" (cambia Cat/Marca/Prov con "+" y Ubicación)
        await tester.tap(find.byKey(const ValueKey('catalog_row_actions_1')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.text('Clasificación rápida (Cat. / Marca / Prov.)'),
        );
        await tester.pumpAndSettle();

        expect(find.text('Clasificación Rápida'), findsOneWidget);

        // Crear proveedor nuevo inline desde el mini-modal
        await tester.tap(
          find.byKey(const ValueKey('quick_classify_create_supplier_btn')),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Razón Social / Nombre *'),
          'Maderera Argentina SRL',
        );
        await tester.tap(find.text('Guardar').last);
        await tester.pumpAndSettle();

        expect(find.text('Maderera Argentina SRL'), findsOneWidget);

        // Cambiar ubicación en depósito
        await tester.enterText(
          find.byKey(const ValueKey('quick_classify_location_field')),
          'Galpón Norte B4',
        );
        await tester.tap(find.byKey(const ValueKey('quick_classify_save_btn')));
        await tester.pumpAndSettle();

        expect(repo.lastUpdatedProductId, 1);
        expect(repo.lastUpdatedPayload?['category_id'], 1);
        expect(repo.lastUpdatedPayload?['brand_id'], 10);
        expect(repo.lastUpdatedPayload?['supplier_id'], 300);
        expect(repo.lastUpdatedPayload?['storage_location'], 'Galpón Norte B4');
        expect(tester.takeException(), isNull);
      },
    );
  });
}
