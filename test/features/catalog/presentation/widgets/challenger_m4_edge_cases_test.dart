import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend_desktop/features/catalog/domain/entities/brand.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/category.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/rubro.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/catalog/presentation/pages/catalog_screen.dart';
import 'package:frontend_desktop/features/catalog/presentation/widgets/categories_manager_dialog.dart';
import 'package:frontend_desktop/features/catalog/presentation/widgets/rubros_manager_dialog.dart';
import 'package:frontend_desktop/core/presentation/widgets/plan_upgrade_dialog.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/features/suppliers/models/supplier_model.dart';
import 'package:frontend_desktop/features/suppliers/providers/supplier_provider.dart';

import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';

// --- ADVERSARIAL FAKES ---
class TestCatalogProvider extends ChangeNotifier implements CatalogProvider {
  final List<Category> _categories;
  final List<Brand> _brands;
  final List<Rubro> _rubros;

  Map<String, dynamic>? lastSubmittedData;
  String? lastCreatedCategoryName;
  int? lastCreatedCategoryRubroId;
  int? lastUpdatedCategoryRubroId;
  int? lastDeletedRubroId;

  TestCatalogProvider({
    List<Category>? categories,
    List<Brand>? brands,
    List<Rubro>? rubros,
  })  : _categories = categories ?? [
          Category(id: 1, name: 'Bebidas', rubroId: 10, rubro: Rubro(id: 10, name: 'Kiosko', isSystem: true)),
          Category(id: 2, name: 'Herramientas', rubroId: 20, rubro: Rubro(id: 20, name: 'Ferretería', isSystem: false)),
        ],
        _brands = brands ?? [Brand(id: 1, name: 'Marca 1')],
        _rubros = rubros ?? [
          Rubro(id: 10, name: 'Kiosko', isSystem: true),
          Rubro(id: 20, name: 'Ferretería', isSystem: false),
        ];

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
  List<Product> get products => [];
  @override
  int get lastPage => 1;
  @override
  int get currentPage => 1;
  @override
  bool get hasPrevPage => false;
  @override
  bool get hasNextPage => false;

