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
  }) : super(
          companyName: companyName,
          address: address,
          phone: phone,
          taxId: taxId,
          receiptFooterMessage: receiptFooterMessage,
          printerType: printerType,
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
        );

  factory BusinessSettingsModel.fromJson(Map<String, dynamic> json) {
    return BusinessSettingsModel(
      companyName: json['company_name'],
      address: json['address'],
      phone: json['phone'],
      taxId: json['tax_id'],
      receiptFooterMessage: json['receipt_footer_message'],
      printerType: json['printer_type'] ?? 'none',
      printerComPort: json['printer_com_port'],
      printerIpAddress: json['printer_ip_address'],
      printerIpPort: json['printer_ip_port'],
      comPortScale: json['com_port_scale'],
      licenseStatus: json['license_key'],     // The actual license key string
      licensePlanType: json['app_plan'],       // Written by LicenseSyncService as 'app_plan'
      licensePlanMode: json['license_plan_mode'] ?? 'saas',
      licenseAllowedAddons: _parseAddons(json['license_allowed_addons']),
      lastLicenseCheck: json['last_license_check'],
      serverTime: json['server_time'],
    );
  }

  static List<String>? _parseAddons(dynamic value) {
    if (value == null) return null;
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    if (value is String) {
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
