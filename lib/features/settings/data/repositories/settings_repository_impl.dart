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

  @override
  Future<BusinessSettings> updateSettings(Map<String, dynamic> data) async {
    return await remoteDataSource.updateSettings(data);
  }

  @override
  Future<String> uploadLogo(String filePath, {List<int>? bytes, String? filename}) async {
    return await remoteDataSource.uploadLogo(filePath, bytes: bytes, filename: filename);
  }

  @override
  Future<Map<String, dynamic>> fetchIntegrations() async {
    return await remoteDataSource.fetchIntegrations();
  }

  @override
  Future<bool> updateIntegrations(Map<String, dynamic> data) async {
    return await remoteDataSource.updateIntegrations(data);
  }

  @override
  Future<Map<String, dynamic>> testMercadoPagoConnection({String? mpAccessToken}) async {
    return await remoteDataSource.testMercadoPagoConnection(mpAccessToken: mpAccessToken);
  }

  @override
  void updateBaseUrl(String newUrl) {
    if (remoteDataSource is SettingsRemoteDataSourceImpl) {
      (remoteDataSource as SettingsRemoteDataSourceImpl).updateBaseUrl(newUrl);
    }
  }
}
