import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
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
import 'package:frontend_desktop/features/settings/data/repositories/settings_repository_impl.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/settings/domain/usecases/get_settings_usecase.dart';
import 'package:frontend_desktop/features/settings/domain/usecases/update_settings_usecase.dart';
import 'package:frontend_desktop/features/settings/presentation/pages/settings_screen.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';

// --- FAKE FILE PICKER ---
class MockFilePicker extends FilePicker {
  FilePickerResult? nextResult;
  bool pickFilesCalled = false;
  FileType? lastType;
  List<String>? lastAllowedExtensions;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    pickFilesCalled = true;
    lastType = type;
    lastAllowedExtensions = allowedExtensions;
    return nextResult;
  }

  @override
  Future<bool?> clearTemporaryFiles() async => true;

  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    bool lockParentWindow = false,
    String? initialDirectory,
  }) async => null;

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async => null;
}

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
  Map<String, dynamic>? get currentUser => {'id': 1, 'name': 'Admin Test', 'role': _isAdmin ? 'admin' : 'cashier'};
  @override
  bool get isAdmin => _isAdmin;
  @override
  bool hasPermission(String permission) => _isAdmin || _permissions.contains(permission);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAfipSettingsProvider extends ChangeNotifier implements SettingsProvider {
  final BusinessSettings? _settings;
  Map<String, dynamic>? _integrationsData;
  final bool _isLoading;
  final bool _isUploadingCertificates;
  String? _errorMessage;

  bool uploadAfipCertificatesCalled = false;
  String? lastUploadedCuit;
  List<int>? lastUploadedCertBytes;
  String? lastUploadedCertFilename;
  List<int>? lastUploadedKeyBytes;
  String? lastUploadedKeyFilename;
  String? lastUploadedPassphrase;
  bool shouldFailUpload = false;
  String failureErrorMessage = 'El par criptográfico no coincide.';

  FakeAfipSettingsProvider({
    BusinessSettings? settings,
    Map<String, dynamic>? integrationsData,
    bool isLoading = false,
    bool isUploadingCertificates = false,
  })  : _settings = settings,
        _isLoading = isLoading,
        _isUploadingCertificates = isUploadingCertificates,
        _integrationsData = integrationsData ??
            {
              'mp_qr_enabled': false,
              'mp_access_token': '',
              'mp_webhook_secret': '',
              'mp_point_device_id': '',
              'mp_webhook_url': '',
              'afip_enabled': true,
              'afip_cuit': '20123456789',
              'afip_pto_vta': 1,
              'afip_environment': 'testing',
              'afip_has_cert': false,
              'afip_has_key': false,
              'afip_cert_expires_at': null,
            };

  @override
  BusinessSettings? get settings => _settings;
  @override
  bool get isLoading => _isLoading;
  @override
  bool get isUploadingCertificates => _isUploadingCertificates;
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
  String get currentApiUrl => 'http://pos-backend.test/api';

  @override
  Map<String, dynamic>? get integrations => _integrationsData;
  @override
  bool get isLoadingIntegrations => false;

  @override
  Future<Map<String, dynamic>?> loadIntegrations({bool isSilent = false}) async => _integrationsData;

  @override
  Future<bool> saveIntegrations(Map<String, dynamic> data) async {
    _integrationsData = {...?_integrationsData, ...data};
    notifyListeners();
    return true;
  }

  @override
  Future<Map<String, dynamic>> testMercadoPagoConnection({String? mpAccessToken}) async =>
      {'success': true, 'message': 'OK'};

  @override
  Future<Map<String, dynamic>> uploadAfipCertificates({
    required String cuit,
    required List<int> certBytes,
    required String certFilename,
    required List<int> keyBytes,
    required String keyFilename,
    String? keyPassphrase,
  }) async {
    uploadAfipCertificatesCalled = true;
    lastUploadedCuit = cuit;
    lastUploadedCertBytes = certBytes;
    lastUploadedCertFilename = certFilename;
    lastUploadedKeyBytes = keyBytes;
    lastUploadedKeyFilename = keyFilename;
    lastUploadedPassphrase = keyPassphrase;

    if (shouldFailUpload) {
      _errorMessage = failureErrorMessage;
      throw Exception(failureErrorMessage);
    }

    _integrationsData = {
      ...?_integrationsData,
      'afip_cuit': cuit,
      'afip_has_cert': true,
      'afip_has_key': true,
      'afip_cert_expires_at': '2028-05-15 12:00:00',
    };
    notifyListeners();

    return {
      'message': 'Certificados de AFIP guardados y validados correctamente.',
      'afip_cuit': cuit,
      'afip_has_cert': true,
      'afip_has_key': true,
      'afip_cert_expires_at': '2028-05-15 12:00:00',
    };
  }

  @override
  Future<bool> saveSettings(Map<String, dynamic> data) async => true;
  @override
  Future<bool> uploadLogo(String filePath, {List<int>? bytes, String? filename}) async => true;
  @override
  Future<void> loadSettings({bool isSilent = false}) async {}
  @override
  void updateBaseUrl(String newUrl) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockFilePicker mockPicker;

  setUp(() {
    mockPicker = MockFilePicker();
    FilePicker.platform = mockPicker;

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

  group('Phase AFIP Certificates: DataSource & Repository Unit Tests', () {
    test('SettingsRemoteDataSourceImpl.uploadAfipCertificates sends multipart POST with files and fields', () async {
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
            'message': 'Certificados de AFIP guardados y validados correctamente.',
            'afip_cuit': '20123456789',
            'afip_has_cert': true,
            'afip_has_key': true,
            'afip_cert_expires_at': '2028-05-15 12:00:00',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final dataSource = SettingsRemoteDataSourceImpl(
        baseUrl: 'http://pos-backend.test/api',
        client: mockClient,
      );

      final result = await dataSource.uploadAfipCertificates(
        cuit: '20123456789',
        certBytes: utf8.encode('-----BEGIN CERTIFICATE-----...'),
        certFilename: 'empresa_afip.crt',
        keyBytes: utf8.encode('-----BEGIN RSA PRIVATE KEY-----...'),
        keyFilename: 'empresa_afip.key',
        keyPassphrase: 'test_passphrase',
      );

      expect(capturedMethod, equals('POST'));
      expect(capturedPath, equals('/api/settings/afip/upload-certificates'));
      expect(capturedContentType, contains('multipart/form-data'));
      expect(capturedBody, contains('name="cuit"'));
      expect(capturedBody, contains('20123456789'));
      expect(capturedBody, contains('name="key_passphrase"'));
      expect(capturedBody, contains('test_passphrase'));
      expect(capturedBody, contains('name="cert_file"'));
      expect(capturedBody, contains('filename="empresa_afip.crt"'));
      expect(capturedBody, contains('name="key_file"'));
      expect(capturedBody, contains('filename="empresa_afip.key"'));
      expect(result['afip_has_cert'], isTrue);
      expect(result['afip_has_key'], isTrue);
      expect(result['afip_cert_expires_at'], equals('2028-05-15 12:00:00'));
    });

    test('SettingsRemoteDataSourceImpl.uploadAfipCertificates parses 422 validation error properly', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'message': 'El par criptográfico no coincide: el certificado no corresponde a la clave privada.',
            'error_code': 'CERT_KEY_MISMATCH',
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
        () => dataSource.uploadAfipCertificates(
          cuit: '20123456789',
          certBytes: [1, 2, 3],
          certFilename: 'cert.crt',
          keyBytes: [4, 5, 6],
          keyFilename: 'key.key',
        ),
        throwsA(predicate((e) => e.toString().contains('El par criptográfico no coincide'))),
      );
    });

    test('SettingsRepositoryImpl forwards uploadAfipCertificates to remoteDataSource', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'message': 'OK',
            'afip_has_cert': true,
            'afip_has_key': true,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final dataSource = SettingsRemoteDataSourceImpl(
        baseUrl: 'http://pos-backend.test/api',
        client: mockClient,
      );
      final repo = SettingsRepositoryImpl(remoteDataSource: dataSource);

      final res = await repo.uploadAfipCertificates(
        cuit: '20123456789',
        certBytes: [1],
        certFilename: 'c.crt',
        keyBytes: [2],
        keyFilename: 'k.key',
      );

      expect(res['afip_has_cert'], isTrue);
    });

    test('SettingsProvider.uploadAfipCertificates updates integrations and resets loading states', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/settings/afip/upload-certificates')) {
          return http.Response(
            jsonEncode({
              'message': 'Certificados guardados.',
              'afip_cuit': '20123456789',
              'afip_has_cert': true,
              'afip_has_key': true,
              'afip_cert_expires_at': '2028-05-15 12:00:00',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path.contains('/settings/integrations')) {
          return http.Response(
            jsonEncode({
              'afip_enabled': true,
              'afip_cuit': '20123456789',
              'afip_has_cert': true,
              'afip_has_key': true,
              'afip_cert_expires_at': '2028-05-15 12:00:00',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(jsonEncode({}), 200, headers: {'content-type': 'application/json'});
      });

      final dataSource = SettingsRemoteDataSourceImpl(baseUrl: 'http://pos-backend.test/api', client: mockClient);
      final repo = SettingsRepositoryImpl(remoteDataSource: dataSource);
      final provider = SettingsProvider(
        getSettingsUseCase: GetSettingsUseCase(repo),
        updateSettingsUseCase: UpdateSettingsUseCase(repo),
      );

      expect(provider.isUploadingCertificates, isFalse);
      final result = await provider.uploadAfipCertificates(
        cuit: '20123456789',
        certBytes: [1, 2, 3],
        certFilename: 'cert.crt',
        keyBytes: [4, 5, 6],
        keyFilename: 'key.key',
      );

      expect(provider.isUploadingCertificates, isFalse);
      expect(provider.isLoading, isFalse);
      expect(result['afip_has_cert'], isTrue);
      expect(provider.integrations?['afip_has_cert'], isTrue);
    });
  });

  group('Phase AFIP Certificates: SettingsScreen Widget Tests', () {
    Widget buildSettingsScreenApp({required FakeAfipSettingsProvider settingsProv, AuthProvider? authProv}) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>.value(value: settingsProv),
          ChangeNotifierProvider<LocalTerminalProvider>.value(value: FakeLocalTerminalProvider()),
          ChangeNotifierProvider<AuthProvider>.value(value: authProv ?? FakeAuthProvider(isAdmin: true)),
          ChangeNotifierProvider<InventoryAlertsProvider>.value(value: FakeInventoryAlertsProvider()),
        ],
        child: const MaterialApp(
          home: SettingsScreen(),
        ),
      );
    }

    testWidgets('Integraciones tab renders AFIP certificate pick buttons and upload button', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final settingsProv = FakeAfipSettingsProvider();

      await tester.pumpWidget(buildSettingsScreenApp(settingsProv: settingsProv));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Switch to Integraciones
      await tester.tap(find.text('Integraciones'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify certificate upload UI elements exist
      expect(find.byKey(const ValueKey('btn_pick_afip_cert')), findsOneWidget);
      expect(find.byKey(const ValueKey('btn_pick_afip_key')), findsOneWidget);
      expect(find.byKey(const ValueKey('field_afip_key_passphrase')), findsOneWidget);
      expect(find.byKey(const ValueKey('btn_upload_afip_certs')), findsOneWidget);

      // Verify initial placeholders
      expect(find.text('Sin archivo seleccionado'), findsNWidgets(2));
      expect(find.text('Certificado AFIP (.crt)'), findsOneWidget);
      expect(find.text('Clave Privada (.key)'), findsOneWidget);
    });

    testWidgets('Clicking upload without CUIT displays warning SnackBar and avoids provider call', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final settingsProv = FakeAfipSettingsProvider(
        integrationsData: {
          'afip_enabled': true,
          'afip_cuit': '',
          'afip_pto_vta': 1,
          'afip_environment': 'testing',
          'afip_has_cert': false,
          'afip_has_key': false,
        },
      );

      await tester.pumpWidget(buildSettingsScreenApp(settingsProv: settingsProv));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Switch to Integraciones
      await tester.tap(find.text('Integraciones'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Clear CUIT field
      await tester.enterText(find.byKey(const ValueKey('field_afip_cuit')), '');
      await tester.pump();

      // Tap Upload button
      final uploadBtnFinder = find.byKey(const ValueKey('btn_upload_afip_certs'));
      await tester.ensureVisible(uploadBtnFinder);
      await tester.tap(uploadBtnFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Expect validation warning
      expect(find.text('Debe ingresar un CUIT comercial válido.'), findsOneWidget);
      expect(settingsProv.uploadAfipCertificatesCalled, isFalse);
    });

    testWidgets('Clicking upload without selecting files displays warning SnackBar and avoids provider call', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final settingsProv = FakeAfipSettingsProvider();

      await tester.pumpWidget(buildSettingsScreenApp(settingsProv: settingsProv));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Switch to Integraciones
      await tester.tap(find.text('Integraciones'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Tap Upload button without picking files
      final uploadBtnFinder = find.byKey(const ValueKey('btn_upload_afip_certs'));
      await tester.ensureVisible(uploadBtnFinder);
      await tester.tap(uploadBtnFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.text('Debe seleccionar tanto el certificado (.crt) como la clave privada (.key).'),
        findsOneWidget,
      );
      expect(settingsProv.uploadAfipCertificatesCalled, isFalse);
    });

    testWidgets('Selecting files updates file names and allows clearing them', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final settingsProv = FakeAfipSettingsProvider();

      await tester.pumpWidget(buildSettingsScreenApp(settingsProv: settingsProv));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Switch to Integraciones
      await tester.tap(find.text('Integraciones'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Pick cert file
      mockPicker.nextResult = FilePickerResult([
        PlatformFile(
          name: 'empresa_afip.crt',
          size: 1200,
          bytes: Uint8List.fromList([1, 2, 3]),
        ),
      ]);
      await tester.ensureVisible(find.byKey(const ValueKey('btn_pick_afip_cert')));
      await tester.tap(find.byKey(const ValueKey('btn_pick_afip_cert')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(mockPicker.lastAllowedExtensions, equals(['crt']));
      expect(find.text('empresa_afip.crt'), findsOneWidget);

      // Pick key file
      mockPicker.nextResult = FilePickerResult([
        PlatformFile(
          name: 'empresa_afip.key',
          size: 1600,
          bytes: Uint8List.fromList([4, 5, 6]),
        ),
      ]);
      await tester.ensureVisible(find.byKey(const ValueKey('btn_pick_afip_key')));
      await tester.tap(find.byKey(const ValueKey('btn_pick_afip_key')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(mockPicker.lastAllowedExtensions, equals(['key']));
      expect(find.text('empresa_afip.key'), findsOneWidget);

      // Clear cert file
      final clearCertFinder = find.byTooltip('Quitar archivo').first;
      await tester.tap(clearCertFinder);
      await tester.pump();

      expect(find.text('empresa_afip.crt'), findsNothing);
      expect(find.text('Sin archivo seleccionado'), findsOneWidget);
      expect(find.text('empresa_afip.key'), findsOneWidget);
    });

    testWidgets('Successful certificate upload sends payload, updates UI status chips, and shows success SnackBar', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final settingsProv = FakeAfipSettingsProvider();

      await tester.pumpWidget(buildSettingsScreenApp(settingsProv: settingsProv));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Switch to Integraciones
      await tester.tap(find.text('Integraciones'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Initially, chips show Not Installed
      expect(find.text('Certificado (.crt) No Instalado'), findsOneWidget);
      expect(find.text('Clave Privada (.key) No Instalada'), findsOneWidget);

      // Pick cert file
      mockPicker.nextResult = FilePickerResult([
        PlatformFile(
          name: 'mi_factura.crt',
          size: 1024,
          bytes: Uint8List.fromList([10, 20, 30]),
        ),
      ]);
      await tester.ensureVisible(find.byKey(const ValueKey('btn_pick_afip_cert')));
      await tester.tap(find.byKey(const ValueKey('btn_pick_afip_cert')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Pick key file
      mockPicker.nextResult = FilePickerResult([
        PlatformFile(
          name: 'mi_clave.key',
          size: 2048,
          bytes: Uint8List.fromList([40, 50, 60]),
        ),
      ]);
      await tester.ensureVisible(find.byKey(const ValueKey('btn_pick_afip_key')));
      await tester.tap(find.byKey(const ValueKey('btn_pick_afip_key')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Enter optional passphrase
      await tester.ensureVisible(find.byKey(const ValueKey('field_afip_key_passphrase')));
      await tester.enterText(find.byKey(const ValueKey('field_afip_key_passphrase')), 'secret123');
      await tester.pump();

      // Tap Upload
      final uploadBtnFinder = find.byKey(const ValueKey('btn_upload_afip_certs'));
      await tester.ensureVisible(uploadBtnFinder);
      await tester.tap(uploadBtnFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify provider was called with exact data
      expect(settingsProv.uploadAfipCertificatesCalled, isTrue);
      expect(settingsProv.lastUploadedCuit, equals('20123456789'));
      expect(settingsProv.lastUploadedCertFilename, equals('mi_factura.crt'));
      expect(settingsProv.lastUploadedCertBytes, equals([10, 20, 30]));
      expect(settingsProv.lastUploadedKeyFilename, equals('mi_clave.key'));
      expect(settingsProv.lastUploadedKeyBytes, equals([40, 50, 60]));
      expect(settingsProv.lastUploadedPassphrase, equals('secret123'));

      // Verify UI updated: Chips now show Installed
      expect(find.text('Certificado (.crt) Instalado'), findsOneWidget);
      expect(find.text('Clave Privada (.key) Instalada'), findsOneWidget);
      expect(find.text('Vence: 2028-05-15 12:00:00'), findsOneWidget);

      // Verify file selection and passphrase were reset
      expect(find.text('Sin archivo seleccionado'), findsNWidgets(2));
      final passphraseField = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const ValueKey('field_afip_key_passphrase')),
          matching: find.byType(TextField),
        ),
      );
      expect(passphraseField.controller?.text, isEmpty);

      // Verify success feedback
      expect(find.text('Certificados de AFIP guardados y validados correctamente.'), findsOneWidget);
    });

    testWidgets('Failed certificate upload shows error SnackBar and preserves file selection', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final settingsProv = FakeAfipSettingsProvider();
      settingsProv.shouldFailUpload = true;
      settingsProv.failureErrorMessage = 'El par criptográfico no coincide: el certificado no corresponde a la clave privada.';

      await tester.pumpWidget(buildSettingsScreenApp(settingsProv: settingsProv));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Switch to Integraciones
      await tester.tap(find.text('Integraciones'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Pick cert file
      mockPicker.nextResult = FilePickerResult([
        PlatformFile(
          name: 'bad_cert.crt',
          size: 1024,
          bytes: Uint8List.fromList([1, 1, 1]),
        ),
      ]);
      await tester.ensureVisible(find.byKey(const ValueKey('btn_pick_afip_cert')));
      await tester.tap(find.byKey(const ValueKey('btn_pick_afip_cert')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Pick key file
      mockPicker.nextResult = FilePickerResult([
        PlatformFile(
          name: 'bad_key.key',
          size: 1024,
          bytes: Uint8List.fromList([2, 2, 2]),
        ),
      ]);
      await tester.ensureVisible(find.byKey(const ValueKey('btn_pick_afip_key')));
      await tester.tap(find.byKey(const ValueKey('btn_pick_afip_key')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Tap Upload
      final uploadBtnFinder = find.byKey(const ValueKey('btn_upload_afip_certs'));
      await tester.ensureVisible(uploadBtnFinder);
      await tester.tap(uploadBtnFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify error feedback
      expect(
        find.text('El par criptográfico no coincide: el certificado no corresponde a la clave privada.'),
        findsOneWidget,
      );

      // Verify files remain selected so user can correct them
      expect(find.text('bad_cert.crt'), findsOneWidget);
      expect(find.text('bad_key.key'), findsOneWidget);
    });
  });
}
