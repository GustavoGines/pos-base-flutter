import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:frontend_desktop/features/catalog/domain/entities/brand.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/category.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/rubro.dart';
import 'package:frontend_desktop/features/catalog/presentation/pages/catalog_screen.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/features/catalog/utils/product_share_helper.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/features/suppliers/models/supplier_model.dart';
import 'package:frontend_desktop/features/suppliers/providers/supplier_provider.dart';

// --- FAKES FOR WIDGET TEST ---
class FakeCatalogProvider extends ChangeNotifier implements CatalogProvider {
  final List<Category> _categories = [Category(id: 1, name: 'Bebidas')];
  final List<Brand> _brands = [Brand(id: 1, name: 'Genérica')];
  final List<Rubro> _rubros = [Rubro(id: 1, name: 'General', isSystem: true)];

  @override
  List<Category> get categories => _categories;
  @override
  List<Brand> get brands => _brands;
  @override
  List<Rubro> get rubros => _rubros;
  @override
  bool get isLoading => false;
  @override
  String? get errorMessage => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSettingsProvider extends ChangeNotifier implements SettingsProvider {
  @override
  BusinessSettings? get settings => BusinessSettings();
  @override
  String get currentPlan => 'basic';
  @override
  FeatureFlags get features => FeatureFlags();
  @override
  bool hasFeature(String featureName) => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSupplierProvider extends ChangeNotifier implements SupplierProvider {
  @override
  List<Supplier> get suppliers => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Milestone 4: ProductShareHelper Unit Tests', () {
    test('formatProductShareText includes all relevant details when fully populated', () {
      final product = Product(
        id: 1,
        name: 'Yerba Mate Premium 1kg',
        barcode: '7791234567890',
        internalCode: 'YM01',
        costPrice: 1500,
        sellingPrice: 2800,
        stock: 50,
        active: true,
        isSoldByWeight: false,
        category: Category(id: 10, name: 'Almacén'),
        brand: Brand(id: 20, name: 'Taragüi'),
      );

      final text = ProductShareHelper.formatProductShareText(product);

      expect(text, contains('📦 *Yerba Mate Premium 1kg*'));
      expect(text, contains('💰 Precio: \$2.800'));
      expect(text, contains('🏷️ Código de Barras: 7791234567890'));
      expect(text, contains('🔢 Código Interno: YM01'));
      expect(text, contains('📂 Categoría: Almacén'));
      expect(text, contains('🏭 Marca: Taragüi'));
      expect(text, isNot(contains('⚖️ Venta por Peso')));
    });

    test('formatProductShareText formats minimally without crashing for basic product', () {
      final product = Product(
        id: 2,
        name: 'Pan Casero',
        internalCode: 'PAN01',
        costPrice: 500,
        sellingPrice: 900,
        stock: 15,
        active: true,
        isSoldByWeight: true,
      );

      final text = ProductShareHelper.formatProductShareText(product);

      expect(text, contains('📦 *Pan Casero*'));
      expect(text, contains('💰 Precio: \$900'));
      expect(text, contains('🔢 Código Interno: PAN01'));
      expect(text, contains('⚖️ Venta por Peso'));
      expect(text, isNot(contains('🏷️ Código de Barras:')));
      expect(text, isNot(contains('📂 Categoría:')));
      expect(text, isNot(contains('🏭 Marca:')));
    });

    test('shareProduct shares text-only when product has no imageUrl', () async {
      final product = Product(
        id: 3,
        name: 'Arroz 1kg',
        internalCode: 'ARR01',
        costPrice: 800,
        sellingPrice: 1300,
        stock: 20,
        active: true,
        isSoldByWeight: false,
      );

      String? sharedText;
      String? sharedSubject;
      List<XFile>? sharedFiles;

      await ProductShareHelper.shareProduct(
        product,
        shareTextFn: (text, {subject}) async {
          sharedText = text;
          sharedSubject = subject;
        },
        shareFilesFn: (files, {text, subject}) async {
          sharedFiles = files;
        },
      );

      expect(sharedFiles, isNull);
      expect(sharedText, isNotNull);
      expect(sharedText, contains('Arroz 1kg'));
      expect(sharedSubject, equals('Arroz 1kg'));
    });

    test('shareProduct downloads image to temp file and shares XFiles when imageUrl is valid', () async {
      final product = Product(
        id: 4,
        name: 'Galletitas Chocolate',
        internalCode: 'GAL01',
        costPrice: 600,
        sellingPrice: 1100,
        stock: 30,
        active: true,
        isSoldByWeight: false,
        imageUrl: 'http://example.com/images/galletitas.png',
      );

      final mockPngBytes = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
      final mockClient = MockClient((request) async {
        if (request.url.toString() == 'http://example.com/images/galletitas.png') {
          return http.Response.bytes(mockPngBytes, 200);
        }
        return http.Response('Not Found', 404);
      });

      final testTempDir = await Directory.systemTemp.createTemp('share_test_');

      List<XFile>? sharedFiles;
      String? sharedText;
      String? sharedSubject;

      try {
        await ProductShareHelper.shareProduct(
          product,
          httpClient: mockClient,
          getTempDir: () async => testTempDir,
          shareFilesFn: (files, {text, subject}) async {
            sharedFiles = files;
            sharedText = text;
            sharedSubject = subject;
          },
        );

        expect(sharedFiles, isNotNull);
        expect(sharedFiles!.length, equals(1));
        expect(sharedFiles!.first.path, contains('producto_4.png'));
        expect(File(sharedFiles!.first.path).existsSync(), isTrue);
        expect(await File(sharedFiles!.first.path).readAsBytes(), equals(mockPngBytes));
        expect(sharedText, contains('Galletitas Chocolate'));
        expect(sharedSubject, equals('Galletitas Chocolate'));
      } finally {
        if (testTempDir.existsSync()) {
          testTempDir.deleteSync(recursive: true);
        }
      }
    });

    test('shareProduct gracefully falls back to text share when image download fails (404/error)', () async {
      final product = Product(
        id: 5,
        name: 'Leche Descremada',
        internalCode: 'LEC01',
        costPrice: 900,
        sellingPrice: 1500,
        stock: 12,
        active: true,
        isSoldByWeight: false,
        imageUrl: 'http://example.com/images/not_found.jpg',
      );

      final mockClient = MockClient((request) async {
        return http.Response('Not found', 404);
      });

      String? fallbackText;
      String? fallbackSubject;
      List<XFile>? sharedFiles;

      await ProductShareHelper.shareProduct(
        product,
        httpClient: mockClient,
        shareTextFn: (text, {subject}) async {
          fallbackText = text;
          fallbackSubject = subject;
        },
        shareFilesFn: (files, {text, subject}) async {
          sharedFiles = files;
        },
      );

      expect(sharedFiles, isNull);
      expect(fallbackText, isNotNull);
      expect(fallbackText, contains('Leche Descremada'));
      expect(fallbackSubject, equals('Leche Descremada'));
    });
  });

