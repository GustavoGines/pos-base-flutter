import '../../domain/repositories/pos_repository.dart';
import '../../domain/entities/sale.dart';
import '../../domain/entities/cart_item.dart';

class ProcessSaleUseCase {
  final PosRepository repository;

  ProcessSaleUseCase(this.repository);

  Future<Sale> call({
    required double total,
    required double totalSurcharge,
    List<Map<String, dynamic>>? payments,
    double? tenderedAmount,
    double? changeAmount,
    required int shiftId,
    required List<CartItem> items,
    int? userId,
    int? customerId,
    int? quoteId,
    String status = 'completed',
  }) async {
    if (items.isEmpty) throw Exception('El carrito está vacío');
    return await repository.processSale(
      total: total,
      totalSurcharge: totalSurcharge,
      payments: payments,
      tenderedAmount: tenderedAmount,
      changeAmount: changeAmount,
      shiftId: shiftId,
      items: items,
      userId: userId,
      customerId: customerId,
      quoteId: quoteId,
      status: status,
    );
  }
}
