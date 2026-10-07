import '../entities/business_settings.dart';

abstract class SettingsRepository {
  Future<BusinessSettings> getSettings();
  Future<BusinessSettings> updateSettings(Map<String, dynamic> data);
  Future<String> uploadLogo(String filePath, {List<int>? bytes, String? filename});
  Future<Map<String, dynamic>> fetchIntegrations();
  Future<bool> updateIntegrations(Map<String, dynamic> data);
  Future<Map<String, dynamic>> testMercadoPagoConnection({String? mpAccessToken});
  void updateBaseUrl(String newUrl);
}
