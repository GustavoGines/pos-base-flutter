import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/product_model.dart';
import '../models/category_model.dart';

abstract class CatalogRemoteDataSource {
  Future<List<ProductModel>> fetchProducts();
  Future<List<CategoryModel>> fetchCategories();
}

class CatalogRemoteDataSourceImpl implements CatalogRemoteDataSource {
  final String baseUrl;
  final http.Client client;

  CatalogRemoteDataSourceImpl({required this.baseUrl, required this.client});

  @override
  Future<List<ProductModel>> fetchProducts() async {
    try {
      final response = await client.get(
        Uri.parse('$baseUrl/catalog/products'),
        headers: {'Accept': 'application/json'},
      );

      if (response.statusCode == 200) {
        final List<dynamic> jsonList = json.decode(response.body);
        return jsonList.map((json) => ProductModel.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load products (Status: ${response.statusCode})');
      }
    } catch (e) {
      print('=== API Error en fetchProducts: $e ===');
      rethrow;
    }
  }

  @override
  Future<List<CategoryModel>> fetchCategories() async {
    try {
      final response = await client.get(
        Uri.parse('$baseUrl/catalog/categories'),
        headers: {'Accept': 'application/json'},
      );

      if (response.statusCode == 200) {
        final List<dynamic> jsonList = json.decode(response.body);
        return jsonList.map((json) => CategoryModel.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load categories (Status: ${response.statusCode})');
      }
    } catch (e) {
      print('=== API Error en fetchCategories: $e ===');
      rethrow;
    }
  }
}
