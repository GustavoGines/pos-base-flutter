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
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'company_name': companyName,
      'address': address,
      'phone': phone,
    };
  }
}
