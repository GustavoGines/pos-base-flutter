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
    String status = 'completed',
  }) async {
    final response = await remoteDataSource.processSale(
      total: total,
      paymentMethod: paymentMethod,
      tenderedAmount: tenderedAmount,
      changeAmount: changeAmount,
      shiftId: shiftId,
      items: items,
      userId: userId,
      status: status,
    );

    return Sale(
      id: response['sale']['id'],
      total: total,
      paymentMethod: paymentMethod,
      shift: CashRegisterShift(
        id: shiftId,
        openedAt: DateTime.now(),
        openingBalance: 0,
        status: 'open',
      ),
    );
  }

  @override
  Future<List<Map<String, dynamic>>> fetchPendingSales() async {
    final list = await remoteDataSource.fetchPendingSales();
    return list.cast<Map<String, dynamic>>();
  }

  @override
  Future<Map<String, dynamic>> payPendingSale({
    required int saleId,
    required String paymentMethod,
    required double tenderedAmount,
    required double changeAmount,
    List<CartItem>? items,
  }) async {
    final response = await remoteDataSource.payPendingSale(
      saleId: saleId,
      paymentMethod: paymentMethod,
      tenderedAmount: tenderedAmount,
      changeAmount: changeAmount,
      items: items,
    );
    return response as Map<String, dynamic>;
  }
}
