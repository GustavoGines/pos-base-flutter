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
import 'package:frontend_desktop/features/pos/domain/entities/cart_item.dart';
import 'package:frontend_desktop/features/offers/data/models/offer_model.dart';
import 'package:frontend_desktop/features/customers/models/customer_model.dart';

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

    test('CartItem promotional offer badges and period types', () {
      final itemDaily = CartItem(
        product: product1,
        promotionalPrice: 800.0,
        promotionalPeriodType: 'daily',
        promotionalLabel: 'Oferta Relámpago',
      );
      expect(itemDaily.hasActiveOffer, isTrue);
      expect(itemDaily.offerBadgeLabel, 'Oferta Diaria');
      expect(itemDaily.unitPrice, 800.0);

      final itemWeekly = CartItem(
        product: product1,
        promotionalPrice: 850.0,
        promotionalPeriodType: 'weekly',
      );
      expect(itemWeekly.hasActiveOffer, isTrue);
      expect(itemWeekly.offerBadgeLabel, 'Oferta Semanal');

      final itemMonthly = CartItem(
        product: product1,
        promotionalPrice: 900.0,
        promotionalPeriodType: 'monthly',
      );
      expect(itemMonthly.hasActiveOffer, isTrue);
      expect(itemMonthly.offerBadgeLabel, 'Oferta Mensual');

      final itemNamed = CartItem(
        product: product1,
        promotionalPrice: 950.0,
        promotionalLabel: 'Liquidación Verano',
      );
      expect(itemNamed.hasActiveOffer, isTrue);
      expect(itemNamed.offerBadgeLabel, 'Oferta: Liquidación Verano');

      final itemAlreadyPrefixed = CartItem(
        product: product1,
        promotionalPrice: 950.0,
        promotionalLabel: 'Oferta Especial Fin de Año',
      );
      expect(itemAlreadyPrefixed.offerBadgeLabel, 'Oferta Especial Fin de Año');

      final itemPromoPrefixed = CartItem(
        product: product1,
        promotionalPrice: 950.0,
        promotionalLabel: 'Promo 2x1',
      );
      expect(itemPromoPrefixed.offerBadgeLabel, 'Promo 2x1');

      final itemRegular = CartItem(product: product1);
      expect(itemRegular.hasActiveOffer, isFalse);
    });

    test('PosProvider requestAddToCartWithPromo preserves promotionalPeriodType', () {
      provider.requestAddToCartWithPromo(
        product1,
        promotionalPrice: 800.0,
        promotionalLabel: 'Promo Lunes',
        promotionalPeriodType: 'daily',
      );

      expect(provider.cart.length, 1);
      final item = provider.cart.first;
      expect(item.promotionalPrice, 800.0);
      expect(item.promotionalPeriodType, 'daily');
      expect(item.hasActiveOffer, isTrue);
      expect(item.offerBadgeLabel, 'Oferta Diaria');
    });

    test('PosProvider recallOrderToCart preserves original selling price and agreed price without false offer', () {
      final pendingSaleData = {
        'id': 99,
        'shipping_cost': '0',
        'items': [
          {
            'product_id': 1,
            'product_name': 'Producto Test',
            'quantity': '2.0',
            'unit_price': '800.0', // precio con descuento pactado
            'product': {
              'id': 1,
              'name': 'Producto Test',
              'internal_code': 'PTEST',
              'cost_price': '500.0',
              'selling_price': '1000.0', // precio original de lista
              'stock': '10',
              'is_sold_by_weight': false,
            }
          }
        ]
      };

      provider.recallOrderToCart(pendingSaleData);

      expect(provider.cart.length, 1);
      final item = provider.cart.first;
      expect(item.product.sellingPrice, 1000.0);
      expect(item.agreedUnitPrice, 800.0);
      expect(item.hasAgreedPrice, isTrue);
      expect(item.unitPrice, 800.0);
      expect(item.hasActiveOffer, isFalse);
      expect(item.discountSavings, 400.0); // (1000 - 800) * 2
    });

    test('PosProvider recallOrderToCart with custom price_list preserves price without false offer badge and recalculates on setPriceTier', () {
      final pendingSaleData = {
        'id': 100,
        'shipping_cost': '0',
        'price_list': 'Jubilados',
        'items': [
          {
            'product_id': 1,
            'product_name': 'Producto Test',
            'quantity': '1.0',
            'unit_price': '900.0', // 10% descuento por lista Jubilados
            'product': {
              'id': 1,
              'name': 'Producto Test',
              'internal_code': 'PTEST',
              'cost_price': '500.0',
              'selling_price': '1000.0',
              'stock': '10',
              'is_sold_by_weight': false,
            }
          }
        ]
      };

      provider.recallOrderToCart(pendingSaleData);

      expect(provider.cart.length, 1);
      final item = provider.cart.first;
      expect(item.activeTier, PriceTier.custom);
      expect(item.customTierLabel, 'Jubilados');
      expect(item.unitPrice, 900.0);
      // No debe marcarse como Oferta porque pertenece a la lista custom Jubilados
      expect(item.hasActiveOffer, isFalse);

      // Si el cajero cambia manualmente la lista a Minorista (base), debe recalcular a 1000.0
      provider.setPriceTier(PriceTier.base);
      expect(item.activeTier, PriceTier.base);
      expect(item.unitPrice, 1000.0);
    });

    test('PosProvider syncActiveOffers preserves cheaper frozen price from recalled order when smaller offer is active', () {
      final pendingSaleData = {
        'id': 105,
        'shipping_cost': '0',
        'price_list': 'base',
        'items': [
          {
            'product_id': 1,
            'product_name': 'Producto Test',
            'quantity': '1.0',
            'unit_price': '700.0', // Precio congelado más barato ($700 sobre $1000)
            'product': {
              'id': 1,
              'name': 'Producto Test',
              'internal_code': 'PTEST',
              'cost_price': '500.0',
              'selling_price': '1000.0',
              'stock': '10',
              'is_sold_by_weight': false,
            }
          }
        ]
      };

      provider.recallOrderToCart(pendingSaleData);
      expect(provider.cart.first.unitPrice, 700.0);

      // Hoy existe una oferta activa menor (10% OFF -> $900)
      final smallerOfferToday = OfferModel(
        id: 88,
        name: 'Promo Hoy 10%',
        type: 'percentage',
        discountPercentage: 10,
        periodType: 'daily',
        startDate: DateTime.now().subtract(const Duration(hours: 1)),
        endDate: DateTime.now().add(const Duration(hours: 5)),
        isActive: true,
        products: [
          {'id': 1, 'selling_price': '1000.0'},
        ],
      );

      provider.syncActiveOffers([smallerOfferToday]);

      // Debe conservar los $700 pactados y no encarecerlo a $900
      expect(provider.cart.first.unitPrice, 700.0);
    });

    test('PosProvider IIBB Perception with override rate in POS', () {
      // Comercio como Agente de Percepción IIBB
      provider.setIsIibbPerceptionAgent(true);

      final customer = Customer(
        id: 10,
        name: 'Cliente Responsable Inscripto',
        documentNumber: '30-11223344-5',
        documentType: 80, // CUIT
        taxCondition: 'responsable_inscripto',
        creditLimit: 50000,
        balance: 0,
        isActive: true,
        appliesIibbPerception: true,
        iibbPerceptionRate: 3.0,
      );

      provider.selectCustomer(customer);
      expect(provider.overrideIibbPerceptionRate, isNull);
      expect(provider.appliesIibbPerception, isTrue);
      expect(provider.iibbPerceptionRate, 3.0);

      // Override a "Sin percepción (0%)"
      provider.setOverrideIibbPerceptionRate(0.0);
      expect(provider.overrideIibbPerceptionRate, 0.0);
      expect(provider.appliesIibbPerception, isFalse);
      expect(provider.iibbPerceptionRate, 0.0);

      // Override a 6.0% (Riesgo fiscal / no inscripto)
      provider.setOverrideIibbPerceptionRate(6.0);
      expect(provider.overrideIibbPerceptionRate, 6.0);
      expect(provider.appliesIibbPerception, isTrue);
      expect(provider.iibbPerceptionRate, 6.0);

      // Al cambiar cliente, el override se resetea a null
      provider.selectCustomer(customer);
      expect(provider.overrideIibbPerceptionRate, isNull);
      expect(provider.iibbPerceptionRate, 3.0);

      // Al limpiar carrito, el override se resetea a null
      provider.setOverrideIibbPerceptionRate(1.5);
      expect(provider.overrideIibbPerceptionRate, 1.5);
      provider.clearCart();
      expect(provider.overrideIibbPerceptionRate, isNull);
    });
  });
}
