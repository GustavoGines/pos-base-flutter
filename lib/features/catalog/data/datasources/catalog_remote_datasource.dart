import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:frontend_desktop/core/utils/image_url_resolver.dart';
import '../models/product_model.dart';
import '../models/product_batch_model.dart';
import '../models/production_order_model.dart';
import '../models/category_model.dart';
import '../models/brand_model.dart';
import '../models/rubro_model.dart';

class CatalogHttpException implements Exception {
  final int statusCode;
  final String message;

  const CatalogHttpException(this.statusCode, this.message);

  bool get isClientError => statusCode >= 400 && statusCode < 500;

  @override
  String toString() => message;
}

abstract class CatalogRemoteDataSource {
  /// Returns a map with 'data' (`List<ProductModel>`), 'current_page', 'last_page'.
  Future<Map<String, dynamic>> fetchProducts({
    int page = 1,
    String? search,
    String? sortBy,
    String? sortDirection,
    int? perPage,
    int? categoryId,
    int? brandId,
    int? supplierId,
    bool? active,
    bool? isSoldByWeight,
    List<int>? ids,
  });
  Future<List<CategoryModel>> fetchCategories();
  // Rubro CRUD
  Future<List<RubroModel>> fetchRubros();
  Future<RubroModel> createRubro(String name, {String? description});
  Future<RubroModel> updateRubro(int id, String name, {String? description});
  Future<void> deleteRubro(int id);
  // Brand CRUD
  Future<List<BrandModel>> fetchBrands();
  Future<BrandModel> createBrand(String name, {String? description});
  Future<BrandModel> updateBrand(int id, String name, {String? description});
  Future<void> deleteBrand(int id);
  // Category CRUD
  Future<CategoryModel> createCategory(String name, {String? description, int? rubroId});
  Future<CategoryModel> updateCategory(int id, String name, {String? description, int? rubroId});
  Future<void> deleteCategory(int id);
  // Product CRUD
  Future<ProductModel> createProduct(Map<String, dynamic> productData);
  Future<ProductModel> updateProduct(int id, Map<String, dynamic> productData);
  Future<Map<String, dynamic>> importProducts(List<int> fileBytes, String filename);
  Future<void> deleteProduct(int id);
  Future<Map<String, dynamic>> bulkDeleteProducts(List<int> ids);
  Future<Map<String, dynamic>> bulkUpdateProducts(
    List<int> ids, {
    int? categoryId,
    bool clearCategory = false,
    int? brandId,
    bool clearBrand = false,
    bool? active,
    int? supplierId,
    bool clearSupplier = false,
  });
  Future<Map<String, dynamic>> bulkPriceUpdate({
    required double percentage,
    required String roundingRule,
    String? targetField,
    List<int>? productIds,
    int? categoryId,
    int? brandId,
    int? supplierId,
  });
  Future<Map<String, dynamic>> bulkPricePreview({
    required double percentage,
    required String roundingRule,
    String? targetField,
    List<int>? productIds,
    int? categoryId,
    int? brandId,
    int? supplierId,
  });
  Future<List<dynamic>> getBulkPriceHistory();
  Future<String> revertBulkPrice(int historyId);
  Future<Map<String, dynamic>> adjustStock({
    required int productId,
    required String type,
    required double quantity,
    double? minStock,
    String? notes,
    int? batchId,
    String? batchCode,
    String? expirationDate,
    String? manufacturedAt,
    double? unitCost,
    String? reasonCode,
  });
  Future<ProductBatchesResponse> fetchProductBatches(
    int productId, {
    bool includeClosed = true,
  });
  Future<Map<String, dynamic>> createProductBatch(
    int productId, {
    required double quantity,
    String? batchCode,
    String? manufacturedAt,
    String? expirationDate,
    double? unitCost,
    String? notes,
  });
  Future<Map<String, dynamic>> updateProductBatch(
    int batchId, {
    String? batchCode,
    String? manufacturedAt,
    String? expirationDate,
    double? unitCost,
    String? notes,
  });
  Future<Map<String, dynamic>> writeOffBatch(
    int batchId, {
    double? quantity,
    String? notes,
  });
  Future<Map<String, dynamic>> fetchExpiredBatches({bool includeToday = true});
  Future<Map<String, dynamic>> splitBatch(
    int batchId, {
    required double quantity,
    String? expirationDate,
    String? batchCode,
    String? notes,
  });
  Future<Map<String, dynamic>> writeOffExpiredBatches({
    List<Map<String, dynamic>>? items,
    bool includeToday = true,
    String? notes,
  });
  Future<Map<String, dynamic>> fetchProductionOrders({
    int page = 1,
    int? productId,
    String? status,
    String? search,
  });
  Future<ProductionOrderModel> createProductionOrder(Map<String, dynamic> payload);
  Future<Map<String, dynamic>> createBatchProductionOrders(Map<String, dynamic> payload);
  Future<ProductionOrderModel> voidProductionOrder(int orderId);
  Future<Map<String, dynamic>> fetchWasteReport({
    String? startDate,
    String? endDate,
  });
  Future<List<ProductModel>> fetchCriticalAlerts();
  /// Returns [{id: int, stock: double}] for the given product IDs. Ultra-lightweight.
  Future<List<Map<String, dynamic>>> fetchBulkStock(List<int> ids);
  Future<String> uploadProductImage(int productId, String filePath, {List<int>? bytes, String? filename});
  Future<void> deleteProductImage(int productId);
  Future<ProductModel> updateProductCalcConfig(int productId, Map<String, dynamic>? calcConfig);
}

