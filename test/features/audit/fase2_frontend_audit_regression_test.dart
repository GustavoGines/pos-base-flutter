import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:frontend_desktop/core/network/api_client.dart';
import 'package:frontend_desktop/features/sales_history/domain/entities/sale_record.dart';
import 'package:frontend_desktop/features/quotes/data/quote_repository.dart';
import 'package:frontend_desktop/features/cash_movements/models/cash_movement_model.dart';
import 'package:frontend_desktop/features/settings/data/models/business_settings_model.dart';
import 'package:frontend_desktop/features/reports/presentation/providers/reports_provider.dart';
import 'package:frontend_desktop/features/reports/data/datasources/reports_remote_datasource.dart';
import 'package:frontend_desktop/features/reports/data/datasources/inventory_alerts_datasource.dart';
import 'package:frontend_desktop/features/logistics/presentation/providers/logistics_provider.dart';
import 'package:frontend_desktop/features/logistics/data/delivery_note_repository.dart';
import 'package:frontend_desktop/features/pos/domain/entities/cart_item.dart';
import 'package:frontend_desktop/features/pos/presentation/providers/pos_provider.dart';
import 'package:frontend_desktop/features/pos/data/datasources/pos_remote_datasource.dart';
import 'package:frontend_desktop/features/pos/data/repositories/pos_repository_impl.dart';
import 'package:frontend_desktop/features/pos/domain/usecases/process_sale_usecase.dart';
import 'package:frontend_desktop/features/pos/domain/usecases/search_products_usecase.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('Fase 2 Frontend Audit Regression Tests', () {
    test('F-05: ApiClient extrae el mensaje de error del JSON ante HTTP 5xx', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'message': 'AFIP WSFE Error 10016: Comprobante no correlativo'}),
          500,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final apiClient = ApiClient(mockClient);

      expect(
        () async => await apiClient.get(Uri.parse('http://localhost/api/test')),
        throwsA(
          isA<NetworkException>().having(
            (e) => e.message,
            'message',
            'AFIP WSFE Error 10016: Comprobante no correlativo',
          ),
        ),
      );
    });

    test('F-05: ApiClient recurre al mensaje amigable si el 500 es HTML o no parseable', () async {
      final mockClient = MockClient((request) async {
        return http.Response('<html><body>Fatal PHP Error</body></html>', 500);
      });

      final apiClient = ApiClient(mockClient);

      expect(
        () async => await apiClient.get(Uri.parse('http://localhost/api/test')),
        throwsA(
          isA<NetworkException>().having(
            (e) => e.message,
            'message',
            contains('No se pudo conectar con el servidor principal'),
          ),
        ),
      );
    });

    test('F-06: Deserialización defensiva en SaleItemRecord, SaleRecord, Quote y CashMovementModel', () {
      // 1. SaleItemRecord con valores nulos o string 'null'
      final itemRecord = SaleItemRecord.fromJson({
        'id': 1,
        'product_id': null,
        'product_name': 'Producto Test',
        'quantity': null,
        'unit_price': null,
        'subtotal': null,
      });
      expect(itemRecord.quantity, 0.0);
      expect(itemRecord.unitPrice, 0.0);
      expect(itemRecord.subtotal, 0.0);

      // 2. SaleRecord con total nulo
      final saleRecord = SaleRecord.fromJson({
        'id': 10,
        'total': null,
        'total_surcharge': null,
        'status': 'completed',
        'created_at': '2026-10-22T10:00:00Z',
        'items': [],
        'payments': [],
      });
      expect(saleRecord.total, 0.0);
      expect(saleRecord.totalSurcharge, 0.0);

      // 3. Quote con valid_until corto o vacío sin RangeError
      final quoteShort = Quote.fromJson({
        'id': 5,
        'quote_number': 'COT-001',
        'subtotal': 100,
        'total': 100,
        'valid_until': '2026',
        'items': [],
      });
      expect(quoteShort.validUntil, '2026');

      final quoteEmpty = Quote.fromJson({
        'id': 6,
        'quote_number': 'COT-002',
        'subtotal': 100,
        'total': 100,
        'valid_until': '',
        'items': [],
      });
      expect(quoteEmpty.validUntil, '');

      // 4. CashMovementModel con id o shift_id nulos
      final cashMovement = CashMovementModel.fromJson({
        'id': null,
        'cash_shift_id': null,
        'user_id': null,
        'amount': null,
        'type': 'expense',
        'category': 'Varios',
        'created_at': null,
      });
      expect(cashMovement.id, 0);
      expect(cashMovement.cashShiftId, 0);
      expect(cashMovement.userId, 0);
      expect(cashMovement.amount, 0.0);
    });

    test('F-07: BusinessSettingsModel.toJson() incluye campos fiscales y de popularidad', () {
      const model = BusinessSettingsModel(
        companyName: 'Ferretería Test',
        taxCondition: 'responsable_inscripto',
        iibb: '901-123456-7',
        activityStartDate: '2021-03-15',
        posPopularityDays: 60,
        posPopularityMetric: 'units',
        posDemoteOutOfStock: true,
        posPopularityResetAt: '2026-10-01 00:00:00',
        globalCardPercentage: 15.0,
        globalWholesalePercentage: -10.0,
      );

      final json = model.toJson();
      expect(json['tax_condition'], 'responsable_inscripto');
      expect(json['iibb'], '901-123456-7');
      expect(json['activity_start_date'], '2021-03-15');
      expect(json['pos_popularity_days'], '60');
      expect(json['pos_popularity_metric'], 'units');
      expect(json['pos_demote_out_of_stock'], '1');
      expect(json['pos_popularity_reset_at'], '2026-10-01 00:00:00');
    });

    test('F-09: ReportsProvider.balanceMaxRevenue retorna al menos 1.0 ante meses en cero', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('balance')) {
          return http.Response(
            jsonEncode({
              'months': [
                {'month': '2026-08', 'total_revenue': 0.0, 'total_profit': 0.0},
                {'month': '2026-09', 'total_revenue': 0.0, 'total_profit': 0.0},
              ],
              'totals': {'total_revenue': 0.0},
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('[]', 200, headers: {'content-type': 'application/json'});
      });

      final dataSource = ReportsRemoteDataSource(baseUrl: 'http://localhost/api', client: mockClient);
      final balanceDataSource = InventoryAlertsDataSource(baseUrl: 'http://localhost/api', client: mockClient);
      final provider = ReportsProvider(dataSource: dataSource, balanceDataSource: balanceDataSource);

      // 1. Inicialmente con lista vacía
      expect(provider.balanceMaxRevenue, greaterThanOrEqualTo(1.0));

      // 2. Tras cargar meses con facturación 0.0
      await provider.fetchMonthlyBalance();
      expect(provider.balanceMonths.length, 2);
      expect(provider.balanceMaxRevenue, greaterThanOrEqualTo(1.0));
    });

    test('F-03: LogisticsProvider cancela _pollingTimer al invocar dispose()', () {
      final mockClient = MockClient((_) async => http.Response('[]', 200));
      final apiClient = ApiClient(mockClient);
      final repo = DeliveryNoteRepository(baseUrl: 'http://localhost/api', client: apiClient);
      final provider = LogisticsProvider(repository: repo);

      provider.startPolling();
      // Invocamos dispose: _pollingTimer debe cancelarse sin fugas ni excepciones
      expect(() => provider.dispose(), returnsNormally);
    });

    test('F-10 y Falso Negativo: CartItem unitPrice difiere de sellingPrice ante descuentos', () {
      final product = Product(
        id: 1,
        name: 'Tornillo 2 Pulgadas',
        internalCode: '00100',
        costPrice: 50.0,
        sellingPrice: 100.0,
        priceWholesale: 80.0,
        stock: 50,
        active: true,
        isSoldByWeight: false,
      );

      final cartItem = CartItem(
        product: product,
        quantity: 5,
        activeTier: PriceTier.wholesale,
      );

      // El precio unitario debe reflejar el precio mayorista bonificado ($80), no el regular ($100)
      expect(cartItem.product.sellingPrice, 100.0);
      expect(cartItem.unitPrice, 80.0);
      expect(cartItem.subtotal, 400.0);
    });

    test('F-01 y FN-F4-02: payPendingSale preserva CAE en venta fiscal y lo limpia en venta posterior no fiscal', () async {
      SharedPreferences.setMockInitialValues({});

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/payment-methods')) {
          return http.Response('[]', 200, headers: {'content-type': 'application/json'});
        }
        if (request.url.path.contains('/pay')) {
          return http.Response(
            jsonEncode({'message': 'Pagada', 'sale': {'id': 105, 'total': 1000}}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path.contains('/invoice')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'invoice': {
                'cae': '74218931284921',
                'voucher_number': 521,
                'voucher_type': 6,
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{}', 200, headers: {'content-type': 'application/json'});
      });

      final ds = PosRemoteDataSourceImpl(baseUrl: 'http://localhost/api', client: mockClient);
      final repo = PosRepositoryImpl(remoteDataSource: ds);
      final posProvider = PosProvider(
        processSaleUseCase: ProcessSaleUseCase(repo),
        searchProductsUseCase: SearchProductsUseCase(repo),
        repository: repo,
        remoteDataSource: ds,
      );

      // 1. Venta en espera #105 CON factura fiscal -> debe preservar CAE en lastElectronicInvoice
      final localTerminal = LocalTerminalProvider();
      posProvider.setPendingFiscalInvoiceData({'voucher_type': 6, 'doc_type': 99, 'doc_number': '0'});
      final okFiscal = await posProvider.payPendingSale(
        saleId: 105,
        saleTotal: 1000,
        totalSurcharge: 0,
        payments: [{'payment_method_id': 1, 'method_code': 'cash', 'amount': 1000}],
        tenderedAmount: 1000,
        changeAmount: 0,
        shiftId: 1,
        localTerminal: localTerminal,
        userName: 'Cajero',
      );
      expect(okFiscal, isTrue);
      expect(posProvider.lastElectronicInvoice, isNotNull);
      expect(posProvider.lastElectronicInvoice!['cae'], '74218931284921');

      // 2. FN-F4-02: Venta en espera #106 SIN factura fiscal -> debe limpiar lastElectronicInvoice a null
      final okNonFiscal = await posProvider.payPendingSale(
        saleId: 106,
        saleTotal: 500,
        totalSurcharge: 0,
        payments: [{'payment_method_id': 1, 'method_code': 'cash', 'amount': 500}],
        tenderedAmount: 500,
        changeAmount: 0,
        shiftId: 1,
        localTerminal: localTerminal,
        userName: 'Cajero',
      );
      expect(okNonFiscal, isTrue);
      expect(posProvider.lastElectronicInvoice, isNull);
    });
  });
}
