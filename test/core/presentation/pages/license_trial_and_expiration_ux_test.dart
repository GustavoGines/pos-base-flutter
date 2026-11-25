import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_desktop/core/network/api_client.dart';
import 'package:frontend_desktop/core/presentation/pages/license_lock_screen.dart';
import 'package:frontend_desktop/core/services/license_heartbeat_service.dart';
import 'package:frontend_desktop/features/settings/data/models/business_settings_model.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

class _FakeSettingsProvider extends ChangeNotifier implements SettingsProvider {
  final BusinessSettings? _settings;
  final LicenseSecurityStatus _securityStatus;
  String? _errorMessage;

  _FakeSettingsProvider({
    BusinessSettings? settings,
    LicenseSecurityStatus securityStatus = LicenseSecurityStatus.ok,
  })  : _settings = settings,
        _securityStatus = securityStatus;

  @override
  BusinessSettings? get settings => _settings;

  @override
  LicenseSecurityStatus get securityStatus => _securityStatus;

  @override
  String? get errorMessage => _errorMessage;

  @override
  String get currentApiUrl => 'http://localhost/api';

  @override
  bool get isLicenseActive => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es_AR');
  });

  group('Expiración exacta local y modelo Trial', () {
    test('convierte 2026-11-30T23:59:59-03:00 a hora local sin saltar al 01/12 y parsea isTrial', () {
      final model = BusinessSettingsModel.fromJson({
        'license_key': 'pos_****abcd',
        'app_plan': 'pro',
        'license_plan_mode': 'saas',
        'license_is_trial': '1',
        'license_block_reason': 'trial_expired',
        'license_expires_at': '2026-11-30T23:59:59-03:00',
      });

      expect(model.isTrial, isTrue);
      expect(model.licenseBlockReason, 'trial_expired');
      // Verificar conversión segura desde UTC del parser Dart hacia local
      final expectedLocal = DateTime.parse('2026-11-30T23:59:59-03:00').toLocal();
      expect(model.localLicenseExpiresAt, expectedLocal);
    });
  });

  group('LicenseLockScreen UX Comercial Diferenciada', () {
    testWidgets('muestra pantalla amigable de Fin de Prueba con WhatsApp, Verificar ahora y campo secundario vacío', (tester) async {
      final settingsProv = _FakeSettingsProvider(
        securityStatus: LicenseSecurityStatus.trialExpired,
        settings: const BusinessSettings(
          companyName: 'Minimercado Sol',
          licenseStatus: 'pos_****abcd',
          licensePlanType: 'blocked',
          isTrial: true,
          licenseBlockReason: 'trial_expired',
        ),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsProvider>.value(
          value: settingsProv,
          child: MaterialApp(
            home: LicenseLockScreen(
              navigatorKey: GlobalKey<NavigatorState>(),
              securityStatus: LicenseSecurityStatus.trialExpired,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('¡Gracias por probar Caja4U!'), findsOneWidget);
      expect(
        find.textContaining('Todos tus productos, precios, clientes, turnos y ventas siguen guardados'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('lock_screen_whatsapp_button')), findsOneWidget);
      expect(find.byKey(const Key('lock_screen_verify_button')), findsOneWidget);

      // El campo de clave alternativa está colapsado al inicio
      expect(find.byKey(const Key('lock_screen_license_key_field')), findsNothing);

      // Al desplegarlo, debe estar 100% vacío (jamás precargado con pos_****abcd)
      final toggleFinder = find.byKey(const Key('lock_screen_toggle_alt_key'));
      await tester.ensureVisible(toggleFinder);
      await tester.pumpAndSettle();
      await tester.tap(toggleFinder);
      await tester.pumpAndSettle();

      final fieldFinder = find.byKey(const Key('lock_screen_license_key_field'));
      await tester.ensureVisible(fieldFinder);
      expect(fieldFinder, findsOneWidget);
      final textField = tester.widget<TextField>(fieldFinder);
      expect(textField.controller?.text, isEmpty);
    });

    testWidgets('muestra pantalla diferenciada para SaaS vencido y Clock Tampered', (tester) async {
      final saasProv = _FakeSettingsProvider(
        securityStatus: LicenseSecurityStatus.subscriptionExpired,
        settings: const BusinessSettings(
          licenseStatus: 'pos_****9999',
          licensePlanType: 'blocked',
          isTrial: false,
          licenseBlockReason: 'subscription_expired',
        ),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsProvider>.value(
          value: saasProv,
          child: MaterialApp(
            home: LicenseLockScreen(
              navigatorKey: GlobalKey<NavigatorState>(),
              securityStatus: LicenseSecurityStatus.subscriptionExpired,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Suscripción pendiente de renovación'), findsOneWidget);
      expect(find.text('Ya aboné · Verificar habilitación ahora'), findsOneWidget);

      final clockProv = _FakeSettingsProvider(
        securityStatus: LicenseSecurityStatus.clockTampered,
        settings: const BusinessSettings(
          licenseStatus: 'pos_****9999',
          licensePlanType: 'blocked',
          licenseBlockReason: 'clock_tampered',
        ),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsProvider>.value(
          value: clockProv,
          child: MaterialApp(
            home: LicenseLockScreen(
              navigatorKey: GlobalKey<NavigatorState>(),
              securityStatus: LicenseSecurityStatus.clockTampered,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Verificación de fecha y hora requerida'), findsOneWidget);
      expect(find.text('Ya corregí la hora · Verificar ahora'), findsOneWidget);
    });
  });

  group('ApiClient 403 Reactive License Callback', () {
    test('dispara onLicenseBlocked ante LICENSE_BLOCKED y LICENSE_CLOCK_TAMPERED sin abrir AdminPinDialog', () async {
      final triggeredCodes = <String?>[];
      bool pinPromptCalled = false;

      final mockClient = MockClient((request) async {
        final code = request.url.path.contains('clock')
            ? 'LICENSE_CLOCK_TAMPERED'
            : 'LICENSE_BLOCKED';
        return http.Response(
          jsonEncode({'error_code': code, 'message': 'Bloqueado'}),
          403,
          headers: {'content-type': 'application/json'},
        );
      });

      final client = ApiClient(mockClient);
      client.onLicenseBlocked = (code) => triggeredCodes.add(code);
      client.onPermissionDenied = (_) async {
        pinPromptCalled = true;
        return '1234';
      };

      final res1 = await client.post(Uri.parse('http://localhost/api/pos/sales'));
      final res2 = await client.post(Uri.parse('http://localhost/api/clock-test'));

      expect(res1.statusCode, 403);
      expect(res2.statusCode, 403);
      expect(pinPromptCalled, isFalse);
      expect(triggeredCodes, ['LICENSE_BLOCKED', 'LICENSE_CLOCK_TAMPERED']);
    });
  });
}
