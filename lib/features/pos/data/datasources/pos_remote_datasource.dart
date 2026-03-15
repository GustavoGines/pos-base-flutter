import 'dart:convert';
import 'package:frontend_desktop/features/pos/domain/entities/cart_item.dart';
import 'package:http/http.dart' as http;
import 'package:frontend_desktop/features/catalog/data/models/product_model.dart';

abstract class PosRemoteDataSource {
  Future<List<ProductModel>> searchProducts(String query);
  Future<dynamic> processSale({
    required double total,
    required String paymentMethod,
    required int shiftId,
    required List<CartItem> items,
  });
}

class PosRemoteDataSourceImpl implements PosRemoteDataSource {
  final String baseUrl;
  final http.Client client;

  PosRemoteDataSourceImpl({required this.baseUrl, required this.client});

  @override
  Future<List<ProductModel>> searchProducts(String query) async {
    try {
      final response = await client.get(
        Uri.parse('$baseUrl/pos/products/search?query=$query'),
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
    required int shiftId,
    required List<CartItem> items,
  }) async {
    try {
      final payload = {
        'total': total,
        'payment_method': paymentMethod,
        'cash_register_shift_id': shiftId,
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
        throw Exception('Failed to process sale (Status: ${response.statusCode})');
      }
    } catch (e) {
      print('=== API Error en processSale: $e ===');
      rethrow;
    }
  }
}
