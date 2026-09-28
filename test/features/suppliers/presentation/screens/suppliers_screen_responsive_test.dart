import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import 'package:frontend_desktop/features/auth/presentation/providers/auth_provider.dart';
import 'package:frontend_desktop/features/reports/presentation/providers/inventory_alerts_provider.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/features/suppliers/models/supplier_model.dart';
import 'package:frontend_desktop/features/suppliers/presentation/screens/suppliers_screen.dart';
import 'package:frontend_desktop/features/suppliers/providers/supplier_provider.dart';

class FakeSupplierProvider extends ChangeNotifier implements SupplierProvider {
  List<Supplier> _suppliers = [];
  @override
  List<Supplier> get suppliers => _suppliers;

  @override
  bool get isLoading => false;

  void setSuppliers(List<Supplier> list) {
    _suppliers = list;
    notifyListeners();
  }

  @override
  Future<void> fetchSuppliers({String? search}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSettingsProvider extends ChangeNotifier implements SettingsProvider {
  @override
  BusinessSettings get settings => BusinessSettings(
        companyName: 'Test Empresa',
        taxId: '20-12345678-9',
      );

  @override
  FeatureFlags get features => const FeatureFlags(fastPos: true, suppliers: true);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeLocalTerminalProvider extends ChangeNotifier implements LocalTerminalProvider {
  @override
  String get printerFormat => 'thermal_80';
  @override
  String get printerConnection => 'none';
  @override
  String get pdfPaperSize => 'a4';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeInventoryAlertsProvider extends ChangeNotifier implements InventoryAlertsProvider {
  @override
  List<dynamic> get alerts => [];
  @override
  int get totalAlertsCount => 0;
  @override
  List<dynamic> get reactiveAlerts => [];
  @override
  List<dynamic> get predictiveCriticalAlerts => [];

  @override
  Future<void> fetchAlerts({int threshold = 3}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAuthProvider extends ChangeNotifier implements AuthProvider {
  @override
  Map<String, dynamic>? get currentUser => {'id': 1, 'name': 'Admin User', 'role': 'admin'};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('SuppliersScreen renders smoothly without overflow on 1024x768 and 1280x800',
      (WidgetTester tester) async {
    final fakeSupplierProv = FakeSupplierProvider();
    fakeSupplierProv.setSuppliers([
      Supplier(
        id: 1,
        name: 'Distribuidora Mayorista de Alimentos y Bebidas SA',
        cuit: '30-71234567-8',
        phone: '11-4567-8901',
        address: 'Av. Corrientes 1234, CABA, Buenos Aires',
        balance: 154000.75,
        isActive: true,
      ),
      Supplier(
        id: 2,
        name: 'Proveedor Secundario SRL',
        cuit: '30-88776655-4',
        phone: '11-9876-5432',
        address: 'Calle Falsa 123',
        balance: -5000.00,
        isActive: true,
      ),
      Supplier(
        id: 3,
        name: 'Lácteos del Sur SA',
        cuit: '30-11223344-5',
        phone: '11-1111-2222',
        address: 'Ruta 2 Km 45',
        balance: 0.00,
        isActive: true,
      ),
    ]);

    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SupplierProvider>.value(value: fakeSupplierProv),
          ChangeNotifierProvider<SettingsProvider>.value(value: FakeSettingsProvider()),
          ChangeNotifierProvider<LocalTerminalProvider>.value(value: FakeLocalTerminalProvider()),
          ChangeNotifierProvider<InventoryAlertsProvider>.value(value: FakeInventoryAlertsProvider()),
          ChangeNotifierProvider<AuthProvider>.value(value: FakeAuthProvider()),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SuppliersScreen(),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Nuevo Proveedor'), findsOneWidget);
    expect(find.text('Distribuidora Mayorista de Alimentos y Bebidas SA'), findsOneWidget);
    expect(find.text('Proveedor Secundario SRL'), findsOneWidget);
    expect(find.text('Lácteos del Sur SA'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'RenderFlex overflow should not occur');
  });

  testWidgets('SuppliersScreen renders smoothly without overflow on narrow screens (e.g. 650x800)',
      (WidgetTester tester) async {
    final fakeSupplierProv = FakeSupplierProvider();
    fakeSupplierProv.setSuppliers([
      Supplier(
        id: 1,
        name: 'Distribuidora Mayorista SA',
        cuit: '30-71234567-8',
        phone: '11-4567-8901',
        address: 'Av. Corrientes 1234',
        balance: 154000.75,
        isActive: true,
      ),
    ]);

    tester.view.physicalSize = const Size(650, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SupplierProvider>.value(value: fakeSupplierProv),
          ChangeNotifierProvider<SettingsProvider>.value(value: FakeSettingsProvider()),
          ChangeNotifierProvider<LocalTerminalProvider>.value(value: FakeLocalTerminalProvider()),
          ChangeNotifierProvider<InventoryAlertsProvider>.value(value: FakeInventoryAlertsProvider()),
          ChangeNotifierProvider<AuthProvider>.value(value: FakeAuthProvider()),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SuppliersScreen(),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Nuevo Proveedor'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'RenderFlex overflow should not occur on 650x800');
  });

  testWidgets('SuppliersScreen renders smoothly without overflow on ultra-compact screens (400x800)',
      (WidgetTester tester) async {
    final fakeSupplierProv = FakeSupplierProvider();
    fakeSupplierProv.setSuppliers([
      Supplier(
        id: 1,
        name: 'Distribuidora Mayorista SA',
        cuit: '30-71234567-8',
        phone: '11-4567-8901',
        address: 'Av. Corrientes 1234',
        balance: 154000.75,
        isActive: true,
      ),
    ]);

    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SupplierProvider>.value(value: fakeSupplierProv),
          ChangeNotifierProvider<SettingsProvider>.value(value: FakeSettingsProvider()),
          ChangeNotifierProvider<LocalTerminalProvider>.value(value: FakeLocalTerminalProvider()),
          ChangeNotifierProvider<InventoryAlertsProvider>.value(value: FakeInventoryAlertsProvider()),
          ChangeNotifierProvider<AuthProvider>.value(value: FakeAuthProvider()),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SuppliersScreen(),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Nuevo Proveedor'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'RenderFlex overflow should not occur on 400x800');
  });

  testWidgets('SuppliersScreen renders smoothly with long phone and CUIT on compact 360x640 without RenderFlex overflow',
      (WidgetTester tester) async {
    final fakeSupplierProv = FakeSupplierProvider();
    fakeSupplierProv.setSuppliers([
      Supplier(
        id: 1,
        name: 'Distribuidora Mayorista SA',
        cuit: '30-71234567-8 (Inscripcion Provincial 98765)',
        phone: '+54 9 11 4567-8901 / +54 9 11 9876-5432 (Lun-Vie 9-18)',
        address: 'Av. Corrientes 1234, Piso 5, Oficina B',
        balance: 154000.75,
        isActive: true,
      ),
    ]);

    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SupplierProvider>.value(value: fakeSupplierProv),
          ChangeNotifierProvider<SettingsProvider>.value(value: FakeSettingsProvider()),
          ChangeNotifierProvider<LocalTerminalProvider>.value(value: FakeLocalTerminalProvider()),
          ChangeNotifierProvider<InventoryAlertsProvider>.value(value: FakeInventoryAlertsProvider()),
          ChangeNotifierProvider<AuthProvider>.value(value: FakeAuthProvider()),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SuppliersScreen(),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final err = tester.takeException();
    expect(err, isNull, reason: 'Long phone and CUIT should not overflow RenderFlex on 360x640');
  });

  testWidgets('SuppliersScreen renders smoothly on extreme compact 320x568 without RenderFlex overflow', (tester) async {
    final fakeSupplierProv = FakeSupplierProvider();
    fakeSupplierProv.setSuppliers([
      Supplier(
        id: 99,
        name: 'Distribuidora Mayorista de Bebidas y Alimentos SRL',
        cuit: '30-99887766-5',
        phone: '+54 9 11 4567-8901',
        address: 'Av. Corrientes 1234, Piso 5',
        balance: 154000.75,
        isActive: true,
      ),
    ]);

    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SupplierProvider>.value(value: fakeSupplierProv),
          ChangeNotifierProvider<SettingsProvider>.value(value: FakeSettingsProvider()),
          ChangeNotifierProvider<LocalTerminalProvider>.value(value: FakeLocalTerminalProvider()),
          ChangeNotifierProvider<InventoryAlertsProvider>.value(value: FakeInventoryAlertsProvider()),
          ChangeNotifierProvider<AuthProvider>.value(value: FakeAuthProvider()),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SuppliersScreen(),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final err = tester.takeException();
    expect(err, isNull, reason: 'RenderFlex should not overflow on 320x568');
  });
}
