import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend_desktop/core/config/business_vertical_profile.dart';
import 'package:frontend_desktop/core/presentation/widgets/demo_environment_widgets.dart';
import 'package:frontend_desktop/core/services/license_heartbeat_service.dart';
import 'package:frontend_desktop/features/settings/data/models/business_settings_model.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/settings/domain/repositories/settings_repository.dart';
import 'package:frontend_desktop/features/settings/domain/usecases/get_settings_usecase.dart';
import 'package:frontend_desktop/features/settings/domain/usecases/update_settings_usecase.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';

class _FakeSettingsRepository extends Fake implements SettingsRepository {
  Map<String, dynamic> statusResponse = {
    'success': true,
    'demo_mode_active': true,
    'is_trial': true,
    'is_fresh_empty_store': false,
    'demo_onboarding_dismissed': true,
    'has_fiscal_block': false,
    'counts': {
      'products': 10,
      'sales': 18,
      'customers': 4,
      'suppliers': 3,
      'quotes': 2,
      'user_added_products_after_seed': 2,
    },
  };

  Map<String, dynamic> seedResponse = {
    'success': true,
    'message': 'Entorno de exploración cargado con datos de ejemplo.',
    'status': {
      'demo_mode_active': true,
      'is_trial': true,
      'is_fresh_empty_store': false,
      'demo_onboarding_dismissed': true,
    },
  };

  Map<String, dynamic> dismissResponse = {
    'success': true,
    'status': {
      'demo_mode_active': false,
      'is_trial': true,
      'is_fresh_empty_store': true,
      'demo_onboarding_dismissed': true,
    },
  };

  Map<String, dynamic> resetResponse = {
    'success': true,
    'message': 'Datos de ejemplo eliminados.',
    'status': {
      'demo_mode_active': false,
      'is_trial': true,
      'is_fresh_empty_store': true,
      'demo_onboarding_dismissed': true,
    },
  };

  int seedCalls = 0;
  int dismissCalls = 0;
  int resetCalls = 0;
  String? lastPin;
  String? lastConfirm;

  BusinessSettings currentSettings = const BusinessSettings(
    companyName: 'Comercio Demo',
    isTrial: true,
    demoModeActive: false,
    isFreshEmptyStore: true,
    businessType: 'hardware_store',
  );

  @override
  Future<BusinessSettings> getSettings() async => currentSettings;

  @override
  Future<Map<String, dynamic>> fetchDemoStatus() async => statusResponse;

  @override
  Future<Map<String, dynamic>> seedDemoEnvironment() async {
    seedCalls++;
    currentSettings = currentSettings.copyWith(
      demoModeActive: true,
      isFreshEmptyStore: false,
      demoOnboardingDismissed: true,
    );
    return seedResponse;
  }

  @override
  Future<Map<String, dynamic>> dismissDemoOnboarding() async {
    dismissCalls++;
    currentSettings = currentSettings.copyWith(demoOnboardingDismissed: true);
    return dismissResponse;
  }

  @override
  Future<Map<String, dynamic>> resetDemoEnvironment({
    required String adminPin,
    required String confirmationText,
  }) async {
    resetCalls++;
    lastPin = adminPin;
    lastConfirm = confirmationText;
    if (resetResponse['success'] == true) {
      currentSettings = currentSettings.copyWith(
        demoModeActive: false,
        demoOnboardingDismissed: true,
        isFreshEmptyStore: true,
      );
    }
    return resetResponse;
  }

  @override
  Future<BusinessSettings> updateSettings(Map<String, dynamic> data) async =>
      currentSettings;
}

