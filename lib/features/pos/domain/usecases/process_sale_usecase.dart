import '../../domain/repositories/pos_repository.dart';
import '../../domain/entities/sale.dart';
import '../../domain/entities/cart_item.dart';

class ProcessSaleUseCase {
  final PosRepository repository;

  ProcessSaleUseCase(this.repository);

  Future<Sale> call({
    required double total,
    required String paymentMethod,
    double? tenderedAmount,
    double? changeAmount,
    required int shiftId,
    required List<CartItem> items,
    int? userId,
  }) async {
    if (items.isEmpty) throw Exception('El carrito está vacío');
    return await repository.processSale(
      total: total, 
      paymentMethod: paymentMethod,
      tenderedAmount: tenderedAmount,
      changeAmount: changeAmount,
      shiftId: shiftId, 
      items: items,
      userId: userId,
    );
  }
}
