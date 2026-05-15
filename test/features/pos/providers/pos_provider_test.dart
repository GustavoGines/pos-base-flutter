import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend_desktop/features/pos/presentation/providers/pos_provider.dart';
import 'package:frontend_desktop/features/pos/domain/usecases/process_sale_usecase.dart';
import 'package:frontend_desktop/features/pos/domain/usecases/search_products_usecase.dart';
import 'package:frontend_desktop/features/pos/domain/repositories/pos_repository.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/core/utils/receipt_printer_service.dart';

@GenerateMocks([
  ProcessSaleUseCase,
  SearchProductsUseCase,
  PosRepository,
  ReceiptPrinterService,
])
import 'pos_provider_test.mocks.dart';

void main() {
  late PosProvider provider;
  late MockProcessSaleUseCase mockProcessSaleUseCase;
  late MockSearchProductsUseCase mockSearchProductsUseCase;
  late MockPosRepository mockPosRepository;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    
    mockProcessSaleUseCase = MockProcessSaleUseCase();
    mockSearchProductsUseCase = MockSearchProductsUseCase();
    mockPosRepository = MockPosRepository();

    when(mockPosRepository.fetchPaymentMethods()).thenAnswer((_) async => []);

    provider = PosProvider(
      processSaleUseCase: mockProcessSaleUseCase,
      searchProductsUseCase: mockSearchProductsUseCase,
      repository: mockPosRepository,
    );
  });

  group('PosProvider Cart Calculations', () {
    final product1 = Product(
      id: 1,
      name: 'Coca Cola 1.5L',
      internalCode: 'P01',
      costPrice: 500,
      sellingPrice: 1000.0,
      stock: 100,
      active: true,
      isSoldByWeight: false,
    );

    final product2 = Product(
      id: 2,
      name: 'Pan',
      internalCode: 'P02',
      costPrice: 200,
      sellingPrice: 300.0,
      stock: 50,
      active: true,
      isSoldByWeight: true,
    );

    test('Sumatoria exacta de subtotales (Cantidad x Precio Unitario)', () {
      // Agregamos unidad simple
      provider.requestAddToCart(product1);
      
      // Agregamos producto por peso (2.5 Kg)
      provider.submitWeighedProduct(product2, 2.5);

      // Coca Cola = 1 x 1000 = 1000
      // Pan = 2.5 x 300 = 750
      // Subtotal esperado = 1750
      expect(provider.cartSubtotal, 1750.0);
    });

    test('Sumatoria al actualizar cantidad de un item', () {
      provider.requestAddToCart(product1);
      
      // Aumentamos a 3 unidades
      provider.updateQuantity(provider.cart[0], 3);

      expect(provider.cartSubtotal, 3000.0);
    });

    test('Cálculo de vuelto (Change) esperado cuando se recibe efectivo', () {
      provider.requestAddToCart(product1); // Subtotal 1000
      
      double tenderedAmount = 1500.0;
      double change = tenderedAmount - provider.cartSubtotal;
      
      expect(change, 500.0);
    });
  });
}
