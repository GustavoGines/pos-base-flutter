import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:frontend_desktop/features/catalog/domain/entities/category.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/rubro.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/features/catalog/presentation/widgets/categories_manager_dialog.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';

class FakeCatalogProvider extends ChangeNotifier implements CatalogProvider {
  final List<Category> _categories;
  final List<Rubro> _rubros;
  int? lastCreatedRubroId;
  String? lastCreatedName;

  FakeCatalogProvider({List<Category>? categories, List<Rubro>? rubros})
      : _categories = categories ?? [
          Category(id: 1, name: 'Bebidas', rubroId: 10, rubro: Rubro(id: 10, name: 'Kiosko')),
          Category(id: 2, name: 'Herramientas', rubroId: 20, rubro: Rubro(id: 20, name: 'Ferretería')),
        ],
        _rubros = rubros ?? [
          Rubro(id: 10, name: 'Kiosko', isSystem: true),
          Rubro(id: 20, name: 'Ferretería', isSystem: false),
        ];

  @override
  List<Category> get categories => _categories;
  @override
  List<Rubro> get rubros => _rubros;
  @override
  bool get isLoading => false;
  @override
  String? get errorMessage => null;

  @override
  Future<void> loadRubros() async {}

  @override
  Future<int?> createCategory(String name, {String? description, int? rubroId}) async {
    lastCreatedName = name;
    lastCreatedRubroId = rubroId;
    final created = Category(
      id: _categories.length + 100,
      name: name,
      rubroId: rubroId,
      rubro: rubroId != null ? _rubros.where((r) => r.id == rubroId).firstOrNull : null,
    );
    _categories.add(created);
    notifyListeners();
    return created.id;
  }

  @override
  Future<bool> updateCategory(int id, String name, {String? description, int? rubroId}) async {
    final idx = _categories.indexWhere((c) => c.id == id);
    if (idx != -1) {
      _categories[idx] = Category(
        id: id,
        name: name,
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildCategoriesApp({
    required FakeCatalogProvider catalogProv,
    required FakeSettingsProvider settingsProv,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<CatalogProvider>.value(value: catalogProv),
        ChangeNotifierProvider<SettingsProvider>.value(value: settingsProv),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showDialog(
                context: context,
                builder: (_) => const CategoriesManagerDialog(),
              ),
              child: const Text('Open Categories Dialog'),
            ),
          ),
        ),
      ),
    );
  }

  group('M4: CategoriesManagerDialog Basic vs Premium Gating & Responsiveness', () {
    testWidgets('Test 1: Plan Básico hides parent Rubro dropdown in form and list', (tester) async {
      final catalogProv = FakeCatalogProvider();
      final settingsProv = FakeSettingsProvider(
        settings: const BusinessSettings(
          licensePlanType: 'basic',
          features: FeatureFlags(multiRubro: false),
        ),
      );

      await tester.pumpWidget(buildCategoriesApp(catalogProv: catalogProv, settingsProv: settingsProv));
      await tester.tap(find.text('Open Categories Dialog'));
      await tester.pumpAndSettle();

      // Debe mostrar el dialog
      expect(find.text('Gestión de Categorías'), findsOneWidget);

      // En Plan Básico NO debe haber selector de "Rubro Padre"
      expect(find.text('Rubro Padre'), findsNothing);
      expect(find.byType(DropdownButtonFormField<int?>), findsNothing);

      // Debe mostrar las categorías existentes
      expect(find.text('Bebidas'), findsOneWidget);
      expect(find.text('Herramientas'), findsOneWidget);

      // Crear nueva categoría en Básico envía rubroId: null
      await tester.enterText(find.byType(TextField).first, 'Limpieza');
      await tester.tap(find.text('Agregar'));
      await tester.pumpAndSettle();

      expect(catalogProv.lastCreatedName, equals('Limpieza'));
      expect(catalogProv.lastCreatedRubroId, isNull);
    });

    testWidgets('Test 2: Plan Premium shows parent Rubro selector and displays parent Rubro on tiles', (tester) async {
      final catalogProv = FakeCatalogProvider();
      final settingsProv = FakeSettingsProvider(
        settings: const BusinessSettings(
          licensePlanType: 'premium',
          features: FeatureFlags(multiRubro: true),
        ),
      );

      await tester.pumpWidget(buildCategoriesApp(catalogProv: catalogProv, settingsProv: settingsProv));
      await tester.tap(find.text('Open Categories Dialog'));
      await tester.pumpAndSettle();

      // En Plan Premium debe haber selector de Rubro Padre
      expect(find.text('Rubro Padre'), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<int?>), findsOneWidget);

      // Debe mostrar el rubro en los items existentes
      expect(find.text('Rubro: Kiosko'), findsOneWidget);
      expect(find.text('Rubro: Ferretería'), findsOneWidget);

      // Crear categoría seleccionando rubro
      await tester.enterText(find.byType(TextField).first, 'Pinturas');
      await tester.tap(find.text('Agregar'));
      await tester.pumpAndSettle();

      expect(catalogProv.lastCreatedName, equals('Pinturas'));
      expect(catalogProv.lastCreatedRubroId, isNotNull);
    });

    testWidgets('Test 3: 320x480 extreme compact viewport renders without RenderFlex overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final catalogProv = FakeCatalogProvider();
      final settingsProv = FakeSettingsProvider(
        settings: const BusinessSettings(
          licensePlanType: 'premium',
          features: FeatureFlags(multiRubro: true),
        ),
      );

      await tester.pumpWidget(buildCategoriesApp(catalogProv: catalogProv, settingsProv: settingsProv));
      await tester.tap(find.text('Open Categories Dialog'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Gestión de Categorías'), findsOneWidget);
    });
  });
}
