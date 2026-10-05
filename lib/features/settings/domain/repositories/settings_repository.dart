import '../entities/business_settings.dart';

abstract class SettingsRepository {
  Future<BusinessSettings> getSettings();
  Future<BusinessSettings> updateSettings(Map<String, dynamic> data);
  Future<String> uploadLogo(String filePath, {List<int>? bytes, String? filename});
  void updateBaseUrl(String newUrl);
}
