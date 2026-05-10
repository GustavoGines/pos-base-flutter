import 'dart:typed_data';
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
  Future<List<Map<String, dynamic>>> fetchPaymentMethods() async {
    final list = await remoteDataSource.fetchPaymentMethods();
    return list.cast<Map<String, dynamic>>();
  }

  @override
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
    String? priceList,
  }) async {
    final response = await remoteDataSource.processSale(
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
      shippingCost: shippingCost,
      requiresDispatch: requiresDispatch,
      fulfillmentStatus: fulfillmentStatus,
      checkDetails: checkDetails,
      deliveryAddress: deliveryAddress,
      priceList: priceList,
    );

    return Sale(
      id: response['sale']['id'],
      total: total,
      paymentMethod: (payments != null && payments.isNotEmpty) ? payments.first['payment_method_id']?.toString() ?? 'unknown' : 'unknown',
      shift: CashRegisterShift(
        id: shiftId,
        cashRegisterId: 1, // Dummy reference since Pos logic only cares about shiftId locally
        userId: userId ?? 1,
        openedAt: DateTime.now(),
        openingBalance: 0,
        status: 'open',
      ),
      deliveryNote: response['sale']['delivery_note'],
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
    required double totalSurcharge,
    required List<Map<String, dynamic>> payments,
    required double tenderedAmount,
    required double changeAmount,
    required int shiftId,
    int? userId,
    List<CartItem>? items,
    double shippingCost = 0.0,
    Map<String, dynamic>? checkDetails,
  }) async {
    final response = await remoteDataSource.payPendingSale(
      saleId: saleId,
      totalSurcharge: totalSurcharge,
      payments: payments,
      tenderedAmount: tenderedAmount,
      changeAmount: changeAmount,
      shiftId: shiftId,
      userId: userId,
      items: items,
      shippingCost: shippingCost,
      checkDetails: checkDetails,
    );
    return response as Map<String, dynamic>;
  }

  @override
  Future<Map<String, dynamic>> voidPendingSale(int saleId) async {
    final response = await remoteDataSource.voidPendingSale(saleId);
    return response as Map<String, dynamic>;
  }

  @override
  Future<void> updatePaymentMethodSurcharge(int id, double surchargeValue) async {
    await remoteDataSource.updatePaymentMethodSurcharge(id, surchargeValue);
  }

  @override
  Future<Uint8List> downloadTicketPdf(int saleId) async {
    return await remoteDataSource.downloadTicketPdf(saleId);
  }

  @override
  Future<Map<String, dynamic>> createDeliveryNoteFromSale(int saleId, {String fulfillmentStatus = 'pending'}) async {
    return await remoteDataSource.createDeliveryNoteFromSale(saleId, fulfillmentStatus: fulfillmentStatus);
  }
}
