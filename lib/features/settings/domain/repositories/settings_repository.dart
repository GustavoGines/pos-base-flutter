import '../entities/business_settings.dart';

abstract class SettingsRepository {
  Future<BusinessSettings> getSettings();
}
