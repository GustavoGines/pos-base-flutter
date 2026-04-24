import 'dart:convert';
import 'package:http/http.dart' as http;

abstract class CheckRemoteDataSource {
  Future<List<dynamic>> fetchThirdPartyChecks();
  Future<dynamic> updateCheckStatus(int checkId, String status, {String? endorsementNote});
}

class CheckRemoteDataSourceImpl implements CheckRemoteDataSource {
  final String baseUrl;
  final http.Client client;

  CheckRemoteDataSourceImpl({required this.baseUrl, required this.client});

  @override
  Future<List<dynamic>> fetchThirdPartyChecks() async {
    final response = await client.get(
      Uri.parse('$baseUrl/third-party-checks'),
      headers: {'Accept': 'application/json'},
    );

    if (response.statusCode == 200) {
      return json.decode(response.body) as List<dynamic>;
    } else {
      try {
        final errorData = json.decode(response.body);
        if (errorData['message'] != null) {
          throw Exception(errorData['message']);
        }
      } catch (_) {}
      throw Exception('Failed to load checks');
    }
  }

  @override
  Future<dynamic> updateCheckStatus(int checkId, String status, {String? endorsementNote}) async {
    final response = await client.patch(
      Uri.parse('$baseUrl/third-party-checks/$checkId/status'),
      headers: {'Accept': 'application/json', 'Content-Type': 'application/json'},
      body: json.encode({
        'status': status,
        if (endorsementNote != null) 'endorsement_note': endorsementNote,
      }),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      try {
        final errorData = json.decode(response.body);
        if (errorData['message'] != null) {
          throw Exception(errorData['message']);
        }
      } catch (_) {}
      throw Exception('Failed to update check status');
    }
  }
}