class CatalogRemoteDataSourceImpl implements CatalogRemoteDataSource {
  final String baseUrl;
  final http.Client client;

  CatalogRemoteDataSourceImpl({required this.baseUrl, required this.client});

  String _parseApiError(String responseBody, String defaultMsg) {
    try {
      final decoded = json.decode(responseBody);
      if (decoded is Map<String, dynamic>) {
        if (decoded.containsKey('errors')) {
          final errors = decoded['errors'] as Map<String, dynamic>;
          if (errors.isNotEmpty) {
            final firstError = errors.values.first;
            if (firstError is List && firstError.isNotEmpty) {
              final msg = firstError.first.toString();
              if (msg.contains('validation.unique')) return 'El nombre ya existe.';
              return msg;
            }
          }
        }
        if (decoded.containsKey('message')) {
          final msg = decoded['message'].toString();
          if (msg.contains('validation.unique')) return 'El nombre ya existe.';
          return msg;
        }
      }
    } catch (_) {}
    return defaultMsg;
  }

  @override
  Future<Map<String, dynamic>> fetchProducts({
    int page = 1,
    String? search,
    String? sortBy,
    String? sortDirection,
    int? perPage,
    int? categoryId,
    int? brandId,
    int? supplierId,
    bool? active,
    bool? isSoldByWeight,
    List<int>? ids,
  }) async {
    try {
      final queryParams = <String, String>{'page': page.toString()};
      if (search != null && search.isNotEmpty) queryParams['search'] = search;
      if (sortBy != null && sortBy.isNotEmpty) {
        queryParams['sort_by'] = sortBy;
        if (sortDirection != null && sortDirection.isNotEmpty) {
          queryParams['sort_direction'] = sortDirection;
        }
      }
      if (perPage != null) queryParams['per_page'] = perPage.toString();
      if (categoryId != null) queryParams['category_id'] = categoryId.toString();
      if (brandId != null) queryParams['brand_id'] = brandId.toString();
      if (supplierId != null) queryParams['supplier_id'] = supplierId.toString();
      if (active != null) queryParams['active'] = active ? '1' : '0';
      if (isSoldByWeight != null) queryParams['is_sold_by_weight'] = isSoldByWeight ? '1' : '0';
      if (ids != null && ids.isNotEmpty) queryParams['ids'] = ids.join(',');

      final uri = Uri.parse('$baseUrl/catalog/products').replace(queryParameters: queryParams);
      final response = await client.get(uri, headers: {'Accept': 'application/json'});

      if (response.statusCode == 200) {
        final Map<String, dynamic> json = jsonDecode(response.body);
        final List<dynamic> dataList = json['data'] as List<dynamic>;
        return {
          'data': dataList.map((j) => ProductModel.fromJson(j)).toList(),
          'current_page': json['current_page'] as int,
          'last_page': json['last_page'] as int,
        };
      } else {
        throw Exception('Failed to load products (Status: ${response.statusCode})');
      }
    } catch (e) {
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
      debugPrint('=== API Error en fetchCategories: $e ===');
      rethrow;
    }
  }

  @override
  Future<List<BrandModel>> fetchBrands() async {
    try {
      final response = await client.get(
        Uri.parse('$baseUrl/catalog/brands'),
        headers: {'Accept': 'application/json'},
      );
      if (response.statusCode == 200) {
        final List<dynamic> jsonList = json.decode(response.body);
        return jsonList.map((j) => BrandModel.fromJson(j)).toList();
      } else {
        throw Exception('Failed to load brands (Status: ${response.statusCode})');
      }
    } catch (e) {
      debugPrint('=== API Error en fetchBrands: $e ===');
      rethrow;
    }
  }

