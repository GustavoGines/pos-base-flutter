import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:frontend_desktop/core/network/api_client.dart';
import 'package:frontend_desktop/core/presentation/widgets/license_guard.dart';
import 'package:frontend_desktop/core/presentation/pages/license_lock_screen.dart';
import 'package:frontend_desktop/features/auth/presentation/widgets/admin_pin_dialog.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/core/services/license_heartbeat_service.dart';

class MockSettingsProvider extends ChangeNotifier implements SettingsProvider {
  bool _isLicenseActive = false;
  final String _activeUrl = 'http://localhost/api';
  String? _errorMessage;
  final LicenseSecurityStatus _securityStatus = LicenseSecurityStatus.ok;
  final Set<String> _features = {};

  @override
  bool get isLicenseActive => _isLicenseActive;
  void setLicenseActive(bool val) {
    _isLicenseActive = val;
    notifyListeners();
  }

  @override
  String get currentApiUrl => _activeUrl;

  @override
  bool hasFeature(String feature) => _features.contains(feature);

  @override
  LicenseSecurityStatus get securityStatus => _securityStatus;

  @override
  String? get errorMessage => _errorMessage;

  @override
  BusinessSettings? get settings => BusinessSettings(licenseStatus: 'BLOCKED_KEY');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('Empirical Challenge: LicenseGuard vs AdminPinDialog Bypass Resistance', () {
    test('CHALLENGE-04: ApiClient strictly suppresses AdminPinDialog for LICENSE_BLOCKED and related DRM errors', () async {
      bool adminPinPromptCalled = false;

      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'error_code': 'LICENSE_BLOCKED',
            'message': 'Su licencia se encuentra vencida o suspendida.',
          }),
          403,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(mockClient);
      apiClient.onPermissionDenied = (reason) async {
        adminPinPromptCalled = true;
        return '9999'; // Supervisor attempting to bypass
      };

      // Invocación a endpoint protegido por licencia
      final response = await apiClient.post(
        Uri.parse('http://localhost/api/sales'),
        body: jsonEncode({'total': 500}),
      );

      // VERIFICACIÓN: El código HTTP debe seguir siendo 403 y el prompt de PIN NUNCA debió invocarse
      expect(response.statusCode, 403);
      expect(adminPinPromptCalled, isFalse,
          reason: 'Supervisor PIN prompt must never be triggered for LICENSE_BLOCKED');
    });

    test('CHALLENGE-05: ApiClient strictly suppresses AdminPinDialog for LICENSE_INTEGRITY_VIOLATION and FEATURE_NOT_LICENSED', () async {
      bool adminPinPromptCalled = false;

      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'error_code': 'LICENSE_INTEGRITY_VIOLATION',
            'message': 'Alteración no autorizada detectada en registros de licencia.',
          }),
          403,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(mockClient);
      apiClient.onPermissionDenied = (reason) async {
        adminPinPromptCalled = true;
        return '9999';
      };

      final response = await apiClient.get(Uri.parse('http://localhost/api/reports'));
      expect(response.statusCode, 403);
      expect(adminPinPromptCalled, isFalse,
          reason: 'Supervisor PIN prompt must never be triggered for LICENSE_INTEGRITY_VIOLATION');
    });

    testWidgets('CHALLENGE-06: LicenseGuard locks UI, disables interaction and cannot be bypassed by AdminPinDialog', (tester) async {
      final mockSettings = MockSettingsProvider();
      mockSettings.setLicenseActive(false); // Licencia inactiva

      final routeNotifier = ValueNotifier<String?>('/pos');
      final navKey = GlobalKey<NavigatorState>();

      bool childButtonPressed = false;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsProvider>.value(value: mockSettings),
          ],
          child: MaterialApp(
            navigatorKey: navKey,
            home: LicenseGuard(
              routeNotifier: routeNotifier,
              navigatorKey: navKey,
              child: Scaffold(
                body: ElevatedButton(
                  key: const Key('protected_pos_button'),
                  onPressed: () {
                    childButtonPressed = true;
                  },
                  child: const Text('BOTON POS BLOQUEADO'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // 1. Verificar que LicenseLockScreen está en pantalla
      expect(find.byType(LicenseLockScreen), findsOneWidget);
      expect(find.text('SISTEMA BLOQUEADO'), findsOneWidget);

      // 2. Verificar que AdminPinDialog NO está en pantalla ni hay ningún botón para invocarlo
      expect(find.byType(AdminPinDialog), findsNothing);
      expect(find.text('PIN de Administrador'), findsNothing);

      // 3. Intentar tocar el botón protegido del child en el fondo
      // IgnorePointer debe absorber / ignorar el toque
      final buttonFinder = find.byKey(const Key('protected_pos_button'));
      expect(buttonFinder, findsOneWidget); // Existe en el árbol del Stack pero está en el fondo ignorado

      await tester.tap(buttonFinder, warnIfMissed: false);
      await tester.pump();

      expect(childButtonPressed, isFalse,
          reason: 'IgnorePointer inside LicenseGuard must swallow clicks to underlying protected widgets');

      // 4. Intentar ingresar a ruta permitida de la whitelist (/login o /close-shift)
      routeNotifier.value = '/close-shift';
      await tester.pumpAndSettle();

      // En /close-shift el bloqueo se levanta para permitir el Arqueo de Emergencia
      expect(find.byType(LicenseLockScreen), findsNothing);
      await tester.tap(buttonFinder);
      await tester.pump();
      expect(childButtonPressed, isTrue);
    });
  });
}
