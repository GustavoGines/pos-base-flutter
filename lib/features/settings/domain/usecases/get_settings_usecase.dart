import '../../domain/entities/business_settings.dart';
import '../../domain/repositories/settings_repository.dart';

class GetSettingsUseCase {
  final SettingsRepository repository;

  GetSettingsUseCase(this.repository);

  Future<BusinessSettings> call() async {
    return await repository.getSettings();
  }
}
