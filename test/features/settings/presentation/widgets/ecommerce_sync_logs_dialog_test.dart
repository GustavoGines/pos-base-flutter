import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:frontend_desktop/core/network/api_client.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/features/settings/presentation/widgets/ecommerce_sync_logs_dialog.dart';
import 'package:frontend_desktop/features/settings/domain/usecases/get_settings_usecase.dart';
import 'package:frontend_desktop/features/settings/domain/usecases/update_settings_usecase.dart';

class FakeGetSettingsUseCase implements GetSettingsUseCase {
  @override
  Future<BusinessSettings> call() async => BusinessSettings();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeUpdateSettingsUseCase implements UpdateSettingsUseCase {
  @override
  Future<BusinessSettings> call(Map<String, dynamic> data) async => BusinessSettings();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('EcommerceSyncLogsDialog Widget Tests', () {
    late ApiClient apiClient;

    final mockLogsResponse = json.encode({
      'data': [
        {
          'id': 101,
          'integration_id': 1,
          'direction': 'outbound',
          'action': 'stock_update',
          'stock_before': '15.000',
          'stock_after': '12.000',
          'http_status': 200,
          'duration_ms': 142,
          'status': 'success',
          'created_at': '2026-10-11T14:30:00Z',
          'request_payload': {'available_quantity': 12},
          'response_payload': {'id': 'MLA999'},
          'integration': {
            'id': 1,
            'platform': 'mercadolibre',
            'name': 'Mercado Libre Oficial',
          },
        },
        {
          'id': 102,
          'integration_id': 2,
          'direction': 'inbound',
          'action': 'order_deduction',
          'stock_before': '12.000',
          'stock_after': '10.000',
          'http_status': 500,
          'duration_ms': 350,
          'status': 'failed',
          'error_message': 'Deadlock detected while locking row',
          'external_order_id': 'WOO-5544',
          'created_at': '2026-10-11T14:35:00Z',
          'integration': {
            'id': 2,
            'platform': 'woocommerce',
            'name': 'Tienda WooCommerce',
          },
        },
      ],
      'current_page': 1,
      'last_page': 1,
      'total': 2,
    });

    Widget createTestApp(http.Client mockClient) {
      apiClient = ApiClient(mockClient);
      final settingsProv = SettingsProvider(
        getSettingsUseCase: FakeGetSettingsUseCase(),
        updateSettingsUseCase: FakeUpdateSettingsUseCase(),
      );

      return MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>.value(value: settingsProv),
          Provider<ApiClient>.value(value: apiClient),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: EcommerceSyncLogsDialog(),
          ),
        ),
      );
    }

    testWidgets('renders dialog header, filter chips and log items from API', (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/ecommerce/logs')) {
          return http.Response(mockLogsResponse, 200, headers: {'content-type': 'application/json'});
        }
        return http.Response('Not Found', 404);
      });

      await tester.pumpWidget(createTestApp(mockClient));
      await tester.pumpAndSettle();

      // Check header
      expect(find.text('Bitácora de Sincronización E-Commerce'), findsOneWidget);
      expect(find.textContaining('2 registros'), findsOneWidget);

      // Check filter chips
      expect(find.text('Todos'), findsOneWidget);
      expect(find.text('Solo Exitosos'), findsOneWidget);
      expect(find.text('Solo Fallidos'), findsOneWidget);
      expect(find.text('Entrantes (Webhooks)'), findsOneWidget);
      expect(find.text('Salientes (Hacia Tiendas)'), findsOneWidget);

      // Check items
      expect(find.text('Mercado Libre Oficial'), findsOneWidget);
      expect(find.text('Tienda WooCommerce'), findsOneWidget);
      expect(find.text('Actualización de Stock'), findsOneWidget);
      expect(find.text('Descuento por Venta Online'), findsOneWidget);
      expect(find.text('Stock: 15.000 ➔ 12.000'), findsOneWidget);
    });

    testWidgets('expands failed log tile to display error detail message', (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/ecommerce/logs')) {
          return http.Response(mockLogsResponse, 200, headers: {'content-type': 'application/json'});
        }
        return http.Response('Not Found', 404);
      });

      await tester.pumpWidget(createTestApp(mockClient));
      await tester.pumpAndSettle();

      // Tap on the failed WooCommerce tile to expand
      final failedTile = find.byKey(const ValueKey('log_102'));
      expect(failedTile, findsOneWidget);
      await tester.tap(failedTile);
      await tester.pumpAndSettle();

      // Error message should be visible inside expanded child
      expect(find.textContaining('Deadlock detected while locking row'), findsOneWidget);
      expect(find.textContaining('WOO-5544'), findsOneWidget);
    });
  });
}
