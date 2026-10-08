import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend_desktop/core/constants/app_permissions.dart';
import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import 'package:frontend_desktop/core/services/license_heartbeat_service.dart';
import 'package:frontend_desktop/features/auth/presentation/providers/auth_provider.dart';
import 'package:frontend_desktop/features/reports/presentation/providers/inventory_alerts_provider.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/settings/data/models/business_settings_model.dart';
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
  Map<String, dynamic>? get currentUser => {'id': 1, 'name': 'Admin User', 'role': _isAdmin ? 'admin' : 'cashier'};
  @override
  bool get isAdmin => _isAdmin;
  @override
  bool hasPermission(String permission) => _isAdmin || _permissions.contains(permission);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeIibbSettingsProvider extends ChangeNotifier implements SettingsProvider {
  BusinessSettings? _settings;
  bool saveSettingsCalled = false;
  Map<String, dynamic>? lastSavedData;

  FakeIibbSettingsProvider({BusinessSettings? settings}) : _settings = settings;

  @override
  BusinessSettings? get settings => _settings;

  @override
  bool get isIibbPerceptionAgent => _settings?.isIibbPerceptionAgent ?? false;

  @override
  double get defaultIibbPerceptionRate => _settings?.defaultIibbPerceptionRate ?? 0.0;

  @override
  bool get isLicenseActive => true;

  @override
  String get currentPlan => 'basic';

  @override
  List<String> get allowedAddons => [];

  @override
  bool get isHardwareStore => false;

  @override
  FeatureFlags get features => _settings?.features ?? const FeatureFlags();

  @override
  bool hasFeature(String featureName) => false;

  @override
  bool get isLoading => false;

  @override
  String? get errorMessage => null;

  @override
  Map<String, dynamic>? get integrations => null;

  @override
  bool get isLoadingIntegrations => false;

  @override
  LicenseSecurityStatus get securityStatus => LicenseSecurityStatus.ok;

  @override
  String get currentApiUrl => 'http://localhost/api';

  @override
  void updateBaseUrl(String newUrl) {}

  @override
  Future<bool> saveSettings(Map<String, dynamic> data) async {
    saveSettingsCalled = true;
    lastSavedData = data;
    _settings = _settings?.copyWith(
      isIibbPerceptionAgent: data['is_iibb_perception_agent'] == '1' || data['is_iibb_perception_agent'] == true,
      defaultIibbPerceptionRate: double.tryParse(data['default_iibb_perception_rate']?.toString() ?? '0.0') ?? 0.0,
    );
    notifyListeners();
    return true;
  }

  @override
  Future<void> loadSettings({bool isSilent = false}) async {}

  @override
  Future<Map<String, dynamic>?> loadIntegrations({bool isSilent = false}) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'pos_api': 'http://localhost/api',
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

  group('BusinessSettings Entity & Model IIBB Tests', () {
    test('BusinessSettings entity has default values for IIBB', () {
      const settings = BusinessSettings();
      expect(settings.isIibbPerceptionAgent, isFalse);
      expect(settings.defaultIibbPerceptionRate, equals(0.0));
    });

    test('BusinessSettings copyWith modifies IIBB fields properly', () {
      const settings = BusinessSettings();
      final updated = settings.copyWith(
        isIibbPerceptionAgent: true,
        defaultIibbPerceptionRate: 3.5,
      );

      expect(updated.isIibbPerceptionAgent, isTrue);
      expect(updated.defaultIibbPerceptionRate, equals(3.5));
      expect(updated.globalWholesalePercentage, equals(-15.0)); // Unmodified
    });

    test('BusinessSettings props includes IIBB fields for equality', () {
      const s1 = BusinessSettings(isIibbPerceptionAgent: true, defaultIibbPerceptionRate: 3.0);
      const s2 = BusinessSettings(isIibbPerceptionAgent: true, defaultIibbPerceptionRate: 3.0);
      const s3 = BusinessSettings(isIibbPerceptionAgent: false, defaultIibbPerceptionRate: 3.0);
      const s4 = BusinessSettings(isIibbPerceptionAgent: true, defaultIibbPerceptionRate: 4.0);

      expect(s1, equals(s2));
      expect(s1, isNot(equals(s3)));
      expect(s1, isNot(equals(s4)));
    });

    test('BusinessSettingsModel.fromJson parses varied formats for is_iibb_perception_agent', () {
      // String '1'
      final m1 = BusinessSettingsModel.fromJson({'is_iibb_perception_agent': '1'});
      expect(m1.isIibbPerceptionAgent, isTrue);

      // Boolean true
      final m2 = BusinessSettingsModel.fromJson({'is_iibb_perception_agent': true});
      expect(m2.isIibbPerceptionAgent, isTrue);

      // Integer 1
      final m3 = BusinessSettingsModel.fromJson({'is_iibb_perception_agent': 1});
      expect(m3.isIibbPerceptionAgent, isTrue);

      // Falsy values
      final m4 = BusinessSettingsModel.fromJson({'is_iibb_perception_agent': '0'});
      expect(m4.isIibbPerceptionAgent, isFalse);

      final m5 = BusinessSettingsModel.fromJson({'is_iibb_perception_agent': false});
      expect(m5.isIibbPerceptionAgent, isFalse);

      final m6 = BusinessSettingsModel.fromJson({});
      expect(m6.isIibbPerceptionAgent, isFalse);
    });

    test('BusinessSettingsModel.fromJson parses varied formats for default_iibb_perception_rate', () {
      final m1 = BusinessSettingsModel.fromJson({'default_iibb_perception_rate': '3.50'});
      expect(m1.defaultIibbPerceptionRate, equals(3.5));

      final m2 = BusinessSettingsModel.fromJson({'default_iibb_perception_rate': 4.25});
      expect(m2.defaultIibbPerceptionRate, equals(4.25));

      final m3 = BusinessSettingsModel.fromJson({'default_iibb_perception_rate': 3});
      expect(m3.defaultIibbPerceptionRate, equals(3.0));

      final m4 = BusinessSettingsModel.fromJson({});
      expect(m4.defaultIibbPerceptionRate, equals(0.0));
    });

    test('BusinessSettingsModel.toJson outputs string formatted rate and flag', () {
      const model = BusinessSettingsModel(
        companyName: 'Test Corp',
        isIibbPerceptionAgent: true,
        defaultIibbPerceptionRate: 3.5,
      );

      final json = model.toJson();
      expect(json['is_iibb_perception_agent'], equals('1'));
      expect(json['default_iibb_perception_rate'], equals('3.50'));

      const modelFalse = BusinessSettingsModel(
        isIibbPerceptionAgent: false,
        defaultIibbPerceptionRate: 0.0,
      );
      final jsonFalse = modelFalse.toJson();
      expect(jsonFalse['is_iibb_perception_agent'], equals('0'));
      expect(jsonFalse['default_iibb_perception_rate'], equals('0.00'));
    });
  });

  group('SettingsScreen IIBB UI Widget Tests', () {
    Widget buildSettingsScreenApp({required FakeIibbSettingsProvider settingsProv}) {
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

    testWidgets('Renders IIBB switch and toggles default rate input in Precios tab', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final settingsProv = FakeIibbSettingsProvider(
        settings: const BusinessSettings(
          companyName: 'Negocio Mayorista S.A.',
          isIibbPerceptionAgent: false,
          defaultIibbPerceptionRate: 0.0,
        ),
      );

      await tester.pumpWidget(buildSettingsScreenApp(settingsProv: settingsProv));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Navigate to Precios section
      await tester.tap(find.text('Precios Globales'));
      await tester.pumpAndSettle();

      // Find switch
      final switchFinder = find.byKey(const ValueKey('switch_iibb_perception_agent'));
      expect(switchFinder, findsOneWidget);

      // Verify that rate field is not visible initially
      final rateFieldFinder = find.byKey(const ValueKey('field_default_iibb_rate'));
      expect(rateFieldFinder, findsNothing);

      // Toggle switch to true
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      // Rate field should now appear
      expect(rateFieldFinder, findsOneWidget);

      // Enter default rate
      await tester.enterText(rateFieldFinder, '3.25');
      await tester.pumpAndSettle();

      // Save settings
      final saveButton = find.text('GUARDAR');
      expect(saveButton, findsOneWidget);
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      expect(settingsProv.saveSettingsCalled, isTrue);
      expect(settingsProv.lastSavedData?['is_iibb_perception_agent'], equals('1'));
      expect(settingsProv.lastSavedData?['default_iibb_perception_rate'], equals(3.25));
    });

    testWidgets('Initializes with existing IIBB agent enabled and pre-filled rate', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final settingsProv = FakeIibbSettingsProvider(
        settings: const BusinessSettings(
          companyName: 'Negocio Mayorista S.A.',
          isIibbPerceptionAgent: true,
          defaultIibbPerceptionRate: 3.5,
        ),
      );

      await tester.pumpWidget(buildSettingsScreenApp(settingsProv: settingsProv));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Navigate to Precios section
      await tester.tap(find.text('Precios Globales'));
      await tester.pumpAndSettle();

      // Switch should be on and rate field should exist with value
      final switchFinder = find.byKey(const ValueKey('switch_iibb_perception_agent'));
      expect(switchFinder, findsOneWidget);

      final rateFieldFinder = find.byKey(const ValueKey('field_default_iibb_rate'));
      expect(rateFieldFinder, findsOneWidget);

      final textField = tester.widget<TextFormField>(rateFieldFinder);
      expect(textField.controller?.text, equals('3.5'));
    });
  });
}
