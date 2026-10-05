import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend_desktop/features/catalog/data/datasources/catalog_remote_datasource.dart';
import 'package:frontend_desktop/features/catalog/data/models/product_model.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/brand.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/category.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/rubro.dart';
import 'package:frontend_desktop/features/catalog/presentation/pages/catalog_screen.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/features/suppliers/models/supplier_model.dart';
import 'package:frontend_desktop/features/suppliers/providers/supplier_provider.dart';

// --- FAKES ---
class FakeCatalogProvider extends ChangeNotifier implements CatalogProvider {
  List<Category> _categories = [];
  List<Brand> _brands = [];
  List<Rubro> _rubros = [];
  Map<String, dynamic>? lastSubmittedData;
  bool uploadProductImageCalled = false;
  int? lastUploadedProductId;
  String? lastUploadedFilePath;
  List<int>? lastUploadedBytes;
  String? lastUploadedFilename;
  Product? _lastCreatedProduct;
  final bool _isLoading;

  FakeCatalogProvider({
    List<Category>? categories,
    List<Brand>? brands,
    List<Rubro>? rubros,
    Product? lastCreatedProduct,
    bool isLoading = false,
  })  : _isLoading = isLoading {
    _categories = categories ?? [
      Category(id: 1, name: 'Bebidas'),
      Category(id: 2, name: 'Snacks'),
    ];
    _brands = brands ?? [Brand(id: 1, name: 'Genérica')];
    _rubros = rubros ?? [Rubro(id: 1, name: 'General', isSystem: true)];
    _lastCreatedProduct = lastCreatedProduct ??
        Product(
          id: 99,
          name: 'Producto Nuevo',
          internalCode: '0099',
          costPrice: 50,
          sellingPrice: 100,
          stock: 10,
          active: true,
          isSoldByWeight: false,
        );
  }

  @override
  Product? get lastCreatedProduct => _lastCreatedProduct;
  @override
  List<Product> get products => _lastCreatedProduct != null ? [_lastCreatedProduct!] : [];
  @override
  List<Category> get categories => _categories;
  @override
  List<Brand> get brands => _brands;
  @override
  List<Rubro> get rubros => _rubros;
  @override
  bool get isLoading => _isLoading;
  @override
  String? get errorMessage => null;

  @override
  Future<bool> createProduct(Map<String, dynamic> productData) async {
    lastSubmittedData = productData;
    return true;
  }

  @override
  Future<bool> updateProduct(int id, Map<String, dynamic> productData) async {
    lastSubmittedData = productData;
    return true;
  }

  @override
  Future<String?> uploadProductImage(int productId, String filePath, {List<int>? bytes, String? filename}) async {
    uploadProductImageCalled = true;
    lastUploadedProductId = productId;
    lastUploadedFilePath = filePath;
    lastUploadedBytes = bytes;
    lastUploadedFilename = filename;
    return 'http://pos-backend.test/storage/products/$productId.jpg';
  }

