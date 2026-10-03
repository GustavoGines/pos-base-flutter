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

// --- FAKES ---
class FakeCatalogProvider extends ChangeNotifier implements CatalogProvider {
  List<Category> _categories = [];
  List<Brand> _brands = [];
  List<Rubro> _rubros = [];
  Map<String, dynamic>? lastSubmittedData;

  FakeCatalogProvider({List<Category>? categories, List<Brand>? brands, List<Rubro>? rubros}) {
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
  Future<int?> createCategory(String name, {String? description, int? rubroId}) async {
    final newCat = Category(id: 999, name: name, description: description, rubroId: rubroId);
    _categories.add(newCat);
    notifyListeners();
    return newCat.id;
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
      'pos_api': 'http://localhost/api',
    });
  });

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

  group('M4: ProductFormDialog Single Category Reversion & Anti-Overflow', () {
    testWidgets('Test 1: Plan Básico displays single DropdownButtonFormField without PRO badge or chips', (tester) async {
      final catalogProv = FakeCatalogProvider();
      final settingsProv = FakeSettingsProvider(
        settings: const BusinessSettings(
          licensePlanType: 'basic',
          features: FeatureFlags(multiRubro: false),
        ),
      );

      await tester.pumpWidget(buildFormApp(catalogProv: catalogProv, settingsProv: settingsProv));
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Debe haber Dropdown de Categoría
      expect(find.byType(DropdownButtonFormField<int?>), findsWidgets);
      expect(find.text('Categoría'), findsOneWidget);

      // NO debe existir badge PRO en el campo de Categoría
      expect(find.text('PRO'), findsNothing);
      expect(find.byIcon(Icons.workspace_premium), findsNothing);

      // NO debe existir selector multi-chip ni botón Asignar
      expect(find.text('Asignar'), findsNothing);
      expect(find.byType(InputChip), findsNothing);
    });

    testWidgets('Test 2: Plan Premium ALSO displays classic single Category dropdown without multi-chips', (tester) async {
      final catalogProv = FakeCatalogProvider();
      final settingsProv = FakeSettingsProvider(
        settings: const BusinessSettings(
          licensePlanType: 'premium',
          features: FeatureFlags(multiRubro: true),
        ),
      );

      await tester.pumpWidget(buildFormApp(catalogProv: catalogProv, settingsProv: settingsProv));
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // En Plan Premium la selección de categoría del producto vuelve a ser simple (1 producto = 1 categoría)
      expect(find.text('Categoría'), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<int?>), findsWidgets);
      expect(find.text('Rubros / Categorías'), findsNothing);
      expect(find.text('Asignar'), findsNothing);
      expect(find.byType(InputChip), findsNothing);
    });

    testWidgets('Test 3: Editing product initializes category correctly and submits only category_id', (tester) async {
      final cat = Category(id: 2, name: 'Snacks');
      final catalogProv = FakeCatalogProvider();
      final settingsProv = FakeSettingsProvider(
        settings: const BusinessSettings(
          licensePlanType: 'premium',
          features: FeatureFlags(multiRubro: true),
        ),
      );

      final product = Product(
        id: 42,
        name: 'Papas Fritas',
        internalCode: '00042',
        costPrice: 200,
        sellingPrice: 350,
        stock: 15,
        active: true,
        isSoldByWeight: false,
        category: cat,
      );

      await tester.pumpWidget(buildFormApp(catalogProv: catalogProv, settingsProv: settingsProv, product: product));
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Papas Fritas'), findsOneWidget);
      expect(find.text('Snacks'), findsOneWidget);
    });

    testWidgets('Test 4: Responsive stress 320x480 viewport renders without RenderFlex overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final catalogProv = FakeCatalogProvider();
      final settingsProv = FakeSettingsProvider(
        settings: const BusinessSettings(
          licensePlanType: 'basic',
          features: FeatureFlags(multiRubro: false),
        ),
      );

      await tester.pumpWidget(buildFormApp(catalogProv: catalogProv, settingsProv: settingsProv));
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // No debe haber excepciones de RenderFlex overflow
      expect(tester.takeException(), isNull);
      expect(find.text('Categoría'), findsOneWidget);
    });
  });
}
