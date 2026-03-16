import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../domain/entities/sale_record.dart';

class SalesHistoryRemoteDataSource {
  final String baseUrl;
  final http.Client client;

  SalesHistoryRemoteDataSource({required this.baseUrl, required this.client});

  /// Obtiene las ventas filtradas por período (shift, today, month, year, all) y opcionalmente shiftId.
  Future<List<SaleRecord>> fetchSales({String period = 'shift', int? shiftId, int? userId}) async {
    final queryParams = {'period': period};
    if (shiftId != null) queryParams['shift_id'] = shiftId.toString();
    if (userId != null) queryParams['user_id'] = userId.toString();

    final uri = Uri.parse('$baseUrl/sales').replace(queryParameters: queryParams);
    final response = await client.get(uri, headers: {'Accept': 'application/json'});
    if (response.statusCode == 200) {
      final List<dynamic> list = json.decode(response.body);
      return list.map((j) => SaleRecord.fromJson(j as Map<String, dynamic>)).toList();
    } else {
      throw Exception('Error al obtener ventas (${response.statusCode})');
    }
  }

  /// Anula una venta y devuelve el registro actualizado.
  Future<SaleRecord> voidSale(int saleId) async {
    final response = await client.post(
      Uri.parse('$baseUrl/sales/$saleId/void'),
      headers: {'Accept': 'application/json'},
    );
    if (response.statusCode == 200) {
      final body = json.decode(response.body) as Map<String, dynamic>;
      return SaleRecord.fromJson(body['sale'] as Map<String, dynamic>);
    } else {
      final error = json.decode(response.body);
      throw Exception(error['message'] ?? 'Error al anular la venta');
    }
  }
}
