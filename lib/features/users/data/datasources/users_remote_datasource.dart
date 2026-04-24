import 'dart:convert';
import 'package:http/http.dart' as http;

class UsersRemoteDataSource {
  final String baseUrl;
  final http.Client client;

  UsersRemoteDataSource({required this.baseUrl, required this.client});

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  Future<List<Map<String, dynamic>>> getAll() async {
    final res = await client.get(Uri.parse('$baseUrl/users'), headers: _headers);
    if (res.statusCode == 200) {
      return List<Map<String, dynamic>>.from(json.decode(res.body));
    }
    throw Exception('Error al obtener empleados (${res.statusCode})');
  }

  Future<Map<String, dynamic>> create(Map<String, dynamic> data) async {
    final res = await client.post(
      Uri.parse('$baseUrl/users'),
      headers: _headers,
      body: json.encode(data),
    );
    if (res.statusCode == 201) return json.decode(res.body);
    final error = json.decode(res.body);
    throw Exception(error['message'] ?? 'Error al crear empleado');
  }

  Future<Map<String, dynamic>> update(int id, Map<String, dynamic> data) async {
    final res = await client.put(
      Uri.parse('$baseUrl/users/$id'),
      headers: _headers,
      body: json.encode(data),
    );
    if (res.statusCode == 200) return json.decode(res.body);
    final error = json.decode(res.body);
    throw Exception(error['message'] ?? 'Error al actualizar empleado');
  }

  // FIX U-3: El backend identifica al actor via X-Session-Token (header del ApiClient).
  // Ya no es necesario enviar current_user_id en el body.
  Future<void> delete(int id) async {
    final res = await client.delete(
      Uri.parse('$baseUrl/users/$id'),
      headers: _headers,
    );
    if (res.statusCode != 200) {
      final error = json.decode(res.body);
      throw Exception(error['message'] ?? 'Error al eliminar empleado');
    }
  }
}
