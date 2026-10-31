class CustomerTransaction {
  final int id;
  final int customerId;
  final int userId;
  final int? saleId;
  final String type; // 'charge' or 'payment'
  final double amount;
  final double balanceAfter;
  final String? description;
  final String? paymentMethod; // 'efectivo', 'transferencia', 'cheque', etc.
  final DateTime createdAt;

  CustomerTransaction({
    required this.id,
    required this.customerId,
    required this.userId,
    this.saleId,
    required this.type,
    required this.amount,
    required this.balanceAfter,
    this.description,
    this.paymentMethod,
    required this.createdAt,
  });

  factory CustomerTransaction.fromJson(Map<String, dynamic> json) {
    return CustomerTransaction(
      id: json['id'],
      customerId: json['customer_id'],
      userId: json['user_id'],
      saleId: json['sale_id'],
      type: json['type'],
      amount: double.tryParse(json['amount'].toString()) ?? 0.0,
      balanceAfter: double.tryParse(json['balance_after'].toString()) ?? 0.0,
      description: json['description'],
      paymentMethod: json['payment_method'],
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}

class Customer {
  final int id;
  final String name;
  final String? phone;
  final String documentNumber;
  final int documentType; // 80=CUIT, 86=CUIL, 96=DNI, 99=Consumidor Final (default 96)
  final String taxCondition; // 'consumidor_final', 'responsable_inscripto', 'monotributo', 'exento'
  final String? fiscalAddress;
  final double creditLimit;
  final double balance;
  final bool isActive;
  final String? defaultPriceTier; // 'base', 'wholesale', 'card'
  final String? deliveryAddress;
  final bool isInternalAccount;
  final bool appliesIibbPerception;
  final double? iibbPerceptionRate;
  final List<CustomerTransaction> transactions;

  Customer({
    required this.id,
    required this.name,
    this.phone,
    required this.documentNumber,
    this.documentType = 96,
    this.taxCondition = 'consumidor_final',
    this.fiscalAddress,
    required this.creditLimit,
    required this.balance,
    required this.isActive,
    this.defaultPriceTier,
    this.deliveryAddress,
    this.isInternalAccount = false,
    this.appliesIibbPerception = false,
    this.iibbPerceptionRate,
    this.transactions = const [],
  });

  factory Customer.fromJson(Map<String, dynamic> json) {
    return Customer(
      id: json['id'],
      name: json['name'],
      phone: json['phone'],
      documentNumber: json['document_number'] ?? '',
      documentType: int.tryParse(json['document_type']?.toString() ?? '96') ?? 96,
      taxCondition: json['tax_condition']?.toString() ?? 'consumidor_final',
      fiscalAddress: json['fiscal_address']?.toString(),
      creditLimit: double.tryParse(json['credit_limit']?.toString() ?? '0') ?? 0.0,
      balance: double.tryParse(json['balance']?.toString() ?? '0') ?? 0.0,
      isActive: json['is_active'] == 1 || json['is_active'] == true,
      defaultPriceTier: json['default_price_tier'],
      deliveryAddress: json['delivery_address'],
      isInternalAccount: json['is_internal_account'] == 1 || json['is_internal_account'] == true,
      appliesIibbPerception: json['applies_iibb_perception'] == 1 ||
          json['applies_iibb_perception'] == true ||
          json['applies_iibb_perception'] == '1',
      iibbPerceptionRate: json['iibb_perception_rate'] != null
          ? double.tryParse(json['iibb_perception_rate'].toString().replaceAll(',', '.'))
          : null,
      transactions: json['transactions'] != null
          ? (json['transactions'] as List).map((t) => CustomerTransaction.fromJson(t)).toList()
          : [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'document_number': documentNumber,
      'document_type': documentType,
      'tax_condition': taxCondition,
      'fiscal_address': fiscalAddress,
      'credit_limit': creditLimit,
      'balance': balance,
      'is_active': isActive,
      'default_price_tier': defaultPriceTier,
      'delivery_address': deliveryAddress,
      'is_internal_account': isInternalAccount,
      'applies_iibb_perception': appliesIibbPerception,
      if (appliesIibbPerception && iibbPerceptionRate != null)
        'iibb_perception_rate': iibbPerceptionRate,
    };
  }

  Customer copyWith({
    int? id,
    String? name,
    String? phone,
    String? documentNumber,
    int? documentType,
    String? taxCondition,
    String? fiscalAddress,
    double? creditLimit,
    double? balance,
    bool? isActive,
    String? defaultPriceTier,
    String? deliveryAddress,
    bool? isInternalAccount,
    bool? appliesIibbPerception,
    double? iibbPerceptionRate,
    List<CustomerTransaction>? transactions,
  }) {
    return Customer(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      documentNumber: documentNumber ?? this.documentNumber,
      documentType: documentType ?? this.documentType,
      taxCondition: taxCondition ?? this.taxCondition,
      fiscalAddress: fiscalAddress ?? this.fiscalAddress,
      creditLimit: creditLimit ?? this.creditLimit,
      balance: balance ?? this.balance,
      isActive: isActive ?? this.isActive,
      defaultPriceTier: defaultPriceTier ?? this.defaultPriceTier,
      deliveryAddress: deliveryAddress ?? this.deliveryAddress,
      isInternalAccount: isInternalAccount ?? this.isInternalAccount,
      appliesIibbPerception: appliesIibbPerception ?? this.appliesIibbPerception,
      iibbPerceptionRate: (appliesIibbPerception == false)
          ? null
          : (iibbPerceptionRate ?? this.iibbPerceptionRate),
      transactions: transactions ?? this.transactions,
    );
  }
}

/// Validador oficial de Módulo 11 para CUIT/CUIL y DNI (AFIP / ARCA RG 4892)
class AfipModulo11 {
  static const List<int> multipliers = [5, 4, 3, 2, 7, 6, 5, 4, 3, 2];

  /// Alias conveniente para validar CUIT/CUIL con Módulo 11
  static bool isValid(String? cuit) => validateCuit(cuit);

  /// Valida CUIT / CUIL usando el algoritmo oficial de Módulo 11 con ponderadores [5,4,3,2,7,6,5,4,3,2].
  /// Resto 0 -> 0, resto 1 -> inválido, otro -> 11 - resto.
  static bool validateCuit(String? cuit) {
    if (cuit == null) return false;
    final clean = cuit.replaceAll(RegExp(r'\D'), '');
    if (clean.length != 11) return false;

    final validPrefixes = ['20', '23', '24', '27', '30', '33', '34'];
    final prefix = clean.substring(0, 2);
    if (!validPrefixes.contains(prefix)) return false;

    int sum = 0;
    for (int i = 0; i < 10; i++) {
      sum += int.parse(clean[i]) * multipliers[i];
    }

    final remainder = sum % 11;
    int expectedDigit;
    if (remainder == 0) {
      expectedDigit = 0;
    } else if (remainder == 1) {
      return false;
    } else {
      expectedDigit = 11 - remainder;
    }

    return int.parse(clean[10]) == expectedDigit;
  }

  /// Valida DNI argentino (numérico entre 7 y 8 dígitos, rango 1.000.000 a 99.999.999).
  static bool validateDni(String? dni) {
    if (dni == null) return false;
    final clean = dni.replaceAll(RegExp(r'\D'), '');
    if (clean.length < 7 || clean.length > 8) return false;
    final num = int.tryParse(clean);
    if (num == null) return false;
    return num >= 1000000 && num <= 99999999;
  }

  /// Detecta inteligentemente el Tipo de Documento AFIP/ARCA (80=CUIT, 86=CUIL, 96=DNI, 99=S/D)
  /// a medida que el usuario tipea los dígitos.
  static int inferDocType(
    String? rawInput, {
    int currentDocType = 96,
    bool isFacturaA = false,
    bool requiresIdentification = false,
  }) {
    if (isFacturaA) return 80;
    final digits = (rawInput ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      return requiresIdentification ? 96 : 99;
    }
    if (digits.length <= 8) {
      return 96; // DNI (mientras tipea hasta 8 dígitos)
    }
    // 9 a 11 dígitos -> CUIT (80) o CUIL (86)
    final isCompanyPrefix = digits.startsWith('30') ||
        digits.startsWith('33') ||
        digits.startsWith('34');
    if (isCompanyPrefix) return 80;
    if (currentDocType == 86) return 86;
    return 80;
  }

  /// Busca instantáneamente en el padrón local de clientes por coincidencia exacta
  /// de DNI/CUIT o por cruce inteligente entre DNI (7-8 dígitos) y los 8 dígitos centrales del CUIT/CUIL (11 dígitos).
  static Customer? findMatchingCustomer(
    Iterable<Customer> customers,
    String? rawInput,
  ) {
    final digits = (rawInput ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.length < 7) return null;
    if (digits.length > 8 && digits.length < 11) return null;

    // 1. Coincidencia exacta de dígitos
    for (final c in customers) {
      final cDigits = c.documentNumber.replaceAll(RegExp(r'\D'), '');
      if (cDigits.isNotEmpty && cDigits == digits) {
        return c;
      }
    }

    // 2. Cruce inteligente DNI (7-8 dígitos) <-> CUIT/CUIL (11 dígitos)
    String? targetDni;
    if (digits.length >= 7 && digits.length <= 8) {
      targetDni = digits.replaceFirst(RegExp(r'^0+'), '');
    } else if (digits.length == 11) {
      targetDni = digits.substring(2, 10).replaceFirst(RegExp(r'^0+'), '');
    }

    if (targetDni != null && targetDni.length >= 7) {
      for (final c in customers) {
        final cDigits = c.documentNumber.replaceAll(RegExp(r'\D'), '');
        if (cDigits.length >= 7 && cDigits.length <= 8) {
          if (cDigits.replaceFirst(RegExp(r'^0+'), '') == targetDni) {
            return c;
          }
        } else if (cDigits.length == 11) {
          final cMiddleDni =
              cDigits.substring(2, 10).replaceFirst(RegExp(r'^0+'), '');
          if (cMiddleDni == targetDni) {
            return c;
          }
        }
      }
    }

    return null;
  }
}
