import 'dart:convert';
import 'package:http/http.dart' as http;

class ReportsRemoteDataSource {
  final String baseUrl;
  final http.Client client;

  ReportsRemoteDataSource({required this.baseUrl, required this.client});

  Future<Map<String, dynamic>> getProfitByCategory(String startDate, String endDate) async {
    final uri = Uri.parse('$baseUrl/reports/profit-by-category?start_date=$startDate&end_date=$endDate');
    
    final response = await client.get(uri, headers: {
      'Accept': 'application/json',
    });

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Error al obtener reporte de rentabilidad: ${response.statusCode}');
    }
  }
  Future<List<int>> downloadExcel(String startDate, String endDate) async {
    final uri = Uri.parse('$baseUrl/reports/profit-by-category/export?start_date=$startDate&end_date=$endDate');
    
    final response = await client.get(uri);

    if (response.statusCode == 200) {
      return response.bodyBytes;
    } else {
      throw Exception('Error al descargar el reporte: ${response.statusCode}');
    }
  }
}
