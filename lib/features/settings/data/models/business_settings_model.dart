import 'dart:convert';
import '../../domain/entities/business_settings.dart';

class BusinessSettingsModel extends BusinessSettings {
  const BusinessSettingsModel({
    String? companyName,
    String? address,
    String? phone,
    String? taxId,
    String? receiptFooterMessage,
    String printerType = 'none',
    String printerPaperWidth = '58',
    String? printerComPort,
    String? printerIpAddress,
    String? printerIpPort,
    String? comPortScale,
    String? licenseStatus,
    String? licensePlanType,
    String? licensePlanMode,
    List<String>? licenseAllowedAddons,
    String? lastLicenseCheck,
    String? serverTime,
    DateTime? licenseExpiresAt,
    DateTime? licenseNextPaymentAt,
    String? licenseManageUrl,
    bool isLifetime = false,
    String businessType = 'retail',
    FeatureFlags features = const FeatureFlags(),
  }) : super(
          companyName: companyName,
          address: address,
          phone: phone,
          taxId: taxId,
          receiptFooterMessage: receiptFooterMessage,
          printerType: printerType,
          printerPaperWidth: printerPaperWidth,
          printerComPort: printerComPort,
          printerIpAddress: printerIpAddress,
          printerIpPort: printerIpPort,
          comPortScale: comPortScale,
          licenseStatus: licenseStatus,
          licensePlanType: licensePlanType,
          licensePlanMode: licensePlanMode,
          licenseAllowedAddons: licenseAllowedAddons,
          lastLicenseCheck: lastLicenseCheck,
          serverTime: serverTime,
          licenseExpiresAt: licenseExpiresAt,
          licenseNextPaymentAt: licenseNextPaymentAt,
          licenseManageUrl: licenseManageUrl,
          isLifetime: isLifetime,
          businessType: businessType,
          features: features,
        );

  factory BusinessSettingsModel.fromJson(Map<String, dynamic> json) {
    // Parsear el diccionario de features dinámico
    final Map<String, dynamic> featuresMap = json['features'] ?? {};
    
    final featureFlags = FeatureFlags(
      fastPos: featuresMap['fast_pos'] ?? false,
      zReports: featuresMap['z_reports'] ?? false,
      quotes: featuresMap['quotes'] ?? false,
      currentAccounts: featuresMap['current_accounts'] ?? false,
      multiplePrices: featuresMap['multiple_prices'] ?? false,
      multiCaja: featuresMap['multi_caja'] ?? false,
      advancedReports: featuresMap['advanced_reports'] ?? false,
      predictiveAlerts: featuresMap['predictive_alerts'] ?? false,
    );

    return BusinessSettingsModel(
      companyName: json['company_name'],
      address: json['address'],
      phone: json['phone'],
      taxId: json['tax_id'],
      receiptFooterMessage: json['receipt_footer_message'],
      printerType: json['printer_type'] ?? 'none',
      printerPaperWidth: json['printer_paper_width'] ?? '58',
      printerComPort: json['printer_com_port'],
      printerIpAddress: json['printer_ip_address'],
      printerIpPort: json['printer_ip_port'],
      comPortScale: json['com_port_scale'],
      licenseStatus: json['license_key'],      // The actual license key string
      licensePlanType: json['app_plan'],        // Written by LicenseSyncService as 'app_plan'
      licensePlanMode: json['license_plan_mode'] ?? 'saas',
      licenseAllowedAddons: _parseList(json['license_allowed_addons']),
      lastLicenseCheck: json['last_license_check'],
      serverTime: json['server_time'],
      licenseExpiresAt: json['license_expires_at'] != null ? DateTime.tryParse(json['license_expires_at']) : null,
      licenseNextPaymentAt: json['license_next_payment_at'] != null ? DateTime.tryParse(json['license_next_payment_at']) : null,
      licenseManageUrl: json['license_manage_url'],
      isLifetime: json['license_is_lifetime'] == '1',
      businessType: json['license_business_type'] ?? 'retail',
      features: featureFlags,
    );
  }

  /// Parser ultra-seguro: nunca crashea. Acepta null, String JSON o List nativa.
  static List<String> _parseList(dynamic value) {
    if (value == null) return [];
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    if (value is String) {
      if (value.isEmpty) return [];
      try {
        final decoded = jsonDecode(value);
        if (decoded is List) {
          return decoded.map((e) => e.toString()).toList();
        }
      } catch (_) {
        return [];
      }
    }
    return [];
  }

  Map<String, dynamic> toJson() {
    return {
      'company_name': companyName,
      'address': address,
      'phone': phone,
    };
  }
}
