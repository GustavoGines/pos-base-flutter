import 'dart:convert';
import 'package:http/http.dart' as http;

class ReportsRemoteDataSource {
  final String baseUrl;
  final http.Client client;

  ReportsRemoteDataSource({required this.baseUrl, required this.client});

  Future<Map<String, dynamic>> getProfitByCategory(String startDate, String endDate) async {
    final uri = Uri.parse('$baseUrl/reports/sales-by-category?start_date=$startDate&end_date=$endDate');
    
    final response = await client.get(uri, headers: {
      'Accept': 'application/json',
    });

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Error al obtener reporte de rentabilidad: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> getProfitByBrand(String startDate, String endDate) async {
    final uri = Uri.parse('$baseUrl/reports/sales-by-brand?start_date=$startDate&end_date=$endDate');
    
    final response = await client.get(uri, headers: {
      'Accept': 'application/json',
    });

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Error al obtener reporte por marca: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> getInternalConsumption(String startDate, String endDate, {int? customerId}) async {
    final params = 'start_date=$startDate&end_date=$endDate${customerId != null ? '&customer_id=$customerId' : ''}';
    final uri = Uri.parse('$baseUrl/reports/internal-consumption?$params');
    
    final response = await client.get(uri, headers: {
      'Accept': 'application/json',
    });

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Error al obtener consumo interno: ${response.statusCode}');
    }
  }

  Future<List<int>> downloadExcel(String startDate, String endDate, {bool isBrand = false}) async {
    final typeParam = isBrand ? '&type=brand' : '';
    final uri = Uri.parse('$baseUrl/reports/sales-by-category/export?start_date=$startDate&end_date=$endDate$typeParam');
    final response = await client.get(uri);
    if (response.statusCode == 200) {
      return response.bodyBytes;
    } else {
      throw Exception('Error al descargar el reporte Excel: ${response.statusCode}');
    }
  }

  Future<List<int>> downloadPdf(String startDate, String endDate, {bool isBrand = false}) async {
    final typeParam = isBrand ? '&type=brand' : '';
    final uri = Uri.parse('$baseUrl/reports/sales-by-category/pdf?start_date=$startDate&end_date=$endDate$typeParam');
    final response = await client.get(uri, headers: {
      'Accept': 'application/pdf',
    });
    if (response.statusCode == 200) {
      return response.bodyBytes;
    } else {
      throw Exception('Error al descargar el reporte PDF: ${response.statusCode}');
    }
  }

  Future<List<int>> downloadMonthlyBalanceExcel(String startMonth, String endMonth) async {
    final uri = Uri.parse('$baseUrl/reports/monthly-balance/export?start_month=$startMonth&end_month=$endMonth');
    final response = await client.get(uri);
    if (response.statusCode == 200) {
      return response.bodyBytes;
    } else {
      throw Exception('Error al descargar el balance Excel: ${response.statusCode}');
    }
  }

  Future<List<int>> downloadMonthlyBalancePdf(String startMonth, String endMonth) async {
    final uri = Uri.parse('$baseUrl/reports/monthly-balance/pdf?start_month=$startMonth&end_month=$endMonth');
    final response = await client.get(uri, headers: {
      'Accept': 'application/pdf',
    });
    if (response.statusCode == 200) {
      return response.bodyBytes;
    } else {
      throw Exception('Error al descargar el balance PDF: ${response.statusCode}');
    }
  }
}
