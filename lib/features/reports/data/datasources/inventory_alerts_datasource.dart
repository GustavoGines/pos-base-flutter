import 'dart:convert';
import 'package:http/http.dart' as http;

class InventoryAlertsDataSource {
  final String baseUrl;
  final http.Client client;

  InventoryAlertsDataSource({required this.baseUrl, required this.client});

  Future<Map<String, dynamic>> getInventoryAlerts({int threshold = 7}) async {
    final uri = Uri.parse('$baseUrl/inventory/alerts?threshold=$threshold');
    final response = await client.get(uri, headers: {'Accept': 'application/json'});
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('Error ${response.statusCode} al obtener alertas de inventario');
  }

  Future<Map<String, dynamic>> getMonthlyBalance(String startMonth, String endMonth, {String fiscalFilter = 'all'}) async {
    final uri = Uri.parse('$baseUrl/reports/monthly-balance?start_month=$startMonth&end_month=$endMonth&fiscal_filter=$fiscalFilter');
    final response = await client.get(uri, headers: {'Accept': 'application/json'});
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('Error ${response.statusCode} al obtener balance mensual');
  }

  Future<Map<String, dynamic>> snoozeExpirationAlert(
    int productId, {
    required String action,
    int? days,
    String? expirationDate,
  }) async {
    final uri = Uri.parse('$baseUrl/inventory/alerts/$productId/snooze');
    final response = await client.post(
      uri,
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: json.encode({
        'action': action,
        if (days != null) 'days': days,
        if (expirationDate != null) 'expiration_date': expirationDate,
      }),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('Error ${response.statusCode} al posponer alerta de vencimiento');
  }
}
