import 'package:equatable/equatable.dart';
import '../../../../core/utils/image_url_resolver.dart';

class FeatureFlags extends Equatable {
  final bool fastPos;
  final bool zReports;
  final bool quotes;
  final bool currentAccounts;
  final bool multiplePrices;
  final bool multiCaja;
  final bool advancedReports;
  final bool predictiveAlerts;
  final bool logistics;
  final bool checks;
  final bool mobileApp;
  final bool remoteAccess;
  final bool suppliers;
  final bool expenses;
  final bool multiRubro;

  const FeatureFlags({
    this.fastPos = false,
    this.zReports = false,
    this.quotes = false,
    this.currentAccounts = false,
    this.multiplePrices = false,
    this.multiCaja = false,
    this.advancedReports = false,
    this.predictiveAlerts = false,
    this.logistics = false,
    this.checks = false,
    this.mobileApp = false,
    this.remoteAccess = false,
    this.suppliers = false,
    this.expenses = false,
    this.multiRubro = false,
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
        logistics,
        checks,
        mobileApp,
        remoteAccess,
        suppliers,
        expenses,
        multiRubro,
      ];
}

class BusinessSettings extends Equatable {
  final String? companyName;
  final String? address;
  final String? phone;
  final String? taxId;
  final String? receiptFooterMessage;
  final String? licenseStatus;
  final String? licensePlanType;
  final String? licensePlanMode; // 'saas' or 'lifetime'
  final String? lastLicenseCheck;
  final String? serverTime; // Timestamp from the server
  final DateTime? licenseExpiresAt;
  final DateTime? licenseNextPaymentAt;
  final String? licenseManageUrl;
  final bool isLifetime;
  
  // [multiple-prices] Modificadores Globales y Dinámicos
  final double globalWholesalePercentage; // Ej: -15.0
  final double globalCardPercentage;      // Ej: 15.0
  final List<Map<String, dynamic>> customPriceTiers; // [{"name": "Jubilados", "modifier": -5}]
  // [feature-flag] Tipo de negocio recibido desde la Licencia remota — solo para uso estético/visual de la UI
  final String businessType;  // 'retail' | 'hardware_store'
  // [feature-flags] Objeto estructurado de características habilitadas
  final FeatureFlags features;
  /// Master switch del modelo Multi-Tenant:
  /// - false (default) → Modo Retail Básico: tier dropdown oculto, surcharges de métodos de pago ACTIVOS.
  /// - true → Modo Avanzado (Ferretería/Mayorista): tier dropdown visible, surcharges SUPRIMIDOS (el precio ya incluye el factor).
  final bool enableAdvancedPriceTiers;
  final bool afipEnabled;

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
    if (features.logistics) list.add('logistics');
    if (features.checks) list.add('checks');
    if (features.mobileApp) list.add('mobile_app');
    if (features.remoteAccess) list.add('remote_access');
    if (features.suppliers) list.add('suppliers');
    if (features.expenses) list.add('expenses');
    if (features.multiRubro) list.add('multi_rubro');
    return list;
  }

  /// Alias legado — mantenido para retrocompatibilidad durante la transición.
  bool get isHardwareStore => businessType == 'hardware_store' || features.quotes;

  final String? logoPath;
  final String? logoUrl;

  String? get effectiveLogoUrl {
    if (logoUrl != null && logoUrl!.isNotEmpty) {
      final resolved = resolveImageUrl(logoUrl);
      if (resolved != null) return resolved;
    }
    if (logoPath != null && logoPath!.isNotEmpty) {
      final resolved = resolveImageUrl(logoPath);
      if (resolved != null) return resolved;
    }
    return null;
  }

  BusinessSettings copyWith({
    String? companyName,
    String? address,
    String? phone,
    String? taxId,
    String? receiptFooterMessage,
    String? licenseStatus,
    String? licensePlanType,
    String? licensePlanMode,
    String? lastLicenseCheck,
    String? serverTime,
    DateTime? licenseExpiresAt,
    DateTime? licenseNextPaymentAt,
    String? licenseManageUrl,
    bool? isLifetime,
    String? logoPath,
    String? logoUrl,
    double? globalWholesalePercentage,
    double? globalCardPercentage,
    List<Map<String, dynamic>>? customPriceTiers,
    String? businessType,
    FeatureFlags? features,
    bool? enableAdvancedPriceTiers,
    bool? afipEnabled,
  }) {
    return BusinessSettings(
      companyName: companyName ?? this.companyName,
      address: address ?? this.address,
      phone: phone ?? this.phone,
      taxId: taxId ?? this.taxId,
      receiptFooterMessage: receiptFooterMessage ?? this.receiptFooterMessage,
      licenseStatus: licenseStatus ?? this.licenseStatus,
      licensePlanType: licensePlanType ?? this.licensePlanType,
      licensePlanMode: licensePlanMode ?? this.licensePlanMode,
      lastLicenseCheck: lastLicenseCheck ?? this.lastLicenseCheck,
      serverTime: serverTime ?? this.serverTime,
      licenseExpiresAt: licenseExpiresAt ?? this.licenseExpiresAt,
      licenseNextPaymentAt: licenseNextPaymentAt ?? this.licenseNextPaymentAt,
      licenseManageUrl: licenseManageUrl ?? this.licenseManageUrl,
      isLifetime: isLifetime ?? this.isLifetime,
      logoPath: logoPath ?? this.logoPath,
      logoUrl: logoUrl ?? this.logoUrl,
      globalWholesalePercentage: globalWholesalePercentage ?? this.globalWholesalePercentage,
      globalCardPercentage: globalCardPercentage ?? this.globalCardPercentage,
      customPriceTiers: customPriceTiers ?? this.customPriceTiers,
      businessType: businessType ?? this.businessType,
      features: features ?? this.features,
      enableAdvancedPriceTiers: enableAdvancedPriceTiers ?? this.enableAdvancedPriceTiers,
      afipEnabled: afipEnabled ?? this.afipEnabled,
    );
  }

  const BusinessSettings({
    this.companyName,
    this.address,
    this.phone,
    this.taxId,
    this.receiptFooterMessage,
    this.licenseStatus,
    this.licensePlanType,
    this.licensePlanMode,
    this.lastLicenseCheck,
    this.serverTime,
    this.licenseExpiresAt,
    this.licenseNextPaymentAt,
    this.licenseManageUrl,
    this.isLifetime = false,
    this.logoPath,
    this.logoUrl,
    this.globalWholesalePercentage = -15.0, // Hardcoded default based on common patterns
    this.globalCardPercentage = 15.0,
    this.customPriceTiers = const [],
    this.businessType = 'retail',
    this.features = const FeatureFlags(),
    this.enableAdvancedPriceTiers = false,
    this.afipEnabled = false,
  });

  @override
  List<Object?> get props => [
        companyName,
        address,
        phone,
        taxId,
        receiptFooterMessage,
        licenseStatus,
        licensePlanType,
        licensePlanMode,
        lastLicenseCheck,
        serverTime,
        licenseExpiresAt,
        licenseNextPaymentAt,
        licenseManageUrl,
        isLifetime,
        logoPath,
        logoUrl,
        globalWholesalePercentage,
        globalCardPercentage,
        customPriceTiers,
        businessType,
        features,
        enableAdvancedPriceTiers,
      ];
}
