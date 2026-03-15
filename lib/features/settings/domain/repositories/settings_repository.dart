import '../entities/business_settings.dart';

abstract class SettingsRepository {
  Future<BusinessSettings> getSettings();
  Future<BusinessSettings> updateSettings(Map<String, dynamic> data);
}
