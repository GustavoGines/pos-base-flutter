import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:frontend_desktop/core/presentation/widgets/searchable_select_field.dart';
import 'package:frontend_desktop/core/utils/search_text_utils.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/category.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/rubro.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/features/catalog/presentation/widgets/categories_manager_dialog.dart';
import 'package:frontend_desktop/features/catalog/presentation/widgets/rubros_manager_dialog.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';

class _FakeCatalogProvider extends ChangeNotifier implements CatalogProvider {
  final List<Category> _categories;
  final List<Rubro> _rubros;
  bool shouldFailCreateRubro = false;
  String? _errorMessage;

  String? lastCreatedCategoryName;
  int? lastCreatedCategoryRubroId;
  int _nextRubroId = 100;

  _FakeCatalogProvider({
    List<Category>? categories,
    List<Rubro>? rubros,
  })  : _categories = categories ?? [],
        _rubros = rubros ??
            [
              Rubro(id: 10, name: 'Carniceria'),
              Rubro(id: 20, name: 'Tecnologia'),
            ];

  @override
  List<Category> get categories => _categories;
  @override
  List<Rubro> get rubros => _rubros;
  @override
  bool get isLoading => false;
  @override
  String? get errorMessage => _errorMessage;

  @override
  Future<void> loadRubros() async {}

  @override
  Future<int?> createRubro(String name, {String? description, String? verticalType}) async {
    if (shouldFailCreateRubro) {
      _errorMessage = 'Ya existe un rubro con ese nombre.';
      notifyListeners();
      return null;
    }
    _errorMessage = null;
    final created = Rubro(
      id: _nextRubroId++,
      name: name,
      description: description,
      verticalType: verticalType,
    );
    _rubros.add(created);
    _rubros.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    notifyListeners();
    return created.id;
  }

