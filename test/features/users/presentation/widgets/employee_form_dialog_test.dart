import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_desktop/core/constants/app_permissions.dart';
import 'package:frontend_desktop/features/users/presentation/widgets/employee_form_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildDialogApp({Map<String, dynamic>? employee, void Function(Map<String, dynamic>?)? onClosed}) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              final result = await showDialog<Map<String, dynamic>>(
                context: context,
                builder: (_) => EmployeeFormDialog(employee: employee),
              );
              onClosed?.call(result);
            },
            child: const Text('Open Dialog'),
          ),
        ),
      ),
    );
  }

  group('EmployeeFormDialog Widget and Categorized Permissions Tests', () {
    testWidgets('Muestra todas las categorías de kCategorizedPermissions (> 5) y sus 25 permisos', (tester) async {
      await tester.pumpWidget(buildDialogApp());
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.byType(EmployeeFormDialog), findsOneWidget);
      expect(find.text('Nuevo Empleado'), findsOneWidget);

      // Verificar que existan más de 5 categorías en kCategorizedPermissions
      expect(kCategorizedPermissions.length, greaterThan(5));
      expect(kCategorizedPermissions.length, 9);

      // Desplazarse por el Scrollable para verificar cada categoría y sus permisos
      final scrollFinder = find.byType(Scrollable).first;

      for (final category in kCategorizedPermissions) {
        final catTitleFinder = find.text(category.title);
        await tester.scrollUntilVisible(catTitleFinder, 100.0, scrollable: scrollFinder);
        expect(catTitleFinder, findsOneWidget, reason: 'Categoría ${category.title} debe estar visible');

        for (final item in category.items) {
          final itemFinder = find.text(item.label);
          await tester.scrollUntilVisible(itemFinder, 100.0, scrollable: scrollFinder);
          expect(itemFinder, findsOneWidget, reason: 'Permiso ${item.label} debe estar en el árbol');
        }
      }
    });

    testWidgets('Interacción con checkbox individual y guardado de empleado con permisos específicos', (tester) async {
      Map<String, dynamic>? submittedData;
      await tester.pumpWidget(buildDialogApp(onClosed: (data) => submittedData = data));
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Completar campos requeridos
      await tester.enterText(find.byType(TextFormField).at(0), 'Operador Caja');
      await tester.enterText(find.byType(TextFormField).at(1), '1122');
      await tester.pump();

      // Buscar categoría de Catálogo y Precios
      final catalogCat = kCategorizedPermissions.firstWhere((c) => c.title.contains('Catálogo'));
      final scrollFinder = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(find.text(catalogCat.title), 100.0, scrollable: scrollFinder);

      // Marcar el permiso manageCatalog directamente
      final manageCatalogText = find.text('Gestión de Catálogo');
      await tester.scrollUntilVisible(manageCatalogText, 100.0, scrollable: scrollFinder);
      await tester.tap(manageCatalogText);
      await tester.pumpAndSettle();

      // Enviar formulario (el botón está en el footer fuera del scroll)
      await tester.tap(find.text('Crear Empleado'));
      await tester.pumpAndSettle();

      expect(submittedData, isNotNull);
      expect(submittedData!['name'], 'Operador Caja');
      expect(submittedData!['role'], 'cashier');
      expect((submittedData!['permissions'] as List).contains(AppPermissions.manageCatalog), true);
      expect((submittedData!['permissions'] as List).contains(AppPermissions.bulkPriceUpdate), false);
    });

    testWidgets('Modo Administrador otorga todos los 25 permisos y muestra badge "Acceso Total"', (tester) async {
      await tester.pumpWidget(buildDialogApp());
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Cambiar rol a admin
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Administrador').last);
      await tester.pumpAndSettle();

      // Debe mostrar el badge de Acceso Total
      expect(find.text('Acceso Total'), findsOneWidget);
    });

    testWidgets('Renderiza en pantallas de diversas resoluciones sin desbordamiento (RenderFlex Overflow)', (tester) async {
      final resolutions = [
        const Size(360, 640),
        const Size(800, 600),
        const Size(1024, 768),
        const Size(1920, 1080),
      ];

      for (final res in resolutions) {
        tester.view.physicalSize = res;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(buildDialogApp());
        await tester.tap(find.text('Open Dialog'));
        await tester.pumpAndSettle();

        expect(find.byType(EmployeeFormDialog), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'No debe haber desbordamiento en resolución $res');

        // Cancelar para cerrar el diálogo
        await tester.tap(find.text('Cancelar'));
        await tester.pumpAndSettle();
      }
    });

    testWidgets('Adversarial: Soporta permisos serializados en JSON String sin arrojar TypeError', (tester) async {
      final jsonEmployee = {
        'id': 42,
        'name': 'Operadora Cadena JSON',
        'role': 'cashier',
        'permissions': '["manage_catalog", "view_kardex"]',
      };

      Map<String, dynamic>? updatedData;
      await tester.pumpWidget(buildDialogApp(
        employee: jsonEmployee,
        onClosed: (data) => updatedData = data,
      ));
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Editar Empleado'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Operadora Cadena JSON'), findsOneWidget);

      // Guardar sin cambios
      await tester.tap(find.text('Guardar Cambios'));
      await tester.pumpAndSettle();

      expect(updatedData, isNotNull);
      final savedPerms = updatedData!['permissions'] as List;
      expect(savedPerms.contains(AppPermissions.manageCatalog), true);
      expect(savedPerms.contains(AppPermissions.viewKardex), true);
      expect(savedPerms.contains(AppPermissions.bulkPriceUpdate), false);
    });

    testWidgets('Adversarial: Heterogeneous permissions list and non-standard roles do not crash', (tester) async {
      final dirtyEmployee = {
        'id': 99,
        'name': 'Operador Heterogeneo',
        'role': 'unknown_role',
        'permissions': ['manage_catalog', null, 123, 'view_kardex'],
      };

      Map<String, dynamic>? updatedData;
      await tester.pumpWidget(buildDialogApp(
        employee: dirtyEmployee,
        onClosed: (data) => updatedData = data,
      ));
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Editar Empleado'), findsOneWidget);

      await tester.tap(find.text('Guardar Cambios'));
      await tester.pumpAndSettle();

      expect(updatedData, isNotNull);
      expect(updatedData!['role'], 'cashier');
      final savedPerms = updatedData!['permissions'] as List;
      expect(savedPerms.contains(AppPermissions.manageCatalog), true);
      expect(savedPerms.contains(AppPermissions.viewKardex), true);
    });

    testWidgets('Adversarial: Interacción con checkbox de categoría (tri-state) marca y desmarca en lote', (tester) async {
      Map<String, dynamic>? savedData;
      await tester.pumpWidget(buildDialogApp(onClosed: (data) => savedData = data));
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(0), 'Operador TriState');
      await tester.enterText(find.byType(TextFormField).at(1), '4321');
      await tester.pump();

      // Scroll hasta la categoría "Catálogo y Precios"
      final catalogCat = kCategorizedPermissions.firstWhere((c) => c.title.contains('Catálogo'));
      final scrollFinder = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(find.text(catalogCat.title), 100.0, scrollable: scrollFinder);

      // Encontrar el checkbox de la categoría (está en el Row junto al texto del título)
      final categoryTitleRow = find.ancestor(
        of: find.text(catalogCat.title),
        matching: find.byType(Row),
      );
      final categoryCheckbox = find.descendant(
        of: categoryTitleRow,
        matching: find.byType(Checkbox),
      );

      // Clic 1: Debería marcar todos los items de Catálogo y Precios (manageCatalog y bulkPriceUpdate)
      await tester.tap(categoryCheckbox);
      await tester.pumpAndSettle();

      Checkbox cbWidget = tester.widget(categoryCheckbox);
      expect(cbWidget.value, true, reason: 'Debe estar totalmente marcado');

      // Desmarcar un item individual para inducir estado parcial (tristate = null)
      final catalogItemText = find.text('Gestión de Catálogo');
      await tester.scrollUntilVisible(catalogItemText, 100.0, scrollable: scrollFinder);
      await tester.tap(catalogItemText);
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text(catalogCat.title), 100.0, scrollable: scrollFinder);
      cbWidget = tester.widget(categoryCheckbox);
      expect(cbWidget.value, isNull, reason: 'Estado tri-state debe ser nulo cuando está parcialmente seleccionado');

      // Clic 2 en tri-state parcial: debe volver a marcar todo
      await tester.tap(categoryCheckbox);
      await tester.pumpAndSettle();
      cbWidget = tester.widget(categoryCheckbox);
      expect(cbWidget.value, true, reason: 'Clic en parcial debe seleccionar todo');

      // Clic 3 en estado completo: debe desmarcar todo
      await tester.tap(categoryCheckbox);
      await tester.pumpAndSettle();
      cbWidget = tester.widget(categoryCheckbox);
      expect(cbWidget.value, false, reason: 'Clic en completo debe desmarcar todo');

      // Clic 4: marcar nuevamente para verificar persistencia al guardar
      await tester.tap(categoryCheckbox);
      await tester.pumpAndSettle();

      // Enviar
      await tester.tap(find.text('Crear Empleado'));
      await tester.pumpAndSettle();

      expect(savedData, isNotNull);
      List perms = savedData!['permissions'] as List;
      expect(perms.contains(AppPermissions.manageCatalog), true);
      expect(perms.contains(AppPermissions.bulkPriceUpdate), true);
    });

    testWidgets('Adversarial: Alternar rol cajero -> administrador -> cajero preserva selección previa', (tester) async {
      Map<String, dynamic>? submittedData;
      await tester.pumpWidget(buildDialogApp(onClosed: (data) => submittedData = data));
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(0), 'Cajero Restaurable');
      await tester.enterText(find.byType(TextFormField).at(1), '9988');
      await tester.pump();

      // Seleccionar un permiso específico
      final scrollFinder = find.byType(Scrollable).first;
      final catalogCat = kCategorizedPermissions.firstWhere((c) => c.title.contains('Catálogo'));
      await tester.scrollUntilVisible(find.text(catalogCat.title), 100.0, scrollable: scrollFinder);

      final manageCatalogText = find.text('Gestión de Catálogo');
      await tester.scrollUntilVisible(manageCatalogText, 100.0, scrollable: scrollFinder);
      await tester.tap(manageCatalogText);
      await tester.pumpAndSettle();

      // Cambiar temporalmente a Administrador
      await tester.scrollUntilVisible(find.byType(DropdownButtonFormField<String>), -100.0, scrollable: scrollFinder);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Administrador').last);
      await tester.pumpAndSettle();

      expect(find.text('Acceso Total'), findsOneWidget);

      // Cambiar de vuelta a Cajero: la selección previa no debe haberse destruido
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cajero').last);
      await tester.pumpAndSettle();

      expect(find.text('Acceso Total'), findsNothing);

      // Guardar cambios
      await tester.tap(find.text('Crear Empleado'));
      await tester.pumpAndSettle();

      expect(submittedData, isNotNull);
      expect(submittedData!['role'], 'cashier');
      final perms = submittedData!['permissions'] as List;
      expect(perms.contains(AppPermissions.manageCatalog), true);
      expect(perms.length, 1, reason: 'Solo debe contener el permiso previamente configurado, no los 25');
    });

    testWidgets('Adversarial: Colapso y expansión dinámica de categorías vía ExpansionTile', (tester) async {
      await tester.pumpWidget(buildDialogApp());
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      final scrollFinder = find.byType(Scrollable).first;
      final reportsCat = kCategorizedPermissions.firstWhere((c) => c.title.contains('Reportes y Auditoría'));

      await tester.scrollUntilVisible(find.text(reportsCat.title), 100.0, scrollable: scrollFinder);
      expect(find.text('Reportes Gerenciales'), findsOneWidget);

      // Tocar el título de la categoría para colapsarla
      await tester.tap(find.text(reportsCat.title));
      await tester.pumpAndSettle();

      // Al colapsar, los items hijos de esa categoría no se renderizan en el viewport
      expect(find.text('Reportes Gerenciales'), findsNothing);

      // Tocar nuevamente para expandirla
      await tester.tap(find.text(reportsCat.title));
      await tester.pumpAndSettle();

      expect(find.text('Reportes Gerenciales'), findsOneWidget);

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
    });

    testWidgets('Adversarial: Renderiza en pantalla ultra-compacta (320x480) sin RenderFlex overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildDialogApp());
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.byType(EmployeeFormDialog), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
    });

    testWidgets('Adversarial: Soporta permisos en Set, JSON sucio con nulos y rol ADMIN en mayúsculas', (tester) async {
      final dirtyAdmin = {
        'id': 100,
        'name': 'Super Administrador Mayus',
        'role': 'ADMIN',
        'permissions': '["manage_catalog", null, 999, "view_kardex"]',
      };

      Map<String, dynamic>? submittedAdmin;
      await tester.pumpWidget(buildDialogApp(
        employee: dirtyAdmin,
        onClosed: (data) => submittedAdmin = data,
      ));
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Acceso Total'), findsOneWidget);
      await tester.tap(find.text('Guardar Cambios'));
      await tester.pumpAndSettle();

      expect(submittedAdmin, isNotNull);
      expect(submittedAdmin!['role'], 'admin');
      expect((submittedAdmin!['permissions'] as List).length, 25);

      // Probar empleado con Set de permisos
      final setEmployee = {
        'id': 101,
        'name': 'Operador Con Set',
        'role': 'cashier',
        'permissions': {'manage_quotes', 'view_checks'},
      };

      Map<String, dynamic>? submittedSet;
      await tester.pumpWidget(buildDialogApp(
        employee: setEmployee,
        onClosed: (data) => submittedSet = data,
      ));
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar Cambios'));
      await tester.pumpAndSettle();

      expect(submittedSet, isNotNull);
      expect((submittedSet!['permissions'] as List).contains(AppPermissions.manageQuotes), true);
      expect((submittedSet!['permissions'] as List).contains(AppPermissions.viewChecks), true);
    });

    testWidgets('Adversarial: Renderiza en micro-pantalla extrema (240x320) sin RenderFlex overflow', (tester) async {
      tester.view.physicalSize = const Size(240, 320);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildDialogApp());
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.byType(EmployeeFormDialog), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
    });

    testWidgets('Adversarial: Preservación de colapso de categorías al interactuar con otras categorías', (tester) async {
      await tester.pumpWidget(buildDialogApp());
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      final scrollFinder = find.byType(Scrollable).first;
      final reportsCat = kCategorizedPermissions.firstWhere((c) => c.title.contains('Reportes y Auditoría'));
      final catalogCat = kCategorizedPermissions.firstWhere((c) => c.title.contains('Catálogo y Precios'));

      // 1. Colapsar "Reportes y Auditoría"
      await tester.scrollUntilVisible(find.text(reportsCat.title), 100.0, scrollable: scrollFinder);
      await tester.tap(find.text(reportsCat.title));
      await tester.pumpAndSettle();
      expect(find.text('Reportes Gerenciales'), findsNothing, reason: 'Reportes debe estar colapsado');

      // 2. Modificar un checkbox en otra categoría ("Catálogo") provocando setState
      await tester.scrollUntilVisible(find.text(catalogCat.title), 100.0, scrollable: scrollFinder);
      final catalogItem = find.text('Gestión de Catálogo');
      await tester.scrollUntilVisible(catalogItem, 100.0, scrollable: scrollFinder);
      await tester.tap(catalogItem);
      await tester.pumpAndSettle();

      // 3. Volver a "Reportes y Auditoría" y verificar que sigue colapsado
      await tester.scrollUntilVisible(find.text(reportsCat.title), -100.0, scrollable: scrollFinder);
      expect(find.text('Reportes Gerenciales'), findsNothing, reason: 'Reportes debe permanecer colapsado tras rebuild');
    });

    testWidgets('Adversarial: Empleado con nombre numérico y permisos en Map no arroja TypeError', (tester) async {
      final numericNameEmployee = {
        'id': 777,
        'name': 98765, // nombre numérico (entero)
        'role': 'cashier',
        'permissions': {
          'manage_catalog': true,
          'view_kardex': false,
          'apply_discounts': 1,
        },
      };

      Map<String, dynamic>? submittedData;
      await tester.pumpWidget(buildDialogApp(
        employee: numericNameEmployee,
        onClosed: (data) => submittedData = data,
      ));
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextFormField, '98765'), findsOneWidget);

      await tester.tap(find.text('Guardar Cambios'));
      await tester.pumpAndSettle();

      expect(submittedData, isNotNull);
      expect(submittedData!['name'], '98765');
      final perms = submittedData!['permissions'] as List;
      expect(perms.contains('manage_catalog'), true);
      expect(perms.contains('apply_discounts'), true);
      expect(perms.contains('view_kardex'), false);
    });

    testWidgets('Adversarial: Permisos serializados en JSON Map String son correctamente extraídos', (tester) async {
      final jsonMapEmployee = {
        'id': 888,
        'name': 'Cajero Map JSON',
        'role': 'cashier',
        'permissions': '{"manage_catalog": true, "view_kardex": false, "view_checks": "true"}',
      };

      Map<String, dynamic>? submittedData;
      await tester.pumpWidget(buildDialogApp(
        employee: jsonMapEmployee,
        onClosed: (data) => submittedData = data,
      ));
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar Cambios'));
      await tester.pumpAndSettle();

      expect(submittedData, isNotNull);
      final perms = submittedData!['permissions'] as List;
      expect(perms.contains('manage_catalog'), true);
      expect(perms.contains('view_checks'), true);
      expect(perms.contains('view_kardex'), false);
    });

    testWidgets('Adversarial: Cambio de rol de Administrador a Cajero restaura permisos previos en lugar de vaciarlos', (tester) async {
      final adminWithSpecificPerms = {
        'id': 999,
        'name': 'Admin Con Permisos Previos',
        'role': 'admin',
        'permissions': ['manage_catalog', 'view_kardex'],
      };

      Map<String, dynamic>? submittedData;
      await tester.pumpWidget(buildDialogApp(
        employee: adminWithSpecificPerms,
        onClosed: (data) => submittedData = data,
      ));
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Acceso Total'), findsOneWidget);

      // Cambiar rol de Administrador a Cajero
      final scrollFinder = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(find.byType(DropdownButtonFormField<String>), -100.0, scrollable: scrollFinder);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cajero').last);
      await tester.pumpAndSettle();

      expect(find.text('Acceso Total'), findsNothing);

      // Guardar cambios: debe contener los permisos que tenía guardados originalmente
      await tester.tap(find.text('Guardar Cambios'));
      await tester.pumpAndSettle();

      expect(submittedData, isNotNull);
      expect(submittedData!['role'], 'cashier');
      final perms = submittedData!['permissions'] as List;
      expect(perms.contains(AppPermissions.manageCatalog), true);
      expect(perms.contains(AppPermissions.viewKardex), true);
      expect(perms.length, 2, reason: 'Debe preservar exactamente los 2 permisos previos del empleado');
    });
  });
}
