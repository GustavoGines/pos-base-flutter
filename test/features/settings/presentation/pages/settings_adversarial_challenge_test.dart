
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend_desktop/core/constants/app_permissions.dart';
import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import 'package:frontend_desktop/core/services/license_heartbeat_service.dart';
import 'package:frontend_desktop/features/auth/presentation/providers/auth_provider.dart';
import 'package:frontend_desktop/features/cash_register/domain/entities/cash_register.dart';
import 'package:frontend_desktop/features/cash_register/domain/entities/cash_register_shift.dart';
import 'package:frontend_desktop/features/cash_register/presentation/providers/cash_register_provider.dart';
import 'package:frontend_desktop/features/reports/presentation/providers/inventory_alerts_provider.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/settings/presentation/pages/settings_screen.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';

// --- FAKE FILE PICKER ---
class AdversarialMockFilePicker extends FilePicker {
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
  Future<String?> getDirectoryPath({String? dialogTitle, bool lockParentWindow = false, String? initialDirectory}) async => null;
  @override
  Future<String?> saveFile({String? dialogTitle, String? fileName, String? initialDirectory, FileType type = FileType.any, List<String>? allowedExtensions, Uint8List? bytes, bool lockParentWindow = false}) async => null;
}

// --- FAKE PROVIDERS ---
class FakeAdversarialAuthProvider extends ChangeNotifier implements AuthProvider {
  final bool _isAdmin;
  final Set<String> _permissions;

  FakeAdversarialAuthProvider({bool isAdmin = true, Set<String>? permissions})
      : _isAdmin = isAdmin,
        _permissions = permissions ?? {AppPermissions.manageSettings};

