import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend_desktop/core/network/api_client.dart';
import 'package:frontend_desktop/features/catalog/data/models/product_model.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'models/offer_model.dart';

class OfferRepository {
  final String baseUrl;
  final ApiClient client;

  OfferRepository({required this.baseUrl, required this.client});

  Future<String> _getActiveUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('pos_api') ?? baseUrl;
  }

  Future<List<OfferModel>> getActiveOffers() async {
    final url = await _getActiveUrl();
    final response = await client.get(
      Uri.parse('$url/offers/active'),
      headers: {'Accept': 'application/json'},
    );

    if (response.statusCode == 200) {
      final jsonResponse = jsonDecode(response.body);
      final list = jsonResponse['data'] as List? ?? [];
      return list.map((item) => OfferModel.fromJson(item as Map<String, dynamic>)).toList();
    } else {
      throw Exception('Error al obtener ofertas activas (${response.statusCode})');
    }
  }

  /// OF-01: Trae COMPLETOS (stock, combo, pesable, imagen, escalas) los productos indicados,
  /// con el mismo formato que el listado del catálogo. Se usa para los productos en oferta
  /// activa que quedaron fuera del bloque inicial de 500 del Acceso Rápido.
  Future<List<Product>> getProductsByIds(List<int> ids) async {
    if (ids.isEmpty) return [];
    final url = await _getActiveUrl();
    final uri = Uri.parse('$url/catalog/products').replace(queryParameters: {
      'ids': ids.join(','),
      'per_page': '500',
    });
    final response = await client.get(uri, headers: {'Accept': 'application/json'});

    if (response.statusCode == 200) {
      final jsonResponse = jsonDecode(response.body);
      final list = jsonResponse['data'] as List? ?? [];
      return list.map((item) => ProductModel.fromJson(item as Map<String, dynamic>)).toList();
    } else {
      throw Exception('Error al obtener productos en oferta (${response.statusCode})');
    }
  }

  Future<List<OfferModel>> getAllOffers({String? status, String? search}) async {
    final url = await _getActiveUrl();
    final queryParams = <String, String>{};
    if (status != null && status.isNotEmpty && status != 'all') {
      queryParams['status'] = status;
    }
    if (search != null && search.trim().isNotEmpty) {
      queryParams['q'] = search.trim();
    }

    final uri = Uri.parse('$url/offers').replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);
    final response = await client.get(
      uri,
      headers: {'Accept': 'application/json'},
    );

    if (response.statusCode == 200) {
      final jsonResponse = jsonDecode(response.body);
      final list = jsonResponse['data'] as List? ?? [];
      return list.map((item) => OfferModel.fromJson(item as Map<String, dynamic>)).toList();
    } else {
      throw Exception('Error al listar ofertas (${response.statusCode})');
    }
  }

  Future<OfferModel> createOffer({
    required String name,
    String? description,
    required String type, // 'percentage' | 'fixed_price'
    double? discountPercentage,
    double? discountAmount,
    required String periodType, // 'daily' | 'weekly' | 'monthly' | 'custom'
    List<String>? daysOfWeek,
    DateTime? startDate,
    DateTime? endDate,
    required List<Map<String, dynamic>> products,
  }) async {
    final payload = {
      'name': name,
      if (description != null && description.isNotEmpty) 'description': description,
      'type': type,
      if (discountPercentage != null) 'discount_percentage': discountPercentage,
      if (discountAmount != null) 'discount_amount': discountAmount,
      'period_type': periodType,
      if (daysOfWeek != null && daysOfWeek.isNotEmpty) 'days_of_week': daysOfWeek,
      if (startDate != null) 'start_date': startDate.toIso8601String(),
      if (endDate != null) 'end_date': endDate.toIso8601String(),
      'products': products,
    };

    final url = await _getActiveUrl();
    final response = await client.post(
      Uri.parse('$url/offers'),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(payload),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      final jsonResponse = jsonDecode(response.body);
      return OfferModel.fromJson(jsonResponse['data'] as Map<String, dynamic>);
    } else {
      final err = jsonDecode(response.body);
      throw Exception(err['message'] ?? 'Error al guardar la oferta');
    }
  }

  Future<OfferModel> updateOffer({
    required int id,
    required String name,
    String? description,
    required String type, // 'percentage' | 'fixed_price'
    double? discountPercentage,
    double? discountAmount,
    required String periodType, // 'daily' | 'weekly' | 'monthly' | 'custom'
    List<String>? daysOfWeek,
    DateTime? startDate,
    DateTime? endDate,
    required List<Map<String, dynamic>> products,
  }) async {
    final payload = {
      'name': name,
      if (description != null && description.isNotEmpty) 'description': description,
      'type': type,
      if (discountPercentage != null) 'discount_percentage': discountPercentage,
      if (discountAmount != null) 'discount_amount': discountAmount,
      'period_type': periodType,
      if (daysOfWeek != null && daysOfWeek.isNotEmpty) 'days_of_week': daysOfWeek,
      if (startDate != null) 'start_date': startDate.toIso8601String(),
      if (endDate != null) 'end_date': endDate.toIso8601String(),
      'products': products,
    };

    final url = await _getActiveUrl();
    final response = await client.put(
      Uri.parse('$url/offers/$id'),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(payload),
    );

    if (response.statusCode == 200) {
      final jsonResponse = jsonDecode(response.body);
      return OfferModel.fromJson(jsonResponse['data'] as Map<String, dynamic>);
    } else {
      final err = jsonDecode(response.body);
      throw Exception(err['message'] ?? 'Error al actualizar la oferta');
    }
  }

  Future<Map<String, dynamic>> relaunchOffer({
    required int id,
    required String periodType,
    DateTime? startDate,
    DateTime? endDate,
    bool duplicate = false,
  }) async {
    final payload = {
      'period_type': periodType,
      if (startDate != null) 'start_date': startDate.toIso8601String(),
      if (endDate != null) 'end_date': endDate.toIso8601String(),
      'duplicate': duplicate,
    };

    final url = await _getActiveUrl();
    final response = await client.post(
      Uri.parse('$url/offers/$id/relaunch'),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(payload),
    );

    if (response.statusCode == 200) {
      final jsonResponse = jsonDecode(response.body);
      final offer = OfferModel.fromJson(jsonResponse['data'] as Map<String, dynamic>);
      final warnings = jsonResponse['margin_warnings'] as List? ?? [];
      return {
        'offer': offer,
        'margin_warnings': warnings,
      };
    } else {
      final err = jsonDecode(response.body);
      throw Exception(err['message'] ?? 'Error al relanzar oferta');
    }
  }

  Future<OfferModel> toggleOfferStatus(int id) async {
    final url = await _getActiveUrl();
    final response = await client.patch(
      Uri.parse('$url/offers/$id/toggle-status'),
      headers: {'Accept': 'application/json'},
    );

    if (response.statusCode == 200) {
      final jsonResponse = jsonDecode(response.body);
      return OfferModel.fromJson(jsonResponse['data'] as Map<String, dynamic>);
    } else {
      final err = jsonDecode(response.body);
      throw Exception(err['message'] ?? 'Error al alternar estado de oferta');
    }
  }

  Future<void> deleteOffer(int id) async {
    final url = await _getActiveUrl();
    final response = await client.delete(
      Uri.parse('$url/offers/$id'),
      headers: {'Accept': 'application/json'},
    );

    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception('Error al eliminar oferta');
    }
  }
}
