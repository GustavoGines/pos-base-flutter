import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend_desktop/core/network/api_client.dart';
import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import 'package:frontend_desktop/features/cash_movements/providers/cash_movement_provider.dart';
import 'package:frontend_desktop/features/cash_register/data/datasources/cash_register_remote_datasource.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/pos/data/datasources/pos_remote_datasource.dart';
import 'package:frontend_desktop/features/pos/data/repositories/pos_repository_impl.dart';
import 'package:frontend_desktop/features/pos/domain/entities/cart_item.dart';
import 'package:frontend_desktop/features/pos/domain/usecases/process_sale_usecase.dart';
import 'package:frontend_desktop/features/pos/domain/usecases/search_products_usecase.dart';
import 'package:frontend_desktop/features/pos/presentation/providers/pos_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Fase 3 Frontend Audit Regression Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('F3-CAJA-01 / FN-F3-02: CashMovementProvider propaga cash_shift_id en fetchMovements y createMovement', () async {
      final capturedUrls = <String>[];

      final mockClient = MockClient((request) async {
        capturedUrls.add(request.url.toString());
        if (request.method == 'POST') {
          return http.Response(
            jsonEncode({
              'message': 'OK',
              'movements': [
                {'id': 99}
              ]
            }),
            201,
          );
        }
        return http.Response(
          jsonEncode({
            'data': [],
            'current_page': 1,
            'last_page': 1,
            'total': 0,
            'kpi_total_in': 0,
            'kpi_total_out': 0,
            'kpi_net': 0,
          }),
          200,
        );
      });

      final provider = CashMovementProvider(
        baseUrl: 'http://localhost/api',
        client: ApiClient(mockClient),
      );

      await provider.fetchMovements(refresh: true, all: false, cashShiftId: 42);
      expect(capturedUrls.last, contains('cash_shift_id=42'));

      await provider.createMovement({
        'type': 'deposit',
        'cash_shift_id': 77,
        'payments': [
          {'amount': 100.0, 'payment_method': 'cash'}
        ],
      });

      // El refresh posterior a createMovement debe mantener el turno 77
      expect(capturedUrls.last, contains('cash_shift_id=77'));
    });

    test('F3-CAJA-02 / FN-F3-05: CashRegisterRemoteDataSource soporta 403 Arqueo Ciego (sin expected_balance) y modo legacy v1.8.5', () async {
      // 1. Modo Arqueo Ciego (v2.0.3+: omite expected_balance y difference)
      final blindClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'message': 'La diferencia de caja requiere autorización de un supervisor.',
            'error_code': 'DIFFERENCE_REQUIRES_ADMIN',
            'actual_balance': 4200.0,
          }),
          403,
        );
      });

      final blindDs = CashRegisterRemoteDataSourceImpl(
        baseUrl: 'http://localhost/api',
        client: blindClient,
      );

      await expectLater(
        () => blindDs.closeShift(1, 4200.0, pin: '1234'),
        throwsA(
          isA<DifferenceRequiresAdminException>()
              .having((e) => e.actualBalance, 'actualBalance', 4200.0)
              .having((e) => e.expectedBalance, 'expectedBalance', isNull)
              .having((e) => e.difference, 'difference', isNull),
        ),
      );

      // 2. Modo Legacy (v1.8.5: incluye expected_balance y difference)
      final legacyClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'message': 'Diferencia detectada.',
            'error_code': 'DIFFERENCE_REQUIRES_ADMIN',
            'expected_balance': 5000.0,
            'actual_balance': 4200.0,
            'difference': -800.0,
          }),
          403,
        );
      });

      final legacyDs = CashRegisterRemoteDataSourceImpl(
        baseUrl: 'http://localhost/api',
        client: legacyClient,
      );

      await expectLater(
        () => legacyDs.closeShift(1, 4200.0, pin: '1234'),
        throwsA(
          isA<DifferenceRequiresAdminException>()
              .having((e) => e.expectedBalance, 'expectedBalance', 5000.0)
              .having((e) => e.difference, 'difference', -800.0),
        ),
      );
    });

    test('F3-RESIL-01 / FN-F3-04: PosRemoteDataSource envía client_transaction_id, X-Idempotency-Key y acepta HTTP 200/201', () async {
      String? capturedHeaderKey;
      String? capturedBodyKey;

      final mockClient = MockClient((request) async {
        capturedHeaderKey = request.headers['X-Idempotency-Key'];
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        capturedBodyKey = body['client_transaction_id'] as String?;
        return http.Response(
          jsonEncode({
            'message': 'Venta registrada correctamente',
            'sale': {'id': 555, 'total': 100.0},
          }),
          200, // Simula respuesta idempotente HTTP 200 o 201
        );
      });

      final ds = PosRemoteDataSourceImpl(
        baseUrl: 'http://localhost/api',
        client: mockClient,
      );

      final prod = Product(
        id: 1,
        name: 'Item',
        internalCode: 'I1',
        costPrice: 50,
        sellingPrice: 100,
        stock: 10,
        active: true,
        isSoldByWeight: false,
      );

      final res = await ds.processSale(
        total: 100.0,
        totalSurcharge: 0.0,
        shiftId: 1,
        items: [CartItem(product: prod, quantity: 1)],
        clientTransactionId: 'tx-uuid-12345',
      );

      expect(capturedHeaderKey, equals('tx-uuid-12345'));
      expect(capturedBodyKey, equals('tx-uuid-12345'));
      expect(res['sale']['id'], equals(555));
    });

    test('F3-AFIP-03 / FN-F3-06: PosProvider evita duplicar ventas si el rollback tras rechazo AFIP 422 no puede anular la venta', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/payment-methods')) {
          return http.Response(jsonEncode([]), 200);
        }
        if (request.url.path.endsWith('/pos/sales')) {
          return http.Response(
            jsonEncode({
              'sale': {'id': 701, 'total': 1000.0}
            }),
            201,
          );
        }
        if (request.url.path.endsWith('/sales/701/invoice')) {
          return http.Response(
            jsonEncode({
              'message': 'La solicitud fiscal no pudo ser autorizada por AFIP.',
              'error': 'CUIT receptor inválido',
            }),
            422,
          );
        }
        if (request.url.path.endsWith('/sales/701/void')) {
          // Simular que el cajero cancela o falla el permiso de anulación
          return http.Response(jsonEncode({'message': 'No autorizado'}), 403);
        }
        return http.Response(jsonEncode([]), 200);
      });

      final ds = PosRemoteDataSourceImpl(
        baseUrl: 'http://localhost/api',
        client: mockClient,
      );
      final repo = PosRepositoryImpl(remoteDataSource: ds);
      final provider = PosProvider(
        processSaleUseCase: ProcessSaleUseCase(repo),
        searchProductsUseCase: SearchProductsUseCase(repo),
        repository: repo,
        remoteDataSource: ds,
      );

      final prod = Product(
        id: 1,
        name: 'Producto Fiscal',
        internalCode: 'PF1',
        costPrice: 500,
        sellingPrice: 1000,
        stock: 10,
        active: true,
        isSoldByWeight: false,
      );
      provider.requestAddToCart(prod);
      provider.setPendingFiscalInvoiceData({
        'voucher_type': 1,
        'doc_type': 80,
        'doc_number': '20000000000',
      });

      final terminal = LocalTerminalProvider();
      final ok = await provider.processCheckout(
        shiftId: 1,
        totalSurcharge: 0,
        payments: [
          {
            'payment_method_id': 1,
            'base_amount': 1000.0,
            'surcharge_amount': 0.0,
            'total_amount': 1000.0,
          }
        ],
        tenderedAmount: 1000.0,
        changeAmount: 0.0,
        printerFormat: 'thermal_80',
        localTerminal: terminal,
        settings: null,
        clientTransactionId: 'tx-afip-rollback-fail',
      );

      // Como la venta #701 ya quedó asentada en el servidor y no pudo anularse,
      // processCheckout debe completarla como Ticket No Fiscal con advertencia y limpiar el carrito
      expect(ok, isTrue);
      expect(provider.cart, isEmpty);
      expect(provider.printerWarning, contains('AFIP rechazó la factura'));
      expect(provider.printerWarning, contains('CUIT receptor inválido'));
    });

    test('F3-RESIL-02: ApiClient conmuta dinámicamente al endpoint de respaldo ante caída de red y recupera el primario tras expirar ventana sticky', () async {
      bool primaryDown = true;
      final requestedHosts = <String>[];

      final innerClient = MockClient((request) async {
        requestedHosts.add(request.url.host);
        if (request.url.host == '192.168.1.50' && primaryDown) {
          throw const SocketException('Connection refused');
        }
        return http.Response(jsonEncode({'ok': true, 'host': request.url.host}), 200);
      });

      final apiClient = ApiClient(innerClient)
        ..fallbackStickyDuration = const Duration(milliseconds: 50)
        ..configureFailover(
          primaryUrl: 'http://192.168.1.50/api',
          fallbackUrl: 'https://cloud.negocio.com/api',
        );

      // 1. Primer request falla en LAN (192.168.1.50) y conmuta en caliente a WAN (cloud.negocio.com)
      final resp1 = await apiClient.get(Uri.parse('http://192.168.1.50/api/settings'));
      expect(resp1.statusCode, equals(200));
      expect(apiClient.isUsingFallbackEndpoint, isTrue);
      expect(requestedHosts, equals(['192.168.1.50', 'cloud.negocio.com']));

      // 2. Segundo request inmediato usa directamente el endpoint de respaldo (sticky)
      requestedHosts.clear();
      final resp2 = await apiClient.get(Uri.parse('http://192.168.1.50/api/settings'));
      expect(resp2.statusCode, equals(200));
      expect(requestedHosts, equals(['cloud.negocio.com']));

      // 3. Una vez restaurada la LAN y expirada la ventana sticky, vuelve automáticamente al primario
      primaryDown = false;
      await Future<void>.delayed(const Duration(milliseconds: 80));
      requestedHosts.clear();
      final resp3 = await apiClient.get(Uri.parse('http://192.168.1.50/api/settings'));
      expect(resp3.statusCode, equals(200));
      expect(apiClient.isUsingFallbackEndpoint, isFalse);
      expect(requestedHosts, equals(['192.168.1.50']));
    });
  });
}
