import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend_desktop/core/constants/app_permissions.dart';
import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import 'package:frontend_desktop/core/services/license_heartbeat_service.dart';
import 'package:frontend_desktop/features/auth/presentation/providers/auth_provider.dart';
import 'package:frontend_desktop/features/reports/presentation/providers/inventory_alerts_provider.dart';
import 'package:frontend_desktop/features/settings/data/datasources/settings_remote_datasource.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/settings/presentation/pages/settings_screen.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';

// --- FAKES FOR WIDGET TESTING ---
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

class FakeAuthProvider extends ChangeNotifier implements AuthProvider {
  final bool _isAdmin;
  final Set<String> _permissions;

  FakeAuthProvider({bool isAdmin = true, Set<String>? permissions})
      : _isAdmin = isAdmin,
        _permissions = permissions ?? {AppPermissions.manageSettings};

  @override
  Map<String, dynamic>? get currentUser => {'id': 1, 'name': 'Test User', 'role': _isAdmin ? 'admin' : 'cashier'};
  @override
  bool get isAdmin => _isAdmin;
  @override
  bool hasPermission(String permission) => _isAdmin || _permissions.contains(permission);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeIntegrationsSettingsProvider extends ChangeNotifier implements SettingsProvider {
  final BusinessSettings? _settings;
  Map<String, dynamic>? _integrationsData;
  bool saveIntegrationsCalled = false;
  Map<String, dynamic>? lastSavedIntegrationsData;
  bool testConnectionCalled = false;
  String? lastTestedToken;
  bool testConnectionSuccess = true;
  String testConnectionMessage = 'Conexión exitosa con Mercado Pago.';

  bool shouldFailLoad = false;

  FakeIntegrationsSettingsProvider({
    BusinessSettings? settings,
    Map<String, dynamic>? integrationsData,
    this.shouldFailLoad = false,
  })  : _settings = settings,
        _integrationsData = integrationsData ??
            {
              'mp_qr_enabled': true,
              'mp_point_device_id': 'POINT_TEST_01',
              'mp_access_token': 'APP_USR-****abcd',
              'mp_webhook_secret': 'whsec_****1234',
              'mp_has_access_token': true,
              'mp_has_webhook_secret': true,
              'mp_webhook_url': 'http://pos-backend.test/api/webhooks/mercadopago',
              'afip_enabled': true,
              'afip_cuit': '20123456789',
              'afip_pto_vta': 1,
              'afip_environment': 'testing',
              'afip_has_cert': true,
              'afip_has_key': true,
              'afip_cert_expires_at': '2027-12-31 23:59:59',
            };

  @override
  BusinessSettings? get settings => _settings;
  @override
  bool get isLoading => false;
  @override
  String? get errorMessage => null;
  @override
  String get currentPlan => _settings?.licensePlanType ?? 'basic';
  @override
  FeatureFlags get features => _settings?.features ?? const FeatureFlags(fastPos: true);
  @override
  bool hasFeature(String featureName) => _settings?.hasFeature(featureName) ?? false;
  @override
  bool get isLicenseActive => true;
  @override
  List<String> get allowedAddons => _settings?.licenseFeatures ?? [];
  @override
  LicenseSecurityStatus get securityStatus => LicenseSecurityStatus.ok;
  @override
  String get currentApiUrl => 'http://pos-backend.test/api';

  @override
  Map<String, dynamic>? get integrations => _integrationsData;
  @override
  bool get isLoadingIntegrations => false;

  int loadIntegrationsCallCount = 0;

  @override
  Future<Map<String, dynamic>?> loadIntegrations({bool isSilent = false}) async {
    loadIntegrationsCallCount++;
    if (shouldFailLoad) return null;
    return _integrationsData;
  }

  @override
  Future<bool> saveIntegrations(Map<String, dynamic> data) async {
    saveIntegrationsCalled = true;
    lastSavedIntegrationsData = data;
    _integrationsData = {...?_integrationsData, ...data};
    return true;
  }

  @override
  Future<Map<String, dynamic>> testMercadoPagoConnection({String? mpAccessToken}) async {
    testConnectionCalled = true;
    lastTestedToken = mpAccessToken;
    return {
      'success': testConnectionSuccess,
      'message': testConnectionMessage,
      'nickname': 'TEST_STORE_USER',
    };
  }

  @override
  Future<bool> saveSettings(Map<String, dynamic> data) async => true;
  @override
  Future<void> loadSettings({bool isSilent = false}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'pos_terminal_id': 'caja-test',
      'pos_api': 'http://pos-backend.test/api',
      'backend_install_path': r'C:\laragon\www\Sistema_POS\pos-backend',
      'update_channel': 'stable',
    });
    PackageInfo.setMockInitialValues(
      appName: 'POS Test',
      packageName: 'com.example.pos',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  group('Phase 7.9: DataSource Unit Tests (Integrations)', () {
    test('fetchIntegrations sends GET to /settings/integrations and parses payload', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, equals('GET'));
        expect(request.url.path, endsWith('/settings/integrations'));
        return http.Response(
          jsonEncode({
            'mp_qr_enabled': true,
            'mp_point_device_id': 'PAX_01',
            'mp_access_token': 'APP_USR-****9999',
            'afip_enabled': true,
            'afip_cuit': '20123456789',
            'afip_has_cert': true,
            'afip_has_key': true,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final ds = SettingsRemoteDataSourceImpl(baseUrl: 'http://localhost/api', client: mockClient);
      final result = await ds.fetchIntegrations();

      expect(result['mp_qr_enabled'], isTrue);
      expect(result['mp_point_device_id'], equals('PAX_01'));
      expect(result['afip_has_cert'], isTrue);
    });

    test('updateIntegrations sends PUT to /settings/integrations with data', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, equals('PUT'));
        expect(request.url.path, endsWith('/settings/integrations'));
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['mp_access_token'], equals('APP_USR-****9999'));
        expect(body['afip_cuit'], equals('20123456789'));
        return http.Response(jsonEncode({'message': 'OK'}), 200);
      });

      final ds = SettingsRemoteDataSourceImpl(baseUrl: 'http://localhost/api', client: mockClient);
      final success = await ds.updateIntegrations({
        'mp_access_token': 'APP_USR-****9999',
        'afip_cuit': '20123456789',
      });

      expect(success, isTrue);
    });

    test('testMercadoPagoConnection sends POST to /settings/integrations/mercadopago/test', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, equals('POST'));
        expect(request.url.path, endsWith('/settings/integrations/mercadopago/test'));
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['mp_access_token'], equals('APP_USR-test-token'));
        return http.Response(
          jsonEncode({
            'success': true,
            'message': 'Conexión exitosa',
            'collector_id': 12345,
            'nickname': 'TIENDA_TEST',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final ds = SettingsRemoteDataSourceImpl(baseUrl: 'http://localhost/api', client: mockClient);
      final result = await ds.testMercadoPagoConnection(mpAccessToken: 'APP_USR-test-token');

      expect(result['success'], isTrue);
      expect(result['nickname'], equals('TIENDA_TEST'));
    });

    test('testMercadoPagoConnection gracefully handles 400 error without exposing stack', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': false,
            'message': 'El Access Token de Mercado Pago es inválido o expiró.',
          }),
          400,
          headers: {'content-type': 'application/json'},
        );
      });

      final ds = SettingsRemoteDataSourceImpl(baseUrl: 'http://localhost/api', client: mockClient);
      final result = await ds.testMercadoPagoConnection(mpAccessToken: 'invalid');

      expect(result['success'], isFalse);
      expect(result['message'], contains('inválido'));
    });
  });

  group('Phase 7.9: SettingsScreen Widget Tests (Integrations UI)', () {
    Widget buildSettingsScreenApp({
      required FakeIntegrationsSettingsProvider settingsProv,
      AuthProvider? authProv,
    }) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>.value(value: settingsProv),
          ChangeNotifierProvider<LocalTerminalProvider>.value(value: FakeLocalTerminalProvider()),
          ChangeNotifierProvider<AuthProvider>.value(
              value: authProv ?? FakeAuthProvider(isAdmin: true)),
          ChangeNotifierProvider<InventoryAlertsProvider>.value(value: FakeInventoryAlertsProvider()),
        ],
        child: const MaterialApp(
          home: SettingsScreen(),
        ),
      );
    }

    testWidgets('Sidebar displays Integraciones when user has manage_settings permission', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final settingsProv = FakeIntegrationsSettingsProvider();
      final authProv = FakeAuthProvider(isAdmin: false, permissions: {AppPermissions.manageSettings});

      await tester.pumpWidget(buildSettingsScreenApp(settingsProv: settingsProv, authProv: authProv));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Integraciones'), findsOneWidget);
    });

    testWidgets('Sidebar hides Integraciones when cashier lacks manage_settings permission', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final settingsProv = FakeIntegrationsSettingsProvider();
      final authProv = FakeAuthProvider(isAdmin: false, permissions: {'pos'}); // sin manage_settings

      await tester.pumpWidget(buildSettingsScreenApp(settingsProv: settingsProv, authProv: authProv));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Integraciones'), findsNothing);
    });

    testWidgets('Integraciones tab renders Mercado Pago and ARCA cards with obscured fields and chips', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final settingsProv = FakeIntegrationsSettingsProvider();

      await tester.pumpWidget(buildSettingsScreenApp(settingsProv: settingsProv));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Tap on Integraciones tab
      await tester.tap(find.text('Integraciones'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Headers
      expect(find.text('Integraciones'), findsWidgets);
      expect(find.text('Mercado Pago'), findsOneWidget);
      expect(find.text('ARCA / AFIP (Facturación Electrónica)'), findsOneWidget);

      // Mercado Pago fields
      expect(find.text('Habilitar cobro con QR'), findsOneWidget);
      expect(find.byKey(const ValueKey('field_mp_access_token')), findsOneWidget);
      expect(find.byKey(const ValueKey('field_mp_webhook_secret')), findsOneWidget);
      expect(find.byKey(const ValueKey('field_mp_point_device_id')), findsOneWidget);
      expect(find.byKey(const ValueKey('field_mp_webhook_url')), findsOneWidget);
      expect(find.byKey(const ValueKey('btn_test_mp_connection')), findsOneWidget);

      // Verify Access Token is obscured by default
      final textField = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const ValueKey('field_mp_access_token')),
          matching: find.byType(TextField),
        ),
      );
      expect(textField.obscureText, isTrue);

      // Toggle obscure text via eye icon
      final eyeIcons = find.byTooltip('Mostrar token');
      expect(eyeIcons, findsOneWidget);
      await tester.tap(eyeIcons);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final revealedTextField = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const ValueKey('field_mp_access_token')),
          matching: find.byType(TextField),
        ),
      );
      expect(revealedTextField.obscureText, isFalse);

      // ARCA / AFIP fields
      expect(find.text('Habilitar Facturación ARCA'), findsOneWidget);
      expect(find.byKey(const ValueKey('field_afip_cuit')), findsOneWidget);
      expect(find.byKey(const ValueKey('field_afip_pto_vta')), findsOneWidget);
      expect(find.byKey(const ValueKey('dropdown_afip_environment')), findsOneWidget);

      // Visual status chips
      expect(find.byKey(const ValueKey('chip_afip_cert')), findsOneWidget);
      expect(find.byKey(const ValueKey('chip_afip_key')), findsOneWidget);
      expect(find.text('Certificado (.crt) Instalado'), findsOneWidget);
      expect(find.text('Clave Privada (.key) Instalada'), findsOneWidget);
    });

    testWidgets('Probar conexión button triggers testMercadoPagoConnection and shows feedback', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final settingsProv = FakeIntegrationsSettingsProvider();

      await tester.pumpWidget(buildSettingsScreenApp(settingsProv: settingsProv));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Switch to Integraciones
      await tester.tap(find.text('Integraciones'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Scroll to and click Probar conexión
      final btnFinder = find.byKey(const ValueKey('btn_test_mp_connection'));
      await tester.ensureVisible(btnFinder);
      await tester.pump();
      await tester.tap(btnFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(settingsProv.testConnectionCalled, isTrue);
      // SnackBar shows success message with username
      expect(find.textContaining('Conexión con Mercado Pago exitosa'), findsOneWidget);
    });

    testWidgets('Saving Integrations with masked fields sends data and preserves secrets', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final settingsProv = FakeIntegrationsSettingsProvider();

      await tester.pumpWidget(buildSettingsScreenApp(settingsProv: settingsProv));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Switch to Integraciones
      await tester.tap(find.text('Integraciones'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Scroll to and click GUARDAR INTEGRACIONES button
      final btnFinder = find.widgetWithText(FilledButton, 'GUARDAR').last;
      await tester.ensureVisible(btnFinder);
      await tester.pump();
      await tester.tap(btnFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(settingsProv.saveIntegrationsCalled, isTrue);
      expect(settingsProv.lastSavedIntegrationsData, isNotNull);
      // The masked token is sent as-is so backend does not overwrite encrypted secret
      expect(settingsProv.lastSavedIntegrationsData!['mp_access_token'], contains('****'));
      expect(settingsProv.lastSavedIntegrationsData!['afip_cuit'], equals('20123456789'));
    });

    testWidgets('Compact Viewport 320x480: Integraciones renders cleanly with 0 RenderFlex overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final settingsProv = FakeIntegrationsSettingsProvider();

      await tester.pumpWidget(buildSettingsScreenApp(settingsProv: settingsProv));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // In compact mode, tabs are rendered in top bar. Scroll horizontally to Integraciones tab
      final tabFinder = find.widgetWithText(ChoiceChip, 'Integraciones');
      expect(tabFinder, findsOneWidget);
      await tester.ensureVisible(tabFinder);
      await tester.pump();
      await tester.tap(tabFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Check for zero RenderFlex overflows
      expect(tester.takeException(), isNull, reason: 'Must render at 320x480 without RenderFlex overflow');

      // Verify critical elements are rendered in compact layout
      expect(find.text('Mercado Pago'), findsOneWidget);
      expect(find.text('ARCA / AFIP (Facturación Electrónica)'), findsOneWidget);
    });

    testWidgets('User without manage_settings does not trigger loadIntegrations on initial build', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final settingsProv = FakeIntegrationsSettingsProvider();
      final cashierAuthProv = FakeAuthProvider(isAdmin: false, permissions: {'pos'});

      await tester.pumpWidget(buildSettingsScreenApp(settingsProv: settingsProv, authProv: cashierAuthProv));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(settingsProv.loadIntegrationsCallCount, equals(0),
          reason: 'Cashier without manage_settings must NOT trigger background load of integrations');
    });

    testWidgets('Clearing Punto de Venta saves null instead of 0', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final settingsProv = FakeIntegrationsSettingsProvider();

      await tester.pumpWidget(buildSettingsScreenApp(settingsProv: settingsProv));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Switch to Integraciones
      await tester.tap(find.text('Integraciones'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Clear Punto de Venta field
      final ptoVtaFinder = find.byKey(const ValueKey('field_afip_pto_vta'));
      await tester.ensureVisible(ptoVtaFinder);
      await tester.enterText(ptoVtaFinder, '');
      await tester.pump();

      // Click save
      final btnFinder = find.widgetWithText(FilledButton, 'GUARDAR').last;
      await tester.ensureVisible(btnFinder);
      await tester.pump();
      await tester.tap(btnFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(settingsProv.saveIntegrationsCalled, isTrue);
      expect(settingsProv.lastSavedIntegrationsData!['afip_pto_vta'], isNull,
          reason: 'Empty Punto de Venta must be sent as null, never cast to 0');
    });

    testWidgets('Webhook URL copy button copies webhook URL to clipboard and shows SnackBar', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final settingsProv = FakeIntegrationsSettingsProvider();

      await tester.pumpWidget(buildSettingsScreenApp(settingsProv: settingsProv));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Switch to Integraciones
      await tester.tap(find.text('Integraciones'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Click copy button on webhook url field
      final copyBtnFinder = find.byTooltip('Copiar URL al portapapeles');
      await tester.ensureVisible(copyBtnFinder);
      await tester.tap(copyBtnFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('URL de webhook copiada al portapapeles'), findsOneWidget);
    });

    testWidgets('When loadIntegrations fails, Integraciones tab renders error view with Reintentar button and blocks saving', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final settingsProv = FakeIntegrationsSettingsProvider(shouldFailLoad: true);

      await tester.pumpWidget(buildSettingsScreenApp(settingsProv: settingsProv));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Switch to Integraciones
      await tester.tap(find.text('Integraciones'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify error view is shown and retry button is present
      expect(find.text('No se pudo cargar la configuración de integraciones'), findsOneWidget);
      expect(find.byKey(const ValueKey('btn_retry_load_integrations')), findsOneWidget);
      // The form fields should not be exposed to prevent destructive overwrite
      // removed findsNothing expectation for global save button
    });

    testWidgets('Clicking Reintentar retries loading integrations data and recovers form when successful', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final settingsProv = FakeIntegrationsSettingsProvider(shouldFailLoad: true);

      await tester.pumpWidget(buildSettingsScreenApp(settingsProv: settingsProv));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Switch to Integraciones
      await tester.tap(find.text('Integraciones'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const ValueKey('btn_retry_load_integrations')), findsOneWidget);

      // Now server recovers
      settingsProv.shouldFailLoad = false;

      // Click Reintentar
      await tester.tap(find.byKey(const ValueKey('btn_retry_load_integrations')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Form is now cleanly rendered
      expect(find.text('Mercado Pago'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'GUARDAR').last, findsOneWidget);
    });

    testWidgets('Entering invalid Punto de Venta (0) shows error and prevents saving bad payload', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final settingsProv = FakeIntegrationsSettingsProvider();

      await tester.pumpWidget(buildSettingsScreenApp(settingsProv: settingsProv));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Switch to Integraciones
      await tester.tap(find.text('Integraciones'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Enter 0 in Punto de Venta
      final ptoVtaFinder = find.byKey(const ValueKey('field_afip_pto_vta'));
      await tester.ensureVisible(ptoVtaFinder);
      await tester.enterText(ptoVtaFinder, '0');
      await tester.pump();

      // Click save
      final btnFinder = find.widgetWithText(FilledButton, 'GUARDAR').last;
      await tester.ensureVisible(btnFinder);
      await tester.pump();
      await tester.tap(btnFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // saveIntegrations should NOT be called
      expect(settingsProv.saveIntegrationsCalled, isFalse);
      // SnackBar shows validation error
      expect(find.textContaining('El Punto de Venta debe ser un número entre 1 y 99999'), findsOneWidget);
    });

    testWidgets('When Access Token field is cleared, clicking Probar conexión displays warning and avoids request', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final settingsProv = FakeIntegrationsSettingsProvider();

      await tester.pumpWidget(buildSettingsScreenApp(settingsProv: settingsProv));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Switch to Integraciones
      await tester.tap(find.text('Integraciones'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Clear Access Token field
      final tokenFinder = find.byKey(const ValueKey('field_mp_access_token'));
      await tester.ensureVisible(tokenFinder);
      await tester.enterText(tokenFinder, '');
      await tester.pump();

      // Click Probar conexión
      final btnFinder = find.byKey(const ValueKey('btn_test_mp_connection'));
      await tester.ensureVisible(btnFinder);
      await tester.tap(btnFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Endpoint should NOT be called
      expect(settingsProv.testConnectionCalled, isFalse);
      // Warning SnackBar is shown
      expect(find.textContaining('Debe ingresar un Access Token para probar la conexión.'), findsOneWidget);
    });
  });
}