  @override
  Future<BrandModel> createBrand(String name, {String? description}) async {
    try {
      final response = await client.post(
        Uri.parse('$baseUrl/catalog/brands'),
        headers: {'Accept': 'application/json', 'Content-Type': 'application/json'},
        body: json.encode({'name': name, if (description != null) 'description': description}),
      );
      if (response.statusCode == 201) {
        return BrandModel.fromJson(json.decode(response.body));
      } else {
        throw Exception(_parseApiError(response.body, 'Error al crear marca.'));
      }
    } catch (e) {
      debugPrint('=== API Error en createBrand: $e ===');
      rethrow;
    }
  }

  @override
  Future<BrandModel> updateBrand(int id, String name, {String? description}) async {
    try {
      final response = await client.put(
        Uri.parse('$baseUrl/catalog/brands/$id'),
        headers: {'Accept': 'application/json', 'Content-Type': 'application/json'},
        body: json.encode({'name': name, if (description != null) 'description': description}),
      );
      if (response.statusCode == 200) {
        return BrandModel.fromJson(json.decode(response.body));
      } else {
        throw Exception(_parseApiError(response.body, 'Error al actualizar marca.'));
      }
    } catch (e) {
      debugPrint('=== API Error en updateBrand: $e ===');
      rethrow;
    }
  }

  @override
  Future<void> deleteBrand(int id) async {
    try {
      final response = await client.delete(
        Uri.parse('$baseUrl/catalog/brands/$id'),
        headers: {'Accept': 'application/json'},
      );
      if (response.statusCode == 422) {
        final error = json.decode(response.body);
        throw Exception(error['message'] ?? 'No se puede eliminar: tiene productos asociados.');
      }
      if (response.statusCode != 204) {
        throw Exception('Error al eliminar marca (Status: ${response.statusCode})');
      }
    } catch (e) {
      debugPrint('=== API Error en deleteBrand: $e ===');
      rethrow;
    }
  }

  // ── Rubro CRUD ──────────────────────────────────────────
  @override
  Future<List<RubroModel>> fetchRubros() async {
    try {
      final response = await client.get(
        Uri.parse('$baseUrl/catalog/rubros'),
        headers: {'Accept': 'application/json'},
      );
      if (response.statusCode == 200) {
        final List<dynamic> jsonList = json.decode(response.body);
        return jsonList.map((j) => RubroModel.fromJson(j)).toList();
      } else {
        throw Exception('Failed to load rubros (Status: ${response.statusCode})');
      }
    } catch (e) {
      debugPrint('=== API Error en fetchRubros: $e ===');
      rethrow;
    }
  }

  @override
  Future<RubroModel> createRubro(String name, {String? description}) async {
    try {
      final response = await client.post(
        Uri.parse('$baseUrl/catalog/rubros'),
        headers: {'Accept': 'application/json', 'Content-Type': 'application/json'},
        body: json.encode({'name': name, if (description != null) 'description': description}),
      );
      if (response.statusCode == 201) {
        return RubroModel.fromJson(json.decode(response.body));
      } else {
        throw Exception(_parseApiError(response.body, 'Error al crear rubro.'));
      }
    } catch (e) {
      debugPrint('=== API Error en createRubro: $e ===');
      rethrow;
    }
  }

  @override
  Future<RubroModel> updateRubro(int id, String name, {String? description}) async {
    try {
      final response = await client.put(
        Uri.parse('$baseUrl/catalog/rubros/$id'),
        headers: {'Accept': 'application/json', 'Content-Type': 'application/json'},
        body: json.encode({'name': name, if (description != null) 'description': description}),
      );
      if (response.statusCode == 200) {
        return RubroModel.fromJson(json.decode(response.body));
      } else {
        throw Exception(_parseApiError(response.body, 'Error al actualizar rubro.'));
      }
    } catch (e) {
      debugPrint('=== API Error en updateRubro: $e ===');
      rethrow;
    }
  }

  @override
  Future<void> deleteRubro(int id) async {
    try {
      final response = await client.delete(
        Uri.parse('$baseUrl/catalog/rubros/$id'),
        headers: {'Accept': 'application/json'},
      );
      if (response.statusCode == 422) {
        final error = json.decode(response.body);
        throw Exception(error['message'] ?? 'No se puede eliminar: tiene categorías asociadas.');
      }
      if (response.statusCode != 204 && response.statusCode != 200) {
        throw Exception('Error al eliminar rubro (Status: ${response.statusCode})');
      }
    } catch (e) {
      debugPrint('=== API Error en deleteRubro: $e ===');
      rethrow;
    }
  }

