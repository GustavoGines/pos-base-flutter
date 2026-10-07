import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import 'package:frontend_desktop/core/services/license_heartbeat_service.dart';
import 'package:frontend_desktop/features/auth/presentation/providers/auth_provider.dart';
import 'package:frontend_desktop/features/reports/presentation/providers/inventory_alerts_provider.dart';
import 'package:frontend_desktop/features/settings/data/datasources/settings_remote_datasource.dart';
import 'package:frontend_desktop/features/settings/data/models/business_settings_model.dart';
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
  @override
  Map<String, dynamic>? get currentUser => {'id': 1, 'name': 'Admin Test', 'role': 'admin'};
  @override
  bool get isAdmin => true;
  @override
  bool hasPermission(String permission) => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSettingsProvider extends ChangeNotifier implements SettingsProvider {
  final BusinessSettings? _settings;
  final bool _isLoading;
  final String? _errorMessage = null;
  bool uploadLogoCalled = false;
  String? lastUploadedPath;
  List<int>? lastUploadedBytes;
  String? lastUploadedFilename;
  bool saveSettingsCalled = false;

  FakeSettingsProvider({BusinessSettings? settings, bool isLoading = false})
      : _settings = settings,
        _isLoading = isLoading;

  @override
  BusinessSettings? get settings => _settings;
  @override
  bool get isLoading => _isLoading;
  @override
  String? get errorMessage => _errorMessage;
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
  Future<bool> saveSettings(Map<String, dynamic> data) async {
    saveSettingsCalled = true;
    return true;
  }

  @override
  Future<bool> uploadLogo(String filePath, {List<int>? bytes, String? filename}) async {
    uploadLogoCalled = true;
    lastUploadedPath = filePath;
    lastUploadedBytes = bytes;
    lastUploadedFilename = filename;
    return true;
  }

  @override
  Future<void> loadSettings({bool isSilent = false}) async {}

  @override
  Future<Map<String, dynamic>?> loadIntegrations({bool isSilent = false}) async => null;

  @override
  Future<bool> saveIntegrations(Map<String, dynamic> data) async => true;

  @override
  Future<Map<String, dynamic>> testMercadoPagoConnection({String? mpAccessToken}) async =>
      {'success': true, 'message': 'Conexión exitosa'};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'pos_terminal_id': 'caja-test',
      'pos_api': 'http://pos-backend.test/api',
      'backend_install_path': 'C:\\laragon\\www\\Sistema_POS\\pos-backend',
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

  group('Phase 2 Logo: Entity & Model Tests', () {
    test('BusinessSettings entity properly calculates effectiveLogoUrl', () {
      // 1. Logo URL is directly present
      const settingsWithUrl = BusinessSettings(
        logoPath: 'logos/logo_1.png',
        logoUrl: 'http://pos-backend.test/storage/logos/logo_1.png',
      );
      expect(settingsWithUrl.effectiveLogoUrl, 'http://pos-backend.test/storage/logos/logo_1.png');

      // 2. LogoPath is a full http URL
      const settingsWithHttpPath = BusinessSettings(
        logoPath: 'http://localhost:8000/storage/logos/logo_2.png',
      );
      expect(settingsWithHttpPath.effectiveLogoUrl, 'http://localhost:8000/storage/logos/logo_2.png');

      // 3. Relative path without logoUrl -> resolves to valid absolute storage URL
      const settingsWithRelativeOnly = BusinessSettings(
        logoPath: 'logos/logo_relative.png',
      );
      expect(settingsWithRelativeOnly.effectiveLogoUrl, contains('/storage/logos/logo_relative.png'));

      // 4. No logo at all -> null
      const settingsNoLogo = BusinessSettings();
      expect(settingsNoLogo.effectiveLogoUrl, isNull);
    });

    test('BusinessSettingsModel serializes and deserializes logoPath and logoUrl', () {
      final jsonMap = {
        'company_name': 'Mi Negocio Test',
        'logo_path': 'logos/negocio_logo.png',
        'logo_url': 'http://pos-backend.test/storage/logos/negocio_logo.png',
        'custom_price_tiers': <Map<String, dynamic>>[],
        'license_plan_type': 'premium',
      };

      final model = BusinessSettingsModel.fromJson(jsonMap);
      expect(model.logoPath, 'logos/negocio_logo.png');
      expect(model.logoUrl, 'http://pos-backend.test/storage/logos/negocio_logo.png');
      expect(model.effectiveLogoUrl, 'http://pos-backend.test/storage/logos/negocio_logo.png');

      final serialized = model.toJson();
      expect(serialized['logo_path'], 'logos/negocio_logo.png');
      // logo_url is read-only and deliberately excluded from payload sent to backend
      expect(serialized.containsKey('logo_url'), false);
    });

    test('BusinessSettings copyWith properly updates fields and preserves existing logo', () {
      const original = BusinessSettings(
        companyName: 'Original Name',
        logoPath: 'business/logo_1.png',
        logoUrl: 'http://pos-backend.test/storage/business/logo_1.png',
      );

      final updated = original.copyWith(companyName: 'Updated Name');
      expect(updated.companyName, 'Updated Name');
      expect(updated.logoPath, 'business/logo_1.png');
      expect(updated.logoUrl, 'http://pos-backend.test/storage/business/logo_1.png');
      expect(updated.effectiveLogoUrl, 'http://pos-backend.test/storage/business/logo_1.png');
    });

    test('BusinessSettingsModel.fromJson resolves logoUrl when only logo_path is present (as returned by PUT /settings)', () {
      final jsonMap = {
        'company_name': 'Negocio Sin LogoUrl Explícito',
        'logo_path': 'business/logo_actualizado.png',
      };

      final model = BusinessSettingsModel.fromJson(jsonMap);
      expect(model.logoPath, 'business/logo_actualizado.png');
      expect(model.logoUrl, isNotNull);
      expect(model.logoUrl, contains('/storage/business/logo_actualizado.png'));
      expect(model.effectiveLogoUrl, contains('/storage/business/logo_actualizado.png'));
    });
  });

  group('Phase 2 Logo: SettingsRemoteDataSourceImpl Tests', () {
    test('uploadLogo sends multipart POST to /settings/logo with "logo" field', () async {
      String? capturedMethod;
      String? capturedPath;
      String? capturedContentType;
      String? capturedBody;

      final mockClient = MockClient((request) async {
        capturedMethod = request.method;
        capturedPath = request.url.path;
        capturedContentType = request.headers['content-type'];
        capturedBody = latin1.decode(request.bodyBytes);

        return http.Response(
          jsonEncode({
            'message': 'Logotipo subido correctamente',
            'logo_path': 'logos/empresa_123.png',
            'logo_url': 'http://pos-backend.test/storage/logos/empresa_123.png',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final dataSource = SettingsRemoteDataSourceImpl(
        baseUrl: 'http://pos-backend.test/api',
        client: mockClient,
      );

      final dummyBytes = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]); // PNG magic bytes
      final result = await dataSource.uploadLogo(
        'my_logo.png',
        bytes: dummyBytes,
        filename: 'my_logo.png',
      );

      expect(capturedMethod, 'POST');
      expect(capturedPath, '/api/settings/logo');
      expect(capturedContentType, contains('multipart/form-data'));
      expect(capturedBody, contains('name="logo"'));
      expect(capturedBody, contains('filename="my_logo.png"'));
      expect(result, 'http://pos-backend.test/storage/logos/empresa_123.png');
    });

    test('uploadLogo throws Exception when server returns non-200 status', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'message': 'Error interno'}),
          500,
          headers: {'content-type': 'application/json'},
        );
      });

      final dataSource = SettingsRemoteDataSourceImpl(
        baseUrl: 'http://pos-backend.test/api',
        client: mockClient,
      );

      expect(
        () => dataSource.uploadLogo('logo.png', bytes: [1, 2, 3], filename: 'logo.png'),
        throwsA(isA<Exception>()),
      );
    });

    test('uploadLogo parses 422 Laravel validation error message properly from JSON', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'message': 'The logo field must not be greater than 2048 kilobytes.',
            'errors': {
              'logo': ['The logo field must not be greater than 2048 kilobytes.']
            }
          }),
          422,
          headers: {'content-type': 'application/json'},
        );
      });

      final dataSource = SettingsRemoteDataSourceImpl(
        baseUrl: 'http://pos-backend.test/api',
        client: mockClient,
      );

      expect(
        () => dataSource.uploadLogo('huge_logo.png', bytes: [1, 2, 3], filename: 'huge_logo.png'),
        throwsA(predicate((e) => e.toString().contains('The logo field must not be greater than 2048 kilobytes.'))),
      );
    });

    test('uploadLogo sets MediaType header in multipart part', () async {
      String? capturedContentType;
      String? capturedBody;

      final mockClient = MockClient((request) async {
        capturedContentType = request.headers['content-type'];
        capturedBody = latin1.decode(request.bodyBytes);

        return http.Response(
          jsonEncode({
            'message': 'OK',
            'logo_path': 'logos/test.webp',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final dataSource = SettingsRemoteDataSourceImpl(
        baseUrl: 'http://pos-backend.test/api',
        client: mockClient,
      );

      await dataSource.uploadLogo('logo.webp', bytes: [1, 2, 3], filename: 'logo.webp');

      expect(capturedContentType, contains('multipart/form-data'));
      expect(capturedBody, contains('content-type: image/webp'));
    });
  });

  group('Phase 2 Logo: SettingsScreen Widget Tests', () {
    Widget buildSettingsScreenApp({required FakeSettingsProvider settingsProv}) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>.value(value: settingsProv),
          ChangeNotifierProvider<LocalTerminalProvider>.value(value: FakeLocalTerminalProvider()),
          ChangeNotifierProvider<AuthProvider>.value(value: FakeAuthProvider()),
          ChangeNotifierProvider<InventoryAlertsProvider>.value(value: FakeInventoryAlertsProvider()),
        ],
        child: const MaterialApp(
          home: SettingsScreen(),
        ),
      );
    }

    testWidgets('General section displays 130x130 logo container and placeholder UI', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final settingsProv = FakeSettingsProvider(
        settings: const BusinessSettings(
          companyName: 'Supermercado Test',
          address: 'Calle Falsa 123',
        ),
      );

      await tester.pumpWidget(buildSettingsScreenApp(settingsProv: settingsProv));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // SettingsScreen opens in subscription section by default -> switch to General
      await tester.tap(find.text('General'));
      await tester.pumpAndSettle();

      // Check Section Header
      expect(find.text('Datos del Negocio'), findsOneWidget);
      expect(find.text('Logotipo del Negocio'), findsOneWidget);

      // Verify exact 130x130 container
      final logoContainerFinder = find.byKey(const ValueKey('settings_logo_container'));
      expect(logoContainerFinder, findsOneWidget);
      final size = tester.getSize(logoContainerFinder);
      expect(size.width, 130.0);
      expect(size.height, 130.0);

      // Placeholder content
      expect(find.text('Subir Logo'), findsOneWidget);
      expect(find.text('130x130'), findsOneWidget);
      expect(find.text('Seleccionar Logo'), findsOneWidget);
    });

    testWidgets('General section renders existing logo preview and "Cambiar Logo" button', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final settingsProv = FakeSettingsProvider(
        settings: const BusinessSettings(
          companyName: 'Supermercado Test',
          logoUrl: 'http://pos-backend.test/storage/logos/existing_logo.png',
        ),
      );

      await tester.pumpWidget(buildSettingsScreenApp(settingsProv: settingsProv));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Navigate to General
      await tester.tap(find.text('General'));
      await tester.pumpAndSettle();

      // 130x130 container is present
      expect(find.byKey(const ValueKey('settings_logo_container')), findsOneWidget);

      // Button says "Cambiar Logo" instead of "Seleccionar Logo"
      expect(find.text('Cambiar Logo'), findsOneWidget);
      expect(find.text('Seleccionar Logo'), findsNothing);
    });

    testWidgets('GUARDAR button is enabled when idle', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final settingsProv = FakeSettingsProvider(
        settings: const BusinessSettings(companyName: 'Supermercado Test'),
      );

      await tester.pumpWidget(buildSettingsScreenApp(settingsProv: settingsProv));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final saveButton = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'GUARDAR'));
      expect(saveButton.onPressed, isNotNull);
    });
  });
}
