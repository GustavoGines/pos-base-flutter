class ThirdPartyCheck {
  final int id;
  final String bankName;
  final String checkNumber;
  final double amount;
  final DateTime issueDate;
  final DateTime paymentDate;
  final String issuerName;
  final String issuerCuit;
  final int? customerId;
  final String? customerName;
  final String status;
  final String? endorsementNote;

  ThirdPartyCheck({
    required this.id,
    required this.bankName,
    required this.checkNumber,
    required this.amount,
    required this.issueDate,
    required this.paymentDate,
    required this.issuerName,
    required this.issuerCuit,
    this.customerId,
    this.customerName,
    required this.status,
    this.endorsementNote,
  });

  factory ThirdPartyCheck.fromJson(Map<String, dynamic> json) {
    return ThirdPartyCheck(
      id: json['id'],
      bankName: json['bank_name'] ?? '',
      checkNumber: json['check_number'] ?? '',
      amount: double.tryParse(json['amount'].toString()) ?? 0.0,
      issueDate: DateTime.parse(json['issue_date']),
      paymentDate: DateTime.parse(json['payment_date']),
      issuerName: json['issuer_name'] ?? '',
      issuerCuit: json['issuer_cuit'] ?? '',
      customerId: json['customer_id'],
      customerName: json['customer'] != null ? json['customer']['name'] : null,
      status: json['status'] ?? 'in_wallet',
      endorsementNote: json['endorsement_note'],
    );
  }
}
