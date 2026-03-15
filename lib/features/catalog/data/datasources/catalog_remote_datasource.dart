import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/product_model.dart';
import '../models/category_model.dart';

abstract class CatalogRemoteDataSource {
  Future<List<ProductModel>> fetchProducts();
  Future<List<CategoryModel>> fetchCategories();
  // Category CRUD
  Future<CategoryModel> createCategory(String name, {String? description});
  Future<CategoryModel> updateCategory(int id, String name, {String? description});
  Future<void> deleteCategory(int id);
  // Product CRUD
  Future<ProductModel> createProduct(Map<String, dynamic> productData);
  Future<ProductModel> updateProduct(int id, Map<String, dynamic> productData);
  Future<void> deleteProduct(int id);
  Future<Map<String, dynamic>> bulkPriceUpdate({
    required double percentage,
    int? categoryId,
    int? brandId,
  });
  Future<Map<String, dynamic>> adjustStock({
    required int productId,
    required String type,
    required double quantity,
    String? notes,
  });
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
        return jsonList.map((j) => ProductModel.fromJson(j)).toList();
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
        return jsonList.map((j) => CategoryModel.fromJson(j)).toList();
      } else {
        throw Exception('Failed to load categories (Status: ${response.statusCode})');
      }
    } catch (e) {
      print('=== API Error en fetchCategories: $e ===');
      rethrow;
    }
  }

  @override
  Future<CategoryModel> createCategory(String name, {String? description}) async {
    try {
      final response = await client.post(
        Uri.parse('$baseUrl/catalog/categories'),
        headers: {'Accept': 'application/json', 'Content-Type': 'application/json'},
        body: json.encode({'name': name, if (description != null) 'description': description}),
      );
      if (response.statusCode == 201) {
        return CategoryModel.fromJson(json.decode(response.body));
      } else {
        throw Exception('Error al crear categoría: ${response.body}');
      }
    } catch (e) {
      print('=== API Error en createCategory: $e ===');
      rethrow;
    }
  }

  @override
  Future<CategoryModel> updateCategory(int id, String name, {String? description}) async {
    try {
      final response = await client.put(
        Uri.parse('$baseUrl/catalog/categories/$id'),
        headers: {'Accept': 'application/json', 'Content-Type': 'application/json'},
        body: json.encode({'name': name, if (description != null) 'description': description}),
      );
      if (response.statusCode == 200) {
        return CategoryModel.fromJson(json.decode(response.body));
      } else {
        throw Exception('Error al actualizar categoría: ${response.body}');
      }
    } catch (e) {
      print('=== API Error en updateCategory: $e ===');
      rethrow;
    }
  }

  @override
  Future<void> deleteCategory(int id) async {
    try {
      final response = await client.delete(
        Uri.parse('$baseUrl/catalog/categories/$id'),
        headers: {'Accept': 'application/json'},
      );
      if (response.statusCode == 422) {
        final error = json.decode(response.body);
        throw Exception(error['message'] ?? 'No se puede eliminar: tiene productos asociados.');
      }
      if (response.statusCode != 204) {
        throw Exception('Error al eliminar categoría (Status: ${response.statusCode})');
      }
    } catch (e) {
      print('=== API Error en deleteCategory: $e ===');
      rethrow;
    }
  }

  @override
  Future<ProductModel> createProduct(Map<String, dynamic> productData) async {
    try {
      final response = await client.post(
        Uri.parse('$baseUrl/catalog/products'),
        headers: {'Accept': 'application/json', 'Content-Type': 'application/json'},
        body: json.encode(productData),
      );
      if (response.statusCode == 201) {
        return ProductModel.fromJson(json.decode(response.body));
      } else {
        throw Exception('Failed to create product: ${response.body}');
      }
    } catch (e) {
      print('=== API Error en createProduct: $e ===');
      rethrow;
    }
  }

  @override
  Future<ProductModel> updateProduct(int id, Map<String, dynamic> productData) async {
    try {
      final response = await client.put(
        Uri.parse('$baseUrl/catalog/products/$id'),
        headers: {'Accept': 'application/json', 'Content-Type': 'application/json'},
        body: json.encode(productData),
      );
      if (response.statusCode == 200) {
        return ProductModel.fromJson(json.decode(response.body));
      } else {
        throw Exception('Failed to update product: ${response.body}');
      }
    } catch (e) {
      print('=== API Error en updateProduct: $e ===');
      rethrow;
    }
  }

  @override
  Future<void> deleteProduct(int id) async {
    try {
      final response = await client.delete(
        Uri.parse('$baseUrl/catalog/products/$id'),
        headers: {'Accept': 'application/json'},
      );
      if (response.statusCode != 204) {
        throw Exception('Failed to delete product (Status: ${response.statusCode})');
      }
    } catch (e) {
      print('=== API Error en deleteProduct: $e ===');
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> bulkPriceUpdate({
    required double percentage,
    int? categoryId,
    int? brandId,
  }) async {
    try {
      final body = <String, dynamic>{'percentage': percentage};
      if (categoryId != null) body['category_id'] = categoryId;
      if (brandId != null) body['brand_id'] = brandId;

      final response = await client.put(
        Uri.parse('$baseUrl/catalog/products/bulk-price-update'),
        headers: {'Accept': 'application/json', 'Content-Type': 'application/json'},
        body: json.encode(body),
      );
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception('Failed to bulk update prices: ${response.body}');
      }
    } catch (e) {
      print('=== API Error en bulkPriceUpdate: $e ===');
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> adjustStock({
    required int productId,
    required String type,
    required double quantity,
    String? notes,
  }) async {
    try {
      final body = <String, dynamic>{
        'type': type,
        'quantity': quantity,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      };
      final response = await client.post(
        Uri.parse('$baseUrl/catalog/products/$productId/adjust-stock'),
        headers: {'Accept': 'application/json', 'Content-Type': 'application/json'},
        body: json.encode(body),
      );
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      } else {
        final error = json.decode(response.body);
        throw Exception(error['message'] ?? 'Error al ajustar stock (${response.statusCode})');
      }
    } catch (e) {
      print('=== API Error en adjustStock: $e ===');
      rethrow;
    }
  }
}
