import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../../core/config/app_config.dart';
import '../models/update_info.dart';

class UpdateService {
  Future<UpdateInfo?> checkUpdate({bool throwErrors = false}) async {
    try {
      final response = await http.get(
        Uri.parse('${AppConfig.kApiBaseUrl}/check-update'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(minutes: 4));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['data'] != null) {
          return UpdateInfo.fromJson(data['data']);
        }
      } else if (response.statusCode == 404) {
        // Server responded cleanly that there are no releases
        return null;
      }
      
      if (throwErrors) {
        throw Exception('El servidor respondió con código ${response.statusCode}');
      }
      return null;
    } on TimeoutException {
      if (throwErrors) {
        throw Exception('Timeout esperando al servidor (posible arranque en Render).');
      }
      return null;
    } catch (e) {
      if (throwErrors) {
        throw Exception('Error de conexión.');
      }
      return null;
    }
  }
}
