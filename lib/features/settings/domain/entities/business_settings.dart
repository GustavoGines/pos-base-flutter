import 'package:equatable/equatable.dart';
import '../../../../core/config/business_vertical_profile.dart';
import '../../../../core/utils/iibb_fiscal_calculator.dart';
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
  final bool mercadopagoQr;
  final bool arcaAfip;
  final bool ecommerceSync;
  final bool batchExpiration;
  final bool production;

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
    this.mercadopagoQr = false,
    this.arcaAfip = false,
    this.ecommerceSync = false,
    this.batchExpiration = false,
    this.production = false,
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
        mercadopagoQr,
        arcaAfip,
        ecommerceSync,
        batchExpiration,
        production,
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
  final bool isTrial;
  final String? licenseBlockReason;
  final String? licenseOtaToken;
  final bool licenseAllowOtaUpdates;
  final DateTime? licenseOtaUnlockedUntil;
  final String? licenseMaxUnlockedVersion;

  DateTime? get localLicenseExpiresAt => licenseExpiresAt?.toLocal();

  int? get remainingLicenseDays {
    if (isLifetime) return null;
    final exp = localLicenseExpiresAt;
    if (exp == null) return null;
    final now = DateTime.now();
    final expDay = DateTime(exp.year, exp.month, exp.day);
    final nowDay = DateTime(now.year, now.month, now.day);
    return expDay.difference(nowDay).inDays;
  }

  bool get hasActiveOtaWindow =>
      licenseOtaUnlockedUntil != null &&
      licenseOtaUnlockedUntil!.isAfter(DateTime.now());
  
  // [multiple-prices] Modificadores Globales y Dinámicos
  final double globalWholesalePercentage; // Ej: -15.0
  final double globalCardPercentage;      // Ej: 15.0
  final List<Map<String, dynamic>> customPriceTiers; // [{"name": "Jubilados", "modifier": -5}]
  /// Estrategia ante lista con recargo (Tarjeta / Custom +%) sobre productos con oferta activa:
  /// 'surcharge_on_offer' | 'card_overrides_offer' | 'offer_no_surcharge'
  final String cardSurchargeOnOffersMode;

  /// Estrategia ante lista con descuento (Mayorista / Custom -%) sobre productos con oferta activa:
  /// 'best_price_wins' | 'wholesale_overrides_offer'
  final String discountTierOnOffersMode;

  /// Si es true (por defecto), los factores porcentuales globales (Mayorista / Tarjeta)
  /// se aplican siempre en todo el catálogo ignorando precios fijos heredados en BD
  /// (`price_wholesale` / `price_card`).
  final bool ignoreProductFixedPrices;
  // [feature-flag] Tipo de negocio recibido desde la Licencia remota — solo para uso estético/visual de la UI
  final String businessType; // 'retail' | 'butcher' | 'hardware_store' | 'apparel' | 'tech' | 'general'
  final List<String> secondaryBusinessTypes;
  // [feature-flags] Objeto estructurado de características habilitadas
  final FeatureFlags features;
  /// Master switch del modelo Multi-Tenant:
  /// - false (default) → Modo Retail Básico: tier dropdown oculto, surcharges de métodos de pago ACTIVOS.
  /// - true → Modo Avanzado (Ferretería/Mayorista): tier dropdown visible, surcharges SUPRIMIDOS (el precio ya incluye el factor).
  final bool enableAdvancedPriceTiers;
  final bool afipEnabled;
  final bool isIibbPerceptionAgent;
  final double defaultIibbPerceptionRate;
  final String iibbCalculationBase;
  final List<String> iibbSubjectTaxConditions;
  final String? taxCondition;

  bool get isIibbGrossBase =>
      IibbFiscalCalculator.normalizeCalculationBase(iibbCalculationBase) ==
      IibbFiscalCalculator.baseGrossWithVat;

  bool isTaxConditionSubjectToIibb(String? rawTaxCondition) =>
      IibbFiscalCalculator.isConditionSubjectToIibb(
        rawTaxCondition,
        iibbSubjectTaxConditions,
      );
  final String? iibb;
  final String? activityStartDate;
  final int posPopularityDays;
  final String posPopularityMetric;
  final bool posDemoteOutOfStock;
  final String? posPopularityResetAt;
  final List<Map<String, dynamic>> bankTransferAccounts;

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
    if (features.mercadopagoQr) list.add('mercadopago_qr');
    if (features.arcaAfip) list.add('arca_afip');
    if (features.ecommerceSync) list.add('ecommerce_sync');
    if (features.batchExpiration) list.add('batch_expiration');
    if (features.production) list.add('production');
    return list;
  }

  bool get canUseBatchExpiration => features.batchExpiration || features.production;
  bool get canUseProduction => features.production;

  /// Alias legado — true si el rubro principal o alguno secundario es `hardware_store`.
  bool get isHardwareStore =>
      businessType == 'hardware_store' ||
      secondaryBusinessTypes.contains('hardware_store');

  /// Perfil visual y operativo unificado para el negocio activo.
  BusinessVerticalProfile get verticalProfile =>
      BusinessVerticalProfile.fromSettings(this);

  /// Verifica que la licencia esté activa y en un plan válido (Básico, PRO/Premium o Lifetime),
  /// excluyendo estados vacíos sin hidratar, suspendidos, expirados o bloqueados.
  bool get hasValidCalculatorLicense {
    final statusLower = (licenseStatus ?? '').trim().toLowerCase();
    final hasHydratedFeatures =
        features.fastPos || features.quotes || features.logistics;
    if (statusLower.isEmpty && !hasHydratedFeatures) {
      return false;
    }
    if (statusLower == 'suspended' ||
        statusLower == 'expired' ||
        statusLower == 'error' ||
        statusLower == 'blocked') {
      return false;
    }
    final plan = (licensePlanType ?? 'basic').trim().toLowerCase();
    if (plan == 'blocked' ||
        plan == 'none' ||
        plan == 'suspended' ||
        plan == 'expired') {
      return false;
    }
    return isLifetime ||
        plan.isEmpty ||
        plan == 'basic' ||
        plan == 'basico' ||
        plan == 'básico' ||
        plan == 'pro' ||
        plan == 'premium' ||
        plan == 'lifetime';
  }

  /// Indica si la Calculadora Rápida de Mostrador para Ferretería (Machimbre, Chapas, Pintura)
  /// está disponible. Requiere explícitamente rubro Ferretería (`hardware_store`),
  /// licencia activa y un plan Básico o Premium válido (SaaS o Lifetime).
  bool get canUseHardwareCalculator =>
      isHardwareStore && hasValidCalculatorLicense;

  /// True cuando la Condición frente al IVA del comercio es Responsable Inscripto
  /// (ej. 'responsable_inscripto' o 'IVA Responsable Inscripto').
  bool get isResponsableInscripto =>
      taxCondition != null &&
      taxCondition!.trim().toLowerCase().contains('inscripto');

  /// True únicamente cuando el comercio emisor es elegible como IVA Responsable Inscripto
  /// (excluyendo Monotributo, IVA Exento y valores legados inválidos como Consumidor Final)
  /// y además tiene activo el switch de Agente de Percepción IIBB.
  bool get isEffectiveIibbPerceptionAgent =>
      isIibbPerceptionAgent &&
      IibbFiscalCalculator.isIssuerEligibleForIibb(taxCondition);

  /// Indica si el módulo de Múltiples Listas de Precios está habilitado en el
  /// plan y activado por el usuario en Configuración -> Precios Globales.
  bool get hasMultiPriceEnabled =>
      features.multiplePrices && enableAdvancedPriceTiers;

  /// Factor multiplicador global para Lista Mayorista (ej: -15% o 15% -> 0.85).
  /// Tolera valores positivos o negativos para evitar recargos accidentales si se omite el signo '-'.
  double get wholesalePriceFactor =>
      1.0 - (globalWholesalePercentage.abs() / 100.0);

  /// Factor multiplicador global para Lista Tarjeta (ej: +15% -> 1.15).
  double get cardPriceFactor => 1.0 + (globalCardPercentage.abs() / 100.0);

  /// True si la lista Mayorista tiene efecto (% != 0 o permite overrides fijos por producto).
  bool get isWholesaleTierAvailable =>
      hasMultiPriceEnabled &&
      (!ignoreProductFixedPrices || globalWholesalePercentage.abs() > 0.0001);

  /// True si la lista Tarjeta tiene efecto (% != 0 o permite overrides fijos por producto).
  bool get isCardTierAvailable =>
      hasMultiPriceEnabled &&
      (!ignoreProductFixedPrices || globalCardPercentage.abs() > 0.0001);

  /// Listas personalizadas activas con nombre válido y modificador != 0%.
  List<Map<String, dynamic>> get activeCustomPriceTiers {
    if (!hasMultiPriceEnabled) return const [];
    return customPriceTiers.where((t) {
      final name = (t['name'] ?? '').toString().trim();
      if (name.isEmpty) return false;
      final mod = double.tryParse(t['modifier']?.toString() ?? '0') ?? 0.0;
      return mod.abs() > 0.0001;
    }).toList();
  }

  /// True si existe al menos una lista alternativa utilizable además de Base.
  bool get hasAnyAlternativePriceTier =>
      isWholesaleTierAvailable ||
      isCardTierAvailable ||
      activeCustomPriceTiers.isNotEmpty;

  /// Verifica si una clave de lista (`base`, `wholesale`, `card`, `custom_<nombre>`) está activa y tiene efecto.
  bool isPriceTierKeyAvailable(String tierKey) {
    if (!hasMultiPriceEnabled) return tierKey == 'base';
    switch (tierKey) {
      case 'base':
        return true;
      case 'wholesale':
        return isWholesaleTierAvailable;
      case 'card':
        return isCardTierAvailable;
      default:
        if (tierKey.startsWith('custom_')) {
          final label = tierKey.substring(7).trim();
          return activeCustomPriceTiers.any(
            (t) => (t['name'] ?? '').toString().trim() == label,
          );
        }
        return false;
    }
  }

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
    bool? isTrial,
    String? licenseBlockReason,
    String? licenseOtaToken,
    bool? licenseAllowOtaUpdates,
    DateTime? licenseOtaUnlockedUntil,
    String? licenseMaxUnlockedVersion,
    String? logoPath,
    String? logoUrl,
    double? globalWholesalePercentage,
    double? globalCardPercentage,
    List<Map<String, dynamic>>? customPriceTiers,
    String? cardSurchargeOnOffersMode,
    String? discountTierOnOffersMode,
    bool? ignoreProductFixedPrices,
    String? businessType,
    List<String>? secondaryBusinessTypes,
    FeatureFlags? features,
    bool? enableAdvancedPriceTiers,
    bool? afipEnabled,
    bool? isIibbPerceptionAgent,
    double? defaultIibbPerceptionRate,
    String? iibbCalculationBase,
    List<String>? iibbSubjectTaxConditions,
    String? taxCondition,
    String? iibb,
    String? activityStartDate,
    int? posPopularityDays,
    String? posPopularityMetric,
    bool? posDemoteOutOfStock,
    String? posPopularityResetAt,
    List<Map<String, dynamic>>? bankTransferAccounts,
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
      isTrial: isTrial ?? this.isTrial,
      licenseBlockReason: licenseBlockReason ?? this.licenseBlockReason,
      licenseOtaToken: licenseOtaToken ?? this.licenseOtaToken,
      licenseAllowOtaUpdates:
          licenseAllowOtaUpdates ?? this.licenseAllowOtaUpdates,
      licenseOtaUnlockedUntil:
          licenseOtaUnlockedUntil ?? this.licenseOtaUnlockedUntil,
      licenseMaxUnlockedVersion:
          licenseMaxUnlockedVersion ?? this.licenseMaxUnlockedVersion,
      logoPath: logoPath ?? this.logoPath,
      logoUrl: logoUrl ?? this.logoUrl,
      globalWholesalePercentage: globalWholesalePercentage ?? this.globalWholesalePercentage,
      globalCardPercentage: globalCardPercentage ?? this.globalCardPercentage,
      customPriceTiers: customPriceTiers ?? this.customPriceTiers,
      cardSurchargeOnOffersMode: cardSurchargeOnOffersMode ?? this.cardSurchargeOnOffersMode,
      discountTierOnOffersMode: discountTierOnOffersMode ?? this.discountTierOnOffersMode,
      ignoreProductFixedPrices: ignoreProductFixedPrices ?? this.ignoreProductFixedPrices,
      businessType: businessType ?? this.businessType,
      secondaryBusinessTypes:
          secondaryBusinessTypes ?? this.secondaryBusinessTypes,
      features: features ?? this.features,
      enableAdvancedPriceTiers: enableAdvancedPriceTiers ?? this.enableAdvancedPriceTiers,
      afipEnabled: afipEnabled ?? this.afipEnabled,
      isIibbPerceptionAgent: isIibbPerceptionAgent ?? this.isIibbPerceptionAgent,
      defaultIibbPerceptionRate: defaultIibbPerceptionRate ?? this.defaultIibbPerceptionRate,
      iibbCalculationBase: iibbCalculationBase ?? this.iibbCalculationBase,
      iibbSubjectTaxConditions:
          iibbSubjectTaxConditions ?? this.iibbSubjectTaxConditions,
      taxCondition: taxCondition ?? this.taxCondition,
      iibb: iibb ?? this.iibb,
      activityStartDate: activityStartDate ?? this.activityStartDate,
      posPopularityDays: posPopularityDays ?? this.posPopularityDays,
      posPopularityMetric: posPopularityMetric ?? this.posPopularityMetric,
      posDemoteOutOfStock: posDemoteOutOfStock ?? this.posDemoteOutOfStock,
      posPopularityResetAt: posPopularityResetAt ?? this.posPopularityResetAt,
      bankTransferAccounts: bankTransferAccounts ?? this.bankTransferAccounts,
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
    this.isTrial = false,
    this.licenseBlockReason,
    this.licenseOtaToken,
    this.licenseAllowOtaUpdates = true,
    this.licenseOtaUnlockedUntil,
    this.licenseMaxUnlockedVersion,
    this.logoPath,
    this.logoUrl,
    this.globalWholesalePercentage = -15.0, // Hardcoded default based on common patterns
    this.globalCardPercentage = 15.0,
    this.customPriceTiers = const [],
    this.cardSurchargeOnOffersMode = 'surcharge_on_offer',
    this.discountTierOnOffersMode = 'best_price_wins',
    this.ignoreProductFixedPrices = true,
    this.businessType = 'retail',
    this.secondaryBusinessTypes = const [],
    this.features = const FeatureFlags(),
    this.enableAdvancedPriceTiers = false,
    this.afipEnabled = false,
    this.isIibbPerceptionAgent = false,
    this.defaultIibbPerceptionRate = 0.0,
    this.iibbCalculationBase = IibbFiscalCalculator.baseNetWithoutVat,
    this.iibbSubjectTaxConditions = const ['responsable_inscripto'],
    this.taxCondition,
    this.iibb,
    this.activityStartDate,
    this.posPopularityDays = 30,
    this.posPopularityMetric = 'tickets',
    this.posDemoteOutOfStock = false,
    this.posPopularityResetAt,
    this.bankTransferAccounts = const [],
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
        isTrial,
        licenseBlockReason,
        licenseOtaToken,
        licenseAllowOtaUpdates,
        licenseOtaUnlockedUntil,
        licenseMaxUnlockedVersion,
        logoPath,
        logoUrl,
        globalWholesalePercentage,
        globalCardPercentage,
        customPriceTiers,
        cardSurchargeOnOffersMode,
        discountTierOnOffersMode,
        ignoreProductFixedPrices,
        businessType,
        secondaryBusinessTypes,
        features,
        enableAdvancedPriceTiers,
        afipEnabled,
        isIibbPerceptionAgent,
        defaultIibbPerceptionRate,
        iibbCalculationBase,
        iibbSubjectTaxConditions,
        taxCondition,
        iibb,
        activityStartDate,
        posPopularityDays,
        posPopularityMetric,
        posDemoteOutOfStock,
        posPopularityResetAt,
        bankTransferAccounts,
      ];
}
