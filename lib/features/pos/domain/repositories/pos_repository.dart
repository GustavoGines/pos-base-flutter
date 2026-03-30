import 'package:frontend_desktop/features/pos/domain/entities/cart_item.dart';
import 'package:frontend_desktop/features/pos/domain/entities/sale.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';

abstract class PosRepository {
  Future<List<Product>> searchProducts(String query);
  Future<List<Map<String, dynamic>>> fetchPaymentMethods();
  
  Future<Sale> processSale({
    required double total,
    required double totalSurcharge,
    List<Map<String, dynamic>>? payments,
    double? tenderedAmount,
    double? changeAmount,
    required int shiftId,
    required List<CartItem> items,
    int? userId,
    int? customerId,
    String status,
  });
  Future<List<Map<String, dynamic>>> fetchPendingSales();
  Future<Map<String, dynamic>> payPendingSale({
    required int saleId,
    required double totalSurcharge,
    required List<Map<String, dynamic>> payments,
    required double tenderedAmount,
    required double changeAmount,
    List<CartItem>? items,
  });
  Future<Map<String, dynamic>> voidPendingSale(int saleId);
}
