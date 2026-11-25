import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend_desktop/core/presentation/widgets/global_app_bar.dart';
import 'package:frontend_desktop/features/updater/data/models/update_info.dart';
import 'package:frontend_desktop/features/updater/data/services/update_service.dart';
import 'package:frontend_desktop/features/updater/presentation/widgets/upgrade_news_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    UpdateService().resetForTesting();
  });

  tearDown(() {
    UpdateService().resetForTesting();
  });

  group('UpdateService - Singleton, Anti Race-Condition y Canales', () {
    test('UpdateService retorna siempre la misma instancia singleton', () {
      final a = UpdateService();
      final b = UpdateService.instance;
      expect(identical(a, b), isTrue);
    });

    test('Anti race-condition: respuesta lenta de beta queda descartada tras cambio rápido a stable', () async {
      final betaFrontendGate = Completer<void>();
      final requestsLog = <String>[];

      final client = MockClient((request) async {
        if (request.url.path.endsWith('/version-check')) {
          return http.Response(jsonEncode({'version': '2.1.2'}), 200);
        }
        final channel = request.url.queryParameters['channel'] ?? 'stable';
        final component = request.url.queryParameters['component'] ?? 'frontend';
        requestsLog.add('$channel:$component');

        if (channel == 'beta') {
          if (component == 'frontend') {
            await betaFrontendGate.future;
            return http.Response(
              jsonEncode({
                'success': true,
                'update_available': true,
                'data': {
                  'version': '2.9.9-beta',
                  'download_url': 'https://example.com/beta.zip',
                  'changelog': 'Beta feature',
                  'is_critical': false,
                },
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({'success': true, 'update_available': false}),
            200,
          );
        }

        // Canal stable responde sin actualizaciones pendientes
        return http.Response(
          jsonEncode({'success': true, 'update_available': false}),
          200,
        );
      });

      final service = UpdateService();
      service.configureForTesting(
        httpClient: client,
        frontendVersionProvider: () async => '2.1.2',
        forceAllowInDebug: true,
      );

      // 1. Dispara cambio a beta (quedará suspendido en frontend check)
      final betaFuture = service.setChannel('beta');
      // Permitir que llegue hasta betaFrontendGate
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(UpdateService.isSwitchingChannelNotifier.value, isTrue);

      // 2. Usuario vuelve rápidamente a stable antes de que beta responda
      final stableResult = await service.setChannel('stable');
      expect(stableResult.channel, 'stable');
      expect(stableResult.hasAny, isFalse);
      expect(UpdateService.updateNotifier.value?.channel, 'stable');
      expect(UpdateService.updateNotifier.value?.hasAny, isFalse);
      expect(UpdateService.isSwitchingChannelNotifier.value, isFalse);

      // 3. Finalmente llega la respuesta tardía de beta: debe descartarse y NO pisar stable
      betaFrontendGate.complete();
      final lateBetaReturn = await betaFuture;

      expect(lateBetaReturn.channel, 'stable');
      expect(UpdateService.updateNotifier.value?.channel, 'stable');
      expect(UpdateService.updateNotifier.value?.hasAny, isFalse);
      expect(UpdateService.channelNotifier.value, 'stable');
    });

    test('setChannel limpia inmediatamente updateNotifier antes de completar la red', () async {
      final netGate = Completer<void>();

      final client = MockClient((request) async {
        if (request.url.path.endsWith('/version-check')) {
          return http.Response(jsonEncode({'version': '2.1.2'}), 200);
        }
        await netGate.future;
        return http.Response(
          jsonEncode({'success': true, 'update_available': false}),
          200,
        );
      });

      final service = UpdateService();
      service.configureForTesting(
        httpClient: client,
        frontendVersionProvider: () async => '2.1.2',
        forceAllowInDebug: true,
      );

      // Simular que había un update beta mostrado en la barra
      UpdateService.updateNotifier.value = UpdateCheckResult(
        channel: 'beta',
        frontendUpdate: UpdateInfo(
          version: '2.2.0-beta.1',
          downloadUrl: 'https://example.com/fe.zip',
          changelog: 'Test beta',
          isCritical: false,
          component: 'frontend',
        ),
      );

      // Cambiar a stable: debe borrar el badge inmediatamente antes del await de red
      final pending = service.setChannel('stable');
      expect(UpdateService.updateNotifier.value, isNull);
      expect(UpdateService.channelNotifier.value, 'stable');
      expect(UpdateService.isSwitchingChannelNotifier.value, isTrue);

      netGate.complete();
      await pending;
      expect(UpdateService.isSwitchingChannelNotifier.value, isFalse);
      expect(UpdateService.updateNotifier.value?.hasAny, isFalse);
    });

    test('Polling singleton no duplica timers y falla en silencio cuando está offline', () async {
      int hitCount = 0;
      final client = MockClient((request) async {
        hitCount++;
        throw const SocketException('Sin conexión');
      });

      final service = UpdateService();
      service.configureForTesting(
        httpClient: client,
        frontendVersionProvider: () async => '2.1.2',
        forceAllowInDebug: true,
      );

      // Estado previo existente que no debe borrarse por un hipo offline del polling
      final existing = UpdateCheckResult(
        channel: 'stable',
        frontendUpdate: UpdateInfo(
          version: '2.2.0',
          downloadUrl: 'https://example.com/app.zip',
          changelog: 'Stable update',
          isCritical: false,
          component: 'frontend',
        ),
      );
      UpdateService.updateNotifier.value = existing;

      // Polling silencioso directo no lanza excepción ni destruye badge existente
      final offlinePoll = await service.checkUpdate(throwErrors: false);
      expect(offlinePoll.serverChecked, isFalse);
      expect(UpdateService.updateNotifier.value?.frontendUpdate?.version, '2.2.0');

      // Llamar startPeriodicCheck varias veces mantiene un único timer activo
      service.startPeriodicCheck(
        interval: const Duration(milliseconds: 30),
        allowInDebug: true,
      );
      service.startPeriodicCheck(
        interval: const Duration(milliseconds: 30),
        allowInDebug: true,
      );
      expect(service.isPeriodicCheckActive, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 95));
      service.stopPeriodicCheck();
      expect(service.isPeriodicCheckActive, isFalse);
      // Con intervalo 30ms en ~95ms solo hubo ~2-3 ticks de 1 timer (nunca el doble)
      expect(hitCount, greaterThanOrEqualTo(1));
      expect(hitCount, lessThanOrEqualTo(8));
    });

    test(
        'Fase 2 Auto-Resume: llamadas concurrentes a checkUpdate sobre el mismo canal completan ambas sin cancelarse mutuamente',
        () async {
      final serverGate = Completer<void>();

      final client = MockClient((request) async {
        if (request.url.path.endsWith('/version-check')) {
          return http.Response(jsonEncode({'version': '2.1.0'}), 200);
        }
        final component = request.url.queryParameters['component'];
        await serverGate.future;
        if (component == 'backend') {
          return http.Response(
            jsonEncode({
              'success': true,
              'update_available': true,
              'data': {
                'version': '2.1.2',
                'download_url': 'https://example.com/backend_2.1.2.zip',
                'changelog': 'Backend update',
                'is_critical': false,
              },
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({'success': true, 'update_available': false}),
          200,
        );
      });

      final service = UpdateService();
      service.configureForTesting(
        httpClient: client,
        frontendVersionProvider: () async => '2.1.2',
        forceAllowInDebug: true,
      );

      // Simula main.dart (Auto-Resume post-OTA) y LoginScreen._checkForUpdates()
      // invocando checkUpdate() casi al mismo instante tras relanzar Sistema_POS.exe
      final autoResumeFuture = service.checkUpdate();
      final loginCheckFuture = service.checkUpdate(throwErrors: true);

      await Future<void>.delayed(const Duration(milliseconds: 20));
      serverGate.complete();

      final results = await Future.wait([autoResumeFuture, loginCheckFuture]);
      expect(results[0].serverChecked, isTrue);
      expect(results[0].backendUpdate?.version, equals('2.1.2'));
      expect(results[1].serverChecked, isTrue);
      expect(results[1].backendUpdate?.version, equals('2.1.2'));
      expect(UpdateService.isCheckingNotifier.value, isFalse);
    });
  });

  group('UpdateBadgeWidget - Reactividad Visual Stable vs Beta', () {
    testWidgets('Muestra pill BETA cuando el canal es beta y Verificando Beta durante el cambio', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(child: UpdateBadgeWidget()),
          ),
        ),
      );

      // Sin updates ni cambio de canal -> oculto
      expect(find.text('Actualizar'), findsNothing);

      // Cambiando a Beta -> spinner de verificación
      UpdateService.channelNotifier.value = 'beta';
      UpdateService.isSwitchingChannelNotifier.value = true;
      await tester.pump();
      expect(find.text('Verificando Beta...'), findsOneWidget);

      // Llega actualización Beta
      UpdateService.isSwitchingChannelNotifier.value = false;
      UpdateService.updateNotifier.value = UpdateCheckResult(
        channel: 'beta',
        frontendUpdate: UpdateInfo(
          version: '2.3.0-beta.1',
          downloadUrl: 'https://example.com/beta.zip',
          changelog: 'Beta',
          isCritical: false,
          component: 'frontend',
        ),
      );
      await tester.pump();
      expect(find.text('Actualizar'), findsOneWidget);
      expect(find.text('BETA'), findsOneWidget);

      // Al volver a stable sin updates -> desaparece por completo
      UpdateService.updateNotifier.value = UpdateCheckResult(channel: 'stable');
      await tester.pump();
      expect(find.text('Actualizar'), findsNothing);
      expect(find.text('BETA'), findsNothing);
    });

    test('checkUpdate envía X-Ota-Protocol: 2 y X-Ota-Token desde SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        'license_ota_token': 'abc123tokenhash',
      });

      final capturedHeaders = <Map<String, String>>[];
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/version-check')) {
          return http.Response(jsonEncode({'version': '2.2.0'}), 200);
        }
        capturedHeaders.add(Map<String, String>.from(request.headers));
        return http.Response(
          jsonEncode({'success': true, 'update_available': false}),
          200,
        );
      });

      final service = UpdateService();
      service.configureForTesting(
        httpClient: client,
        frontendVersionProvider: () async => '2.2.0',
        forceAllowInDebug: true,
      );

      final res = await service.checkUpdate();
      expect(res.currentFrontendVersion, '2.2.0');
      expect(capturedHeaders, hasLength(2));
      for (final h in capturedHeaders) {
        expect(h['X-Ota-Protocol'], '2');
        expect(h['X-Ota-Token'], 'abc123tokenhash');
      }
    });

    testWidgets('Lifetime bloqueado muestra badge sutil ✨ Novedades, abre UpgradeNewsDialog y permite ocultar versión hasta la siguiente', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      UpdateService.updateNotifier.value = UpdateCheckResult(
        channel: 'stable',
        currentFrontendVersion: '2.2.0',
        frontendUpdate: UpdateInfo(
          version: '2.3.0',
          downloadUrl: '',
          changelog: '• Facturación rápida\n• Reporte de caja mejorado',
          isCritical: false,
          canAutoUpdate: false,
          otaBlockReason: 'lifetime_upgrade_required',
          component: 'frontend',
        ),
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(child: UpdateBadgeWidget()),
          ),
        ),
      );

      expect(find.text('✨ Novedades v2.3.0'), findsOneWidget);
      expect(find.text('Actualizar'), findsNothing);

      await tester.tap(find.text('✨ Novedades v2.3.0'));
      await tester.pumpAndSettle();

      expect(find.byType(UpgradeNewsDialog), findsOneWidget);
      expect(find.textContaining('Tu licencia actual es Pago Único (v2.2.0)'), findsOneWidget);
      expect(find.text('Ocultar aviso de esta versión'), findsOneWidget);

      await tester.tap(find.text('Ocultar aviso de esta versión'));
      await tester.pumpAndSettle();

      // El badge de la 2.3.0 desaparece de la barra superior
      expect(find.text('✨ Novedades v2.3.0'), findsNothing);

      // Si llega una versión más nueva (2.4.0), vuelve a mostrarse
      UpdateService.updateNotifier.value = UpdateCheckResult(
        channel: 'stable',
        currentFrontendVersion: '2.2.0',
        frontendUpdate: UpdateInfo(
          version: '2.4.0',
          downloadUrl: '',
          changelog: 'Novedades v2.4.0',
          isCritical: false,
          canAutoUpdate: false,
          otaBlockReason: 'lifetime_upgrade_required',
          component: 'frontend',
        ),
      );
      await tester.pump();
      expect(find.text('✨ Novedades v2.4.0'), findsOneWidget);
    });

    testWidgets('SaaS vencido o sin licencia no muestran badge comercial en UpdateBadgeWidget', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(child: UpdateBadgeWidget()),
          ),
        ),
      );

      UpdateService.updateNotifier.value = UpdateCheckResult(
        channel: 'stable',
        currentFrontendVersion: '2.2.0',
        frontendUpdate: UpdateInfo(
          version: '2.3.0',
          downloadUrl: '',
          changelog: 'Novedades',
          isCritical: false,
          canAutoUpdate: false,
          otaBlockReason: 'subscription_expired',
          component: 'frontend',
        ),
      );
      await tester.pump();
      expect(find.textContaining('Novedades'), findsNothing);
      expect(find.text('Actualizar'), findsNothing);

      UpdateService.updateNotifier.value = UpdateCheckResult(
        channel: 'stable',
        currentFrontendVersion: '2.2.0',
        frontendUpdate: UpdateInfo(
          version: '2.3.0',
          downloadUrl: '',
          changelog: 'Novedades',
          isCritical: false,
          canAutoUpdate: false,
          otaBlockReason: 'missing_license',
          component: 'frontend',
        ),
      );
      await tester.pump();
      expect(find.textContaining('Novedades'), findsNothing);
      expect(find.text('Actualizar'), findsNothing);
    });
  });
}
