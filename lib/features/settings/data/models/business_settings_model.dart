import '../../domain/entities/business_settings.dart';

class BusinessSettingsModel extends BusinessSettings {
  BusinessSettingsModel({
    required String companyName,
    required String currencySymbol,
    required String timezone,
    required String receiptFooterMessage,
    String? taxId,
    String? logoPath,
    String? address,
    String? phone,
  }) : super(
          companyName: companyName,
          currencySymbol: currencySymbol,
          timezone: timezone,
          receiptFooterMessage: receiptFooterMessage,
          taxId: taxId,
          logoPath: logoPath,
          address: address,
          phone: phone,
        );

  factory BusinessSettingsModel.fromJson(Map<String, dynamic> json) {
    return BusinessSettingsModel(
      companyName: json['company_name'] ?? 'Mi Negocio',
      currencySymbol: json['currency_symbol'] ?? '\$',
      timezone: json['timezone'] ?? 'UTC',
      receiptFooterMessage: json['receipt_footer_message'] ?? '',
      taxId: json['tax_id'],
      logoPath: json['logo_path'],
      address: json['address'],
      phone: json['phone'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'company_name': companyName,
      'currency_symbol': currencySymbol,
      'timezone': timezone,
      'receipt_footer_message': receiptFooterMessage,
      'tax_id': taxId,
      'logo_path': logoPath,
      'address': address,
      'phone': phone,
    };
  }
}
