import '../../domain/entities/business_settings.dart';
import '../../domain/repositories/settings_repository.dart';
import '../datasources/settings_remote_datasource.dart';

class SettingsRepositoryImpl implements SettingsRepository {
  final SettingsRemoteDataSource remoteDataSource;

  SettingsRepositoryImpl({required this.remoteDataSource});

  @override
  Future<BusinessSettings> getSettings() async {
    return await remoteDataSource.fetchSettings();
  }
}
