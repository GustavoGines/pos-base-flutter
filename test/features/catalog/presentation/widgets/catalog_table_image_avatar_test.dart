import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/catalog/presentation/pages/catalog_screen.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/features/suppliers/providers/supplier_provider.dart';
import 'package:frontend_desktop/features/suppliers/models/supplier_model.dart';
import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import 'package:frontend_desktop/features/auth/presentation/providers/auth_provider.dart';
import 'package:frontend_desktop/features/reports/presentation/providers/inventory_alerts_provider.dart';

// --- FAKE PROVIDERS ---

class FakeCatalogProvider extends ChangeNotifier implements CatalogProvider {
  final List<Product> _products;
  final bool _isLoading;

  FakeCatalogProvider({List<Product>? products, bool isLoading = false})
      : _products = products ?? [],
        _isLoading = isLoading;

  @override
  List<Product> get products => _products;
  @override
  bool get isLoading => _isLoading;
  @override
  int get currentPage => 1;
  @override
  int get lastPage => 1;
  int get totalProducts => _products.length;
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
  List<Product> get criticalAlerts => [];

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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSettingsProvider extends ChangeNotifier implements SettingsProvider {
  final BusinessSettings? _settings;

  FakeSettingsProvider({BusinessSettings? settings})
      : _settings = settings ??
            const BusinessSettings(
              licensePlanType: 'premium',
              features: FeatureFlags(quotes: true, suppliers: true),
            );

  @override
  BusinessSettings? get settings => _settings;
  @override
  bool get isLoading => false;
  @override
  String? get errorMessage => null;
  @override
  String get currentPlan => _settings?.licensePlanType ?? 'basic';
  @override
  FeatureFlags get features => _settings?.features ?? const FeatureFlags();
  @override
  bool hasFeature(String featureName) => _settings?.hasFeature(featureName) ?? false;
  @override
  bool get isLicenseActive => true;
  @override
  List<String> get allowedAddons => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSupplierProvider extends ChangeNotifier implements SupplierProvider {
  @override
  List<Supplier> get suppliers => [];
  @override
  bool get isLoading => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeLocalTerminalProvider extends ChangeNotifier implements LocalTerminalProvider {
  @override
  String get printerFormat => 'thermal_80';
  @override
  String get printerConnection => 'none';
  @override
  String get pdfPaperSize => 'a4';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAuthProvider extends ChangeNotifier implements AuthProvider {
  @override
  Map<String, dynamic>? get currentUser => {'id': 1, 'name': 'Admin Test', 'role': 'admin'};
  @override
  bool get isAdmin => true;
  @override
  bool hasPermission(String permission) => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeInventoryAlertsProvider extends ChangeNotifier implements InventoryAlertsProvider {
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
      'pos_terminal_id': 'caja-test',
      'disable_pusher': true,
    });
  });

  Widget buildTestCatalog({
    required List<Product> products,
    Size viewport = const Size(1280, 800),
  }) {
    final catalogProv = FakeCatalogProvider(products: products);
    final settingsProv = FakeSettingsProvider();
    final supplierProv = FakeSupplierProvider();
    final terminalProv = FakeLocalTerminalProvider();
    final authProv = FakeAuthProvider();
    final alertsProv = FakeInventoryAlertsProvider();

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<CatalogProvider>.value(value: catalogProv),
        ChangeNotifierProvider<SettingsProvider>.value(value: settingsProv),
        ChangeNotifierProvider<SupplierProvider>.value(value: supplierProv),
        ChangeNotifierProvider<LocalTerminalProvider>.value(value: terminalProv),
        ChangeNotifierProvider<AuthProvider>.value(value: authProv),
        ChangeNotifierProvider<InventoryAlertsProvider>.value(value: alertsProv),
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

  group('Milestone 2: Catalog Table Product Image Avatar Tests', () {
    testWidgets('Header row displays 48px fixed-width image column header', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final product = Product(
        id: 1,
        name: 'Producto A',
        internalCode: 'P01',
        costPrice: 10,
        sellingPrice: 20,
        stock: 5,
        active: true,
        isSoldByWeight: false,
      );

      await tester.pumpWidget(buildTestCatalog(products: [product]));
      await tester.pump();

      expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    });

    testWidgets('Product with valid imageUrl renders 40x40 circular avatar with CachedNetworkImage', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const validUrl = 'http://pos-backend.test/storage/products/101.jpg';
      final productWithImage = Product(
        id: 101,
        name: 'Gaseosa Cola 2L',
        internalCode: 'GAS-101',
        costPrice: 150,
        sellingPrice: 300,
        stock: 50,
        active: true,
        isSoldByWeight: false,
        imageUrl: validUrl,
      );

      await tester.pumpWidget(buildTestCatalog(products: [productWithImage]));
      await tester.pump();

      // Verify CachedNetworkImage widget is present in the table
      final cachedImageFinder = find.byType(CachedNetworkImage);
      expect(cachedImageFinder, findsOneWidget);

      final cachedImage = tester.widget<CachedNetworkImage>(cachedImageFinder);
      expect(cachedImage.imageUrl, validUrl);
      expect(cachedImage.width, 40.0);
      expect(cachedImage.height, 40.0);
      expect(cachedImage.fit, BoxFit.cover);

      // Verify ClipOval wraps the avatar
      expect(find.byType(ClipOval), findsOneWidget);
    });

    testWidgets('Unit product without image renders fallback Icon(Icons.inventory_2_outlined)', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final unitProductNoImage = Product(
        id: 102,
        name: 'Cuaderno A4',
        internalCode: 'ART-102',
        costPrice: 50,
        sellingPrice: 120,
        stock: 15,
        active: true,
        isSoldByWeight: false,
        imageUrl: null,
      );

      await tester.pumpWidget(buildTestCatalog(products: [unitProductNoImage]));
      await tester.pump();

      // No CachedNetworkImage widget rendered
      expect(find.byType(CachedNetworkImage), findsNothing);

      // Fallback icon for unit product is inventory_2_outlined
      expect(find.byIcon(Icons.inventory_2_outlined), findsWidgets);
    });

    testWidgets('Weighed product without image renders fallback Icon(Icons.scale_rounded)', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final weighedProductNoImage = Product(
        id: 103,
        name: 'Queso Cremoso',
        internalCode: 'PES-103',
        costPrice: 800,
        sellingPrice: 1500,
        stock: 12.5,
        active: true,
        isSoldByWeight: true,
        imageUrl: null,
      );

      await tester.pumpWidget(buildTestCatalog(products: [weighedProductNoImage]));
      await tester.pump();

      // No CachedNetworkImage widget rendered
      expect(find.byType(CachedNetworkImage), findsNothing);

      // Fallback icon for weighed product is scale_rounded
      expect(find.byIcon(Icons.scale_rounded), findsWidgets);
    });

