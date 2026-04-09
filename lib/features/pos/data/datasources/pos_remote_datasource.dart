import 'dart:convert';
import 'package:frontend_desktop/features/pos/domain/entities/cart_item.dart';
import 'package:http/http.dart' as http;
import 'package:frontend_desktop/features/catalog/data/models/product_model.dart';

/// Excepción tipada que se lanza cuando el backend rechaza una venta
/// porque el turno de caja ya fue cerrado desde otra terminal.
/// Permite a la capa superior distinguir este error crítico de seguridad
/// de un error de red genérico y forzar la recarga del estado.
class ClosedShiftException implements Exception {
  final String message;
  const ClosedShiftException(this.message);
  @override
  String toString() => message;
}

abstract class PosRemoteDataSource {
  Future<List<ProductModel>> searchProducts(String query);
  Future<List<dynamic>> fetchPaymentMethods();
  Future<dynamic> processSale({
    required double total,
    required double totalSurcharge,
    List<Map<String, dynamic>>? payments,
    double? tenderedAmount,
    double? changeAmount,
    required int shiftId,
    required List<CartItem> items,
    int? userId,
    int? customerId,
    int? quoteId,
    String status,
  });
  Future<List<dynamic>> fetchPendingSales();
  Future<dynamic> payPendingSale({
    required int saleId,
    required double totalSurcharge,
    required List<Map<String, dynamic>> payments,
    required double tenderedAmount,
    required double changeAmount,
    int? userId,
    List<CartItem>? items,
  });
  Future<dynamic> voidPendingSale(int saleId);
  Future<void> updatePaymentMethodSurcharge(int id, double surchargeValue);
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
  Future<List<dynamic>> fetchPaymentMethods() async {
    try {
      final response = await client.get(
        Uri.parse('$baseUrl/payment-methods'),
        headers: {'Accept': 'application/json'},
      );
      if (response.statusCode == 200) {
        return json.decode(response.body) as List<dynamic>;
      } else {
        throw Exception('Error al cargar métodos de pago (HTTP ${response.statusCode})');
      }
    } catch (e) {
      print('=== API Error en fetchPaymentMethods: $e ===');
      rethrow;
    }
  }

  @override
  Future<void> updatePaymentMethodSurcharge(int id, double surchargeValue) async {
    try {
      final response = await client.put(
        Uri.parse('$baseUrl/payment-methods/$id'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: json.encode({'surcharge_value': surchargeValue}),
      );
      if (response.statusCode != 200) {
        throw Exception('Error al actualizar recargo (HTTP ${response.statusCode})');
      }
    } catch (e) {
      print('=== API Error en updatePaymentMethodSurcharge: $e ===');
      rethrow;
    }
  }

  @override
  Future<dynamic> processSale({
    required double total,
    required double totalSurcharge,
    List<Map<String, dynamic>>? payments,
    double? tenderedAmount,
    double? changeAmount,
    required int shiftId,
    required List<CartItem> items,
    int? userId,
    int? customerId,
    int? quoteId,
    String status = 'completed',
  }) async {
    try {
      final payload = {
        'total': total,
        'total_surcharge': totalSurcharge,
        if (payments != null) 'payments': payments,
        'status': status,
        if (tenderedAmount != null) 'tendered_amount': tenderedAmount,
        if (changeAmount != null) 'change_amount': changeAmount,
        'cash_shift_id': shiftId,
        if (userId != null) 'user_id': userId,
        if (customerId != null) 'customer_id': customerId,
        if (quoteId != null) 'quote_id': quoteId,
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
        bool isClosedShift = false;
        try {
          final errBody = json.decode(response.body);
          if (errBody is Map) {
            if (errBody.containsKey('errors')) {
              final errs = errBody['errors'] as Map;
              // Detectar específicamente el error de turno cerrado
              if (errs.containsKey('cash_shift_id')) {
                isClosedShift = true;
                detail = (errs['cash_shift_id'] as List).first.toString();
              } else {
                detail = errs.values.expand((v) => v is List ? v : [v]).join(', ');
              }
            } else if (errBody.containsKey('message')) {
              detail = errBody['message'];
            }
          }
        } catch (_) {
          detail = response.body;
        }

        // Lanzar excepción tipada para que el Provider pueda reaccionar específicamente
        if (isClosedShift) {
          throw ClosedShiftException(detail);
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
    required double totalSurcharge,
    required List<Map<String, dynamic>> payments,
    required double tenderedAmount,
    required double changeAmount,
    int? userId,
    List<CartItem>? items,
  }) async {
    try {
      final payload = {
        'total_surcharge': totalSurcharge,
        'payments': payments,
        'tendered_amount': tenderedAmount,
        'change_amount': changeAmount,
        if (userId != null) 'user_id': userId,
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