  group('Milestone 4: ProductFormDialog Share Button Widget Tests', () {
    Widget buildDialogTestWidget({Product? product}) {
      final catalogProv = FakeCatalogProvider();
      final settingsProv = FakeSettingsProvider();
      final supplierProv = FakeSupplierProvider();

      return MultiProvider(
        providers: [
          ChangeNotifierProvider<CatalogProvider>.value(value: catalogProv),
          ChangeNotifierProvider<SettingsProvider>.value(value: settingsProv),
          ChangeNotifierProvider<SupplierProvider>.value(value: supplierProv),
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
                child: const Text('Abrir Dialog'),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('Shows Share button in title when editing an existing product', (tester) async {
      final existingProduct = Product(
        id: 42,
        name: 'Aceite de Oliva 500ml',
        barcode: '7790001112223',
        internalCode: 'ACE01',
        costPrice: 3200,
        sellingPrice: 4800,
        stock: 10,
        active: true,
        isSoldByWeight: false,
      );

      await tester.pumpWidget(buildDialogTestWidget(product: existingProduct));
      await tester.tap(find.text('Abrir Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Editar Producto'), findsOneWidget);
      expect(find.byKey(const Key('product_share_button')), findsOneWidget);
      expect(find.byTooltip('Compartir producto'), findsOneWidget);
      expect(find.byIcon(Icons.share_outlined), findsOneWidget);
    });

    testWidgets('Does NOT show Share button when creating a new product', (tester) async {
      await tester.pumpWidget(buildDialogTestWidget(product: null));
      await tester.tap(find.text('Abrir Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Nuevo Producto'), findsOneWidget);
      expect(find.byKey(const Key('product_share_button')), findsNothing);
      expect(find.byTooltip('Compartir producto'), findsNothing);
      expect(find.byIcon(Icons.share_outlined), findsNothing);
    });
  });
}
