import '../../domain/entities/sale.dart';
import 'package:frontend_desktop/features/cash_register/domain/entities/cash_register_shift.dart';

class SaleModel extends Sale {
  SaleModel({
    super.id,
    required super.total,
    required super.paymentMethod,
    required super.shift,
    super.deliveryNote,
    super.iibbPerceptionAmount,
    super.iibbPerceptionRate,
  });

  factory SaleModel.fromJson(Map<String, dynamic> json) {
    return SaleModel(
      id: json['id'] as int?,
      total: double.tryParse((json['total'] ?? 0).toString()) ?? 0.0,
      paymentMethod: json['payment_method']?.toString() ?? 'unknown',
      shift: json['shift'] != null
          ? CashRegisterShift(id: int.tryParse((json['cash_shift_id'] ?? 1).toString()) ?? 1, cashRegisterId: 1, userId: 1, openedAt: DateTime.now(), openingBalance: 0.0, status: 'open')
          : CashRegisterShift(
              id: int.tryParse((json['cash_shift_id'] ?? 1).toString()) ?? 1,
              cashRegisterId: 1,
              userId: int.tryParse((json['user_id'] ?? 1).toString()) ?? 1,
              openedAt: DateTime.now(),
              openingBalance: 0,
              status: 'open',
            ),
      deliveryNote: json['delivery_note'] as Map<String, dynamic>?,
      iibbPerceptionAmount: json['iibb_perception_amount'] != null
          ? double.tryParse(json['iibb_perception_amount'].toString())
          : null,
      iibbPerceptionRate: json['iibb_perception_rate'] != null
          ? double.tryParse(json['iibb_perception_rate'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'total': total,
      'payment_method': paymentMethod,
      'cash_shift_id': shift.id,
      if (deliveryNote != null) 'delivery_note': deliveryNote,
      if (iibbPerceptionAmount != null)
        'iibb_perception_amount': iibbPerceptionAmount,
      if (iibbPerceptionRate != null)
        'iibb_perception_rate': iibbPerceptionRate,
    };
  }
}


