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
  Future<Map<String, dynamic>> uploadAfipCertificates({
    required String cuit,
    required List<int> certBytes,
    required String certFilename,
    required List<int> keyBytes,
    required String keyFilename,
    String? keyPassphrase,
  }) async {
    return await remoteDataSource.uploadAfipCertificates(
      cuit: cuit,
      certBytes: certBytes,
      certFilename: certFilename,
      keyBytes: keyBytes,
      keyFilename: keyFilename,
      keyPassphrase: keyPassphrase,
    );
  }

  @override
  void updateBaseUrl(String newUrl) {
    if (remoteDataSource is SettingsRemoteDataSourceImpl) {
      (remoteDataSource as SettingsRemoteDataSourceImpl).updateBaseUrl(newUrl);
    }
  }
}
