class Supplier {
  final int id;
  final String name;
  final String? cuit;
  final String? taxCategory;
  final String? contactName;
  final String? phone;
  final String? email;
  final String? address;
  final double balance;
  final bool isActive;

  Supplier({
    required this.id,
    required this.name,
    this.cuit,
    this.taxCategory,
    this.contactName,
    this.phone,
    this.email,
    this.address,
    required this.balance,
    required this.isActive,
  });

  factory Supplier.fromJson(Map<String, dynamic> json) {
    return Supplier(
      id: json['id'],
      name: json['name'],
      cuit: json['cuit'],
      taxCategory: json['tax_category'],
      contactName: json['contact_name'],
      phone: json['phone'],
      email: json['email'],
      address: json['address'],
      balance: double.tryParse(json['balance'].toString()) ?? 0.0,
      isActive: json['is_active'] == 1 || json['is_active'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'cuit': cuit,
      'tax_category': taxCategory,
      'contact_name': contactName,
      'phone': phone,
      'email': email,
      'address': address,
      'balance': balance,
      'is_active': isActive,
    };
  }
}
