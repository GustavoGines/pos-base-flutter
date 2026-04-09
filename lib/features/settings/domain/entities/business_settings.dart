import 'package:equatable/equatable.dart';

class BusinessSettings extends Equatable {
  final String? companyName;
  final String? address;
  final String? phone;
  final String? taxId;
  final String? receiptFooterMessage;
  final String printerType;
  final String printerPaperWidth;
  final String? printerComPort;
  final String? printerIpAddress;
  final String? printerIpPort;
  final String? comPortScale;
  final String? licenseStatus;
  final String? licensePlanType;
  final String? licensePlanMode; // 'saas' or 'lifetime'
  final List<String>? licenseAllowedAddons;
  final String? lastLicenseCheck;
  final String? serverTime; // Timestamp from the server
  final DateTime? licenseExpiresAt;
  final DateTime? licenseNextPaymentAt;
  final String? licenseManageUrl;
  final bool isLifetime;
  // [feature-flag] Tipo de negocio recibido desde la Licencia remota — solo para uso estético/visual de la UI
  final String businessType;  // 'retail' | 'hardware_store'
  // [feature-flags] Array modular de características habilitadas por el Servidor de Licencias
  final List<String> licenseFeatures;  // ej: ['fast_pos', 'quotes', 'multiple_prices']

  /// Consulta ágil de permisos modulares.
  bool hasFeature(String featureName) => licenseFeatures.contains(featureName);

  /// Alias legado — mantenido para retrocompatibilidad durante la transición.
  bool get isHardwareStore => businessType == 'hardware_store' || hasFeature('quotes');

  const BusinessSettings({
    this.companyName,
    this.address,
    this.phone,
    this.taxId,
    this.receiptFooterMessage,
    this.printerType = 'none',
    this.printerPaperWidth = '58',
    this.printerComPort,
    this.printerIpAddress,
    this.printerIpPort,
    this.comPortScale,
    this.licenseStatus,
    this.licensePlanType,
    this.licensePlanMode,
    this.licenseAllowedAddons,
    this.lastLicenseCheck,
    this.serverTime,
    this.licenseExpiresAt,
    this.licenseNextPaymentAt,
    this.licenseManageUrl,
    this.isLifetime = false,
    this.businessType = 'retail',
    this.licenseFeatures = const [],  // default vacío = sin features = sin acceso a módulos extra
  });

  @override
  List<Object?> get props => [
        companyName,
        address,
        phone,
        taxId,
        receiptFooterMessage,
        printerType,
        printerPaperWidth,
        printerComPort,
        printerIpAddress,
        printerIpPort,
        comPortScale,
        licenseStatus,
        licensePlanType,
        licensePlanMode,
        licenseAllowedAddons,
        lastLicenseCheck,
        serverTime,
        licenseExpiresAt,
        licenseNextPaymentAt,
        licenseManageUrl,
        isLifetime,
        businessType,
        licenseFeatures,  // [feature-flags]
      ];
}
