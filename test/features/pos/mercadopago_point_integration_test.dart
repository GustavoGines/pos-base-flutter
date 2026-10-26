import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend_desktop/core/network/api_client.dart';
import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import 'package:frontend_desktop/features/pos/presentation/widgets/posnet_waiting_dialog.dart';
import 'package:frontend_desktop/features/settings/data/datasources/settings_remote_datasource.dart';
import 'package:frontend_desktop/features/settings/data/repositories/settings_repository_impl.dart';
import 'package:frontend_desktop/features/settings/domain/usecases/get_settings_usecase.dart';
import 'package:frontend_desktop/features/settings/domain/usecases/update_settings_usecase.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Bloque 4 & 5 - PosnetWaitingDialog Point Physical Integration Tests', () {
    testWidgets('Envía device_id al crear payment intent y aprueba con sondeo',
        (WidgetTester tester) async {
      String? capturedCreateBody;
      int pollCount = 0;

      final client = ApiClient(
        MockClient((request) async {
          if (request.url.path.contains('create-point-intent')) {
            capturedCreateBody = request.body;
            return http.Response(
              jsonEncode({
                'success': true,
                'payment_intent_id': 'INTENT-POINT-444',
                'external_reference': 'POS-REF-444',
              }),
              200,
            );
          }
          if (request.url.path.contains('status/POS-REF-444')) {
            pollCount++;
            if (pollCount == 1) {
              return http.Response(jsonEncode({'status': 'pending'}), 200);
            }
            return http.Response(
              jsonEncode({
                'status': 'approved',
                'mp_payment_id': 'MP-PAY-777',
              }),
              200,
            );
          }
          return http.Response('{"success": true}', 200);
        }),
      );

      Map<String, dynamic>? dialogResult;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  dialogResult = await showDialog<Map<String, dynamic>>(
                    context: context,
                    builder: (_) => PosnetWaitingDialog(
                      amount: 2500.0,
                      description: 'Cobro Test Point',
                      deviceId: 'PAX_A910__CAJA1',
                      client: client,
                      baseUrl: 'http://localhost/api',
                    ),
                  );
                },
                child: const Text('Abrir Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir Dialog'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(PosnetWaitingDialog), findsOneWidget);
      expect(capturedCreateBody, contains('"device_id":"PAX_A910__CAJA1"'));
      expect(capturedCreateBody, contains('"amount":2500.0'));

      // Avanzar el timer para el sondeo 1 (pending) y sondeo 2 (approved)
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      expect(dialogResult, isNotNull);
      expect(dialogResult!['status'], equals('approved'));
      expect(dialogResult!['mp_payment_id'], equals('MP-PAY-777'));
      expect(dialogResult!['mp_order_id'], equals('INTENT-POINT-444'));
      expect(dialogResult!['external_reference'], equals('POS-REF-444'));
    });

    testWidgets('Detecta cancelación o abandono físico en Point y muestra error',
        (WidgetTester tester) async {
      final client = ApiClient(
        MockClient((request) async {
          if (request.url.path.contains('create-point-intent')) {
            return http.Response(
              jsonEncode({
                'success': true,
                'payment_intent_id': 'INTENT-POINT-CANCEL',
                'external_reference': 'POS-REF-CANCEL',
              }),
              200,
            );
          }
          if (request.url.path.contains('status/POS-REF-CANCEL')) {
            return http.Response(
              jsonEncode({
                'status': 'cancelled',
                'state': 'CANCELED',
                'message': 'El cliente canceló la operación en el Point.',
              }),
              200,
            );
          }
          return http.Response('{"success": true}', 200);
        }),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => PosnetWaitingDialog(
                    amount: 1500.0,
                    client: client,
                    baseUrl: 'http://localhost/api',
                  ),
                ),
                child: const Text('Abrir Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir Dialog'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Primer sondeo de 2 segundos -> devuelve cancelled
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();

      expect(
        find.text('El cliente canceló la operación en el Point.'),
        findsOneWidget,
      );
      expect(find.text('Reintentar'), findsOneWidget);
    });

    testWidgets('Al cancelar la operación en pantalla invoca cancel-order en backend',
        (WidgetTester tester) async {
      String? cancelledRef;

      final client = ApiClient(
        MockClient((request) async {
          if (request.url.path.contains('create-point-intent')) {
            return http.Response(
              jsonEncode({
                'success': true,
                'payment_intent_id': 'INTENT-POINT-555',
                'external_reference': 'POS-REF-ABORT-555',
              }),
              200,
            );
          }
          if (request.url.path.contains('cancel-order')) {
            final body = jsonDecode(request.body);
            cancelledRef = body['external_reference'];
            return http.Response(jsonEncode({'success': true}), 200);
          }
          if (request.url.path.contains('status')) {
            return http.Response(jsonEncode({'status': 'pending'}), 200);
          }
          return http.Response('{"success": true}', 200);
        }),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => PosnetWaitingDialog(
                    amount: 3200.0,
                    client: client,
                    baseUrl: 'http://localhost/api',
                  ),
                ),
                child: const Text('Abrir Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir Dialog'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Presionar "Cancelar Operación"
      await tester.tap(find.text('Cancelar Operación'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(cancelledRef, equals('POS-REF-ABORT-555'));
      expect(find.byType(PosnetWaitingDialog), findsNothing);
    });
  });

  group('Bloque 4 & 5 - SettingsProvider Point Terminals Management Tests', () {
    test('fetchMpPointDevices obtiene la lista de terminales Point', () async {
      final mockHttpClient = MockClient((request) async {
        if (request.url.path.contains('/pos/mp/devices')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'devices': [
                {
                  'id': 'PAX_A910__CAJA_1',
                  'operating_mode': 'PDV',
                  'pos_id': 12345,
                },
                {
                  'id': 'POINT_SMART_2',
                  'operating_mode': 'STANDALONE',
                  'pos_id': 67890,
                },
              ],
            }),
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      final remoteSource = SettingsRemoteDataSourceImpl(baseUrl: 'http://pos-backend.test/api', client: mockHttpClient);
      final repo = SettingsRepositoryImpl(remoteDataSource: remoteSource);
      final provider = SettingsProvider(
        getSettingsUseCase: GetSettingsUseCase(repo),
        updateSettingsUseCase: UpdateSettingsUseCase(repo),
      );

      final devices = await provider.fetchMpPointDevices();
      expect(devices.length, equals(2));
      expect(devices[0]['id'], equals('PAX_A910__CAJA_1'));
      expect(devices[0]['operating_mode'], equals('PDV'));
      expect(devices[1]['id'], equals('POINT_SMART_2'));
      expect(devices[1]['operating_mode'], equals('STANDALONE'));
    });

    test('updateMpPointDeviceOperatingMode conmuta modo a PDV con éxito', () async {
      String? sentMode;
      String? sentDeviceId;

      final mockHttpClient = MockClient((request) async {
        if (request.url.path.contains('/pos/mp/devices/operating-mode')) {
          final body = jsonDecode(request.body);
          sentMode = body['operating_mode'];
          sentDeviceId = body['device_id'];
          return http.Response(
            jsonEncode({
              'success': true,
              'device_id': sentDeviceId,
              'operating_mode': sentMode,
            }),
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      final remoteSource = SettingsRemoteDataSourceImpl(baseUrl: 'http://pos-backend.test/api', client: mockHttpClient);
      final repo = SettingsRepositoryImpl(remoteDataSource: remoteSource);
      final provider = SettingsProvider(
        getSettingsUseCase: GetSettingsUseCase(repo),
        updateSettingsUseCase: UpdateSettingsUseCase(repo),
      );

      final result = await provider.updateMpPointDeviceOperatingMode(
        deviceId: 'POINT_SMART_2',
        operatingMode: 'PDV',
      );

      expect(result['success'], isTrue);
      expect(sentDeviceId, equals('POINT_SMART_2'));
      expect(sentMode, equals('PDV'));
    });
  });

  group('Bloque 4 & 5 - Multi-Caja Point Device ID Isolation in LocalTerminalProvider', () {
    test('Permite persistir y recuperar dispositivo Point por Caja independientemente', () async {
      SharedPreferences.setMockInitialValues({
        'local_mp_point_device_id': 'POINT_CAJA_A',
      });

      final terminal = LocalTerminalProvider();
      await Future.delayed(const Duration(milliseconds: 50));

      expect(terminal.mpPointDeviceId, equals('POINT_CAJA_A'));

      await terminal.setMpPointDeviceId('POINT_CAJA_B');
      expect(terminal.mpPointDeviceId, equals('POINT_CAJA_B'));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('local_mp_point_device_id'), equals('POINT_CAJA_B'));

      // Al limpiar vuelve a vacío para heredar de empresa
      await terminal.setMpPointDeviceId('');
      expect(terminal.mpPointDeviceId, equals(''));
      expect(prefs.getString('local_mp_point_device_id'), equals(''));
    });
  });
}
