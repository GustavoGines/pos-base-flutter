import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend_desktop/core/network/api_client.dart';
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

  Future<List<OfferModel>> getAllOffers() async {
    final url = await _getActiveUrl();
    final response = await client.get(
      Uri.parse('$url/offers'),
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
