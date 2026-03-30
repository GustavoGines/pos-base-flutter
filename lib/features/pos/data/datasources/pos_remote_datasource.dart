import 'dart:convert';
import 'package:frontend_desktop/features/pos/domain/entities/cart_item.dart';
import 'package:http/http.dart' as http;
import 'package:frontend_desktop/features/catalog/data/models/product_model.dart';

abstract class PosRemoteDataSource {
  Future<List<ProductModel>> searchProducts(String query);
  Future<dynamic> processSale({
    required double total,
    required String paymentMethod,
    double? tenderedAmount,
    double? changeAmount,
    required int shiftId,
    required List<CartItem> items,
    int? userId,
    int? customerId,
    String status,
  });
  Future<List<dynamic>> fetchPendingSales();
  Future<dynamic> payPendingSale({
    required int saleId,
    required String paymentMethod,
    required double tenderedAmount,
    required double changeAmount,
    List<CartItem>? items,
  });
  Future<dynamic> voidPendingSale(int saleId);
}

class PosRemoteDataSourceImpl implements PosRemoteDataSource {
  final String baseUrl;
  final http.Client client;

  PosRemoteDataSourceImpl({required this.baseUrl, required this.client});

  @override
  Future<List<ProductModel>> searchProducts(String query) async {
    try {
      final uri = Uri.parse('$baseUrl/pos/products/search')
          .replace(queryParameters: {'query': query});

      final response = await client.get(
        uri,
        headers: {'Accept': 'application/json'},
      );

      if (response.statusCode == 200) {
        final List<dynamic> jsonList = json.decode(response.body);
        return jsonList.map((json) => ProductModel.fromJson(json)).toList();
      } else {
        throw Exception('Failed to search products (Status: ${response.statusCode})');
      }
    } catch (e) {
      print('=== API Error en searchProducts: $e ===');
      rethrow;
    }
  }

  @override
  Future<dynamic> processSale({
    required double total,
    required String paymentMethod,
    double? tenderedAmount,
    double? changeAmount,
    required int shiftId,
    required List<CartItem> items,
    int? userId,
    int? customerId,
    String status = 'completed',
  }) async {
    try {
      final payload = {
        'total': total,
        'payment_method': paymentMethod,
        'status': status,
        if (tenderedAmount != null) 'tendered_amount': tenderedAmount,
        if (changeAmount != null) 'change_amount': changeAmount,
        'cash_shift_id': shiftId,
        if (userId != null) 'user_id': userId,
        if (customerId != null) 'customer_id': customerId,
        'items': items.map((item) => {
          'product_id': item.product.id,
          'quantity': item.quantity,
          'unit_price': item.product.sellingPrice,
          'subtotal': item.subtotal,
        }).toList(),
      };

      final response = await client.post(
        Uri.parse('$baseUrl/pos/sales'),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json'
        },
        body: json.encode(payload),
      );

      if (response.statusCode == 201) {
        return json.decode(response.body);
      } else {
        String detail = '';
        try {
          final errBody = json.decode(response.body);
          if (errBody is Map) {
            if (errBody.containsKey('errors')) {
              final errs = errBody['errors'] as Map;
              detail = errs.values.expand((v) => v is List ? v : [v]).join(', ');
            } else if (errBody.containsKey('message')) {
              detail = errBody['message'];
            }
          }
        } catch (_) {
          detail = response.body;
        }
        throw Exception('Error al procesar venta: $detail (HTTP ${response.statusCode})');
      }
    } catch (e) {
      print('=== API Error en processSale: $e ===');
      rethrow;
    }
  }

  @override
  Future<List<dynamic>> fetchPendingSales() async {
    try {
      final response = await client.get(
        Uri.parse('$baseUrl/sales/pending'),
        headers: {'Accept': 'application/json'},
      );
      if (response.statusCode == 200) {
        return json.decode(response.body) as List<dynamic>;
      } else {
        throw Exception('Error al cargar órdenes pendientes (HTTP ${response.statusCode})');
      }
    } catch (e) {
      print('=== API Error en fetchPendingSales: $e ===');
      rethrow;
    }
  }

  @override
  Future<dynamic> payPendingSale({
    required int saleId,
    required String paymentMethod,
    required double tenderedAmount,
    required double changeAmount,
    List<CartItem>? items,
  }) async {
    try {
      final payload = {
        'payment_method': paymentMethod,
        'tendered_amount': tenderedAmount,
        'change_amount': changeAmount,
      };
      if (items != null) {
        payload['items'] = items.map((item) => {
          'product_id': item.product.id,
          'quantity': item.quantity,
          'unit_price': item.product.sellingPrice,
          'subtotal': item.subtotal,
        }).toList();
      }

      final response = await client.put(
        Uri.parse('$baseUrl/sales/$saleId/pay'),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: json.encode(payload),
      );
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        String detail = '';
        try {
          final errBody = json.decode(response.body);
          detail = errBody['message'] ?? response.body;
        } catch (_) {
          detail = response.body;
        }
        throw Exception('Error al cobrar orden: $detail (HTTP ${response.statusCode})');
      }
    } catch (e) {
      print('=== API Error en payPendingSale: $e ===');
      rethrow;
    }
  }

  @override
  Future<dynamic> voidPendingSale(int saleId) async {
    try {
      final response = await client.post(
        Uri.parse('$baseUrl/sales/$saleId/void'),
        headers: {'Accept': 'application/json'},
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return json.decode(response.body);
      } else {
        throw Exception('Error al anular orden pendiente (HTTP ${response.statusCode})');
      }
    } catch (e) {
      print('=== API Error en voidPendingSale: $e ===');
      rethrow;
    }
  }
}