  @override
  Future<void> loadProducts({int page = 1, String? search, String? sortBy, String? sortDirection}) async {}
  @override
  Future<void> loadMetadata() async {}
  @override
  Future<void> loadRubros() async {}

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
    lastCreatedCategoryName = name;
    lastCreatedCategoryRubroId = rubroId;
    final newCat = Category(
      id: _categories.length + 100,
      name: name,
      description: description,
      rubroId: rubroId,
      rubro: rubroId != null ? _rubros.where((r) => r.id == rubroId).firstOrNull : null,
    );
    _categories.add(newCat);
    notifyListeners();
    return newCat.id;
  }

  @override
  Future<bool> updateCategory(int id, String name, {String? description, int? rubroId}) async {
    lastUpdatedCategoryRubroId = rubroId;
    final idx = _categories.indexWhere((c) => c.id == id);
    if (idx != -1) {
      _categories[idx] = Category(
        id: id,
        name: name,
        description: description,
        rubroId: rubroId,
        rubro: rubroId != null ? _rubros.where((r) => r.id == rubroId).firstOrNull : null,
      );
      notifyListeners();
    }
    return true;
  }

  @override
  Future<bool> deleteCategory(int id) async {
    _categories.removeWhere((c) => c.id == id);
    notifyListeners();
    return true;
  }

  @override
  Future<int?> createRubro(String name, {String? description}) async {
    final newRubro = Rubro(
      id: _rubros.length + 50,
      name: name,
      description: description,
      isSystem: false,
    );
    _rubros.add(newRubro);
    notifyListeners();
    return newRubro.id;
  }

  @override
  Future<bool> updateRubro(int id, String name, {String? description}) async {
    final idx = _rubros.indexWhere((r) => r.id == id);
    if (idx != -1) {
      _rubros[idx] = Rubro(
        id: id,
        name: name,
        description: description,
        isSystem: _rubros[idx].isSystem,
      );
      notifyListeners();
    }
    return true;
  }

  @override
  Future<bool> deleteRubro(int id) async {
    lastDeletedRubroId = id;
    _rubros.removeWhere((r) => r.id == id);
    notifyListeners();
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestSettingsProvider extends ChangeNotifier implements SettingsProvider {
  BusinessSettings _settings;

  TestSettingsProvider({required BusinessSettings settings}) : _settings = settings;

  @override
  BusinessSettings? get settings => _settings;
  @override
  String get currentPlan => _settings.licensePlanType ?? 'basic';
  @override
  FeatureFlags get features => _settings.features;
  @override
  bool hasFeature(String featureName) => _settings.hasFeature(featureName);

  void updateSettings(BusinessSettings newSettings) {
    _settings = newSettings;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestSupplierProvider extends ChangeNotifier implements SupplierProvider {
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
      'pos_terminal_id': 'caja-challenger',
      'pos_api': 'http://localhost/api',
    });
  });

  Widget wrapWithHarness({
    required TestCatalogProvider catalogProv,
    required TestSettingsProvider settingsProv,
    required Widget child,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<CatalogProvider>.value(value: catalogProv),
        ChangeNotifierProvider<SettingsProvider>.value(value: settingsProv),
        ChangeNotifierProvider<SupplierProvider>.value(value: TestSupplierProvider()),
        ChangeNotifierProvider<LocalTerminalProvider>(create: (_) => LocalTerminalProvider()),
      ],
      child: MaterialApp(
        home: Scaffold(body: child),
      ),
    );
  }

  group('CHALLENGE 1: Product Null Category & Dropdown Null Selection', () {
    testWidgets('1.A: User can select "— Sin categoría —" in dropdown to unassign category and submit null', (tester) async {
      final catalogProv = TestCatalogProvider();
      final settingsProv = TestSettingsProvider(
        settings: const BusinessSettings(
          licensePlanType: 'basic',
          features: FeatureFlags(multiRubro: false),
        ),
      );

      final product = Product(
        id: 99,
        name: 'Producto Con Categoria',
        internalCode: '00099',
        costPrice: 50,
        sellingPrice: 100,
        stock: 5,
        active: true,
        isSoldByWeight: false,
        category: catalogProv.categories.first, // ID: 1
      );

      await tester.pumpWidget(wrapWithHarness(
        catalogProv: catalogProv,
        settingsProv: settingsProv,
        child: ProductFormDialog(provider: catalogProv, product: product),
      ));
      await tester.pumpAndSettle();

      // Product initially has "Bebidas"
      expect(find.text('Bebidas'), findsOneWidget);

      // Open the Category dropdown (the first dropdown on screen)
      final categoryDropdown = find.byType(DropdownButtonFormField<int?>).first;
      await tester.tap(categoryDropdown);
      await tester.pumpAndSettle();

      // Tap on "— Sin categoría —"
      final unassignOption = find.text('— Sin categoría —').last;
      await tester.tap(unassignOption);
      await tester.pumpAndSettle();

      // Submit changes
      await tester.tap(find.text('Guardar Cambios'));
      await tester.pumpAndSettle();

      expect(catalogProv.lastSubmittedData, isNotNull);
      expect(catalogProv.lastSubmittedData!['category_id'], isNull);
    });

    testWidgets('1.B: Product creation without selecting category leaves category_id as null', (tester) async {
      final catalogProv = TestCatalogProvider();
      final settingsProv = TestSettingsProvider(
        settings: const BusinessSettings(
          licensePlanType: 'basic',
          features: FeatureFlags(multiRubro: false),
        ),
      );

      await tester.pumpWidget(wrapWithHarness(
        catalogProv: catalogProv,
        settingsProv: settingsProv,
        child: ProductFormDialog(provider: catalogProv),
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'Nombre del Producto *'), 'Nuevo Item');
      await tester.enterText(find.widgetWithText(TextFormField, 'PLU (Interno) *'), '54321');
      await tester.enterText(find.widgetWithText(TextFormField, 'Precio Costo'), '100');
      await tester.enterText(find.widgetWithText(TextFormField, 'Precio Venta *'), '200');

      await tester.tap(find.text('Crear Producto'));
      await tester.pumpAndSettle();

      expect(catalogProv.lastSubmittedData, isNotNull);
      expect(catalogProv.lastSubmittedData!['category_id'], isNull);
    });

    testWidgets('1.C: Empty category list in provider renders cleanly with only "— Sin categoría —"', (tester) async {
      final catalogProv = TestCatalogProvider(categories: []);
      final settingsProv = TestSettingsProvider(
        settings: const BusinessSettings(
          licensePlanType: 'basic',
          features: FeatureFlags(multiRubro: false),
        ),
      );

      await tester.pumpWidget(wrapWithHarness(
        catalogProv: catalogProv,
        settingsProv: settingsProv,
        child: ProductFormDialog(provider: catalogProv),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('— Sin categoría —'), findsOneWidget);
    });
  });

  group('CHALLENGE 2: Category Creation Without Rubro in Basic Plan', () {
    testWidgets('2.A: CategoriesManagerDialog in Basic Plan creates category with rubroId == null', (tester) async {
      final catalogProv = TestCatalogProvider();
      final settingsProv = TestSettingsProvider(
        settings: const BusinessSettings(
          licensePlanType: 'basic',
          features: FeatureFlags(multiRubro: false),
        ),
      );

      await tester.pumpWidget(wrapWithHarness(
        catalogProv: catalogProv,
        settingsProv: settingsProv,
        child: const CategoriesManagerDialog(),
      ));
      await tester.pumpAndSettle();

      // Rubro Padre selector must not be rendered
      expect(find.text('Rubro Padre'), findsNothing);

      // Enter name and submit
      final inputField = find.byType(TextField).first;
      await tester.enterText(inputField, 'Verdulería');
      await tester.tap(find.text('Agregar'));
      await tester.pumpAndSettle();

      expect(catalogProv.lastCreatedCategoryName, equals('Verdulería'));
      expect(catalogProv.lastCreatedCategoryRubroId, isNull);
    });

    testWidgets('2.B: Quick Category Dialog in ProductFormDialog in Basic Plan creates category with rubroId == null', (tester) async {
      final catalogProv = TestCatalogProvider();
      final settingsProv = TestSettingsProvider(
        settings: const BusinessSettings(
          licensePlanType: 'basic',
          features: FeatureFlags(multiRubro: false),
        ),
      );

      await tester.pumpWidget(wrapWithHarness(
        catalogProv: catalogProv,
        settingsProv: settingsProv,
        child: ProductFormDialog(provider: catalogProv),
      ));
      await tester.pumpAndSettle();

      // Open quick category modal
      await tester.tap(find.byTooltip('Crear categoría'));
      await tester.pumpAndSettle();

      expect(find.text('Nueva Categoría'), findsOneWidget);
      expect(find.text('Rubro Padre'), findsNothing);

      await tester.enterText(find.widgetWithText(TextField, 'Nombre *'), 'Lácteos');
      await tester.tap(find.text('Crear'));
      await tester.pumpAndSettle();

      expect(catalogProv.lastCreatedCategoryName, equals('Lácteos'));
      expect(catalogProv.lastCreatedCategoryRubroId, isNull);
    });
  });

  group('CHALLENGE 3: Premium Plan Category Custom Rubro Assignment', () {
    testWidgets('3.A: CategoriesManagerDialog in Premium Plan allows selecting custom rubro', (tester) async {
      final catalogProv = TestCatalogProvider();
      final settingsProv = TestSettingsProvider(
        settings: const BusinessSettings(
          licensePlanType: 'premium',
          features: FeatureFlags(multiRubro: true),
        ),
      );

      await tester.pumpWidget(wrapWithHarness(
        catalogProv: catalogProv,
        settingsProv: settingsProv,
        child: const CategoriesManagerDialog(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Rubro Padre'), findsOneWidget);

      // Select "Ferretería" (ID: 20) instead of the default "Kiosko" (ID: 10)
      final rubroDropdown = find.byType(DropdownButtonFormField<int?>).first;
      await tester.tap(rubroDropdown);
      await tester.pumpAndSettle();

      final ferreteriaOption = find.text('Ferretería').last;
      await tester.tap(ferreteriaOption);
      await tester.pumpAndSettle();

      // Enter category name
      final nameField = find.byType(TextField).first;
      await tester.enterText(nameField, 'Bulonería');
      await tester.tap(find.text('Agregar'));
      await tester.pumpAndSettle();

      expect(catalogProv.lastCreatedCategoryName, equals('Bulonería'));
      expect(catalogProv.lastCreatedCategoryRubroId, equals(20));
    });

    testWidgets('3.B: Editing existing category in Premium Plan allows reassigning to another rubro', (tester) async {
      final catalogProv = TestCatalogProvider();
      final settingsProv = TestSettingsProvider(
        settings: const BusinessSettings(
          licensePlanType: 'premium',
          features: FeatureFlags(multiRubro: true),
        ),
      );

      await tester.pumpWidget(wrapWithHarness(
        catalogProv: catalogProv,
        settingsProv: settingsProv,
        child: const CategoriesManagerDialog(),
      ));
      await tester.pumpAndSettle();

      // Tap edit on first category ("Bebidas", currently rubroId 10)
      final editBtn = find.byTooltip('Editar').first;
      await tester.tap(editBtn);
      await tester.pumpAndSettle();

      // Change rubro to Ferretería (ID: 20)
      final editRubroDropdown = find.byType(DropdownButtonFormField<int?>).last;
      await tester.tap(editRubroDropdown);
      await tester.pumpAndSettle();

      final ferreteriaOption = find.text('Ferretería').last;
      await tester.tap(ferreteriaOption);
      await tester.pumpAndSettle();

      // Tap save
      final saveBtn = find.byTooltip('Guardar');
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(catalogProv.lastUpdatedCategoryRubroId, equals(20));
    });

    testWidgets('3.C: Quick Category modal in Premium Plan allows selecting custom rubro', (tester) async {
      final catalogProv = TestCatalogProvider();
      final settingsProv = TestSettingsProvider(
        settings: const BusinessSettings(
          licensePlanType: 'premium',
          features: FeatureFlags(multiRubro: true),
        ),
      );

      await tester.pumpWidget(wrapWithHarness(
        catalogProv: catalogProv,
        settingsProv: settingsProv,
        child: ProductFormDialog(provider: catalogProv),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Crear categoría'));
      await tester.pumpAndSettle();

      expect(find.text('Rubro Padre'), findsOneWidget);

      // Select Ferretería (ID: 20) inside the Quick Category dialog
      final quickCategoryDialog = find.widgetWithText(AlertDialog, 'Nueva Categoría');
      final rubroDropdown = find.descendant(
        of: quickCategoryDialog,
        matching: find.byType(DropdownButtonFormField<int?>),
      );
      await tester.tap(rubroDropdown);
      await tester.pumpAndSettle();

      final ferreteriaOption = find.text('Ferretería').last;
      await tester.tap(ferreteriaOption);
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, 'Nombre *'), 'Pinturas Sintéticas');
      await tester.tap(find.text('Crear'));
      await tester.pumpAndSettle();

      expect(catalogProv.lastCreatedCategoryName, equals('Pinturas Sintéticas'));
      expect(catalogProv.lastCreatedCategoryRubroId, equals(20));
    });
  });

  group('CHALLENGE 4: System Rubro Deletion Prevention in UI', () {
    testWidgets('4.A: System rubro displays lock icon and has NO delete button; non-system rubro has delete button', (tester) async {
      final catalogProv = TestCatalogProvider();

      await tester.pumpWidget(wrapWithHarness(
        catalogProv: catalogProv,
        settingsProv: TestSettingsProvider(
          settings: const BusinessSettings(
            licensePlanType: 'premium',
            features: FeatureFlags(multiRubro: true),
          ),
        ),
        child: const RubrosManagerDialog(),
      ));
      await tester.pumpAndSettle();

      // Check System Rubro ("Kiosko", isSystem: true)
      expect(find.text('Kiosko'), findsOneWidget);
      expect(find.text('Principal'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);

      // Exactly 1 delete button (for "Ferretería", isSystem: false)
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    });

    testWidgets('4.B: Deleting non-system rubro prompts confirmation and executes deleteRubro', (tester) async {
      final catalogProv = TestCatalogProvider();

      await tester.pumpWidget(wrapWithHarness(
        catalogProv: catalogProv,
        settingsProv: TestSettingsProvider(
          settings: const BusinessSettings(
            licensePlanType: 'premium',
            features: FeatureFlags(multiRubro: true),
          ),
        ),
        child: const RubrosManagerDialog(),
      ));
      await tester.pumpAndSettle();

      // Tap delete button of Ferretería
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      expect(find.text('Confirmar eliminación'), findsOneWidget);
      expect(find.text('¿Eliminar el rubro "Ferretería"?\n\nSi tiene categorías asociadas, la operación será rechazada.'), findsOneWidget);

      // Confirm
      await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
      await tester.pumpAndSettle();

      expect(catalogProv.lastDeletedRubroId, equals(20));
      expect(find.text('Ferretería'), findsNothing);
    });
  });

  group('CHALLENGE 5: Rubros Action Plan Gating', () {
    testWidgets('5.A: Opening Rubros in Basic Plan displays PlanUpgradeDialog', (tester) async {
      final settingsProv = TestSettingsProvider(
        settings: const BusinessSettings(
          licensePlanType: 'basic',
          features: FeatureFlags(multiRubro: false),
        ),
      );

      await tester.pumpWidget(wrapWithHarness(
        catalogProv: TestCatalogProvider(),
        settingsProv: settingsProv,
        child: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () {
              final hasMultiRubro = context.read<SettingsProvider>().features.multiRubro;
              if (!hasMultiRubro) {
                PlanUpgradeDialog.show(
                  context,
                  featureName: 'Gestión de Rubros',
                  description: 'La gestión de múltiples rubros comerciales es exclusiva del Plan Premium.',
                );
                return;
              }
              showDialog(context: context, builder: (_) => const RubrosManagerDialog());
            },
            child: const Text('Gestionar Rubros'),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Gestionar Rubros'));
      await tester.pumpAndSettle();

      expect(find.byType(PlanUpgradeDialog), findsOneWidget);
      expect(find.text('Gestión de Rubros'), findsOneWidget);
      expect(find.text('La gestión de múltiples rubros comerciales es exclusiva del Plan Premium.'), findsOneWidget);
    });

    testWidgets('5.B: Opening Rubros in Premium Plan opens RubrosManagerDialog', (tester) async {
      final settingsProv = TestSettingsProvider(
        settings: const BusinessSettings(
          licensePlanType: 'premium',
          features: FeatureFlags(multiRubro: true),
        ),
      );

      await tester.pumpWidget(wrapWithHarness(
        catalogProv: TestCatalogProvider(),
        settingsProv: settingsProv,
        child: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () {
              final hasMultiRubro = context.read<SettingsProvider>().features.multiRubro;
              if (!hasMultiRubro) {
                PlanUpgradeDialog.show(
                  context,
                  featureName: 'Gestión de Rubros',
                  description: 'La gestión de múltiples rubros comerciales es exclusiva del Plan Premium.',
                );
                return;
              }
              showDialog(context: context, builder: (_) => const RubrosManagerDialog());
            },
            child: const Text('Gestionar Rubros'),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Gestionar Rubros'));
      await tester.pumpAndSettle();

      expect(find.byType(RubrosManagerDialog), findsOneWidget);
      expect(find.text('Gestión de Rubros'), findsOneWidget);
    });
  });
}
