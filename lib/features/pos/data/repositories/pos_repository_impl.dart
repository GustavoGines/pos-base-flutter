import '../../domain/repositories/pos_repository.dart';
import '../datasources/pos_remote_datasource.dart';
import '../../domain/entities/sale.dart';
import '../../domain/entities/cart_item.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/cash_register/domain/entities/cash_register_shift.dart';

class PosRepositoryImpl implements PosRepository {
  final PosRemoteDataSource remoteDataSource;

  PosRepositoryImpl({required this.remoteDataSource});

  @override
  Future<List<Product>> searchProducts(String query) async {
    return await remoteDataSource.searchProducts(query);
  }

  @override
  Future<Sale> processSale({
    required double total,
    required String paymentMethod,
    double? tenderedAmount,
    double? changeAmount,
    required int shiftId,
    required List<CartItem> items,
    int? userId,
  }) async {
    // Retornamos un Sale 'dummy' o parseado tras la respuesta correcta para fines de la app
    final response = await remoteDataSource.processSale(
      total: total,
      paymentMethod: paymentMethod,
      tenderedAmount: tenderedAmount,
      changeAmount: changeAmount,
      shiftId: shiftId,
      items: items,
      userId: userId,
    );
    
    return Sale(
      id: response['sale']['id'],
      total: total,
      paymentMethod: paymentMethod,
      shift: CashRegisterShift(
        id: shiftId,
        openedAt: DateTime.now(),
        openingBalance: 0,
        status: 'open'
      )
    );
  }
}
