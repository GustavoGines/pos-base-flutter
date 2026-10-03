import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend_desktop/features/catalog/domain/entities/brand.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/category.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/rubro.dart';
import 'package:frontend_desktop/features/catalog/presentation/pages/catalog_screen.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/features/catalog/presentation/widgets/categories_manager_dialog.dart';
import 'package:frontend_desktop/features/catalog/presentation/widgets/rubros_manager_dialog.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/features/suppliers/models/supplier_model.dart';
import 'package:frontend_desktop/features/suppliers/providers/supplier_provider.dart';

class AdversarialCatalogProvider extends ChangeNotifier implements CatalogProvider {
  final List<Category> _categories;
  final List<Brand> _brands;
  final List<Rubro> _rubros;
  final bool _isLoading = false;
  final String? _errorMessage = null;

  AdversarialCatalogProvider({
    List<Category>? categories,
    List<Brand>? brands,
    List<Rubro>? rubros,
  })  : _categories = categories ?? [],
        _brands = brands ?? [Brand(id: 1, name: 'Marca Estándar')],
        _rubros = rubros ?? [Rubro(id: 1, name: 'Rubro General', isSystem: true)];

  @override
  List<Category> get categories => _categories;
  @override
  List<Brand> get brands => _brands;
  @override
  List<Rubro> get rubros => _rubros;
  @override
  bool get isLoading => _isLoading;
  @override
  String? get errorMessage => _errorMessage;

  @override
  Future<void> loadRubros() async {}

  @override
  Future<bool> createProduct(Map<String, dynamic> data) async => true;

  @override
  Future<bool> updateProduct(int id, Map<String, dynamic> data) async => true;

  @override
  Future<int?> createCategory(String name, {String? description, int? rubroId}) async {
    final newCat = Category(
      id: _categories.length + 1000,
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
      id: _rubros.length + 500,
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
    _rubros.removeWhere((r) => r.id == id);
    notifyListeners();
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class AdversarialSettingsProvider extends ChangeNotifier implements SettingsProvider {
  final BusinessSettings _settings;

  AdversarialSettingsProvider({required BusinessSettings settings}) : _settings = settings;

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

class AdversarialSupplierProvider extends ChangeNotifier implements SupplierProvider {
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
      'pos_terminal_id': 'caja-adversarial-viewport',
      'pos_api': 'http://localhost/api',
    });
  });