  @override
  Future<void> loadRubros() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSettingsProvider extends ChangeNotifier implements SettingsProvider {
  final BusinessSettings _settings;

  FakeSettingsProvider({required BusinessSettings settings}) : _settings = settings;

  @override
  BusinessSettings? get settings => _settings;
  @override
  String get currentPlan => _settings.licensePlanType ?? 'basic';
  @override
  FeatureFlags get features => _settings.features;
  @override
  bool hasFeature(String featureName) => _settings.hasFeature(featureName);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSupplierProvider extends ChangeNotifier implements SupplierProvider {
  @override
  List<Supplier> get suppliers => [];
  @override
  Future<void> fetchSuppliers({String? search}) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'pos_terminal_id': 'caja-test',
      'pos_api': 'http://pos-backend.test/api',
    });
  });

  group('Phase 2 Product Image: ProductModel Serialization & Resolution Tests', () {
    test('ProductModel.fromJson resolves relative image_url into full storage URL', () {
      final jsonMap = {
        'id': 10,
        'name': 'Gaseosa Cola',
        'internal_code': '0010',
        'cost_price': 80.0,
        'selling_price': 150.0,
        'stock': 25.0,
        'active': true,
        'is_sold_by_weight': false,
        'image_url': 'products/10_cola.png',
      };

      final product = ProductModel.fromJson(jsonMap);
      expect(product.imageUrl, isNotNull);
      expect(product.imageUrl, contains('/storage/products/10_cola.png'));
    });

    test('ProductModel.fromJson falls back to image_path when image_url is missing', () {
      final jsonMap = {
        'id': 11,
        'name': 'Galletitas',
        'internal_code': '0011',
        'cost_price': 40.0,
        'selling_price': 70.0,
        'stock': 12.0,
        'active': true,
        'is_sold_by_weight': false,
        'image_path': 'products/11_cookies.webp',
      };

      final product = ProductModel.fromJson(jsonMap);
      expect(product.imageUrl, isNotNull);
      expect(product.imageUrl, contains('/storage/products/11_cookies.webp'));
    });

    test('ProductModel.fromJson falls back to image_path when image_url is empty string or "null" string', () {
      final jsonWithEmptyUrl = {
        'id': 13,
        'name': 'Jugo Naranja',
        'internal_code': '0013',
        'cost_price': 60.0,
        'selling_price': 120.0,
        'stock': 15.0,
        'active': true,
        'is_sold_by_weight': false,
        'image_url': '',
        'image_path': 'products/13_orange.jpg',
      };
      final product1 = ProductModel.fromJson(jsonWithEmptyUrl);
      expect(product1.imageUrl, isNotNull);
      expect(product1.imageUrl, contains('/storage/products/13_orange.jpg'));

      final jsonWithNullString = {
        'id': 14,
        'name': 'Agua Mineral',
        'internal_code': '0014',
        'cost_price': 30.0,
        'selling_price': 60.0,
        'stock': 20.0,
        'active': true,
        'is_sold_by_weight': false,
        'image_url': 'null',
        'image_path': r'products\14_water.png',
      };
      final product2 = ProductModel.fromJson(jsonWithNullString);
      expect(product2.imageUrl, isNotNull);
      expect(product2.imageUrl, contains('/storage/products/14_water.png'));
    });

    test('ProductModel.fromJson leaves imageUrl null when neither image_url nor image_path exists', () {
      final jsonMap = {
        'id': 12,
        'name': 'Servicio',
        'internal_code': '0012',
        'cost_price': 0.0,
        'selling_price': 500.0,
        'stock': 0.0,
        'active': true,
        'is_sold_by_weight': false,
      };

      final product = ProductModel.fromJson(jsonMap);
      expect(product.imageUrl, isNull);
    });
  });

  group('Phase 2 Product Image: Remote Datasource Unit Tests', () {
    test('uploadProductImage sends multipart POST to /catalog/products/{id}/image with "image" field', () async {
      String? capturedMethod;
      String? capturedPath;
      String? capturedContentType;
      String? capturedBody;

      final mockClient = MockClient((request) async {
        capturedMethod = request.method;
        capturedPath = request.url.path;
        capturedContentType = request.headers['content-type'];
        capturedBody = latin1.decode(request.bodyBytes);

        return http.Response(
          jsonEncode({
            'message': 'Imagen de producto subida correctamente',
            'image_url': 'http://pos-backend.test/storage/products/42_abc.png',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final dataSource = CatalogRemoteDataSourceImpl(
        baseUrl: 'http://pos-backend.test/api',
        client: mockClient,
      );

      final dummyBytes = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);
      final result = await dataSource.uploadProductImage(
        42,
        'product_test.png',
        bytes: dummyBytes,
        filename: 'product_test.png',
      );

      expect(capturedMethod, 'POST');
      expect(capturedPath, '/api/catalog/products/42/image');
      expect(capturedContentType, contains('multipart/form-data'));
      expect(capturedBody, contains('name="image"'));
      expect(capturedBody, contains('filename="product_test.png"'));
      expect(result, 'http://pos-backend.test/storage/products/42_abc.png');
    });

    test('uploadProductImage throws Exception when server returns non-200 error', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'message': 'Error al procesar archivo'}),
          422,
          headers: {'content-type': 'application/json'},
        );
      });

      final dataSource = CatalogRemoteDataSourceImpl(
        baseUrl: 'http://pos-backend.test/api',
        client: mockClient,
      );

      expect(
        () => dataSource.uploadProductImage(42, 'product.png', bytes: [1, 2, 3], filename: 'product.png'),
        throwsA(isA<Exception>()),
      );
    });

    test('uploadProductImage sets MediaType image/webp in multipart part', () async {
      String? capturedContentType;
      String? capturedBody;

      final mockClient = MockClient((request) async {
        capturedContentType = request.headers['content-type'];
        capturedBody = latin1.decode(request.bodyBytes);

        return http.Response(
          jsonEncode({
            'message': 'OK',
            'image_url': 'http://pos-backend.test/storage/products/1_photo.webp',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final dataSource = CatalogRemoteDataSourceImpl(
        baseUrl: 'http://pos-backend.test/api',
        client: mockClient,
      );

      await dataSource.uploadProductImage(1, 'photo.webp', bytes: [1, 2, 3], filename: 'photo.webp');

      expect(capturedContentType, contains('multipart/form-data'));
      expect(capturedBody, contains('content-type: image/webp'));
    });
  });

  group('Phase 2 Product Image: ProductFormDialog Widget Tests', () {
    Widget buildFormApp({
      required FakeCatalogProvider catalogProv,
      required FakeSettingsProvider settingsProv,
      Product? product,
    }) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<CatalogProvider>.value(value: catalogProv),
          ChangeNotifierProvider<SettingsProvider>.value(value: settingsProv),
          ChangeNotifierProvider<SupplierProvider>.value(value: FakeSupplierProvider()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => ProductFormDialog(
                      provider: catalogProv,
                      product: product,
                    ),
                  );
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('Renders product image container, "Foto del Producto" text, and "Seleccionar Foto" button', (tester) async {
      final catalogProv = FakeCatalogProvider();
      final settingsProv = FakeSettingsProvider(
        settings: const BusinessSettings(
          licensePlanType: 'basic',
          features: FeatureFlags(),
        ),
      );

      await tester.pumpWidget(buildFormApp(catalogProv: catalogProv, settingsProv: settingsProv));
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Verify product image container exists
      final containerFinder = find.byKey(const ValueKey('product_image_container'));
      expect(containerFinder, findsOneWidget);

      // Verify header texts and action button
      expect(find.text('Foto del Producto'), findsOneWidget);
      expect(find.text('Subir Foto'), findsOneWidget);
      expect(find.text('Seleccionar Foto'), findsOneWidget);
    });

    testWidgets('Renders existing product image and shows "Cambiar Foto" button when editing', (tester) async {
      final catalogProv = FakeCatalogProvider();
      final settingsProv = FakeSettingsProvider(
        settings: const BusinessSettings(
          licensePlanType: 'basic',
          features: FeatureFlags(),
        ),
      );

      final existingProduct = Product(
        id: 77,
        name: 'Coca Cola 1.5L',
        internalCode: '0077',
        costPrice: 500,
        sellingPrice: 850,
        stock: 24,
        active: true,
        isSoldByWeight: false,
        imageUrl: 'http://pos-backend.test/storage/products/77.jpg',
      );

      await tester.pumpWidget(buildFormApp(catalogProv: catalogProv, settingsProv: settingsProv, product: existingProduct));
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Product image container exists
      expect(find.byKey(const ValueKey('product_image_container')), findsOneWidget);

      // Action button updates to "Cambiar Foto"
      expect(find.text('Cambiar Foto'), findsOneWidget);
      expect(find.text('Seleccionar Foto'), findsNothing);
    });

    testWidgets('Responsive stress: 320x480 viewport renders compact image container without RenderFlex overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final catalogProv = FakeCatalogProvider();
      final settingsProv = FakeSettingsProvider(
        settings: const BusinessSettings(
          licensePlanType: 'basic',
          features: FeatureFlags(),
        ),
      );

      await tester.pumpWidget(buildFormApp(catalogProv: catalogProv, settingsProv: settingsProv));
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // No RenderFlex exceptions
      expect(tester.takeException(), isNull);

      final containerFinder = find.byKey(const ValueKey('product_image_container'));
      expect(containerFinder, findsOneWidget);

      // Compact size in narrow view is 80x80
      final size = tester.getSize(containerFinder);
      expect(size.width, 80.0);
      expect(size.height, 80.0);
    });

    testWidgets('Action buttons (Cancelar, Guardar) are disabled when provider is loading', (tester) async {
      final catalogProv = FakeCatalogProvider(isLoading: true);
      final settingsProv = FakeSettingsProvider(
        settings: const BusinessSettings(
          licensePlanType: 'basic',
          features: FeatureFlags(),
        ),
      );

      await tester.pumpWidget(buildFormApp(catalogProv: catalogProv, settingsProv: settingsProv));
      await tester.tap(find.text('Open Dialog'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final filledButton = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(filledButton.onPressed, isNull);

      final cancelButton = tester.widget<TextButton>(find.widgetWithText(TextButton, 'Cancelar'));
      expect(cancelButton.onPressed, isNull);
    });
  });
}