  @override
  Future<CategoryModel> createCategory(String name, {String? description, int? rubroId}) async {
    try {
      final response = await client.post(
        Uri.parse('$baseUrl/catalog/categories'),
        headers: {'Accept': 'application/json', 'Content-Type': 'application/json'},
        body: json.encode({
          'name': name,
          if (description != null) 'description': description,
          if (rubroId != null) 'rubro_id': rubroId,
        }),
      );
      if (response.statusCode == 201) {
        return CategoryModel.fromJson(json.decode(response.body));
      } else {
        throw Exception(_parseApiError(response.body, 'Error al crear categoría.'));
      }
    } catch (e) {
      debugPrint('=== API Error en createCategory: $e ===');
      rethrow;
    }
  }

  @override
  Future<CategoryModel> updateCategory(int id, String name, {String? description, int? rubroId}) async {
    try {
      final response = await client.put(
        Uri.parse('$baseUrl/catalog/categories/$id'),
        headers: {'Accept': 'application/json', 'Content-Type': 'application/json'},
        body: json.encode({
          'name': name,
          if (description != null) 'description': description,
          if (rubroId != null) 'rubro_id': rubroId,
        }),
      );
      if (response.statusCode == 200) {
        return CategoryModel.fromJson(json.decode(response.body));
      } else {
        throw Exception(_parseApiError(response.body, 'Error al actualizar categoría.'));
      }
    } catch (e) {
      debugPrint('=== API Error en updateCategory: $e ===');
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
      debugPrint('=== API Error en deleteCategory: $e ===');
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
        throw Exception(_parseApiError(response.body, 'Error al crear producto.'));
      }
    } catch (e) {
      debugPrint('=== API Error en createProduct: $e ===');
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
        throw Exception(_parseApiError(response.body, 'Error al actualizar producto.'));
      }
    } catch (e) {
      debugPrint('=== API Error en updateProduct: $e ===');
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
      debugPrint('=== API Error en deleteProduct: $e ===');
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> bulkDeleteProducts(List<int> ids) async {
    try {
      final response = await client.post(
        Uri.parse('$baseUrl/catalog/products/bulk-delete'),
        headers: {'Accept': 'application/json', 'Content-Type': 'application/json'},
        body: json.encode({'product_ids': ids}),
      );
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception('Error al eliminar productos: ${response.body}');
      }
    } catch (e) {
      debugPrint('=== API Error en bulkDeleteProducts: $e ===');
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> bulkUpdateProducts(
    List<int> ids, {
    int? categoryId,
    bool clearCategory = false,
    int? brandId,
    bool clearBrand = false,
    bool? active,
    int? supplierId,
    bool clearSupplier = false,
  }) async {
    try {
      final body = <String, dynamic>{'product_ids': ids};
      if (clearCategory) {
        body['category_id'] = null;
      } else if (categoryId != null) {
        body['category_id'] = categoryId;
      }

      if (clearBrand) {
        body['brand_id'] = null;
      } else if (brandId != null) {
        body['brand_id'] = brandId;
      }

      if (clearSupplier) {
        body['supplier_id'] = null;
      } else if (supplierId != null) {
        body['supplier_id'] = supplierId;
      }

      if (active != null) body['active'] = active;

      final response = await client.post(
        Uri.parse('$baseUrl/catalog/bulk-update'),
        headers: {'Accept': 'application/json', 'Content-Type': 'application/json'},
        body: json.encode(body),
      );
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception('Error al actualizar productos masivamente: ${response.body}');
      }
    } catch (e) {
      debugPrint('=== API Error en bulkUpdateProducts: $e ===');
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> bulkPriceUpdate({
    required double percentage,
    required String roundingRule,
    String? targetField,
    List<int>? productIds,
    int? categoryId,
    int? brandId,
    int? supplierId,
  }) async {
    try {
      final body = <String, dynamic>{
        'percentage': percentage,
        'rounding_rule': roundingRule,
      };
      if (targetField != null) body['target_field'] = targetField;
      if (productIds != null && productIds.isNotEmpty) body['product_ids'] = productIds;
      if (categoryId != null) body['category_id'] = categoryId;
      if (brandId != null) body['brand_id'] = brandId;
      if (supplierId != null) body['supplier_id'] = supplierId;

      final response = await client.put(
        Uri.parse('$baseUrl/catalog/products/bulk-price-update'),
        headers: {'Accept': 'application/json', 'Content-Type': 'application/json'},
        body: json.encode(body),
      );
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception('Error al actualizar precios masivamente: ${response.body}');
      }
    } catch (e) {
      debugPrint('=== API Error en bulkPriceUpdate: $e ===');
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> bulkPricePreview({
    required double percentage,
    required String roundingRule,
    String? targetField,
    List<int>? productIds,
    int? categoryId,
    int? brandId,
    int? supplierId,
  }) async {
    try {
      final body = <String, dynamic>{
        'percentage': percentage,
        'rounding_rule': roundingRule,
      };
      if (targetField != null) body['target_field'] = targetField;
      if (productIds != null && productIds.isNotEmpty) body['product_ids'] = productIds;
      if (categoryId != null) body['category_id'] = categoryId;
      if (brandId != null) body['brand_id'] = brandId;
      if (supplierId != null) body['supplier_id'] = supplierId;

      final response = await client.post(
        Uri.parse('$baseUrl/catalog/products/bulk-price-preview'),
        headers: {'Accept': 'application/json', 'Content-Type': 'application/json'},
        body: json.encode(body),
      );
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception('Error al previsualizar la actualización de precios: ${response.body}');
      }
    } catch (e) {
      debugPrint('=== API Error en bulkPricePreview: $e ===');
      rethrow;
    }
  }

  @override
  Future<List<dynamic>> getBulkPriceHistory() async {
    final response = await client.get(Uri.parse('$baseUrl/catalog/bulk-price-history'));
    if (response.statusCode == 200) {
      return json.decode(response.body) as List<dynamic>;
    }
    throw Exception('Error al cargar el historial de aumentos de precios');
  }

  @override
  Future<String> revertBulkPrice(int historyId) async {
    final response = await client.post(Uri.parse('$baseUrl/catalog/bulk-price-history/$historyId/revert'));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['message'] ?? 'Revertido con éxito';
    }
    throw Exception('Error al revertir el aumento de precios: ${response.body}');
  }

  @override
  Future<Map<String, dynamic>> adjustStock({
    required int productId,
    required String type,
    required double quantity,
    double? minStock,
    String? notes,
    int? batchId,
    String? batchCode,
    String? expirationDate,
    String? manufacturedAt,
    double? unitCost,
    String? reasonCode,
  }) async {
    try {
      final body = <String, dynamic>{
        'type': type,
        'quantity': quantity,
        if (minStock != null) 'min_stock': minStock,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
        if (batchId != null) 'batch_id': batchId,
        if (batchCode != null && batchCode.isNotEmpty) 'batch_code': batchCode,
        if (expirationDate != null && expirationDate.isNotEmpty)
          'expiration_date': expirationDate,
        if (manufacturedAt != null && manufacturedAt.isNotEmpty)
          'manufactured_at': manufacturedAt,
        if (unitCost != null) 'unit_cost': unitCost,
        if (reasonCode != null && reasonCode.isNotEmpty) 'reason_code': reasonCode,
      };
      final response = await client.post(
        Uri.parse('$baseUrl/catalog/products/$productId/adjust-stock'),
        headers: {'Accept': 'application/json', 'Content-Type': 'application/json'},
        body: json.encode(body),
      );
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception(_parseApiError(
            response.body, 'Error al ajustar stock (${response.statusCode})'));
      }
    } catch (e) {
      debugPrint('=== API Error en adjustStock: $e ===');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _sendBatchJsonRequest({
    required String method,
    required String path,
    required Map<String, dynamic> body,
    required String fallbackError,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final headers = {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
    final encoded = json.encode(body);
    final http.Response response;
    if (method == 'PATCH') {
      response = await client.patch(uri, headers: headers, body: encoded);
    } else {
      response = await client.post(uri, headers: headers, body: encoded);
    }
    if (response.statusCode == 200 || response.statusCode == 201) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    throw Exception(_parseApiError(response.body, fallbackError));
  }

  @override
  Future<ProductBatchesResponse> fetchProductBatches(
    int productId, {
    bool includeClosed = true,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/catalog/products/$productId/batches')
          .replace(queryParameters: {'include_closed': includeClosed ? '1' : '0'});
      final response = await client.get(uri, headers: {'Accept': 'application/json'});
      if (response.statusCode == 200) {
        return ProductBatchesResponse.fromJson(
          json.decode(response.body) as Map<String, dynamic>,
        );
      }
      throw Exception(_parseApiError(
          response.body, 'Error al cargar lotes (${response.statusCode})'));
    } catch (e) {
      debugPrint('=== API Error en fetchProductBatches: $e ===');
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> createProductBatch(
    int productId, {
    required double quantity,
    String? batchCode,
    String? manufacturedAt,
    String? expirationDate,
    double? unitCost,
    String? notes,
  }) async {
    try {
      return await _sendBatchJsonRequest(
        method: 'POST',
        path: '/catalog/products/$productId/batches',
        body: {
          'quantity': quantity,
          if (batchCode != null && batchCode.isNotEmpty) 'batch_code': batchCode,
          if (manufacturedAt != null && manufacturedAt.isNotEmpty)
            'manufactured_at': manufacturedAt,
          if (expirationDate != null && expirationDate.isNotEmpty)
            'expiration_date': expirationDate,
          if (unitCost != null) 'unit_cost': unitCost,
          if (notes != null && notes.isNotEmpty) 'notes': notes,
        },
        fallbackError: 'Error al registrar lote.',
      );
    } catch (e) {
      debugPrint('=== API Error en createProductBatch: $e ===');
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> updateProductBatch(
    int batchId, {
    String? batchCode,
    String? manufacturedAt,
    String? expirationDate,
    double? unitCost,
    String? notes,
  }) async {
    try {
      return await _sendBatchJsonRequest(
        method: 'PATCH',
        path: '/batches/$batchId',
        body: {
          if (batchCode != null) 'batch_code': batchCode,
          if (manufacturedAt != null) 'manufactured_at': manufacturedAt,
          if (expirationDate != null) 'expiration_date': expirationDate,
          if (unitCost != null) 'unit_cost': unitCost,
          if (notes != null) 'notes': notes,
        },
        fallbackError: 'Error al actualizar lote.',
      );
    } catch (e) {
      debugPrint('=== API Error en updateProductBatch: $e ===');
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> writeOffBatch(
    int batchId, {
    double? quantity,
    String? notes,
  }) async {
    try {
      return await _sendBatchJsonRequest(
        method: 'POST',
        path: '/batches/$batchId/write-off',
        body: {
          if (quantity != null) 'quantity': quantity,
          if (notes != null && notes.isNotEmpty) 'notes': notes,
        },
        fallbackError: 'Error al registrar merma del lote.',
      );
    } catch (e) {
      debugPrint('=== API Error en writeOffBatch: $e ===');
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> fetchExpiredBatches({bool includeToday = true}) async {
    try {
      final uri = Uri.parse('$baseUrl/batches/expired').replace(
        queryParameters: {'include_today': includeToday ? '1' : '0'},
      );
      final response = await client.get(uri, headers: {'Accept': 'application/json'});
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
      throw Exception(_parseApiError(
          response.body, 'Error al cargar lotes vencidos (${response.statusCode})'));
    } catch (e) {
      debugPrint('=== API Error en fetchExpiredBatches: $e ===');
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> splitBatch(
    int batchId, {
    required double quantity,
    String? expirationDate,
    String? batchCode,
    String? notes,
  }) async {
    try {
      return await _sendBatchJsonRequest(
        method: 'POST',
        path: '/batches/$batchId/split',
        body: {
          'quantity': quantity,
          if (expirationDate != null && expirationDate.isNotEmpty)
            'expiration_date': expirationDate,
          if (batchCode != null && batchCode.isNotEmpty) 'batch_code': batchCode,
          if (notes != null && notes.isNotEmpty) 'notes': notes,
        },
        fallbackError: 'Error al dividir lote hacia vitrina.',
      );
    } catch (e) {
      debugPrint('=== API Error en splitBatch: $e ===');
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> writeOffExpiredBatches({
    List<Map<String, dynamic>>? items,
    bool includeToday = true,
    String? notes,
  }) async {
    try {
      return await _sendBatchJsonRequest(
        method: 'POST',
        path: '/batches/write-off-expired',
        body: {
          'include_today': includeToday,
          if (items != null) 'items': items,
          if (notes != null && notes.isNotEmpty) 'notes': notes,
        },
        fallbackError: 'Error al realizar barrido masivo de vencidos.',
      );
    } catch (e) {
      debugPrint('=== API Error en writeOffExpiredBatches: $e ===');
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> fetchProductionOrders({
    int page = 1,
    int? productId,
    String? status,
    String? search,
  }) async {
    try {
      final params = <String, String>{'page': page.toString()};
      if (productId != null) params['product_id'] = productId.toString();
      if (status != null && status.isNotEmpty) params['status'] = status;
      if (search != null && search.isNotEmpty) params['search'] = search;
      final uri = Uri.parse('$baseUrl/production-orders').replace(queryParameters: params);
      final response = await client.get(uri, headers: {'Accept': 'application/json'});
      if (response.statusCode == 200) {
        final decoded = json.decode(response.body) as Map<String, dynamic>;
        final rawData = (decoded['data'] as List?) ?? const [];
        return {
          'data': rawData
              .whereType<Map>()
              .map((e) => ProductionOrderModel.fromJson(Map<String, dynamic>.from(e)))
              .toList(),
          'current_page': (decoded['current_page'] as num?)?.toInt() ?? 1,
          'last_page': (decoded['last_page'] as num?)?.toInt() ?? 1,
          'total': (decoded['total'] as num?)?.toInt() ?? rawData.length,
        };
      }
      throw Exception(_parseApiError(
          response.body, 'Error al cargar órdenes de producción (${response.statusCode})'));
    } catch (e) {
      debugPrint('=== API Error en fetchProductionOrders: $e ===');
      rethrow;
    }
  }

  @override
  Future<ProductionOrderModel> createProductionOrder(Map<String, dynamic> payload) async {
    try {
      final decoded = await _sendBatchJsonRequest(
        method: 'POST',
        path: '/production-orders',
        body: payload,
        fallbackError: 'Error al registrar orden de producción.',
      );
      final rawOrder = decoded['order'] ?? decoded;
      return ProductionOrderModel.fromJson(Map<String, dynamic>.from(rawOrder as Map));
    } catch (e) {
      debugPrint('=== API Error en createProductionOrder: $e ===');
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> createBatchProductionOrders(Map<String, dynamic> payload) async {
    try {
      final decoded = await _sendBatchJsonRequest(
        method: 'POST',
        path: '/production-orders/batch',
        body: payload,
        fallbackError: 'Error al registrar planilla de producción.',
      );
      final rawOrders = (decoded['orders'] as List?) ?? const [];
      final parsedOrders = rawOrders
          .whereType<Map>()
          .map((e) => ProductionOrderModel.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      return {
        ...decoded,
        'orders': parsedOrders,
      };
    } catch (e) {
      debugPrint('=== API Error en createBatchProductionOrders: $e ===');
      rethrow;
    }
  }

  @override
  Future<ProductionOrderModel> voidProductionOrder(int orderId) async {
    try {
      final decoded = await _sendBatchJsonRequest(
        method: 'POST',
        path: '/production-orders/$orderId/void',
        body: const {},
        fallbackError: 'Error al anular orden de producción.',
      );
      final rawOrder = decoded['order'] ?? decoded;
      return ProductionOrderModel.fromJson(Map<String, dynamic>.from(rawOrder as Map));
    } catch (e) {
      debugPrint('=== API Error en voidProductionOrder: $e ===');
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> fetchWasteReport({
    String? startDate,
    String? endDate,
  }) async {
    try {
      final params = <String, String>{};
      if (startDate != null && startDate.isNotEmpty) params['start_date'] = startDate;
      if (endDate != null && endDate.isNotEmpty) params['end_date'] = endDate;
      final uri = Uri.parse('$baseUrl/reports/waste')
          .replace(queryParameters: params.isEmpty ? null : params);
      final response = await client.get(uri, headers: {'Accept': 'application/json'});
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
      throw Exception(_parseApiError(
          response.body, 'Error al cargar reporte de mermas (${response.statusCode})'));
    } catch (e) {
      debugPrint('=== API Error en fetchWasteReport: $e ===');
      rethrow;
    }
  }

  @override
  Future<List<ProductModel>> fetchCriticalAlerts() async {
    try {
      final response = await client.get(
        Uri.parse('$baseUrl/catalog/products/alerts/critical'),
        headers: {'Accept': 'application/json'},
      );
      if (response.statusCode == 200) {
        final List<dynamic> jsonList = json.decode(response.body);
        return jsonList.map((j) => ProductModel.fromJson(j)).toList();
      } else {
        throw Exception('Error al cargar alertas críticas (${response.statusCode})');
      }
    } catch (e) {
      debugPrint('=== API Error en fetchCriticalAlerts: $e ===');
      rethrow;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> fetchBulkStock(List<int> ids) async {
    if (ids.isEmpty) return [];
    try {
      final uri = Uri.parse('$baseUrl/catalog/products/stock')
          .replace(queryParameters: {'ids': ids.join(',')});
      final response = await client.get(uri, headers: {'Accept': 'application/json'});
      if (response.statusCode == 200) {
        final List<dynamic> jsonList = json.decode(response.body);
        return jsonList.cast<Map<String, dynamic>>();
      } else {
        throw Exception('Error al obtener stock bulk (${response.statusCode})');
      }
    } catch (e) {
      debugPrint('=== API Error en fetchBulkStock: $e ===');
      rethrow;
    }
  }

  MediaType _resolveMediaType(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    switch (ext) {
      case 'png':
        return MediaType('image', 'png');
      case 'jpg':
      case 'jpeg':
        return MediaType('image', 'jpeg');
      case 'webp':
        return MediaType('image', 'webp');
      default:
        return MediaType('image', 'jpeg');
    }
  }

  @override
  Future<String> uploadProductImage(int productId, String filePath, {List<int>? bytes, String? filename}) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/catalog/products/$productId/image'),
      );
      request.headers['Accept'] = 'application/json';

      final name = filename ?? (filePath.isNotEmpty ? filePath.split(RegExp(r'[/\\]')).last : 'product.jpg');
      final mediaType = _resolveMediaType(name);

      if (bytes != null) {
        request.files.add(http.MultipartFile.fromBytes('image', bytes, filename: name, contentType: mediaType));
      } else {
        request.files.add(await http.MultipartFile.fromPath('image', filePath, contentType: mediaType));
      }

      final streamedResponse = await client.send(request);
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        final rawUrl = (decoded['image_url'] ?? decoded['image_path'])?.toString();
        return resolveImageUrl(rawUrl, baseUrl: baseUrl) ?? (rawUrl ?? '');
      } else if (response.statusCode == 404) {
        throw Exception('Error de conexión: No se encontró el servidor o el producto.');
      } else if (response.statusCode == 500) {
        throw Exception('Error interno del servidor. Contacte a soporte técnico.');
      } else {
        throw Exception(_parseApiError(response.body, 'Error al subir imagen del producto.'));
      }
    } on FormatException catch (e) {
      throw Exception(e.message);
    } catch (e) {
      debugPrint('=== API Error en uploadProductImage: $e ===');
      final errStr = e.toString();
      if (errStr.contains('SocketException') ||
          errStr.contains('TimeoutException') ||
          errStr.contains('ClientException')) {
        throw Exception('Error de conexión: No se encontró el servidor. Verifica la URL configurada.');
      }
      rethrow;
    }
  }

  @override
  Future<void> deleteProductImage(int productId) async {
    try {
      final response = await client.delete(
        Uri.parse('$baseUrl/catalog/products/$productId/image'),
        headers: {'Accept': 'application/json'},
      );

      if (response.statusCode != 200 && response.statusCode != 204) {
        throw Exception(_parseApiError(response.body, 'Error al eliminar imagen del producto.'));
      }
    } on FormatException catch (e) {
      throw Exception(e.message);
    } catch (e) {
      debugPrint('=== API Error en deleteProductImage: $e ===');
      final errStr = e.toString();
      if (errStr.contains('SocketException') ||
          errStr.contains('TimeoutException') ||
          errStr.contains('ClientException')) {
        throw Exception('Error de conexión: No se encontró el servidor. Verifica la URL configurada.');
      }
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> importProducts(List<int> fileBytes, String filename) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/catalog/products/import'),
      );
      
      // Use the client's headers (e.g., auth tokens) if we were using a generic interceptor.
      // Wait, client is an http.Client. We might need to copy headers from ApiClient if it's customized.
      // But looking at uploadProductImage, we can see how it's done. Wait, let's just do what uploadProductImage does.
      
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          fileBytes,
          filename: filename,
        ),
      );

      request.headers['Accept'] = 'application/json';
      // If we are using ApiClient, it intercepts normal requests, but MultipartRequest is a separate object.
      // Let's send the request via the client to apply interceptors:
      final streamedResponse = await client.send(request);
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200 || response.statusCode == 201) {
        return json.decode(response.body);
      } else {
        throw Exception(_parseApiError(response.body, 'Error al importar catálogo.'));
      }
    } catch (e) {
      debugPrint('=== API Error en importProducts: $e ===');
      rethrow;
    }
  }

  @override
  Future<ProductModel> updateProductCalcConfig(
    int productId,
    Map<String, dynamic>? calcConfig,
  ) async {
    final uri = Uri.parse('$baseUrl/catalog/products/$productId/calc-config');
    final response = await client.patch(
      uri,
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: json.encode({'calc_config': calcConfig}),
    );
    if (response.statusCode == 200 || response.statusCode == 201) {
      final decoded = json.decode(response.body) as Map<String, dynamic>;
      final rawProd = decoded['product'] ?? decoded;
      return ProductModel.fromJson(Map<String, dynamic>.from(rawProd as Map));
    }
    throw CatalogHttpException(
      response.statusCode,
      _parseApiError(
        response.body,
        'Error al guardar configuración de calculadora.',
      ),
    );
  }
}


