import 'dart:convert';
import 'package:frontend_desktop/core/network/api_client.dart';

class DeliveryNoteRepository {
  final String baseUrl;
  final ApiClient client;

  DeliveryNoteRepository({required this.baseUrl, required this.client});

  String get _base => '$baseUrl/delivery-notes';

  /// Obtiene los remitos paginados según el estado (pending, partial, delivered) y un término de búsqueda opcional.
  /// Retorna un mapa con 'data' (lista de remitos) y 'meta' (información de paginación).
  Future<Map<String, dynamic>> fetchDeliveryNotes({
    String? status,
    String? search,
    int page = 1,
    int perPage = 50,
  }) async {
    final params = <String, String>{
      'page': page.toString(),
      'per_page': perPage.toString(),
    };
    if (status != null && status.isNotEmpty) params['status'] = status;
    if (search != null && search.isNotEmpty) params['search'] = search;

    final uri = Uri.parse(_base).replace(queryParameters: params);

    final response = await client.get(
      uri,
      headers: {'Accept': 'application/json'},
    );

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded is List) {
        // Mock a paginated response if backend returns a flat array
        return {
          'data': decoded,
          'meta': {
            'current_page': 1,
            'last_page': 1,
          }
        };
      } else if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    }
    
    throw Exception('Error al cargar los remitos de logística: ${response.statusCode} - ${response.body}');
  }

  /// Confirma el despacho parcial o total de un remito.
  /// [deliveredNow] es un mapa de { item_id: cantidad_a_entregar }.
  Future<Map<String, dynamic>> dispatchItems(int deliveryNoteId, Map<int, double> deliveredNow) async {
    final uri = Uri.parse('$_base/$deliveryNoteId/deliver');

    final itemsPayload = deliveredNow.entries
        .where((e) => e.value > 0)
        .map((e) => {'id': e.key, 'delivered_now': e.value})
        .toList();

    final body = jsonEncode({
      'items': itemsPayload,
    });

    final response = await client.put(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: body,
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    
    throw Exception('Error al despachar remito: ${response.body}');
  }
}
