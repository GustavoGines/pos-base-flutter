import 'package:equatable/equatable.dart';

class FeatureFlags extends Equatable {
  final bool fastPos;
  final bool zReports;
  final bool quotes;
  final bool currentAccounts;
  final bool multiplePrices;
  final bool multiCaja;
  final bool advancedReports;
  final bool predictiveAlerts;

  const FeatureFlags({
    this.fastPos = false,
    this.zReports = false,
    this.quotes = false,
    this.currentAccounts = false,
    this.multiplePrices = false,
    this.multiCaja = false,
    this.advancedReports = false,
    this.predictiveAlerts = false,
  });

  @override
  List<Object?> get props => [
        fastPos,
        zReports,
        quotes,
        currentAccounts,
        multiplePrices,
        multiCaja,
        advancedReports,
        predictiveAlerts,
      ];
}

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
  final String? lastLicenseCheck;
  final String? serverTime; // Timestamp from the server
  final DateTime? licenseExpiresAt;
  final DateTime? licenseNextPaymentAt;
  final String? licenseManageUrl;
  final bool isLifetime;
  // [feature-flag] Tipo de negocio recibido desde la Licencia remota — solo para uso estético/visual de la UI
  final String businessType;  // 'retail' | 'hardware_store'
  // [feature-flags] Objeto estructurado de características habilitadas
  final FeatureFlags features;

  /// @deprecated Use [features] instead for better type safety.
  bool hasFeature(String featureName) => licenseFeatures.contains(featureName);

  /// Getter legado para retrocompatibilidad.
  List<String> get licenseFeatures {
    final list = <String>[];
    if (features.fastPos) list.add('fast_pos');
    if (features.zReports) list.add('z_reports');
    if (features.quotes) list.add('quotes');
    if (features.currentAccounts) list.add('current_accounts');
    if (features.multiplePrices) list.add('multiple_prices');
    if (features.multiCaja) list.add('multi_caja');
    if (features.advancedReports) list.add('advanced_reports');
    if (features.predictiveAlerts) list.add('predictive_alerts');
    return list;
  }

  /// Alias legado — mantenido para retrocompatibilidad durante la transición.
  bool get isHardwareStore => businessType == 'hardware_store' || features.quotes;

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
    this.lastLicenseCheck,
    this.serverTime,
    this.licenseExpiresAt,
    this.licenseNextPaymentAt,
    this.licenseManageUrl,
    this.isLifetime = false,
    this.businessType = 'retail',
    this.features = const FeatureFlags(),
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
        lastLicenseCheck,
        serverTime,
        licenseExpiresAt,
        licenseNextPaymentAt,
        licenseManageUrl,
        isLifetime,
        businessType,
        features,
      ];
}