  @override
  Map<String, dynamic>? get currentUser => {'id': 1, 'name': 'Adversarial Admin', 'role': _isAdmin ? 'admin' : 'cashier'};
  @override
  bool get isAdmin => _isAdmin;
  @override
  bool hasPermission(String permission) => _isAdmin || _permissions.contains(permission);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAdversarialLocalTerminalProvider extends ChangeNotifier implements LocalTerminalProvider {
  @override
  String get printerFormat => 'thermal_80';
  @override
  String get printerConnection => 'none';
  @override
  String get pdfPaperSize => 'a4';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAdversarialInventoryAlertsProvider extends ChangeNotifier implements InventoryAlertsProvider {
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

class FakeAdversarialCashRegisterProvider extends ChangeNotifier implements CashRegisterProvider {
  @override
  List<CashRegister>? get availableRegisters => [];
  @override
  CashRegisterShift? get currentShift => null;
  @override
  List<CashRegisterShift> get shiftsHistory => [];
  @override
  bool get isLoading => false;
  @override
  String? get errorMessage => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAdversarialSettingsProvider extends ChangeNotifier implements SettingsProvider {
  BusinessSettings? _settings;
  Map<String, dynamic>? _integrationsData;
  bool _isLoading = false;
  bool _isLoadingIntegrations = false;
  String? _errorMessage;

  bool uploadAfipCertificatesCalled = false;
  String? lastUploadedCuit;
  List<int>? lastUploadedCertBytes;
  String? lastUploadedCertFilename;
  List<int>? lastUploadedKeyBytes;
  String? lastUploadedKeyFilename;
  String? lastUploadedPassphrase;

  bool saveIntegrationsCalled = false;
  Map<String, dynamic>? lastSavedIntegrationsData;

  bool testMercadoPagoConnectionCalled = false;
  String? lastTestedMpToken;

  FakeAdversarialSettingsProvider({
    BusinessSettings? settings,
    Map<String, dynamic>? integrationsData,
  })  : _settings = settings ??
            const BusinessSettings(
              
              companyName: 'Challenger POS Megastore',
              address: 'Av. Corrientes 1234, CABA',
              phone: '+54 11 5555-5555',
              taxId: '30-12345678-9',
              receiptFooterMessage: '¡Gracias por su compra!',
              globalCardPercentage: 15.0,
              globalWholesalePercentage: -15.0,
              enableAdvancedPriceTiers: true,
              customPriceTiers: [
                {'name': 'Gremio', 'percentage': -20.0},
                {'name': 'VIP', 'percentage': -10.0},
              ],
              licensePlanType: 'premium',
              licenseStatus: 'LIC-CHALLENGER-2026',
              isLifetime: true,
              features: FeatureFlags(
                fastPos: true,
                multiplePrices: true,
                multiCaja: true,
                advancedReports: true,
                predictiveAlerts: true,
                mobileApp: true,
              ),
              licenseExpiresAt: null,
              lastLicenseCheck: '2026-10-07 18:00:00',
            ),
        _integrationsData = integrationsData ??
            {
              'mp_qr_enabled': true,
              'mp_point_device_id': 'POINT_ADV_99',
              'mp_access_token': 'APP_USR-****9999',
              'mp_webhook_secret': 'whsec_****1234',
              'mp_has_access_token': true,
              'mp_has_webhook_secret': true,
              'mp_webhook_url': 'https://pos-backend.test/api/webhooks/mercadopago',
              'afip_enabled': true,
              'afip_cuit': '20123456789',
              'afip_pto_vta': 1,
              'afip_environment': 'testing',
              'afip_has_cert': true,
              'afip_has_key': true,
              'afip_cert_expires_at': '2028-05-15 12:00:00',
            };

  @override
  BusinessSettings? get settings => _settings;
  @override
  bool get isLoading => _isLoading;
  @override
  String? get errorMessage => _errorMessage;
  @override
  String get currentPlan => _settings?.licensePlanType ?? 'premium';
  @override
  FeatureFlags get features => _settings?.features ?? const FeatureFlags(fastPos: true, multiplePrices: true);
  @override
  bool hasFeature(String featureName) => _settings?.hasFeature(featureName) ?? true;
  @override
  bool get isLicenseActive => true;
  @override
  List<String> get allowedAddons => _settings?.licenseFeatures ?? [];
  @override
  LicenseSecurityStatus get securityStatus => LicenseSecurityStatus.ok;
  @override
  String get currentApiUrl => 'https://pos-backend.test/api';

  @override
  Map<String, dynamic>? get integrations => _integrationsData;
  @override
  bool get isLoadingIntegrations => _isLoadingIntegrations;

  @override
  Future<Map<String, dynamic>?> loadIntegrations({bool isSilent = false}) async {
    return _integrationsData;
  }

  @override
  Future<bool> saveIntegrations(Map<String, dynamic> data) async {
    saveIntegrationsCalled = true;
    lastSavedIntegrationsData = data;
    _integrationsData = {...?_integrationsData, ...data};
    notifyListeners();
    return true;
  }

  @override
  Future<Map<String, dynamic>> testMercadoPagoConnection({String? mpAccessToken}) async {
    testMercadoPagoConnectionCalled = true;
    lastTestedMpToken = mpAccessToken;
    return {
      'success': true,
      'message': 'Conexión con Mercado Pago exitosa.',
      'nickname': 'TIENDA_CHALLENGER',
    };
  }

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

    _integrationsData = {
      ...?_integrationsData,
      'afip_cuit': cuit,
      'afip_has_cert': true,
      'afip_has_key': true,
      'afip_cert_expires_at': '2029-01-01 00:00:00',
    };
    notifyListeners();

    return {
      'message': 'Certificados de AFIP guardados y validados correctamente.',
      'afip_cuit': cuit,
      'afip_has_cert': true,
      'afip_has_key': true,
      'afip_cert_expires_at': '2029-01-01 00:00:00',
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

  late AdversarialMockFilePicker mockPicker;

  final List<Size> testViewports = const [
    Size(320, 480),   // Compact Mobile 320x480
    Size(360, 640),   // Mobile Portrait 360x640
    Size(712, 800),   // Narrow Desktop / Tablet Breakpoint (> 700 threshold)
    Size(1280, 800),  // Standard Desktop / POS 1280x800
    Size(1920, 1080), // Full HD Desktop 1920x1080
  ];

  setUp(() {
    mockPicker = AdversarialMockFilePicker();
    FilePicker.platform = mockPicker;

    SharedPreferences.setMockInitialValues({
      'pos_terminal_id': 'caja-challenger',
      'pos_api': 'https://pos-backend.test/api',
      'backend_install_path': r'C:\laragon\www\Sistema_POS\pos-backend',
      'update_channel': 'stable',
    });
    PackageInfo.setMockInitialValues(
      appName: 'POS Challenger',
      packageName: 'com.example.pos',
      version: '2.0.0',
      buildNumber: '42',
      buildSignature: '',
    );
  });

  Widget createHarnessApp({
    FakeAdversarialSettingsProvider? settingsProv,
    FakeAdversarialAuthProvider? authProv,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsProvider>.value(value: settingsProv ?? FakeAdversarialSettingsProvider()),
        ChangeNotifierProvider<AuthProvider>.value(value: authProv ?? FakeAdversarialAuthProvider()),
        ChangeNotifierProvider<LocalTerminalProvider>.value(value: FakeAdversarialLocalTerminalProvider()),
        ChangeNotifierProvider<InventoryAlertsProvider>.value(value: FakeAdversarialInventoryAlertsProvider()),
        ChangeNotifierProvider<CashRegisterProvider>.value(value: FakeAdversarialCashRegisterProvider()),
      ],
      child: const MaterialApp(
        home: SettingsScreen(),
      ),
    );
  }

  Future<void> navigateToTab(WidgetTester tester, String tabName, {required bool isCompact}) async {
    if (isCompact) {
      final chipFinder = find.widgetWithText(ChoiceChip, tabName);
      expect(chipFinder, findsOneWidget, reason: 'Tab $tabName should exist in compact mode');
      await tester.ensureVisible(chipFinder);
      await tester.pump();
      await tester.tap(chipFinder);
    } else {
      final tabFinder = find.text(tabName);
      expect(tabFinder, findsWidgets, reason: 'Tab $tabName should exist in desktop mode');
      await tester.tap(tabFinder.first);
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
  }

  void assertZeroRenderFlexOverflow(WidgetTester tester, String contextDescription) {
    final exception = tester.takeException();
    if (exception != null) {
      fail('RenderFlex overflow or exception encountered in $contextDescription: $exception');
    }
  }

  group('Quality Gate Iteration 2: Adversarial Multi-Viewport Stress Testing', () {
    for (final viewport in testViewports) {
      final width = viewport.width;
      final height = viewport.height;
      final isCompact = width < 700;

      testWidgets('Viewport ${width.toInt()}x${height.toInt()} renders initial tab (Subscription) with ZERO RenderFlex overflow', (tester) async {
        tester.view.physicalSize = viewport;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(createHarnessApp());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        assertZeroRenderFlexOverflow(tester, 'Initial Subscription at ${width.toInt()}x${height.toInt()}');
        expect(find.text('Suscripción y Licencia'), findsOneWidget);
      });

      testWidgets('Viewport ${width.toInt()}x${height.toInt()} renders Integraciones tab with ZERO RenderFlex overflow', (tester) async {
        tester.view.physicalSize = viewport;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(createHarnessApp());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        await navigateToTab(tester, 'Integraciones', isCompact: isCompact);

        assertZeroRenderFlexOverflow(tester, 'Integraciones tab at ${width.toInt()}x${height.toInt()}');
        expect(find.text('Mercado Pago'), findsOneWidget);
        expect(find.text('ARCA / AFIP (Facturación Electrónica)'), findsOneWidget);
      });

      testWidgets('Viewport ${width.toInt()}x${height.toInt()} renders General tab with ZERO RenderFlex overflow', (tester) async {
        tester.view.physicalSize = viewport;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(createHarnessApp());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        await navigateToTab(tester, 'General', isCompact: isCompact);

        assertZeroRenderFlexOverflow(tester, 'General tab at ${width.toInt()}x${height.toInt()}');
        expect(find.text('Datos del Negocio'), findsOneWidget);
      });

      testWidgets('Viewport ${width.toInt()}x${height.toInt()} renders Precios tab with ZERO RenderFlex overflow', (tester) async {
        tester.view.physicalSize = viewport;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(createHarnessApp());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        await navigateToTab(tester, isCompact ? 'Precios' : 'Precios Globales', isCompact: isCompact);

        assertZeroRenderFlexOverflow(tester, 'Precios tab at ${width.toInt()}x${height.toInt()}');
        expect(find.text('Precios y Factores'), findsOneWidget);
      });

      testWidgets('Viewport ${width.toInt()}x${height.toInt()} renders Red tab with ZERO RenderFlex overflow', (tester) async {
        tester.view.physicalSize = viewport;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(createHarnessApp());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        await navigateToTab(tester, isCompact ? 'Red' : 'Red y Terminales', isCompact: isCompact);

        assertZeroRenderFlexOverflow(tester, 'Red tab at ${width.toInt()}x${height.toInt()}');
      });
    }
  });

  group('Quality Gate Iteration 2: Dynamic Interactions & State Transitions', () {
    // We challenge dynamic interactions at boundary viewports: 320x480 (narrowest mobile), 712x800 (critical breakpoint), and 1280x800 (standard desktop)
    final challengeViewports = const [
      Size(320, 480),
      Size(712, 800),
      Size(1280, 800),
    ];

    for (final viewport in challengeViewports) {
      final width = viewport.width;
      final height = viewport.height;
      final isCompact = width < 700;

      testWidgets('Dynamic interaction: Expanding and collapsing tiles at ${width.toInt()}x${height.toInt()}', (tester) async {
        tester.view.physicalSize = viewport;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final settingsProv = FakeAdversarialSettingsProvider();
        await tester.pumpWidget(createHarnessApp(settingsProv: settingsProv));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        await navigateToTab(tester, 'Integraciones', isCompact: isCompact);

        // Tap Mercado Pago ExpansionTile header to collapse
        final mpHeaderFinder = find.text('Mercado Pago');
        await tester.ensureVisible(mpHeaderFinder);
        await tester.tap(mpHeaderFinder);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        assertZeroRenderFlexOverflow(tester, 'After collapsing MP tile at ${width.toInt()}x${height.toInt()}');

        // Tap Mercado Pago ExpansionTile header to re-expand
        await tester.tap(mpHeaderFinder);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        assertZeroRenderFlexOverflow(tester, 'After expanding MP tile at ${width.toInt()}x${height.toInt()}');

        // Tap ARCA ExpansionTile header to collapse
        final afipHeaderFinder = find.text('ARCA / AFIP (Facturación Electrónica)');
        await tester.ensureVisible(afipHeaderFinder);
        await tester.tap(afipHeaderFinder);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        assertZeroRenderFlexOverflow(tester, 'After collapsing ARCA tile at ${width.toInt()}x${height.toInt()}');

        // Tap ARCA ExpansionTile header to re-expand
        await tester.tap(afipHeaderFinder);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        assertZeroRenderFlexOverflow(tester, 'After expanding ARCA tile at ${width.toInt()}x${height.toInt()}');
      });

      testWidgets('Dynamic interaction: Toggling switches at ${width.toInt()}x${height.toInt()}', (tester) async {
        tester.view.physicalSize = viewport;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final settingsProv = FakeAdversarialSettingsProvider();
        await tester.pumpWidget(createHarnessApp(settingsProv: settingsProv));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        await navigateToTab(tester, 'Integraciones', isCompact: isCompact);

        // Find switches in the Integraciones tab
        final switches = find.byType(Switch);
        expect(switches, findsWidgets);

        // Toggle first switch (MP trailing switch)
        await tester.tap(switches.first);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        assertZeroRenderFlexOverflow(tester, 'After toggling MP switch at ${width.toInt()}x${height.toInt()}');

        // Toggle back
        await tester.tap(switches.first);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        assertZeroRenderFlexOverflow(tester, 'After re-toggling MP switch at ${width.toInt()}x${height.toInt()}');
      });

      testWidgets('Dynamic interaction: File picking and clearing at ${width.toInt()}x${height.toInt()}', (tester) async {
        tester.view.physicalSize = viewport;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final settingsProv = FakeAdversarialSettingsProvider();
        await tester.pumpWidget(createHarnessApp(settingsProv: settingsProv));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        await navigateToTab(tester, 'Integraciones', isCompact: isCompact);

        // Pick cert file
        mockPicker.nextResult = FilePickerResult([
          PlatformFile(
            name: 'empresa_afip_cert.crt',
            size: 2048,
            bytes: Uint8List.fromList([10, 20, 30]),
          ),
        ]);
        final pickCertBtn = find.byKey(const ValueKey('btn_pick_afip_cert'));
        await tester.ensureVisible(pickCertBtn);
        await tester.tap(pickCertBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        assertZeroRenderFlexOverflow(tester, 'After picking AFIP cert at ${width.toInt()}x${height.toInt()}');
        expect(find.text('empresa_afip_cert.crt'), findsOneWidget);

        // Pick key file
        mockPicker.nextResult = FilePickerResult([
          PlatformFile(
            name: 'empresa_afip_private.key',
            size: 1024,
            bytes: Uint8List.fromList([40, 50, 60]),
          ),
        ]);
        final pickKeyBtn = find.byKey(const ValueKey('btn_pick_afip_key'));
        await tester.ensureVisible(pickKeyBtn);
        await tester.tap(pickKeyBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        assertZeroRenderFlexOverflow(tester, 'After picking AFIP key at ${width.toInt()}x${height.toInt()}');
        expect(find.text('empresa_afip_private.key'), findsOneWidget);

        // Clear cert file
        final clearBtns = find.byTooltip('Quitar archivo');
        expect(clearBtns, findsNWidgets(2));
        await tester.tap(clearBtns.first);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        assertZeroRenderFlexOverflow(tester, 'After clearing cert at ${width.toInt()}x${height.toInt()}');
        expect(find.text('empresa_afip_cert.crt'), findsNothing);

        // Clear key file
        final remainingClearBtn = find.byTooltip('Quitar archivo');
        expect(remainingClearBtn, findsOneWidget);
        await tester.tap(remainingClearBtn.first);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        assertZeroRenderFlexOverflow(tester, 'After clearing key at ${width.toInt()}x${height.toInt()}');
        expect(find.text('empresa_afip_private.key'), findsNothing);
      });

      testWidgets('Dynamic interaction: Obscure text toggles at ${width.toInt()}x${height.toInt()}', (tester) async {
        tester.view.physicalSize = viewport;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final settingsProv = FakeAdversarialSettingsProvider();
        await tester.pumpWidget(createHarnessApp(settingsProv: settingsProv));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        await navigateToTab(tester, 'Integraciones', isCompact: isCompact);

        // Toggle MP Access Token visibility
        final tokenEye = find.byTooltip('Mostrar token');
        if (tokenEye.evaluate().isNotEmpty) {
          await tester.ensureVisible(tokenEye.first);
          await tester.tap(tokenEye.first);
          await tester.pump();
          assertZeroRenderFlexOverflow(tester, 'After revealing MP token at ${width.toInt()}x${height.toInt()}');
        }

        // Toggle MP Webhook Secret visibility
        final secretEye = find.byTooltip('Mostrar secret');
        if (secretEye.evaluate().isNotEmpty) {
          await tester.ensureVisible(secretEye.first);
          await tester.tap(secretEye.first);
          await tester.pump();
          assertZeroRenderFlexOverflow(tester, 'After revealing MP secret at ${width.toInt()}x${height.toInt()}');
        }

        // Toggle AFIP Passphrase visibility
        final passEye = find.byTooltip('Mostrar contraseña');
        if (passEye.evaluate().isNotEmpty) {
          await tester.ensureVisible(passEye.first);
          await tester.tap(passEye.first);
          await tester.pump();
          assertZeroRenderFlexOverflow(tester, 'After revealing AFIP passphrase at ${width.toInt()}x${height.toInt()}');
        }
      });
    }
  });

  group('Quality Gate Iteration 2: Edge Cases & Heavy Content Stress Tests', () {
    testWidgets('Long text and boundary data injection does NOT cause RenderFlex overflow at 320x480', (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final settingsProv = FakeAdversarialSettingsProvider(
        integrationsData: {
          'mp_qr_enabled': true,
          'mp_point_device_id': 'VERY_LONG_POINT_IDENTIFIER_NUMBER_00000000000000000001',
          'mp_access_token': 'APP_USR-999999999999999999999999999999999999999999999999999999999999999999',
          'mp_webhook_secret': 'whsec_SUPER_LONG_SECRET_STRING_ABCD_1234_EFGH_5678_IJKL_9012_MNOP_3456',
          'mp_has_access_token': true,
          'mp_has_webhook_secret': true,
          'mp_webhook_url': 'https://pos-backend.test/api/webhooks/mercadopago/subdomain/super/long/path/name/endpoint',
          'afip_enabled': true,
          'afip_cuit': '20123456789',
          'afip_pto_vta': 99999,
          'afip_environment': 'testing',
          'afip_has_cert': true,
          'afip_has_key': true,
          'afip_cert_expires_at': '2099-12-31 23:59:59 (Certificado con expiración muy extendida)',
        },
      );

      await tester.pumpWidget(createHarnessApp(settingsProv: settingsProv));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await navigateToTab(tester, 'Integraciones', isCompact: true);

      // Scroll through the entire page from top to bottom
      await tester.drag(find.byType(SingleChildScrollView).last, const Offset(0, -300));
      await tester.pump();
      assertZeroRenderFlexOverflow(tester, 'Scrolling down 300px with heavy strings at 320x480');

      await tester.drag(find.byType(SingleChildScrollView).last, const Offset(0, -300));
      await tester.pump();
      assertZeroRenderFlexOverflow(tester, 'Scrolling down 600px with heavy strings at 320x480');

      await tester.drag(find.byType(SingleChildScrollView).last, const Offset(0, -300));
      await tester.pump();
      assertZeroRenderFlexOverflow(tester, 'Scrolling down 900px with heavy strings at 320x480');

      // Scroll back up
      await tester.drag(find.byType(SingleChildScrollView).last, const Offset(0, 900));
      await tester.pump();
      assertZeroRenderFlexOverflow(tester, 'Scrolling back to top with heavy strings at 320x480');
    });

    testWidgets('Long text and boundary data injection does NOT cause RenderFlex overflow at 712x800', (tester) async {
      tester.view.physicalSize = const Size(712, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final settingsProv = FakeAdversarialSettingsProvider(
        integrationsData: {
          'mp_qr_enabled': true,
          'mp_point_device_id': 'VERY_LONG_POINT_IDENTIFIER_NUMBER_00000000000000000001',
          'mp_access_token': 'APP_USR-999999999999999999999999999999999999999999999999999999999999999999',
          'mp_webhook_secret': 'whsec_SUPER_LONG_SECRET_STRING_ABCD_1234_EFGH_5678_IJKL_9012_MNOP_3456',
          'mp_has_access_token': true,
          'mp_has_webhook_secret': true,
          'mp_webhook_url': 'https://pos-backend.test/api/webhooks/mercadopago/subdomain/super/long/path/name/endpoint',
          'afip_enabled': true,
          'afip_cuit': '20123456789',
          'afip_pto_vta': 99999,
          'afip_environment': 'production',
          'afip_has_cert': true,
          'afip_has_key': true,
          'afip_cert_expires_at': '2099-12-31 23:59:59 (Certificado con expiración muy extendida)',
        },
      );

      await tester.pumpWidget(createHarnessApp(settingsProv: settingsProv));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await navigateToTab(tester, 'Integraciones', isCompact: false);

      // Scroll content area
      await tester.drag(find.byType(SingleChildScrollView).last, const Offset(0, -400));
      await tester.pump();
      assertZeroRenderFlexOverflow(tester, 'Scrolling down 400px at 712x800 breakpoint');

      await tester.drag(find.byType(SingleChildScrollView).last, const Offset(0, 400));
      await tester.pump();
      assertZeroRenderFlexOverflow(tester, 'Scrolling back to top at 712x800 breakpoint');
    });
  });
}
