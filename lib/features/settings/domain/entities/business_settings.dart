class BusinessSettings {
  final String companyName;
  final String currencySymbol;
  final String timezone;
  final String receiptFooterMessage;
  final String? taxId;
  final String? logoPath;
  final String? address;
  final String? phone;

  BusinessSettings({
    required this.companyName,
    required this.currencySymbol,
    required this.timezone,
    required this.receiptFooterMessage,
    this.taxId,
    this.logoPath,
    this.address,
    this.phone,
  });
}
