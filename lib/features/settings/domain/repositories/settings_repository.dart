import '../entities/business_settings.dart';
import '../entities/ecommerce_integration.dart';

abstract class SettingsRepository {
  Future<BusinessSettings> getSettings();
  Future<BusinessSettings> updateSettings(Map<String, dynamic> data);
  Future<String> uploadLogo(String filePath, {List<int>? bytes, String? filename});
  Future<Map<String, dynamic>> fetchIntegrations();
  Future<bool> updateIntegrations(Map<String, dynamic> data);
  Future<Map<String, dynamic>> testMercadoPagoConnection({String? mpAccessToken});
  Future<Map<String, dynamic>> uploadAfipCertificates({
    required String cuit,
    required List<int> certBytes,
    required String certFilename,
    required List<int> keyBytes,
    required String keyFilename,
    String? keyPassphrase,
  });
  Future<List<EcommerceIntegration>> getEcommerceIntegrations();
  Future<EcommerceIntegration> createEcommerceIntegration(Map<String, dynamic> data);
  Future<EcommerceIntegration> updateEcommerceIntegration(int id, Map<String, dynamic> data);
  Future<bool> deleteEcommerceIntegration(int id);
  Future<Map<String, dynamic>> testEcommerceConnection(int id);
  Future<EcommerceIntegration> toggleEcommerceActive(int id);
  void updateBaseUrl(String newUrl);
}

