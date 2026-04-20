import 'package:frontend_desktop/features/cash_register/domain/entities/cash_register_shift.dart';

class Sale {
  final int? id;
  final double total;
  final String paymentMethod;
  final CashRegisterShift shift;
  final Map<String, dynamic>? deliveryNote;

  Sale({
    this.id,
    required this.total,
    required this.paymentMethod,
    required this.shift,
    this.deliveryNote,
  });
}
  