  @override
  Future<int?> createCategory(
    String name, {
    String? description,
    int? rubroId,
  }) async {
    lastCreatedCategoryName = name;
    lastCreatedCategoryRubroId = rubroId;
    final created = Category(
      id: _categories.length + 500,
      name: name,
      rubroId: rubroId,
      rubro: rubroId != null
          ? _rubros.where((r) => r.id == rubroId).firstOrNull
          : null,
    );
    _categories.add(created);
    notifyListeners();
    return created.id;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSettingsProvider extends ChangeNotifier implements SettingsProvider {
  final BusinessSettings _settings;

  _FakeSettingsProvider({bool multiRubro = true})
      : _settings = BusinessSettings(
          companyName: 'Test Store',
          features: FeatureFlags(multiRubro: multiRubro),
        );

  @override
  int get assignedRegisterId => 1;
  @override
  BusinessSettings? get settings => _settings;
  @override
  FeatureFlags get features => _settings.features;
  @override
  bool hasFeature(String featureName) => _settings.hasFeature(featureName);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget wrapApp({
    required _FakeCatalogProvider catalogProv,
    required _FakeSettingsProvider settingsProv,
    required Widget child,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<CatalogProvider>.value(value: catalogProv),
        ChangeNotifierProvider<SettingsProvider>.value(value: settingsProv),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    );
  }

  group('Creación inline de Rubro desde Categorías', () {
    testWidgets(
      'RubrosManagerDialog.showQuickCreateDialog valida vacío, muestra error del backend y retorna ID al crear',
      (tester) async {
        final catalogProv = _FakeCatalogProvider();
        final settingsProv = _FakeSettingsProvider();
        int? returnedId;

        await tester.pumpWidget(
          wrapApp(
            catalogProv: catalogProv,
            settingsProv: settingsProv,
            child: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () async {
                  returnedId = await RubrosManagerDialog.showQuickCreateDialog(
                    ctx,
                    initialName: '',
                  );
                },
                child: const Text('Abrir Quick Rubro'),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Abrir Quick Rubro'));
        await tester.pumpAndSettle();

        expect(find.text('Nuevo Rubro Comercial'), findsOneWidget);

        // Enviar vacío muestra error sin cerrar
        await tester.tap(find.text('Crear Rubro'));
        await tester.pumpAndSettle();
        expect(find.text('Ingresá el nombre del rubro.'), findsOneWidget);
        expect(find.text('Nuevo Rubro Comercial'), findsOneWidget);

        // Simular error de backend
        catalogProv.shouldFailCreateRubro = true;
        await tester.enterText(find.byType(TextField).first, 'Pastelería');
        await tester.tap(find.text('Crear Rubro'));
        await tester.pumpAndSettle();
        expect(find.text('Ya existe un rubro con ese nombre.'), findsOneWidget);

        // Crear exitosamente -> cierra dialog y devuelve ID
        catalogProv.shouldFailCreateRubro = false;
        await tester.tap(find.text('Crear Rubro'));
        await tester.pumpAndSettle();

        expect(returnedId, 100);
        expect(find.text('Nuevo Rubro Comercial'), findsNothing);
        expect(catalogProv.rubros.any((r) => r.id == 100 && r.name == 'Pastelería'), isTrue);
      },
    );

    testWidgets(
      'CategoriesManagerDialog permite crear Rubro inline sin perder el nombre de categoría ni romper ancho angosto',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final catalogProv = _FakeCatalogProvider(rubros: []);
        final settingsProv = _FakeSettingsProvider(multiRubro: true);

        await tester.pumpWidget(
          wrapApp(
            catalogProv: catalogProv,
            settingsProv: settingsProv,
            child: const CategoriesManagerDialog(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(DropdownButtonFormField<int?>), findsOneWidget);
        expect(find.byTooltip('Crear nuevo rubro'), findsOneWidget);

        // Escribir categoría "Tortas" primero y luego darse cuenta de que falta el rubro
        await tester.enterText(
          find.widgetWithText(TextField, 'Nombre de categoría...'),
          'Tortas',
        );
        await tester.pump();

        // Tocar "+" junto a Rubro Padre
        await tester.tap(find.byTooltip('Crear nuevo rubro'));
        await tester.pumpAndSettle();

        expect(find.text('Nuevo Rubro Comercial'), findsOneWidget);
        await tester.enterText(
          find.widgetWithText(TextField, 'Nombre *'),
          'Pastelería',
        );
        await tester.tap(find.text('Crear Rubro'));
        await tester.pumpAndSettle();

        // Auto-seleccionado "Pastelería" y conservado "Tortas"
        expect(find.text('Pastelería'), findsWidgets);
        expect(
          find.widgetWithText(TextField, 'Tortas'),
          findsOneWidget,
        );

        await tester.tap(find.text('Agregar'));
        await tester.pumpAndSettle();

        expect(catalogProv.lastCreatedCategoryName, 'Tortas');
        expect(catalogProv.lastCreatedCategoryRubroId, 100);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'SearchableSelectField de Rubro Padre permite crear rubro desde búsqueda vacía o sin coincidencias',
      (tester) async {
        final catalogProv = _FakeCatalogProvider(
          rubros: [Rubro(id: 10, name: 'Carniceria')],
        );
        final settingsProv = _FakeSettingsProvider(multiRubro: true);
        int? selectedRubroId = 10;

        await tester.pumpWidget(
          wrapApp(
            catalogProv: catalogProv,
            settingsProv: settingsProv,
            child: StatefulBuilder(
              builder: (ctx, setState) {
                final sortedRubros = sortByAlphabeticalName(
                  ctx.watch<CatalogProvider>().rubros,
                  (r) => r.name,
                );
                return SearchableSelectField<int?>(
                  value: selectedRubroId,
                  showClearButton: false,
                  labelText: 'Rubro Padre',
                  dialogTitle: 'Seleccionar Rubro Padre',
                  searchHintText: 'Buscar rubro...',
                  emptySearchText: 'No hay rubros registrados',
                  border: const OutlineInputBorder(),
                  options: sortedRubros
                      .map((r) => SearchableSelectOption<int?>(
                            value: r.id,
                            label: r.name,
                          ))
                      .toList(),
                  onChanged: (val) => setState(() => selectedRubroId = val),
                  onCreateNew: (query) async {
                    final newId =
                        await RubrosManagerDialog.showQuickCreateDialog(
                      ctx,
                      initialName: query,
                    );
                    if (newId != null && ctx.mounted) {
                      setState(() => selectedRubroId = newId);
                    }
                  },
                  createLabelBuilder: (query) => query.trim().isEmpty
                      ? 'Crear nuevo rubro'
                      : 'Crear rubro "${query.trim()}"',
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byType(SearchableSelectField<int?>));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.widgetWithText(TextField, 'Buscar rubro...'),
          'Pastelería',
        );
        await tester.pumpAndSettle();

        expect(find.text('Crear rubro "Pastelería"'), findsOneWidget);
        await tester.tap(find.text('Crear rubro "Pastelería"'));
        await tester.pumpAndSettle();

        // El diálogo ya viene prellenado con "Pastelería"
        expect(find.text('Nuevo Rubro Comercial'), findsOneWidget);
        expect(find.widgetWithText(TextField, 'Pastelería'), findsOneWidget);

        await tester.tap(find.text('Crear Rubro'));
        await tester.pumpAndSettle();

        expect(selectedRubroId, 100);
        expect(find.text('Pastelería'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
