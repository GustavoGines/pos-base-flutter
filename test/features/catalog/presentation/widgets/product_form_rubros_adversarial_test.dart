import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend_desktop/features/catalog/domain/entities/brand.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/category.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/rubro.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/catalog/presentation/pages/catalog_screen.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/features/suppliers/models/supplier_model.dart';
import 'package:frontend_desktop/features/suppliers/providers/supplier_provider.dart';

// --- FAKES FOR ADVERSARIAL STRESS TESTING ---
class FakeCatalogProvider extends ChangeNotifier implements CatalogProvider {
  List<Category> _categories = [];
  List<Brand> _brands = [];
  List<Rubro> _rubros = [];

  FakeCatalogProvider({
    List<Category>? categories,
    List<Brand>? brands,
    List<Rubro>? rubros,
  }) {
    _categories = categories ?? [
      Category(id: 1, name: 'Bebidas'),
      Category(id: 2, name: 'Snacks'),
      Category(id: 3, name: 'Almacén'),
    ];
    _brands = brands ?? [Brand(id: 1, name: 'Genérica')];
    _rubros = rubros ?? [Rubro(id: 1, name: 'General', isSystem: true)];
  }

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

  Map<String, dynamic>? lastSubmittedData;
  String? lastCreatedCatName;
  int? lastCreatedCatRubroId;

  @override
  Future<bool> createProduct(Map<String, dynamic> data) async {
    lastSubmittedData = data;
    return true;
  }

  @override
  Future<bool> updateProduct(int id, Map<String, dynamic> data) async {
    lastSubmittedData = data;
    return true;
  }

  @override
  Future<int?> createCategory(String name, {String? description, int? rubroId}) async {
    lastCreatedCatName = name;
    lastCreatedCatRubroId = rubroId;
    final newCat = Category(id: 999, name: name, description: description, rubroId: rubroId);
    _categories.add(newCat);
    notifyListeners();
    return newCat.id;
  }

  @override
  Future<int?> createBrand(String name, {String? description}) async {
    final newBrand = Brand(id: 888, name: name);
    _brands.add(newBrand);
    notifyListeners();
    return newBrand.id;
  }

