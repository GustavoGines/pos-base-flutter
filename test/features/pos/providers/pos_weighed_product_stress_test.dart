import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend_desktop/features/pos/presentation/providers/pos_provider.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';

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

  group('Empirical Stress Test: submitWeighedProduct (Bug Heuristic > 50kg Elimination)', () {
    final weighedProduct = Product(
      id: 99,
      name: 'Bolsa de Cemento / Forraje Granel',
      internalCode: 'BULK-99',
      costPrice: 500.0,
      sellingPrice: 1000.0, // $1000 por kg
      stock: 10000,
      active: true,
      isSoldByWeight: true,
    );

    // Exact weights demanded by user instructions:
    // 0.05, 5.0, 50.0, 50.001, 100.0, 500.0 kg
    final targetWeights = [
      0.05,
      5.0,
      50.0,
      50.001,
      100.0,
      500.0,
    ];

    for (final weight in targetWeights) {
      test('Weight $weight kg MUST NOT be divided by 1000 (quantity must equal $weight)', () {
        provider.clearCart();
        expect(provider.cart, isEmpty);

        provider.submitWeighedProduct(weighedProduct, weight);

        expect(provider.cart.length, 1);
        final item = provider.cart.first;

        // 1. Verify exact quantity matches input weight
        expect(item.quantity, equals(weight));

        // 2. Explicitly assert that quantity is NEVER the divided-by-1000 corrupted value
        final corruptedWeight = weight / 1000.0;
        expect(item.quantity, isNot(equals(corruptedWeight)));

        // 3. Verify subtotal financial calculation is based on full weight, not corrupted weight
        final expectedSubtotal = weight * weighedProduct.sellingPrice;
        expect(item.subtotal, equals(expectedSubtotal));
        expect(provider.cartSubtotal, equals(expectedSubtotal));

        // 4. Verify financial loss prevention for bulk orders (> 50kg)
        if (weight > 50.0) {
          final corruptedSubtotal = corruptedWeight * weighedProduct.sellingPrice;
          expect(provider.cartSubtotal, isNot(equals(corruptedSubtotal)));
          expect(provider.cartSubtotal, greaterThan(50000.0));
        }
      });
    }

    test('Boundary Stress Test around 50kg threshold (49.999, 50.0, 50.0001, 50.001, 50.1, 75.0, 1000.0)', () {
      final boundaryWeights = [
        49.999,
        50.0,
        50.0001,
        50.001,
        50.1,
        75.0,
        1000.0,
      ];

      for (final bWeight in boundaryWeights) {
        provider.clearCart();
        provider.submitWeighedProduct(weighedProduct, bWeight);

        expect(provider.cart.first.quantity, equals(bWeight),
            reason: 'Failed boundary check for weight $bWeight kg');
        expect(provider.cart.first.quantity, isNot(equals(bWeight / 1000.0)),
            reason: 'Weight $bWeight was erroneously divided by 1000!');
      }
    });
  });
}
