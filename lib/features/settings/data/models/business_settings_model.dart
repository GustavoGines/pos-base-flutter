import 'dart:convert';
import '../../domain/entities/business_settings.dart';

class BusinessSettingsModel extends BusinessSettings {
  const BusinessSettingsModel({
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
    bool isLifetime = false,
    double globalWholesalePercentage = -15.0,
    double globalCardPercentage = 15.0,
    List<Map<String, dynamic>> customPriceTiers = const [],
    String businessType = 'retail',
    FeatureFlags features = const FeatureFlags(),
  }) : super(
          companyName: companyName,
          address: address,
          phone: phone,
          taxId: taxId,
          receiptFooterMessage: receiptFooterMessage,
          licenseStatus: licenseStatus,
          licensePlanType: licensePlanType,
          licensePlanMode: licensePlanMode,
          lastLicenseCheck: lastLicenseCheck,
          serverTime: serverTime,
          licenseExpiresAt: licenseExpiresAt,
          licenseNextPaymentAt: licenseNextPaymentAt,
          licenseManageUrl: licenseManageUrl,
          isLifetime: isLifetime,
          globalWholesalePercentage: globalWholesalePercentage,
          globalCardPercentage: globalCardPercentage,
          customPriceTiers: customPriceTiers,
          businessType: businessType,
          features: features,
        );

  factory BusinessSettingsModel.fromJson(Map<String, dynamic> json) {
    // Parser ultra-robusto para el diccionario de features
    Map<String, dynamic> featuresMap = {};
    final rawFeatures = json['license_features_dict'];
    
    if (rawFeatures != null) {
      if (rawFeatures is Map<String, dynamic>) {
        featuresMap = rawFeatures;
      } else if (rawFeatures is String && rawFeatures.isNotEmpty) {
        try {
          final decoded = jsonDecode(rawFeatures);
          if (decoded is Map<String, dynamic>) {
            featuresMap = decoded;
          }
        } catch (e) {
          // Log silencioso si falla la decodificación del string
          print('Error decodificando license_features_dict: $e');
        }
      }
    }
    
    // Fallback: Si no hay dict, intentamos leer 'features' (para respuestas directas de API)
    if (featuresMap.isEmpty && json['features'] is Map<String, dynamic>) {
      featuresMap = json['features'];
    }
    
    final featureFlags = FeatureFlags(
      fastPos: featuresMap['fast_pos'] == true || featuresMap['fast_pos'] == 1,
      zReports: featuresMap['z_reports'] == true || featuresMap['z_reports'] == 1,
      quotes: featuresMap['quotes'] == true || featuresMap['quotes'] == 1,
      currentAccounts: featuresMap['current_accounts'] == true || featuresMap['current_accounts'] == 1,
      multiplePrices: featuresMap['multiple_prices'] == true || featuresMap['multiple_prices'] == 1,
      multiCaja: featuresMap['multi_caja'] == true || featuresMap['multi_caja'] == 1,
      advancedReports: featuresMap['advanced_reports'] == true || featuresMap['advanced_reports'] == 1,
      predictiveAlerts: featuresMap['predictive_alerts'] == true || featuresMap['predictive_alerts'] == 1,
      logistics: featuresMap['logistics'] == true || featuresMap['logistics'] == 1,
    );

    return BusinessSettingsModel(
      companyName: json['company_name'],
      address: json['address'],
      phone: json['phone'],
      taxId: json['tax_id'],
      receiptFooterMessage: json['receipt_footer_message'],
      licenseStatus: json['license_key'],      // The actual license key string
      licensePlanType: json['app_plan'],        // Written by LicenseSyncService as 'app_plan'
      licensePlanMode: json['license_plan_mode'] ?? 'saas',
      lastLicenseCheck: json['last_license_check'],
      serverTime: json['server_time'],
      licenseExpiresAt: json['license_expires_at'] != null ? DateTime.tryParse(json['license_expires_at']) : null,
      licenseNextPaymentAt: json['license_next_payment_at'] != null ? DateTime.tryParse(json['license_next_payment_at']) : null,
      licenseManageUrl: json['license_manage_url'],
      isLifetime: json['license_is_lifetime'] == '1',
      globalWholesalePercentage: double.tryParse(json['wholesale_percentage']?.toString() ?? '-15.0') ?? -15.0,
      globalCardPercentage: double.tryParse(json['card_percentage']?.toString() ?? '15.0') ?? 15.0,
      customPriceTiers: _parseCustomTiers(json['custom_price_tiers']),
      businessType: json['license_business_type'] ?? 'retail',
      features: featureFlags,
    );
  }

  /// Parsea el campo custom_price_tiers de forma segura (acepta JSON string o lista directa)
  static List<Map<String, dynamic>> _parseCustomTiers(dynamic raw) {
    if (raw == null) return const [];
    try {
      List<dynamic> list;
      if (raw is String && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is! List) return const [];
        list = decoded;
      } else if (raw is List) {
        list = raw;
      } else {
        return const [];
      }
      return list
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (e) {
      return const [];
    }
  }



  Map<String, dynamic> toJson() {
    return {
      'company_name': companyName,
      'address': address,
      'phone': phone,
    };
  }
}