SettingsProvider _buildProvider(_FakeSettingsRepository repo) {
  return SettingsProvider(
    getSettingsUseCase: GetSettingsUseCase(repo),
    updateSettingsUseCase: UpdateSettingsUseCase(repo),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    const secureStorageChannel =
        MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async => null);
  });

  tearDown(() {
    LicenseHeartbeatService().stop();
  });

  test('BusinessSettingsModel.fromJson parses demo flags cleanly', () {
    final modelTrue = BusinessSettingsModel.fromJson({
      'store_name': 'Ferreteria Norte',
      'demo_mode_active': '1',
      'demo_onboarding_dismissed': '1',
      'is_fresh_empty_store': false,
      'demo_seeded_at': '2026-11-25T14:30:00-03:00',
    });

    expect(modelTrue.demoModeActive, isTrue);
    expect(modelTrue.demoOnboardingDismissed, isTrue);
    expect(modelTrue.isFreshEmptyStore, isFalse);
    expect(modelTrue.demoSeededAt, '2026-11-25T14:30:00-03:00');

    final modelBool = BusinessSettingsModel.fromJson({
      'store_name': 'Kiosco Sur',
      'demo_mode_active': false,
      'demo_onboarding_dismissed': '0',
      'is_fresh_empty_store': true,
    });

    expect(modelBool.demoModeActive, isFalse);
    expect(modelBool.demoOnboardingDismissed, isFalse);
    expect(modelBool.isFreshEmptyStore, isTrue);
    expect(modelBool.demoSeededAt, isNull);
  });

  testWidgets('DemoModeBanner adapts admin vs cashier copy without overflow at 1024px',
      (tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              DemoModeBanner(isAdmin: true),
              Expanded(child: SizedBox()),
            ],
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('demo_banner_reset_btn')), findsOneWidget);
    expect(find.textContaining('MODO EXPLORACIÓN'), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              DemoModeBanner(isAdmin: false),
              Expanded(child: SizedBox()),
            ],
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('demo_banner_reset_btn')), findsNothing);
    expect(find.textContaining('pedile a un Administrador'), findsOneWidget);
  });

  testWidgets('DemoOnboardingDialog shows vertical and triggers seed or clean start',
      (tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final repo = _FakeSettingsRepository();
    final provider = _buildProvider(repo);
    final profile = BusinessVerticalProfile.fromType(
      BusinessVerticalProfile.hardwareStore,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => Center(
                child: ElevatedButton(
                  key: const Key('open_onboarding_test_btn'),
                  onPressed: () => DemoOnboardingDialog.show(
                    ctx,
                    verticalProfile: profile,
                  ),
                  child: const Text('Abrir'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open_onboarding_test_btn')));
    await tester.pumpAndSettle();

    expect(find.textContaining(profile.displayLabel), findsOneWidget);
    expect(find.byKey(const Key('demo_onboarding_seed_btn')), findsOneWidget);
    expect(find.byKey(const Key('demo_onboarding_clean_btn')), findsOneWidget);

    await tester.tap(find.byKey(const Key('demo_onboarding_seed_btn')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    expect(repo.seedCalls, 1);

    await tester.tap(find.byKey(const Key('open_onboarding_test_btn')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('demo_onboarding_clean_btn')));
    await tester.pumpAndSettle();
    expect(repo.dismissCalls, 1);
    LicenseHeartbeatService().stop();
  });

  testWidgets('DemoResetConfirmDialog validates LIMPIAR + PIN and shows backend error',
      (tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final repo = _FakeSettingsRepository();
    repo.resetResponse = {
      'success': false,
      'message': 'El PIN de administrador ingresado es incorrecto.',
      'error_code': 'INVALID_ADMIN_PIN',
    };
    final provider = _buildProvider(repo);

    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: provider,
        child: const MaterialApp(
          home: Scaffold(
            body: DemoResetConfirmDialog(navigateHomeOnSuccess: false),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // User-added products warning shown from fetched counts
    expect(find.textContaining('2 producto(s) propio(s)'), findsOneWidget);

    final submitBtn = find.byKey(const Key('demo_reset_submit_btn'));
    expect(tester.widget<ElevatedButton>(submitBtn).onPressed, isNull);

    await tester.enterText(
      find.byKey(const Key('demo_reset_confirm_text_field')),
      'LIMPIAR',
    );
    await tester.enterText(
      find.byKey(const Key('demo_reset_pin_field')),
      '0000',
    );
    await tester.pump();

    expect(tester.widget<ElevatedButton>(submitBtn).onPressed, isNotNull);

    await tester.tap(submitBtn);
    await tester.pumpAndSettle();

    expect(repo.resetCalls, 1);
    expect(repo.lastPin, '0000');
    expect(repo.lastConfirm, 'LIMPIAR');
    expect(
      find.text('El PIN de administrador ingresado es incorrecto.'),
      findsOneWidget,
    );
  });
}