  @override
  Future<void> loadRubros() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSettingsProvider extends ChangeNotifier implements SettingsProvider {
  BusinessSettings _settings;

  FakeSettingsProvider({required BusinessSettings settings}) : _settings = settings;

  @override
  BusinessSettings? get settings => _settings;
  @override
  String get currentPlan => _settings.licensePlanType ?? 'basic';
  @override
  FeatureFlags get features => _settings.features;
  @override
  bool hasFeature(String featureName) => _settings.hasFeature(featureName);

  void setPlan({required String plan, required bool multiRubro}) {
    _settings = BusinessSettings(
      licensePlanType: plan,
      features: FeatureFlags(multiRubro: multiRubro),
    );
    notifyListeners();
  }

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
      'pos_terminal_id': 'caja-test-adversarial',
      'pos_api': 'http://localhost/api',
    });
  });

  Widget buildTestApp({
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
              child: const Text('Open Product Dialog'),
            ),
          ),
        ),
      ),
    );
  }

  group('Adversarial Group 1: Visual & Layout Stress Testing', () {
    testWidgets('1.1 Extreme compact viewport 320x480 with 25+ categories in dropdown: no RenderFlex overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final manyCategories = List.generate(
        30,
        (i) => Category(id: i + 1, name: 'Categoría Rubro #${i + 1} Extremadamente Larga y Detallada'),
      );

      final catalogProv = FakeCatalogProvider(categories: manyCategories);
      final settingsProv = FakeSettingsProvider(
        settings: const BusinessSettings(
          licensePlanType: 'premium',
          features: FeatureFlags(multiRubro: true),
        ),
      );

      final product = Product(
        id: 501,
        name: 'Producto con 30 Categorias',
        internalCode: '18001',
        costPrice: 100,
        sellingPrice: 150,
        stock: 10,
        active: true,
        isSoldByWeight: false,
        category: manyCategories.first,
      );

      await tester.pumpWidget(buildTestApp(
        catalogProv: catalogProv,
        settingsProv: settingsProv,
        product: product,
      ));
      await tester.tap(find.text('Open Product Dialog'));
      await tester.pumpAndSettle();

      // Invariant 1: No RenderFlex overflow
      expect(tester.takeException(), isNull);

      // Invariant 2: Single dropdown exists and is visible
      expect(find.byType(DropdownButtonFormField<int?>), findsNWidgets(2)); // Category & Brand
      expect(find.text('Categoría Rubro #1 Extremadamente Larga y Detallada'), findsOneWidget);
    });

    testWidgets('1.2 Extreme compact viewports (280x480 and 300x500): no RenderFlex overflow', (tester) async {
      for (final size in [const Size(280, 480), const Size(300, 500)]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;

        final catalogProv = FakeCatalogProvider();
        final settingsProv = FakeSettingsProvider(
          settings: const BusinessSettings(
            licensePlanType: 'basic',
            features: FeatureFlags(multiRubro: false),
          ),
        );

        await tester.pumpWidget(buildTestApp(catalogProv: catalogProv, settingsProv: settingsProv));
        await tester.tap(find.text('Open Product Dialog'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull, reason: 'Failed at size $size');

        // Close dialog
        final cancelButton = find.text('Cancelar');
        if (cancelButton.evaluate().isNotEmpty) {
          await tester.tap(cancelButton);
          await tester.pumpAndSettle();
        }
      }
      tester.view.resetPhysicalSize();
    });

    testWidgets('1.3 Extremely long category name (100+ chars): ellipsizes cleanly without RenderFlex overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const extremeLongName = 'Rubro con nombre extremadamente largo para probar truncado y overflow de caracteres en dropdowns y selecciones';
      final longCategory = Category(id: 999, name: extremeLongName);

      final catalogProv = FakeCatalogProvider(categories: [longCategory]);
      final settingsProv = FakeSettingsProvider(
        settings: const BusinessSettings(
          licensePlanType: 'premium',
          features: FeatureFlags(multiRubro: true),
        ),
      );

      final product = Product(
        id: 777,
        name: 'Producto Nombre Largo',
        internalCode: '77701',
        costPrice: 10,
        sellingPrice: 20,
        stock: 5,
        active: true,
        isSoldByWeight: false,
        category: longCategory,
      );

      await tester.pumpWidget(buildTestApp(
        catalogProv: catalogProv,
        settingsProv: settingsProv,
        product: product,
      ));
      await tester.tap(find.text('Open Product Dialog'));
      await tester.pumpAndSettle();

      // No RenderFlex exception despite huge label
      expect(tester.takeException(), isNull);
      expect(find.text(extremeLongName), findsOneWidget);
    });

    testWidgets('1.4 Responsiveness: width < 450px collapses paired rows into vertical Columns', (tester) async {
      tester.view.physicalSize = const Size(400, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final catalogProv = FakeCatalogProvider();
      final settingsProv = FakeSettingsProvider(
        settings: const BusinessSettings(
          licensePlanType: 'basic',
          features: FeatureFlags(multiRubro: false),
        ),
      );

      await tester.pumpWidget(buildTestApp(catalogProv: catalogProv, settingsProv: settingsProv));
      await tester.tap(find.text('Open Product Dialog'));
      await tester.pumpAndSettle();

      // Verify that the form content renders
      expect(find.text('PLU (Interno) *'), findsOneWidget);
      expect(find.text('Código de Barras (EAN)'), findsOneWidget);
      expect(find.text('Categoría'), findsOneWidget);
      expect(find.text('Marca'), findsOneWidget);

      // Verify PLU and Barcode are stacked vertically (Column), so PLU is above Barcode in dy
      final pluPos = tester.getCenter(find.text('PLU (Interno) *'));
      final barcodePos = tester.getCenter(find.text('Código de Barras (EAN)'));
      expect(pluPos.dy, lessThan(barcodePos.dy), reason: 'PLU should be above Barcode in narrow mode (stacked Column)');

      // Verify Category and Brand are stacked vertically
      final catPos = tester.getCenter(find.text('Categoría'));
      final brandPos = tester.getCenter(find.text('Marca'));
      expect(catPos.dy, lessThan(brandPos.dy), reason: 'Category should be above Brand in narrow mode (stacked Column)');
    });

    testWidgets('1.5 Responsiveness: width >= 450px keeps paired rows in horizontal Rows', (tester) async {
      tester.view.physicalSize = const Size(800, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final catalogProv = FakeCatalogProvider();
      final settingsProv = FakeSettingsProvider(
        settings: const BusinessSettings(
          licensePlanType: 'basic',
          features: FeatureFlags(multiRubro: false),
        ),
      );

      await tester.pumpWidget(buildTestApp(catalogProv: catalogProv, settingsProv: settingsProv));
      await tester.tap(find.text('Open Product Dialog'));
      await tester.pumpAndSettle();

      // In wide mode, PLU and Barcode are side-by-side (same or nearly same dy)
      final pluPos = tester.getCenter(find.text('PLU (Interno) *'));
      final barcodePos = tester.getCenter(find.text('Código de Barras (EAN)'));
      expect((pluPos.dy - barcodePos.dy).abs(), lessThan(5.0), reason: 'PLU and Barcode should be side-by-side in wide mode');
    });

    testWidgets('1.6 Extreme compact viewport 320x480: opening Quick Category modal renders without overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final catalogProv = FakeCatalogProvider(
        categories: [Category(id: 1, name: 'Bebidas')],
        rubros: [Rubro(id: 1, name: 'Alimentos y Bebidas', isSystem: true)],
      );
      final settingsProv = FakeSettingsProvider(
        settings: const BusinessSettings(
          licensePlanType: 'premium',
          features: FeatureFlags(multiRubro: true),
        ),
      );

      await tester.pumpWidget(buildTestApp(catalogProv: catalogProv, settingsProv: settingsProv));
      await tester.tap(find.text('Open Product Dialog'));
      await tester.pumpAndSettle();

      final addCatBtn = find.byTooltip('Crear categoría');
      expect(addCatBtn, findsOneWidget);

      await tester.ensureVisible(addCatBtn);
      await tester.pumpAndSettle();

      await tester.tap(addCatBtn);
      await tester.pumpAndSettle();

      expect(find.text('Nueva Categoría'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Dismiss modal
      await tester.tap(find.text('Cancelar').last);
      await tester.pumpAndSettle();
    });
  });

  group('Adversarial Group 2: Business Logic & Invariant Stress Testing', () {
    testWidgets('2.1 Both Basic and Premium strictly use single Category dropdown (NO chips, NO Asignar Rubros, NO PRO badge)', (tester) async {
      for (final isPrem in [false, true]) {
        final catalogProv = FakeCatalogProvider();
        final settingsProv = FakeSettingsProvider(
          settings: BusinessSettings(
            licensePlanType: isPrem ? 'premium' : 'basic',
            features: FeatureFlags(multiRubro: isPrem),
          ),
        );

        await tester.pumpWidget(buildTestApp(catalogProv: catalogProv, settingsProv: settingsProv));
        await tester.tap(find.text('Open Product Dialog'));
        await tester.pumpAndSettle();

        // UI strictly shows single Dropdown, NO multi-select chip interface
        expect(find.byType(DropdownButtonFormField<int?>), findsWidgets);
        expect(find.text('Asignar Rubros'), findsNothing);
        expect(find.text('PRO'), findsNothing);
        expect(find.byIcon(Icons.workspace_premium), findsNothing);

        // Close
        await tester.tap(find.text('Cancelar'));
        await tester.pumpAndSettle();
      }
    });

    testWidgets('2.2 Quick Category Creation in Basic Plan: displays category name only, hides parent Rubro dropdown', (tester) async {
      final catalogProv = FakeCatalogProvider();
      final settingsProv = FakeSettingsProvider(
        settings: const BusinessSettings(
          licensePlanType: 'basic',
          features: FeatureFlags(multiRubro: false),
        ),
      );

      await tester.pumpWidget(buildTestApp(catalogProv: catalogProv, settingsProv: settingsProv));
      await tester.tap(find.text('Open Product Dialog'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Crear categoría'));
      await tester.pumpAndSettle();

      expect(find.text('Nueva Categoría'), findsOneWidget);
      expect(find.text('Nombre *'), findsOneWidget);
      expect(find.text('Rubro Padre'), findsNothing);

      // Dismiss
      await tester.tap(find.text('Cancelar').last);
      await tester.pumpAndSettle();
    });

    testWidgets('2.3 Quick Category Creation in Premium Plan: displays parent Rubro dropdown', (tester) async {
      final catalogProv = FakeCatalogProvider(
        rubros: [
          Rubro(id: 10, name: 'Rubro Premium Alpha'),
          Rubro(id: 20, name: 'Rubro Premium Beta'),
        ],
      );
      final settingsProv = FakeSettingsProvider(
        settings: const BusinessSettings(
          licensePlanType: 'premium',
          features: FeatureFlags(multiRubro: true),
        ),
      );

      await tester.pumpWidget(buildTestApp(catalogProv: catalogProv, settingsProv: settingsProv));
      await tester.tap(find.text('Open Product Dialog'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Crear categoría'));
      await tester.pumpAndSettle();

      expect(find.text('Nueva Categoría'), findsOneWidget);
      expect(find.text('Nombre *'), findsOneWidget);
      expect(find.text('Rubro Padre'), findsOneWidget);
      expect(find.text('Rubro Premium Alpha'), findsOneWidget);

      // Dismiss
      await tester.tap(find.text('Cancelar').last);
      await tester.pumpAndSettle();
    });

    testWidgets('2.4 Quick Category creation immediately selects newly created category in the dropdown', (tester) async {
      final catalogProv = FakeCatalogProvider();
      final settingsProv = FakeSettingsProvider(
        settings: const BusinessSettings(
          licensePlanType: 'basic',
          features: FeatureFlags(multiRubro: false),
        ),
      );

      await tester.pumpWidget(buildTestApp(catalogProv: catalogProv, settingsProv: settingsProv));
      await tester.tap(find.text('Open Product Dialog'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Crear categoría'));
      await tester.pumpAndSettle();

      // Enter new category name and submit
      await tester.enterText(find.widgetWithText(TextField, 'Nombre *'), 'Frescos');
      await tester.tap(find.text('Crear'));
      await tester.pumpAndSettle();

      expect(find.text('Nueva Categoría'), findsNothing);
      expect(find.text('Frescos'), findsOneWidget);
      expect(catalogProv.lastCreatedCatName, equals('Frescos'));
    });

    testWidgets('2.5 Form submission transmits exclusively category_id (eliminates obsolete fields)', (tester) async {
      final catalogProv = FakeCatalogProvider(
        categories: [Category(id: 7, name: 'Bazar')],
      );
      final settingsProv = FakeSettingsProvider(
        settings: const BusinessSettings(
          licensePlanType: 'premium',
          features: FeatureFlags(multiRubro: true),
        ),
      );

      final product = Product(
        id: 701,
        name: 'Plato Cerámica',
        internalCode: '07001',
        costPrice: 50,
        sellingPrice: 100,
        stock: 20,
        active: true,
        isSoldByWeight: false,
        category: Category(id: 7, name: 'Bazar'),
      );

      await tester.pumpWidget(buildTestApp(
        catalogProv: catalogProv,
        settingsProv: settingsProv,
        product: product,
      ));
      await tester.tap(find.text('Open Product Dialog'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar Cambios'));
      await tester.pumpAndSettle();

      expect(catalogProv.lastSubmittedData, isNotNull);
      expect(catalogProv.lastSubmittedData!['category_id'], equals(7));
      expect(catalogProv.lastSubmittedData!.containsKey('category_ids'), isFalse);
      expect(catalogProv.lastSubmittedData!.containsKey('primary_category_id'), isFalse);
    });

    testWidgets('2.6 Product with null category submits correctly with null category_id', (tester) async {
      final catalogProv = FakeCatalogProvider(
        categories: [Category(id: 1, name: 'Bebidas')],
      );
      final settingsProv = FakeSettingsProvider(
        settings: const BusinessSettings(
          licensePlanType: 'basic',
          features: FeatureFlags(multiRubro: false),
        ),
      );

      await tester.pumpWidget(buildTestApp(catalogProv: catalogProv, settingsProv: settingsProv));
      await tester.tap(find.text('Open Product Dialog'));
      await tester.pumpAndSettle();

      // Fill required fields
      await tester.enterText(find.widgetWithText(TextFormField, 'Nombre del Producto *'), 'Producto Sin Cat');
      await tester.enterText(find.widgetWithText(TextFormField, 'PLU (Interno) *'), '12345');
      await tester.enterText(find.widgetWithText(TextFormField, 'Precio Costo'), '10');
      await tester.enterText(find.widgetWithText(TextFormField, 'Precio Venta *'), '20');

      await tester.tap(find.text('Crear Producto'));
      await tester.pumpAndSettle();

      expect(catalogProv.lastSubmittedData, isNotNull);
      expect(catalogProv.lastSubmittedData!['category_id'], isNull);
      expect(catalogProv.lastSubmittedData!.containsKey('category_ids'), isFalse);
      expect(catalogProv.lastSubmittedData!.containsKey('primary_category_id'), isFalse);
    });
  });
}
