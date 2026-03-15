import '../../domain/entities/business_settings.dart';
import '../../domain/repositories/settings_repository.dart';

class UpdateSettingsUseCase {
  final SettingsRepository repository;

  UpdateSettingsUseCase(this.repository);

  Future<BusinessSettings> call(Map<String, dynamic> data) {
    return repository.updateSettings(data);
  }
}
