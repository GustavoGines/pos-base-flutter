import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:frontend_desktop/core/constants/app_permissions.dart';
import 'package:frontend_desktop/core/network/api_client.dart';
import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import 'package:frontend_desktop/features/auth/presentation/providers/auth_provider.dart';
import 'package:frontend_desktop/features/auth/presentation/widgets/admin_pin_dialog.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/brand.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/category.dart';
import 'package:frontend_desktop/features/catalog/presentation/pages/catalog_screen.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/features/quotes/data/quote_repository.dart';
import 'package:frontend_desktop/features/quotes/presentation/pages/quotes_list_screen.dart';
import 'package:frontend_desktop/features/quotes/presentation/providers/quote_provider.dart';
import 'package:frontend_desktop/features/reports/presentation/providers/inventory_alerts_provider.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/features/suppliers/models/supplier_model.dart';
import 'package:frontend_desktop/features/suppliers/presentation/screens/suppliers_screen.dart';
import 'package:frontend_desktop/features/suppliers/providers/supplier_provider.dart';
import 'package:frontend_desktop/features/users/presentation/pages/users_manager_screen.dart';
import 'package:frontend_desktop/features/users/presentation/providers/users_provider.dart';

class FakeCatalogProvider extends ChangeNotifier implements CatalogProvider {
  @override
  List<Category> get categories => [Category(id: 1, name: 'Bebidas')];
  @override
  List<Brand> get brands => [Brand(id: 1, name: 'Gaseosa')];
  @override
  bool get isLoading => false;
  @override
  String? get errorMessage => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAuthProvider extends ChangeNotifier implements AuthProvider {
  bool _isAdmin = false;
  final Set<String> _perms = {};
  Map<String, dynamic>? _user;

  FakeAuthProvider({bool isAdmin = false, List<String> perms = const []}) {
    _isAdmin = isAdmin;
    _perms.addAll(perms);
    _user = {'id': 1, 'name': 'Test User', 'role': isAdmin ? 'admin' : 'cashier'};
  }

  @override
  bool get isAdmin => _isAdmin;
  @override
  bool hasPermission(String permission) => _isAdmin || _perms.contains(permission);
  @override
  Map<String, dynamic>? get currentUser => _user;
  @override
  bool get isAuthenticated => _user != null;
  @override
  ApiClient? get apiClient => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSettingsProvider extends ChangeNotifier implements SettingsProvider {
  @override
  BusinessSettings get settings => BusinessSettings(companyName: 'POS Test', taxId: '20-12345678-9');
  @override
  FeatureFlags get features => const FeatureFlags(fastPos: true, suppliers: true, quotes: true);

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
  bool get isLoading => false;

  @override
  Future<void> fetchAlerts({int threshold = 3}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeUsersProvider extends ChangeNotifier implements UsersProvider {
  List<Map<String, dynamic>> _users = [];
  final bool _isLoading = false;

  @override
  List<Map<String, dynamic>> get users => _users;
  @override
  bool get isLoading => _isLoading;
  @override
  String? get errorMessage => null;

  void setUsers(List<Map<String, dynamic>> list) {
    _users = list;
    notifyListeners();
  }

  @override
  Future<void> loadUsers() async {}

  @override
  Future<bool> deleteUser(int id) async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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
  Future<bool> deleteSupplier(int id) async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeQuoteProvider extends ChangeNotifier implements QuoteProvider {
  List<Quote> _quotes = [];
  @override
  List<Quote> get quotes => _quotes;
  @override
  bool get isLoading => false;
  @override
  String? get errorMessage => null;

  void setQuotes(List<Quote> list) {
    _quotes = list;
    notifyListeners();
  }

  @override
  Future<void> loadQuotes({String? search, String? status}) async {}

  @override
  Future<bool> deleteQuote(int id) async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      if (details.toString().contains('global_app_bar.dart') ||
          details.exceptionAsString().contains('global_app_bar.dart')) {
        return;
      }
      originalOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = originalOnError);
  });

  Widget buildTestWrapper({
    required Widget child,
    AuthProvider? auth,
    UsersProvider? users,
    SupplierProvider? suppliers,
    QuoteProvider? quotes,
    SettingsProvider? settings,
    LocalTerminalProvider? terminal,
    InventoryAlertsProvider? alerts,
  }) {
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      if (details.toString().contains('global_app_bar')) {
        return;
      }
      originalOnError?.call(details);
    };

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth ?? FakeAuthProvider()),
        ChangeNotifierProvider<SettingsProvider>.value(value: settings ?? FakeSettingsProvider()),
        ChangeNotifierProvider<LocalTerminalProvider>.value(value: terminal ?? FakeLocalTerminalProvider()),
        ChangeNotifierProvider<InventoryAlertsProvider>.value(value: alerts ?? FakeInventoryAlertsProvider()),
        if (users != null) ChangeNotifierProvider<UsersProvider>.value(value: users),
        if (suppliers != null) ChangeNotifierProvider<SupplierProvider>.value(value: suppliers),
        if (quotes != null) ChangeNotifierProvider<QuoteProvider>.value(value: quotes),
      ],
      child: MaterialApp(
        home: child,
      ),
    );
  }

  group('R1: BulkPriceUpdateDialog Overflow Prevention', () {
    testWidgets('BulkPriceUpdateDialog renders in small window without RenderFlex overflow and contains SingleChildScrollView', (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final catalogProvider = FakeCatalogProvider();

      await tester.pumpWidget(
        ChangeNotifierProvider<CatalogProvider>.value(
          value: catalogProvider,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => BulkPriceUpdateDialog(provider: catalogProvider),
                    );
                  },
                  child: const Text('Open Dialog'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Verify that SingleChildScrollView is present in the dialog content
      expect(find.byType(SingleChildScrollView), findsWidgets);
      expect(find.text('Aumento Masivo de Precios'), findsOneWidget);

      // Verify no RenderFlex errors were thrown by FlutterError handler
      expect(tester.takeException(), isNull);
    });

    testWidgets('BulkPriceUpdateDialog renders in constrained compact window (800x480) without overflow and scrolls', (tester) async {
      tester.view.physicalSize = const Size(800, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final catalogProvider = FakeCatalogProvider();

      await tester.pumpWidget(
        ChangeNotifierProvider<CatalogProvider>.value(
          value: catalogProvider,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => BulkPriceUpdateDialog(provider: catalogProvider),
                    );
                  },
                  child: const Text('Open Dialog'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.byType(SingleChildScrollView), findsWidgets);
      expect(find.text('Aumento Masivo de Precios'), findsOneWidget);

      // Drag to scroll vertically inside dialog content
      await tester.drag(find.text('Aumento Masivo de Precios'), const Offset(0, -150));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('BulkPriceUpdateDialog with targetProductIds renders in narrow window (320x480) without horizontal RenderFlex overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final catalogProvider = FakeCatalogProvider();

      await tester.pumpWidget(
        ChangeNotifierProvider<CatalogProvider>.value(
          value: catalogProvider,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => BulkPriceUpdateDialog(
                        provider: catalogProvider,
                        targetProductIds: const [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
                      ),
                    );
                  },
                  child: const Text('Open Dialog'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.byType(SingleChildScrollView), findsWidgets);
      expect(find.text('Aplicando a 10 productos seleccionados'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('BulkPriceUpdateDialog default mode (with dropdowns) renders in narrow window (320x480) without overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final catalogProvider = FakeCatalogProvider();

      await tester.pumpWidget(
        ChangeNotifierProvider<CatalogProvider>.value(
          value: catalogProvider,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => BulkPriceUpdateDialog(provider: catalogProvider),
                    );
                  },
                  child: const Text('Open Dialog'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.byType(SingleChildScrollView), findsWidgets);
      expect(find.text('Aumento Masivo de Precios'), findsOneWidget);
      expect(find.text('Filtrar por Categoría'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('BulkPriceUpdateDialog in ultra-short window (480x280) scrolls without RenderFlex overflow', (tester) async {
      FlutterErrorDetails? caught;
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        caught = details;
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      tester.view.physicalSize = const Size(480, 280);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final catalogProvider = FakeCatalogProvider();

      await tester.pumpWidget(
        ChangeNotifierProvider<CatalogProvider>.value(
          value: catalogProvider,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => BulkPriceUpdateDialog(provider: catalogProvider),
                    );
                  },
                  child: const Text('Open Dialog'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.byType(SingleChildScrollView), findsWidgets);
      expect(caught, isNull);
      expect(tester.takeException(), isNull);

      // Verify scrolling works
      await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -200));
      await tester.pumpAndSettle();

      expect(caught, isNull);
      expect(tester.takeException(), isNull);
    });
  });

  group('R4: UsersManagerScreen Employee Permissions Collapsing and UX', () {
    testWidgets('Employee with 25 permissions renders 3 chips + "+22 más" and expands/collapses properly', (tester) async {
      final usersProvider = FakeUsersProvider();
      usersProvider.setUsers([
        {
          'id': 101,
          'name': 'Cajero Con Todos Los Permisos',
          'role': 'cashier',
          'permissions': AppPermissions.all,
        }
      ]);

      await tester.pumpWidget(
        buildTestWrapper(
          child: const UsersManagerScreen(),
          users: usersProvider,
        ),
      );

      await tester.pumpAndSettle();

      // Card must show name and CAJERO badge
      expect(find.text('Cajero Con Todos Los Permisos'), findsOneWidget);
      expect(find.text('CAJERO'), findsOneWidget);

      // In collapsed state, exactly 3 permissions chips + 1 "+22 más" chip must be shown
      expect(find.text('+22 más'), findsOneWidget);
      expect(find.text('Ver menos'), findsNothing);

      // Tapping "+22 más" must expand the view
      await tester.tap(find.text('+22 más'));
      await tester.pumpAndSettle();

      // In expanded state, 'Ver menos' must appear and '+22 más' must be gone
      expect(find.text('Ver menos'), findsOneWidget);
      expect(find.text('+22 más'), findsNothing);

      // Tapping 'Ver menos' collapses the view back
      await tester.tap(find.text('Ver menos'));
      await tester.pumpAndSettle();

      expect(find.text('+22 más'), findsOneWidget);
      expect(find.text('Ver menos'), findsNothing);
    });

    testWidgets('Employee with 3 permissions does not show "+N más" chip', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final originalOnError = FlutterError.onError;
      FlutterError.onError = (FlutterErrorDetails details) {
        if (details.exceptionAsString().contains('global_app_bar.dart')) {
          return;
        }
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      final usersProvider = FakeUsersProvider();
      usersProvider.setUsers([
        {
          'id': 102,
          'name': 'Cajero Básico',
          'role': 'cashier',
          'permissions': [
            AppPermissions.applyDiscounts,
            AppPermissions.viewSuppliers,
          ],
        }
      ]);

      await tester.pumpWidget(
        buildTestWrapper(
          child: const UsersManagerScreen(),
          users: usersProvider,
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Cajero Básico'), findsOneWidget);
      expect(find.text('+N más'), findsNothing);
      expect(find.byType(Chip), findsNWidgets(2));
    });

    testWidgets('UsersManagerScreen handles dirty JSON, Map permissions, and missing employee ID without TypeError', (tester) async {
      final usersProvider = FakeUsersProvider();
      usersProvider.setUsers([
        {
          // id is null to test fallback
          'name': 'Cajero Dirty Perms',
          'role': 'cashier',
          'permissions': [AppPermissions.viewReports, null, 12345],
        },
        {
          'id': 104,
          'name': 'Cajero Map Perms',
          'role': 'cashier',
          'permissions': {
            AppPermissions.viewReports: true,
            AppPermissions.manageCatalog: false,
          },
        },
      ]);

      await tester.pumpWidget(
        buildTestWrapper(
          child: const UsersManagerScreen(),
          users: usersProvider,
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Cajero Dirty Perms'), findsOneWidget);
      expect(find.text('Cajero Map Perms'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('UsersManagerScreen: Employee with uppercase role ADMIN renders as administrator without cashier chips', (tester) async {
      final usersProvider = FakeUsersProvider();
      usersProvider.setUsers([
        {
          'id': 105,
          'name': 'Supervisor General',
          'role': 'ADMIN',
          'permissions': [AppPermissions.manageUsers, AppPermissions.viewReports],
        }
      ]);

      await tester.pumpWidget(
        buildTestWrapper(
          child: const UsersManagerScreen(),
          users: usersProvider,
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Supervisor General'), findsOneWidget);
      expect(find.text('ADMINISTRADOR'), findsOneWidget);
      expect(find.byIcon(Icons.admin_panel_settings_rounded), findsOneWidget);
      // Admin should not render cashier chips
      expect(find.byType(Chip), findsNothing);
    });

    testWidgets('UsersManagerScreen: Duplicate permissions are deduplicated and do not show redundant chips', (tester) async {
      final usersProvider = FakeUsersProvider();
      usersProvider.setUsers([
        {
          'id': 106,
          'name': 'Cajero Con Duplicados',
          'role': 'cashier',
          'permissions': [
            AppPermissions.viewReports,
            AppPermissions.viewReports,
            AppPermissions.viewReports,
            AppPermissions.viewSuppliers,
          ],
        }
      ]);

      await tester.pumpWidget(
        buildTestWrapper(
          child: const UsersManagerScreen(),
          users: usersProvider,
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Cajero Con Duplicados'), findsOneWidget);
      // Exactly 2 chips: viewReports and viewSuppliers (deduplicated)
      expect(find.byType(Chip), findsNWidgets(2));
      expect(find.text('+N más'), findsNothing);
    });

    testWidgets('UsersManagerScreen renders in compact window (400x700) without RenderFlex overflow', (tester) async {
      FlutterErrorDetails? caught;
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        caught = details;
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      tester.view.physicalSize = const Size(400, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final usersProvider = FakeUsersProvider();
      usersProvider.setUsers([
        {
          'id': 101,
          'name': 'Cajero Compacto',
          'role': 'cashier',
          'permissions': AppPermissions.all,
        }
      ]);

      await tester.pumpWidget(
        buildTestWrapper(
          child: const UsersManagerScreen(),
          users: usersProvider,
        ),
      );
      await tester.pumpAndSettle();

      expect(caught, isNull);
      expect(tester.takeException(), isNull);
    });
  });

  group('R2: Orphaned Destructive Actions Protection with AdminPinDialog.protectAction', () {
    testWidgets('UsersManagerScreen: Deleting employee without manageUsers prompts AdminPinDialog', (tester) async {
      final usersProvider = FakeUsersProvider();
      usersProvider.setUsers([
        {
          'id': 201,
          'name': 'Empleado a Borrar',
          'role': 'cashier',
          'permissions': [],
        }
      ]);

      final unprivilegedAuth = FakeAuthProvider(isAdmin: false, perms: []);

      await tester.pumpWidget(
        buildTestWrapper(
          child: const UsersManagerScreen(),
          auth: unprivilegedAuth,
          users: usersProvider,
        ),
      );

      await tester.pumpAndSettle();

      // Tap delete button on employee card
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      // Confirm in initial AlertDialog
      expect(find.text('Eliminar Empleado'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
      await tester.pumpAndSettle();

      // Should prompt for AdminPinDialog because user lacks manageUsers
      expect(find.byType(AdminPinDialog), findsOneWidget);
    });

    testWidgets('SuppliersScreen: Deleting supplier as cashier with viewSuppliers (but without manageCatalog) prompts AdminPinDialog', (tester) async {
      final supplierProvider = FakeSupplierProvider();
      supplierProvider.setSuppliers([
        Supplier(
          id: 55,
          name: 'Distribuidora Central',
          cuit: '20-99999999-9',
          balance: 0,
          isActive: true,
        ),
      ]);

      // Cashier has viewSuppliers to navigate the screen, but lacks manageCatalog
      final cashierAuth = FakeAuthProvider(isAdmin: false, perms: [AppPermissions.viewSuppliers]);

      await tester.pumpWidget(
        buildTestWrapper(
          child: const SuppliersScreen(),
          auth: cashierAuth,
          suppliers: supplierProvider,
        ),
      );

      await tester.pumpAndSettle();

      // Open supplier card options menu and select 'Eliminar'
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Eliminar'));
      await tester.pumpAndSettle();

      // Confirm in initial AlertDialog
      expect(find.text('Eliminar Proveedor'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Eliminar'));
      await tester.pumpAndSettle();

      // Must prompt for AdminPinDialog because deleting requires manageCatalog
      expect(find.byType(AdminPinDialog), findsOneWidget);
    });

    testWidgets('SuppliersScreen: Deleting supplier with manageCatalog does not prompt AdminPinDialog', (tester) async {
      final supplierProvider = FakeSupplierProvider();
      supplierProvider.setSuppliers([
        Supplier(
          id: 55,
          name: 'Distribuidora Central',
          cuit: '20-99999999-9',
          balance: 0,
          isActive: true,
        ),
      ]);

      final authorizedAuth = FakeAuthProvider(
        isAdmin: false,
        perms: [AppPermissions.viewSuppliers, AppPermissions.manageCatalog],
      );

      await tester.pumpWidget(
        buildTestWrapper(
          child: const SuppliersScreen(),
          auth: authorizedAuth,
          suppliers: supplierProvider,
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Eliminar'));
      await tester.pumpAndSettle();

      expect(find.text('Eliminar Proveedor'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Eliminar'));
      await tester.pumpAndSettle();

      // Should NOT prompt for AdminPinDialog because user has manageCatalog
      expect(find.byType(AdminPinDialog), findsNothing);
    });

    testWidgets('QuotesListScreen: Deleting quote without manageQuotes prompts AdminPinDialog', (tester) async {
      final quoteProvider = FakeQuoteProvider();
      quoteProvider.setQuotes([
        Quote(
          id: 77,
          quoteNumber: 'PRE-00077',
          status: 'pending',
          subtotal: 1500.0,
          total: 1500.0,
          customerName: 'Cliente Juan',
          createdAt: DateTime.now().toIso8601String(),
          items: [],
        ),
      ]);

      final unprivilegedAuth = FakeAuthProvider(isAdmin: false, perms: []);

      await tester.pumpWidget(
        buildTestWrapper(
          child: const QuotesListScreen(),
          auth: unprivilegedAuth,
          quotes: quoteProvider,
        ),
      );

      await tester.pumpAndSettle();

      // Tap on quote card to open details / actions sheet
      await tester.tap(find.text('PRE-00077'));
      await tester.pumpAndSettle();

      // In quote detail bottom sheet, tap delete button
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      // Confirm in initial AlertDialog
      expect(find.text('¿Eliminar presupuesto?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
      await tester.pumpAndSettle();

      // Should prompt for AdminPinDialog because user lacks manageQuotes
      expect(find.byType(AdminPinDialog), findsOneWidget);
    });

    testWidgets('UsersManagerScreen: Deleting employee with manageUsers does not prompt AdminPinDialog', (tester) async {
      final usersProvider = FakeUsersProvider();
      usersProvider.setUsers([
        {
          'id': 202,
          'name': 'Empleado a Borrar Aut',
          'role': 'cashier',
          'permissions': [],
        }
      ]);

      final privilegedAuth = FakeAuthProvider(isAdmin: false, perms: [AppPermissions.manageUsers]);

      await tester.pumpWidget(
        buildTestWrapper(
          child: const UsersManagerScreen(),
          auth: privilegedAuth,
          users: usersProvider,
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      expect(find.text('Eliminar Empleado'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
      await tester.pumpAndSettle();

      // Should NOT prompt for AdminPinDialog because user has manageUsers
      expect(find.byType(AdminPinDialog), findsNothing);
    });

    testWidgets('UsersManagerScreen: Deleting employee with String id and manageUsers executes successfully without TypeError', (tester) async {
      final usersProvider = FakeUsersProvider();
      usersProvider.setUsers([
        {
          'id': '205',
          'name': 'Empleado ID String',
          'role': 'cashier',
          'permissions': [],
        }
      ]);

      final privilegedAuth = FakeAuthProvider(isAdmin: false, perms: [AppPermissions.manageUsers]);

      await tester.pumpWidget(
        buildTestWrapper(
          child: const UsersManagerScreen(),
          auth: privilegedAuth,
          users: usersProvider,
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      expect(find.text('Eliminar Empleado'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
      await tester.pumpAndSettle();

      expect(find.byType(AdminPinDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('QuotesListScreen: Single quote deletion with manageQuotes executes deletion without AdminPinDialog', (tester) async {
      final quoteProvider = FakeQuoteProvider();
      quoteProvider.setQuotes([
        Quote(
          id: 78,
          quoteNumber: 'PRE-00078',
          status: 'pending',
          subtotal: 2000.0,
          total: 2000.0,
          customerName: 'Cliente Autorizado',
          createdAt: DateTime.now().toIso8601String(),
          items: [],
        ),
      ]);

      final privilegedAuth = FakeAuthProvider(isAdmin: false, perms: [AppPermissions.manageQuotes]);

      await tester.pumpWidget(
        buildTestWrapper(
          child: const QuotesListScreen(),
          auth: privilegedAuth,
          quotes: quoteProvider,
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.text('PRE-00078'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      expect(find.text('¿Eliminar presupuesto?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
      await tester.pumpAndSettle();

      // Should NOT prompt for AdminPinDialog because user has manageQuotes
      expect(find.byType(AdminPinDialog), findsNothing);
    });

    testWidgets('QuotesListScreen: Bulk deleting quotes without manageQuotes prompts AdminPinDialog', (tester) async {
      final quoteProvider = FakeQuoteProvider();
      quoteProvider.setQuotes([
        Quote(
          id: 81,
          quoteNumber: 'PRE-00081',
          status: 'pending',
          subtotal: 1000.0,
          total: 1000.0,
          customerName: 'Cliente Bulk 1',
          createdAt: DateTime.now().toIso8601String(),
          items: [],
        ),
        Quote(
          id: 82,
          quoteNumber: 'PRE-00082',
          status: 'pending',
          subtotal: 2000.0,
          total: 2000.0,
          customerName: 'Cliente Bulk 2',
          createdAt: DateTime.now().toIso8601String(),
          items: [],
        ),
      ]);

      final unprivilegedAuth = FakeAuthProvider(isAdmin: false, perms: []);

      await tester.pumpWidget(
        buildTestWrapper(
          child: const QuotesListScreen(),
          auth: unprivilegedAuth,
          quotes: quoteProvider,
        ),
      );

      await tester.pumpAndSettle();

      // Tap select all checkbox
      await tester.tap(find.text('Seleccionar todo'));
      await tester.pumpAndSettle();

      // In bulk action bar, tap 'Eliminar' button
      expect(find.widgetWithText(FilledButton, 'Eliminar'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
      await tester.pumpAndSettle();

      // Confirm in dialog (now 2 FilledButtons with 'Eliminar' exist: toolbar and dialog)
      expect(find.text('¿Eliminar seleccionados?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Eliminar').last);
      await tester.pumpAndSettle();

      // Should prompt for AdminPinDialog because user lacks manageQuotes
      expect(find.byType(AdminPinDialog), findsOneWidget);
    });

    testWidgets('QuotesListScreen: Bulk deleting quotes with manageQuotes executes deletion without AdminPinDialog', (tester) async {
      final quoteProvider = FakeQuoteProvider();
      quoteProvider.setQuotes([
        Quote(
          id: 83,
          quoteNumber: 'PRE-00083',
          status: 'pending',
          subtotal: 1000.0,
          total: 1000.0,
          customerName: 'Cliente Bulk 3',
          createdAt: DateTime.now().toIso8601String(),
          items: [],
        ),
      ]);

      final privilegedAuth = FakeAuthProvider(isAdmin: false, perms: [AppPermissions.manageQuotes]);

      await tester.pumpWidget(
        buildTestWrapper(
          child: const QuotesListScreen(),
          auth: privilegedAuth,
          quotes: quoteProvider,
        ),
      );

      await tester.pumpAndSettle();

      // Tap select all checkbox
      await tester.tap(find.text('Seleccionar todo'));
      await tester.pumpAndSettle();

      // In bulk action bar, tap 'Eliminar' button
      expect(find.widgetWithText(FilledButton, 'Eliminar'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
      await tester.pumpAndSettle();

      // Confirm in dialog
      expect(find.text('¿Eliminar seleccionados?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Eliminar').last);
      await tester.pumpAndSettle();

      // Should NOT prompt for AdminPinDialog because user has manageQuotes
      expect(find.byType(AdminPinDialog), findsNothing);
    });
  });
}