  Widget createHarness({
    required Widget child,
    required AdversarialCatalogProvider catalogProv,
    required AdversarialSettingsProvider settingsProv,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<CatalogProvider>.value(value: catalogProv),
        ChangeNotifierProvider<SettingsProvider>.value(value: settingsProv),
        ChangeNotifierProvider<SupplierProvider>.value(value: AdversarialSupplierProvider()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => showDialog(context: ctx, builder: (_) => child),
              child: const Text('Open Dialog Under Test'),
            ),
          ),
        ),
      ),
    );
  }

  group('CHALLENGER STRESS SUITE: 320x480 & 280x480 Viewports & 100+ Char Strings', () {
    const extreme100CharWithSpaces =
        'Rubro Comercial de Pruebas Adversariales con Mas de Cien Caracteres Exactamente Para Overflow 1234567890';
    const extreme100CharWithoutSpaces =
        'RubroSinEspaciosExtremadamenteLargoConMasDeCienCaracteresContinuosSinEspaciosNiSaltosDeLinea1234567890';

    testWidgets('T1: ProductFormDialog at 280x480 and 320x480 with 100+ char strings in Category & Brand: ZERO RenderFlex overflow', (tester) async {
      final longCategory = Category(id: 101, name: extreme100CharWithSpaces);
      final longCategoryNoSpaces = Category(id: 102, name: extreme100CharWithoutSpaces);
      final longBrand = Brand(id: 201, name: extreme100CharWithSpaces);

      final catalogProv = AdversarialCatalogProvider(
        categories: [longCategory, longCategoryNoSpaces],
        brands: [longBrand],
      );

      final settingsProv = AdversarialSettingsProvider(
        settings: const BusinessSettings(
          licensePlanType: 'premium',
          features: FeatureFlags(multiRubro: true),
        ),
      );

      for (final size in [const Size(320, 480), const Size(280, 480)]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;

        await tester.pumpWidget(createHarness(
          child: ProductFormDialog(provider: catalogProv),
          catalogProv: catalogProv,
          settingsProv: settingsProv,
        ));

        await tester.tap(find.text('Open Dialog Under Test'));
        await tester.pumpAndSettle();

        // Strict assertion: zero exceptions
        expect(tester.takeException(), isNull, reason: 'Failed with exception at $size');

        // Form elements must be present
        expect(find.text('PLU (Interno) *'), findsOneWidget);
        expect(find.text('Categoría'), findsOneWidget);

        // Close dialog
        await tester.tap(find.text('Cancelar'));
        await tester.pumpAndSettle();
      }
      tester.view.resetPhysicalSize();
    });

    testWidgets('T2: CategoriesManagerDialog at 280x480 and 320x480 in Plan Básico: ZERO RenderFlex overflow', (tester) async {
      final catalogProv = AdversarialCatalogProvider(
        categories: [
          Category(id: 1, name: extreme100CharWithSpaces),
          Category(id: 2, name: extreme100CharWithoutSpaces),
          Category(id: 3, name: 'Normal'),
        ],
      );

      final settingsProv = AdversarialSettingsProvider(
        settings: const BusinessSettings(
          licensePlanType: 'basic',
          features: FeatureFlags(multiRubro: false),
        ),
      );

      for (final size in [const Size(320, 480), const Size(280, 480)]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;

        await tester.pumpWidget(createHarness(
          child: const CategoriesManagerDialog(),
          catalogProv: catalogProv,
          settingsProv: settingsProv,
        ));

        await tester.tap(find.text('Open Dialog Under Test'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull, reason: 'Failed at size $size');
        expect(find.text('Gestión de Categorías'), findsOneWidget);

        // Close dialog
        await tester.tap(find.text('Cerrar'));
        await tester.pumpAndSettle();
      }
      tester.view.resetPhysicalSize();
    });

    testWidgets('T3: CategoriesManagerDialog at 280x480 and 320x480 in Plan Premium with 100+ char rubro & category: ZERO RenderFlex overflow', (tester) async {
      final longRubro1 = Rubro(id: 1, name: extreme100CharWithSpaces, isSystem: true);
      final longRubro2 = Rubro(id: 2, name: extreme100CharWithoutSpaces, isSystem: false);

      final catalogProv = AdversarialCatalogProvider(
        categories: [
          Category(id: 1, name: extreme100CharWithSpaces, rubroId: 1, rubro: longRubro1),
          Category(id: 2, name: extreme100CharWithoutSpaces, rubroId: 2, rubro: longRubro2),
        ],
        rubros: [longRubro1, longRubro2],
      );

      final settingsProv = AdversarialSettingsProvider(
        settings: const BusinessSettings(
          licensePlanType: 'premium',
          features: FeatureFlags(multiRubro: true),
        ),
      );

      for (final size in [const Size(320, 480), const Size(280, 480)]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;

        await tester.pumpWidget(createHarness(
          child: const CategoriesManagerDialog(),
          catalogProv: catalogProv,
          settingsProv: settingsProv,
        ));

        await tester.tap(find.text('Open Dialog Under Test'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull, reason: 'Failed at size $size');
        expect(find.text('Gestión de Categorías'), findsOneWidget);
        expect(find.text('Rubro Padre'), findsOneWidget);

        // Trigger inline edit on category 1
        final editButtons = find.byTooltip('Editar');
        if (editButtons.evaluate().isNotEmpty) {
          await tester.tap(editButtons.first);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'Inline edit overflowed at $size');
        }

        // Close dialog
        await tester.tap(find.text('Cerrar'));
        await tester.pumpAndSettle();
      }
      tester.view.resetPhysicalSize();
    });

    testWidgets('T4: RubrosManagerDialog at 280x480 and 320x480 with 100+ char rubro name and description: ZERO RenderFlex overflow', (tester) async {
      final longRubro1 = Rubro(
        id: 1,
        name: extreme100CharWithSpaces,
        description: 'Descripcion larguisima con muchos detalles para poner a prueba el text overflow del widget ListTile',
        isSystem: true,
      );
      final longRubro2 = Rubro(
        id: 2,
        name: extreme100CharWithoutSpaces,
        description: 'OtraDescripcionSinEspaciosExtremadamenteLargaParaComprobarEllipsisYWrapEnPantallasPequenas',
        isSystem: false,
      );

      final catalogProv = AdversarialCatalogProvider(
        rubros: [longRubro1, longRubro2],
      );

      final settingsProv = AdversarialSettingsProvider(
        settings: const BusinessSettings(
          licensePlanType: 'premium',
          features: FeatureFlags(multiRubro: true),
        ),
      );

      for (final size in [const Size(320, 480), const Size(280, 480)]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;

        await tester.pumpWidget(createHarness(
          child: const RubrosManagerDialog(),
          catalogProv: catalogProv,
          settingsProv: settingsProv,
        ));

        await tester.tap(find.text('Open Dialog Under Test'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull, reason: 'Failed at size $size');
        expect(find.text('Gestión de Rubros'), findsOneWidget);

        // Inline edit
        final editButtons = find.byTooltip('Editar');
        if (editButtons.evaluate().isNotEmpty) {
          await tester.tap(editButtons.first);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'Inline edit overflowed at $size');
        }

        // Close dialog
        await tester.tap(find.text('Cerrar'));
        await tester.pumpAndSettle();
      }
      tester.view.resetPhysicalSize();
    });

    testWidgets('T5: Massive list stress (50+ rubros and categories) at 280x480 scrolls smoothly without RenderFlex overflow', (tester) async {
      tester.view.physicalSize = const Size(280, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final manyRubros = List.generate(
        50,
        (i) => Rubro(
          id: i + 1,
          name: 'Rubro Adversarial #$i ${i == 0 ? "(Principal)" : ""}',
          isSystem: i == 0,
        ),
      );

      final catalogProv = AdversarialCatalogProvider(rubros: manyRubros);
      final settingsProv = AdversarialSettingsProvider(
        settings: const BusinessSettings(
          licensePlanType: 'premium',
          features: FeatureFlags(multiRubro: true),
        ),
      );

      await tester.pumpWidget(createHarness(
        child: const RubrosManagerDialog(),
        catalogProv: catalogProv,
        settingsProv: settingsProv,
      ));

      await tester.tap(find.text('Open Dialog Under Test'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      // Scroll the list down
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      // Close
      await tester.tap(find.text('Cerrar'));
      await tester.pumpAndSettle();
    });
  });
}
