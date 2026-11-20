import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import 'package:frontend_desktop/features/auth/presentation/providers/auth_provider.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/brand.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/category.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/catalog/presentation/pages/catalog_screen.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/features/reports/presentation/providers/inventory_alerts_provider.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/features/suppliers/models/supplier_model.dart';
import 'package:frontend_desktop/features/suppliers/providers/supplier_provider.dart';

class _LoadProductsCall {
  final String? sortBy;
  final String? sortDirection;

  const _LoadProductsCall(this.sortBy, this.sortDirection);
}

class _StatefulFakeCatalogProvider extends ChangeNotifier
    implements CatalogProvider {
  final List<Product> _products;
  final List<_LoadProductsCall> loadCalls = [];
  String _sortBy = 'name';
  String _sortDirection = 'asc';

  _StatefulFakeCatalogProvider({required List<Product> products})
      : _products = products;

  @override
  List<Product> get products => _products;

  @override
  List<Product> get criticalAlerts => const [];

  @override
  bool get isLoading => false;

  @override
  int get currentPage => 1;

  @override
  int get lastPage => 1;

  @override
  bool get hasNextPage => false;

  @override
  bool get hasPrevPage => false;

  @override
  String get sortBy => _sortBy;

  @override
  String get sortDirection => _sortDirection;

  @override
  String? get errorMessage => null;

  @override
  Future<void> loadProducts({
    int page = 1,
    String? search,
    int? categoryId,
    int? brandId,
    int? supplierId,
    String? sortBy,
    String? sortDirection,
    bool? activeOnly,
    int? rubroId,
    int? perPage,
  }) async {
    loadCalls.add(_LoadProductsCall(sortBy, sortDirection));
    if (sortBy != null) _sortBy = sortBy;
    if (sortDirection != null) _sortDirection = sortDirection;
    notifyListeners();
  }

  @override
  Future<void> fetchCriticalAlerts() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSettingsProvider extends ChangeNotifier implements SettingsProvider {
  final FeatureFlags _features;
  final String _businessType;

  _FakeSettingsProvider({
    FeatureFlags features = const FeatureFlags(
      quotes: true,
      suppliers: true,
      multiRubro: true,
      batchExpiration: true,
    ),
    String businessType = 'retail',
  })  : _features = features,
        _businessType = businessType;

  @override
  int get assignedRegisterId => 1;

  @override
  BusinessSettings? get settings => BusinessSettings(
        licensePlanType: 'premium',
        businessType: _businessType,
        features: _features,
      );

  @override
  bool get isLoading => false;

  @override
  String? get errorMessage => null;

  @override
  String get currentPlan => 'premium';

  @override
  FeatureFlags get features => _features;

  @override
  bool hasFeature(String featureName) => true;

  @override
  bool get isLicenseActive => true;

  @override
  List<String> get allowedAddons => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSupplierProvider extends ChangeNotifier implements SupplierProvider {
  @override
  List<Supplier> get suppliers => const [];

  @override
  bool get isLoading => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLocalTerminalProvider extends ChangeNotifier
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

class _FakeAuthProvider extends ChangeNotifier implements AuthProvider {
  @override
  Map<String, dynamic>? get currentUser =>
      const {'id': 1, 'name': 'Admin UX', 'role': 'admin'};

  @override
  bool get isAdmin => true;

  @override
  bool hasPermission(String permission) => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeInventoryAlertsProvider extends ChangeNotifier
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

String _isoDate(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

String _displayDate(DateTime date) {
  final d = date.day.toString().padLeft(2, '0');
  final m = date.month.toString().padLeft(2, '0');
  final y = date.year.toString().padLeft(4, '0');
  return '$d/$m/$y';
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'pos_api': 'http://localhost:8000',
      'pos_terminal_id': 'caja-ux',
      'disable_pusher': true,
    });
  });

  List<Product> buildProducts() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final overdue2d = today.subtract(const Duration(days: 2));

    return [
      Product(
        id: 1,
        name: 'XIAOMI 15T NFC DUAL SIM 512GB',
        barcode: '6941812790012',
        internalCode: 'G3-0002',
        costPrice: 1001340,
        sellingPrice: 1252900,
        stock: 995,
        active: true,
        isSoldByWeight: false,
        category: Category(id: 1, name: 'CELULARES'),
        brand: Brand(id: 1, name: 'Xiaomi'),
        supplier: Supplier(
          id: 1,
          name: 'Distri Tech',
          balance: 0,
          isActive: true,
        ),
        expirationDate: '2099-11-15',
      ),
      Product(
        id: 2,
        name: 'YOGUR ENTERO VENCE HOY',
        barcode: '7790001000001',
        internalCode: 'LAC-010',
        costPrice: 900,
        sellingPrice: 1400,
        stock: 10,
        active: true,
        isSoldByWeight: false,
        expirationDate: _isoDate(today),
        expiryAlertDays: 7,
      ),
      Product(
        id: 3,
        name: 'QUESO CREMA VENCIDO',
        barcode: '7790001000002',
        internalCode: 'LAC-011',
        costPrice: 1500,
        sellingPrice: 2200,
        stock: 4.5,
        active: true,
        isSoldByWeight: true,
        expirationDate: _isoDate(overdue2d),
      ),
      Product(
        id: 4,
        name: 'PRODUCTO SIN VENCIMIENTO',
        barcode: null,
        internalCode: 'SIN-001',
        costPrice: 500,
        sellingPrice: 800,
        stock: 12,
        active: true,
        isSoldByWeight: false,
      ),
    ];
  }

  Widget wrapCatalog({
    required _StatefulFakeCatalogProvider catalogProvider,
    required Size viewport,
    _FakeSettingsProvider? settingsProvider,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<CatalogProvider>.value(value: catalogProvider),
        ChangeNotifierProvider<SettingsProvider>.value(
          value: settingsProvider ?? _FakeSettingsProvider(),
        ),
        ChangeNotifierProvider<SupplierProvider>.value(
          value: _FakeSupplierProvider(),
        ),
        ChangeNotifierProvider<LocalTerminalProvider>.value(
          value: _FakeLocalTerminalProvider(),
        ),
        ChangeNotifierProvider<AuthProvider>.value(value: _FakeAuthProvider()),
        ChangeNotifierProvider<InventoryAlertsProvider>.value(
          value: _FakeInventoryAlertsProvider(),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(size: viewport),
            child: const CatalogScreen(),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'Marca limpia sin caja índigo, VTO. completo y 1.º clic VTO. ordena DESC -> 2.º ASC',
    (tester) async {
      const viewport = Size(1280, 800);
      await tester.binding.setSurfaceSize(viewport);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final catalogProv = _StatefulFakeCatalogProvider(
        products: buildProducts(),
      );

      await tester.pumpWidget(
        wrapCatalog(catalogProvider: catalogProv, viewport: viewport),
      );
      await tester.pumpAndSettle();

      // 1. Marca limpia (Opción B): sin contenedor ni borde pastel índigo.
      final brandFinder = find.text('Xiaomi');
      expect(brandFinder, findsOneWidget);
      final indigoContainerAncestor = find.ancestor(
        of: brandFinder,
        matching: find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).color == Colors.indigo.shade50,
        ),
      );
      expect(indigoContainerAncestor, findsNothing);

      // Misma tipografía limpia que Categoría y Proveedor.
      final brandText = tester.widget<Text>(brandFinder);
      final catText = tester.widget<Text>(find.text('CELULARES'));
      final provText = tester.widget<Text>(find.text('Distri Tech'));
      expect(brandText.overflow, TextOverflow.ellipsis);
      expect(brandText.style?.color, catText.style?.color);
      expect(brandText.style?.fontSize, provText.style?.fontSize);

      // 2. Columnas derechas y fecha completa dd/MM/yyyy sin recorte.
      expect(find.text('Bal.'), findsOneWidget);
      expect(find.text('Activo'), findsOneWidget);
      expect(find.text('VTO.'), findsOneWidget);
      expect(find.text('Acciones'), findsOneWidget);
      expect(find.text('15/11/2099'), findsOneWidget);

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final overdue2d = today.subtract(const Duration(days: 2));

      // Tooltips corregidos para vence hoy y vencido.
      expect(
        find.byTooltip('¡Vence HOY! (${_displayDate(today)}) • Clic para ver/administrar lotes'),
        findsOneWidget,
      );
      expect(
        find.byTooltip('Vencido hace 2 días (${_displayDate(overdue2d)}) • Clic para ver/administrar lotes'),
        findsOneWidget,
      );

      // 3. Clic en VTO.: 1.º clic => DESC (fecha más nueva arriba), 2.º clic => ASC.
      final vtoInkWell = find.ancestor(
        of: find.text('VTO.'),
        matching: find.byType(InkWell),
      );
      catalogProv.loadCalls.clear();
      await tester.tap(find.text('VTO.'));
      await tester.pumpAndSettle();

      expect(catalogProv.loadCalls, isNotEmpty);
      expect(catalogProv.loadCalls.last.sortBy, 'expiration_date');
      expect(catalogProv.loadCalls.last.sortDirection, 'desc');
      expect(
        find.descendant(
          of: vtoInkWell,
          matching: find.byIcon(Icons.arrow_downward),
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('VTO.'));
      await tester.pumpAndSettle();

      expect(catalogProv.loadCalls.last.sortBy, 'expiration_date');
      expect(catalogProv.loadCalls.last.sortDirection, 'asc');
      expect(
        find.descendant(
          of: vtoInkWell,
          matching: find.byIcon(Icons.arrow_upward),
        ),
        findsOneWidget,
      );

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Tabla de catálogo no desborda en 1200x800 ni en viewport estrecho 320x480',
    (tester) async {
      for (final viewport in [const Size(1200, 800), const Size(320, 480)]) {
        await tester.binding.setSurfaceSize(viewport);
        final catalogProv = _StatefulFakeCatalogProvider(
          products: buildProducts(),
        );

        await tester.pumpWidget(
          wrapCatalog(catalogProvider: catalogProv, viewport: viewport),
        );
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason: 'Overflow o excepción en viewport $viewport',
        );
      }
      await tester.binding.setSurfaceSize(null);
    },
  );

  testWidgets(
    'Opción 1A: En Ferretería (batchExpiration: false, production: false) se ocultan VTO., ícono de Lotes y botón Producción',
    (tester) async {
      const viewport = Size(1280, 800);
      await tester.binding.setSurfaceSize(viewport);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final catalogProv = _StatefulFakeCatalogProvider(
        products: buildProducts(),
      );
      final hardwareSettings = _FakeSettingsProvider(
        businessType: 'hardware_store',
        features: const FeatureFlags(
          quotes: true,
          logistics: true,
          suppliers: true,
          batchExpiration: false,
          production: false,
        ),
      );

      await tester.pumpWidget(
        wrapCatalog(
          catalogProvider: catalogProv,
          viewport: viewport,
          settingsProvider: hardwareSettings,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Acciones'), findsOneWidget);
      expect(find.text('VTO.'), findsNothing);
      expect(find.byIcon(Icons.layers_outlined), findsNothing);
      expect(find.text('Producción'), findsNothing);
      expect(find.byIcon(Icons.bakery_dining_outlined), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