    testWidgets('Product with malformed or schemeless imageUrl falls back gracefully to icon', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final productMalformedUrl = Product(
        id: 104,
        name: 'Galletitas Dulces',
        internalCode: 'GAL-104',
        costPrice: 70,
        sellingPrice: 140,
        stock: 20,
        active: true,
        isSoldByWeight: false,
        imageUrl: 'not_a_valid_url',
      );

      await tester.pumpWidget(buildTestCatalog(products: [productMalformedUrl]));
      await tester.pump();

      // Should not attempt to render CachedNetworkImage for invalid url
      expect(find.byType(CachedNetworkImage), findsNothing);
      expect(find.byIcon(Icons.inventory_2_outlined), findsWidgets);
    });

    testWidgets('Responsive stress test: 1024x768 and 800x600 viewport renders cleanly without overflow', (tester) async {
      final sampleProducts = List.generate(
        5,
        (i) => Product(
          id: i + 1,
          name: 'Producto de prueba $i con nombre largo para probar layout responsivo',
          barcode: '77912345678$i',
          internalCode: 'PRD-00$i',
          costPrice: 100.0 * (i + 1),
          sellingPrice: 150.0 * (i + 1),
          stock: 25.0,
          active: true,
          isSoldByWeight: i.isEven,
          imageUrl: i == 0 ? 'http://pos-backend.test/storage/products/1.jpg' : null,
        ),
      );

      // Test on 1024x768
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      await tester.pumpWidget(buildTestCatalog(products: sampleProducts));
      await tester.pump();
      expect(tester.takeException(), isNull);

      // Test on compact 800x600 (horizontal scroll graceful behavior)
      tester.view.physicalSize = const Size(800, 600);
      await tester.pumpWidget(buildTestCatalog(products: sampleProducts));
      await tester.pump();
      expect(tester.takeException(), isNull);

      addTearDown(() => tester.view.resetPhysicalSize());
    });
  });
}
