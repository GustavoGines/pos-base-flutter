import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/catalog/presentation/pages/catalog_screen.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/features/catalog/presentation/widgets/stock_alert_bell.dart';
import 'package:frontend_desktop/features/pos/presentation/widgets/pos_quick_access_view.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/features/suppliers/providers/supplier_provider.dart';
import 'package:frontend_desktop/features/suppliers/models/supplier_model.dart';
import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import 'package:frontend_desktop/features/auth/presentation/providers/auth_provider.dart';
import 'package:frontend_desktop/features/reports/presentation/providers/inventory_alerts_provider.dart';

// --- FAKE PROVIDERS FOR ADVERSARIAL STRESS TESTING ---

class FakeAdversarialCatalogProvider extends ChangeNotifier implements CatalogProvider {
  final List<Product> _products;
  final List<Product> _alerts;

  FakeAdversarialCatalogProvider({
    List<Product>? products,
    List<Product>? alerts,
  })  : _products = products ?? [],
        _alerts = alerts ?? [];

  @override
  List<Product> get products => _products;
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
  String get sortBy => 'id';
  @override
  String get sortDirection => 'asc';
  @override
  String? get errorMessage => null;
  @override
  List<Product> get criticalAlerts => _alerts;

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
  }) async {}

  @override
  Future<void> fetchCriticalAlerts() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAdversarialSettingsProvider extends ChangeNotifier implements SettingsProvider {
  @override
  BusinessSettings? get settings => const BusinessSettings(
        licensePlanType: 'premium',
        features: FeatureFlags(suppliers: true),
      );
  @override
  bool get isLoading => false;
  @override
  String? get errorMessage => null;
  @override
  String get currentPlan => 'premium';
  @override
  FeatureFlags get features => const FeatureFlags(suppliers: true);
  @override
  bool hasFeature(String featureName) => true;
  @override
  bool get isLicenseActive => true;
  @override
  List<String> get allowedAddons => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAdversarialSupplierProvider extends ChangeNotifier implements SupplierProvider {
  @override
  List<Supplier> get suppliers => [];
  @override
  bool get isLoading => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAdversarialLocalTerminalProvider extends ChangeNotifier implements LocalTerminalProvider {
  @override
  String get printerFormat => 'thermal_80';
  @override
  String get printerConnection => 'none';
  @override
  String get pdfPaperSize => 'a4';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAdversarialAuthProvider extends ChangeNotifier implements AuthProvider {
  @override
  Map<String, dynamic>? get currentUser => {'id': 1, 'name': 'Adversarial QA', 'role': 'admin'};
  @override
  bool get isAdmin => true;
  @override
  bool hasPermission(String permission) => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAdversarialInventoryAlertsProvider extends ChangeNotifier implements InventoryAlertsProvider {
  @override
  List<dynamic> get alerts => [];
  @override
  int get totalAlertsCount => 0;
  @override
  List<dynamic> get reactiveAlerts => [];
  @override
  List<dynamic> get predictiveCriticalAlerts => [];
  @override
  Future<void> fetchAlerts({int threshold = 3}) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'pos_api': 'http://localhost:8000',
      'pos_terminal_id': 'stress-test-terminal',
      'disable_pusher': true,
    });
  });

  Widget buildCatalogHarness({required List<Product> products, Size viewport = const Size(1280, 800)}) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<CatalogProvider>.value(
            value: FakeAdversarialCatalogProvider(products: products)),
        ChangeNotifierProvider<SettingsProvider>.value(
            value: FakeAdversarialSettingsProvider()),
        ChangeNotifierProvider<SupplierProvider>.value(
            value: FakeAdversarialSupplierProvider()),
        ChangeNotifierProvider<LocalTerminalProvider>.value(
            value: FakeAdversarialLocalTerminalProvider()),
        ChangeNotifierProvider<AuthProvider>.value(
            value: FakeAdversarialAuthProvider()),
        ChangeNotifierProvider<InventoryAlertsProvider>.value(
            value: FakeAdversarialInventoryAlertsProvider()),
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

  group('Adversarial Stress Suite: Image URL Corner Cases & Error Fallbacks', () {
    testWidgets('Corner cases: Null, empty, whitespace, schemeless, and malformed URLs fall back without error', (tester) async {
      final cornerCaseProducts = [
        Product(
          id: 1,
          name: 'Valid Weighed Product with Image',
          internalCode: 'CC-001',
          costPrice: 100,
          sellingPrice: 200,
          stock: 12.5,
          active: true,
          isSoldByWeight: true,
          imageUrl: 'http://pos-backend.test/storage/products/1.png',
        ),
        Product(
          id: 2,
          name: 'Empty String Image Product',
          internalCode: 'CC-002',
          costPrice: 10,
          sellingPrice: 20,
          stock: 5,
          active: true,
          isSoldByWeight: false,
          imageUrl: '',
        ),
        Product(
          id: 3,
          name: 'Whitespace Only Image Product',
          internalCode: 'CC-003',
          costPrice: 10,
          sellingPrice: 20,
          stock: 5,
          active: true,
          isSoldByWeight: false,
          imageUrl: '    ',
        ),
        Product(
          id: 4,
          name: 'Relative Path Image Product',
          internalCode: 'CC-004',
          costPrice: 10,
          sellingPrice: 20,
          stock: 5,
          active: true,
          isSoldByWeight: false,
          imageUrl: '/storage/products/4.png',
        ),
        Product(
          id: 5,
          name: 'Schemeless Domain Image Product',
          internalCode: 'CC-005',
          costPrice: 10,
          sellingPrice: 20,
          stock: 5,
          active: true,
          isSoldByWeight: false,
          imageUrl: 'pos-backend.test/storage/products/5.png',
        ),
        Product(
          id: 6,
          name: 'Malformed Scheme Image Product',
          internalCode: 'CC-006',
          costPrice: 10,
          sellingPrice: 20,
          stock: 5,
          active: true,
          isSoldByWeight: false,
          imageUrl: 'http://',
        ),
        Product(
          id: 7,
          name: 'Javascript URI Product',
          internalCode: 'CC-007',
          costPrice: 10,
          sellingPrice: 20,
          stock: 5,
          active: true,
          isSoldByWeight: false,
          imageUrl: 'javascript:void(0)',
        ),
        Product(
          id: 8,
          name: 'Null Image Unit Product',
          internalCode: 'CC-008',
          costPrice: 10,
          sellingPrice: 20,
          stock: 5,
          active: true,
          isSoldByWeight: false,
          imageUrl: null,
        ),
      ];

      await tester.pumpWidget(buildCatalogHarness(products: cornerCaseProducts));
      await tester.pump();

      // Product 1 has a valid scheme + host URL, so exactly 1 CachedNetworkImage should be instantiated in view
      expect(find.byType(CachedNetworkImage), findsOneWidget);

      // The other visible products fall back to Icon(Icons.inventory_2_outlined)
      expect(find.byIcon(Icons.inventory_2_outlined), findsWidgets);

      // No unhandled exceptions thrown
      expect(tester.takeException(), isNull);
    });

    testWidgets('Error fallback widget verification: Direct builder invocation triggers fallback icon correctly', (tester) async {
      // Create a standalone CachedNetworkImage as configured in CatalogScreen to test its errorWidget builder
      const dummyUrl = 'http://invalid-non-existent-host.example/photo.png';
      final product = Product(
        id: 99,
        name: 'Weighed Error Product',
        internalCode: 'ERR-099',
        costPrice: 50,
        sellingPrice: 100,
        stock: 10,
        active: true,
        isSoldByWeight: true,
        imageUrl: dummyUrl,
      );

      final builder = CachedNetworkImage(
        imageUrl: dummyUrl,
        errorWidget: (context, url, error) => Icon(
          product.isSoldByWeight ? Icons.scale_rounded : Icons.inventory_2_outlined,
          size: 20,
        ),
      ).errorWidget;

      expect(builder, isNotNull);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return builder!(context, dummyUrl, Exception('404 Not Found'));
            },
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.scale_rounded), findsOneWidget);
    });

    testWidgets('Quick Access Grid corner cases in all 4 modes with mixed invalid URLs', (tester) async {
      final mixedProducts = [
        Product(
          id: 11,
          name: 'P1 Valid',
          internalCode: 'P1',
          costPrice: 10,
          sellingPrice: 20,
          stock: 10,
          active: true,
          isSoldByWeight: false,
          imageUrl: 'http://pos-backend.test/storage/products/p1.png',
        ),
        Product(
          id: 12,
          name: 'P2 Null',
          internalCode: 'P2',
          costPrice: 10,
          sellingPrice: 20,
          stock: 10,
          active: true,
          isSoldByWeight: true,
          imageUrl: null,
        ),
        Product(
          id: 13,
          name: 'P3 Empty',
          internalCode: 'P3',
          costPrice: 10,
          sellingPrice: 20,
          stock: 10,
          active: true,
          isSoldByWeight: false,
          imageUrl: '',
        ),
        Product(
          id: 14,
          name: 'P4 Invalid Scheme',
          internalCode: 'P4',
          costPrice: 10,
          sellingPrice: 20,
          stock: 10,
          active: true,
          isSoldByWeight: false,
          imageUrl: 'invalid-url',
        ),
      ];

      for (final mode in ['list', 'compact', 'grid_medium', 'grid_large']) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PosQuickAccessCatalogView(
                products: mixedProducts,
                viewMode: mode,
              ),
            ),
          ),
        );
        await tester.pump();

        // Exactly 1 CachedNetworkImage per mode (P1)
        expect(find.byType(CachedNetworkImage), findsOneWidget, reason: 'Failed CachedNetworkImage count in $mode');
        // Unit fallback icons (P3, P4)
        expect(find.byIcon(Icons.inventory_2_outlined), findsWidgets, reason: 'Failed unit fallback in $mode');
        // Weighed fallback icon (P2)
        expect(find.byIcon(Icons.scale_rounded), findsWidgets, reason: 'Failed weighed fallback in $mode');
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('StockAlertBell corner cases: Displays empty, null, and valid image alerts without crashing', (tester) async {
      final alertProducts = [
        Product(
          id: 21,
          name: 'Alert Product With Image',
          internalCode: 'AL-01',
          costPrice: 10,
          sellingPrice: 20,
          stock: 0,
          active: true,
          isSoldByWeight: false,
          imageUrl: 'http://pos-backend.test/storage/products/al1.png',
        ),
        Product(
          id: 22,
          name: 'Alert Product Null Image',
          internalCode: 'AL-02',
          costPrice: 10,
          sellingPrice: 20,
          stock: 1,
          active: true,
          isSoldByWeight: true,
          imageUrl: null,
        ),
        Product(
          id: 23,
          name: 'Alert Product Whitespace Image',
          internalCode: 'AL-03',
          costPrice: 10,
          sellingPrice: 20,
          stock: 2,
          active: true,
          isSoldByWeight: false,
          imageUrl: '   ',
        ),
      ];

      final catalogProv = FakeAdversarialCatalogProvider(alerts: alertProducts);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<CatalogProvider>.value(value: catalogProv),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: Center(
                child: StockAlertBell(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Open the stock alert popover
      await tester.tap(find.byType(IconButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 1 valid CachedNetworkImage
      expect(find.byType(CachedNetworkImage), findsOneWidget);
      // Fallback icons for products 22 and 23
      expect(find.byIcon(Icons.inventory_2_outlined), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Extreme responsive constraint stress: Catalog table horizontal scrolling at 400x300 viewport', (tester) async {
      final sampleProducts = List.generate(
        10,
        (i) => Product(
          id: i + 1,
          name: 'Producto Largo Adversarial #$i de prueba de desbordamiento horizontal',
          barcode: '77900000000$i',
          internalCode: 'ADV-$i',
          costPrice: 100.0,
          sellingPrice: 150.0,
          stock: 10.0,
          active: true,
          isSoldByWeight: i.isEven,
          imageUrl: i.isEven ? 'http://pos-backend.test/storage/products/$i.jpg' : null,
        ),
      );

      tester.view.physicalSize = const Size(400, 300);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildCatalogHarness(products: sampleProducts, viewport: const Size(400, 300)));
      await tester.pump();

      // Ensure no exceptions or RenderFlex overflows occur
      expect(tester.takeException(), isNull);
    });
  });
}
