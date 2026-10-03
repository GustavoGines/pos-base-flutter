import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:frontend_desktop/features/catalog/domain/entities/rubro.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/features/catalog/presentation/widgets/rubros_manager_dialog.dart';

class FakeCatalogProvider extends ChangeNotifier implements CatalogProvider {
  final List<Rubro> _rubros;
  String? lastCreatedName;
  String? lastCreatedDesc;
  int? lastDeletedId;

  FakeCatalogProvider({List<Rubro>? rubros})
      : _rubros = rubros ?? [
          Rubro(id: 1, name: 'General', isSystem: true, description: 'Rubro por defecto'),
          Rubro(id: 2, name: 'Ferretería', isSystem: false, description: 'Herramientas y afines'),
        ];

  @override
  List<Rubro> get rubros => _rubros;
  @override
  bool get isLoading => false;
  @override
  String? get errorMessage => null;

  @override
  Future<void> loadRubros() async {}

  @override
  Future<int?> createRubro(String name, {String? description}) async {
    lastCreatedName = name;
    lastCreatedDesc = description;
    final created = Rubro(
      id: _rubros.length + 10,
      name: name,
      description: description,
      isSystem: false,
    );
    _rubros.add(created);
    notifyListeners();
    return created.id;
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
    lastDeletedId = id;
    _rubros.removeWhere((r) => r.id == id);
    notifyListeners();
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildRubrosApp({required FakeCatalogProvider catalogProv}) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<CatalogProvider>.value(value: catalogProv),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showDialog(
                context: context,
                builder: (_) => const RubrosManagerDialog(),
              ),
              child: const Text('Open Rubros Dialog'),
            ),
          ),
        ),
      ),
    );
  }

  group('M4: RubrosManagerDialog CRUD, System Protection & Responsiveness', () {
    testWidgets('Test 1: Displays rubros and protects system rubro with Principal badge and lock', (tester) async {
      final catalogProv = FakeCatalogProvider();

      await tester.pumpWidget(buildRubrosApp(catalogProv: catalogProv));
      await tester.tap(find.text('Open Rubros Dialog'));
      await tester.pumpAndSettle();

      // Debe mostrar el dialog
      expect(find.text('Gestión de Rubros'), findsOneWidget);

      // Debe listar los rubros
      expect(find.text('General'), findsOneWidget);
      expect(find.text('Ferretería'), findsOneWidget);

      // El rubro del sistema debe mostrar el badge "Principal"
      expect(find.text('Principal'), findsOneWidget);

      // El rubro del sistema tiene icono de lock en vez de botón de eliminar activo
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    });

    testWidgets('Test 2: Creates a new rubro via form inputs', (tester) async {
      final catalogProv = FakeCatalogProvider();

      await tester.pumpWidget(buildRubrosApp(catalogProv: catalogProv));
      await tester.tap(find.text('Open Rubros Dialog'));
      await tester.pumpAndSettle();

      // Ingresar nombre y descripción
      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(0), 'Kiosko');
      await tester.enterText(textFields.at(1), 'Golosinas y bebidas');
      await tester.tap(find.text('Agregar'));
      await tester.pumpAndSettle();

      expect(catalogProv.lastCreatedName, equals('Kiosko'));
      expect(catalogProv.lastCreatedDesc, equals('Golosinas y bebidas'));
      expect(find.text('Kiosko'), findsOneWidget);
    });

    testWidgets('Test 3: Allows deleting a non-system rubro with confirmation dialog', (tester) async {
      final catalogProv = FakeCatalogProvider();

      await tester.pumpWidget(buildRubrosApp(catalogProv: catalogProv));
      await tester.tap(find.text('Open Rubros Dialog'));
      await tester.pumpAndSettle();

      // Pulsar eliminar en el rubro no-sistema (Ferretería)
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      // Debe mostrar diálogo de confirmación
      expect(find.text('Confirmar eliminación'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
      await tester.pumpAndSettle();

      expect(catalogProv.lastDeletedId, equals(2));
      expect(find.text('Ferretería'), findsNothing);
    });

    testWidgets('Test 4: 320x480 extreme compact viewport renders cleanly without RenderFlex overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final catalogProv = FakeCatalogProvider();

      await tester.pumpWidget(buildRubrosApp(catalogProv: catalogProv));
      await tester.tap(find.text('Open Rubros Dialog'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Gestión de Rubros'), findsOneWidget);
    });
  });
}
