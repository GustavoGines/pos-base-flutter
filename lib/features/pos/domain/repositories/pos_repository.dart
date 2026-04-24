import 'dart:typed_data';
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
    int? quoteId,
    String status = 'completed',
    double shippingCost = 0.0,
    bool requiresDispatch = false,
    String fulfillmentStatus = 'pending',
    Map<String, dynamic>? checkDetails,
    String? deliveryAddress,
  });
  Future<List<Map<String, dynamic>>> fetchPendingSales();
  Future<Map<String, dynamic>> payPendingSale({
    required int saleId,
    required double totalSurcharge,
    required List<Map<String, dynamic>> payments,
    required double tenderedAmount,
    required double changeAmount,
    int? userId,
    List<CartItem>? items,
    double shippingCost = 0.0,
    Map<String, dynamic>? checkDetails,
  });
  Future<Map<String, dynamic>> voidPendingSale(int saleId);
  Future<void> updatePaymentMethodSurcharge(int id, double surchargeValue);
  Future<Uint8List> downloadTicketPdf(int saleId);
  /// Crea automáticamente un Remito de Logística a partir de una venta ya procesada.
  /// Se llama como side-effect silencioso cuando el cajero activa "Enviar a Logística".
  Future<Map<String, dynamic>> createDeliveryNoteFromSale(int saleId, {String fulfillmentStatus = 'pending'});
}
