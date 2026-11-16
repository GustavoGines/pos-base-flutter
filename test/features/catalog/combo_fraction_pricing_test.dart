import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_desktop/features/catalog/utils/combo_fraction_pricing.dart';

void main() {
  group('ComboFractionPricing', () {
    test('detects fractional and decimal ingredient quantities accurately', () {
      expect(ComboFractionPricing.hasFractionalQuantities(const []), isFalse);
      expect(
        ComboFractionPricing.hasFractionalQuantities([
          {'id': 1, 'quantity': 1.0},
          {'id': 2, 'quantity': 3.0},
        ]),
        isFalse,
      );
      expect(
        ComboFractionPricing.hasFractionalQuantities([
          {'id': 1, 'quantity': 0.125},
        ]),
        isTrue,
      );
      expect(
        ComboFractionPricing.hasFractionalQuantities([
          {'id': 1, 'quantity': 1.5},
        ]),
        isTrue,
      );
    });

    test('buildSuggestions switches cleanly between Fraction (+%) and Combo (-%) scales', () {
      final fractionSuggestions = ComboFractionPricing.buildSuggestions(
        baseTotal: 3125.0,
        isFractionMode: true,
      );
      expect(
        fractionSuggestions.map((s) => s.keySuffix).toList(),
        ['plus30', 'plus50', 'plus80', 'plus100', 'plus120'],
      );
      expect(fractionSuggestions[0].targetPrice, 4062.5);
      expect(fractionSuggestions[1].targetPrice, 4687.5);
      expect(fractionSuggestions[2].targetPrice, 5625.0);
      expect(fractionSuggestions[3].targetPrice, 6250.0);
      expect(fractionSuggestions[3].buttonLabel, contains('+100% (x2)'));
      expect(fractionSuggestions[4].targetPrice, 6875.0);

      final comboSuggestions = ComboFractionPricing.buildSuggestions(
        baseTotal: 10000.0,
        isFractionMode: false,
      );
      expect(
        comboSuggestions.map((s) => s.keySuffix).toList(),
        ['promo10', 'promo15'],
      );
      expect(comboSuggestions[0].targetPrice, 9000.0);
      expect(comboSuggestions[1].targetPrice, 8500.0);
    });

    test('computeWholeUnitYield snaps single-fraction denominators (1/6 & 1/8) and handles multi-ingredient fallback', () {
      // Caso 1/8 torta ($25.000 entera -> $6.500 porción = $52.000 rendimiento, +108%)
      final tortaOctavos = ComboFractionPricing.computeWholeUnitYield(
        ingredients: [
          {'id': 10, 'quantity': 0.125, 'selling_price': 25000.0},
        ],
        appliedPrice: 6500.0,
        proportionalBaseTotal: 3125.0,
      );
      expect(tortaOctavos, isNotNull);
      expect(
        tortaOctavos!.formatSummary(),
        'Rendimiento por unidad entera (8 porc.): \$52.000 (+108% vs \$25.000 entera)',
      );

      // Caso 1/6 redondeado (0.167 -> 6 porciones)
      final tortaSextos = ComboFractionPricing.computeWholeUnitYield(
        ingredients: [
          {'id': 11, 'quantity': 0.167, 'selling_price': 24000.0},
        ],
        appliedPrice: 5000.0,
        proportionalBaseTotal: 4008.0,
      );
      expect(tortaSextos, isNotNull);
      expect(
        tortaSextos!.formatSummary(),
        'Rendimiento por unidad entera (6 porc.): \$30.000 (+25% vs \$24.000 entera)',
      );

      // Caso multi-ingrediente proporcional sin denominador entero único
      final multiMix = ComboFractionPricing.computeWholeUnitYield(
        ingredients: [
          {'id': 1, 'quantity': 0.5, 'selling_price': 10000.0},
          {'id': 2, 'quantity': 0.25, 'selling_price': 12000.0},
        ],
        appliedPrice: 12000.0,
        proportionalBaseTotal: 8000.0,
      );
      expect(multiMix, isNotNull);
      expect(multiMix!.formatSummary(), 'Vs. valor proporcional (\$8.000): +50%');
    });
  });
}
