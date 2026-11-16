import 'package:flutter/material.dart';

import '../../../core/utils/currency_formatter.dart';
import '../../pos/domain/services/product_pricing_calculator.dart';

/// Opción sugerida de precio para el armador de Combos y Fracciones.
class ComboPriceSuggestion {
  final String keySuffix;
  final double factor;
  final String shortTag;
  final double targetPrice;

  const ComboPriceSuggestion({
    required this.keySuffix,
    required this.factor,
    required this.shortTag,
    required this.targetPrice,
  });

  String get buttonLabel => '$shortTag (\$${targetPrice.toCurrency()})';
  String get appliedLabel => '$shortTag (\$${targetPrice.toCurrency()}) aplicado';
}

/// Resumen comercial del rendimiento proyectado al vender por fracciones.
class WholeUnitYieldSummary {
  final double? portionsPerWholeUnit;
  final double projectedRevenue;
  final double referenceWholePrice;
  final double percentVsReference;
  final bool isSingleFractionReference;

  const WholeUnitYieldSummary({
    required this.portionsPerWholeUnit,
    required this.projectedRevenue,
    required this.referenceWholePrice,
    required this.percentVsReference,
    required this.isSingleFractionReference,
  });

  String formatSummary() {
    final pctAbs = percentVsReference.abs().toStringAsFixed(
          percentVsReference.abs() >= 10 ||
                  (percentVsReference - percentVsReference.roundToDouble()).abs() < 0.05
              ? 0
              : 1,
        );
    final sign = percentVsReference >= 0 ? '+' : '-';

    if (isSingleFractionReference && portionsPerWholeUnit != null) {
      final p = portionsPerWholeUnit!;
      final pStr = (p - p.roundToDouble()).abs() < 0.01
          ? p.round().toString()
          : p.toStringAsFixed(1);
      return 'Rendimiento por unidad entera ($pStr porc.): '
          '\$${projectedRevenue.toCurrency()} '
          '($sign$pctAbs% vs \$${referenceWholePrice.toCurrency()} entera)';
    }

    return 'Vs. valor proporcional (\$${referenceWholePrice.toCurrency()}): '
        '$sign$pctAbs%';
  }
}

/// Helper compartido para detección automática y cálculo de precios
/// entre "Combo / Pack (-%)" y "Porción / Fracción (+%)" en Catálogo y POS Rápido.
class ComboFractionPricing {
  ComboFractionPricing._();

  static const List<(String keySuffix, double factor, String tag)>
      _fractionFactors = [
    ('plus30', 1.30, '+30%'),
    ('plus50', 1.50, '+50%'),
    ('plus80', 1.80, '+80%'),
    ('plus100', 2.00, '+100% (x2)'),
    ('plus120', 2.20, '+120%'),
  ];

  static const List<(String keySuffix, double factor, String tag)> _comboFactors =
      [
    ('promo10', 0.90, '-10%'),
    ('promo15', 0.85, '-15%'),
  ];

  /// Retorna true si al menos un ingrediente tiene cantidad fraccionaria (< 1 o decimal).
  static bool hasFractionalQuantities(List<Map<String, dynamic>> ingredients) {
    for (final ing in ingredients) {
      final qty = (ing['quantity'] as num?)?.toDouble() ?? 0.0;
      if (qty <= 0) continue;
      if (qty < 0.9995 || (qty - qty.roundToDouble()).abs() >= 0.0005) {
        return true;
      }
    }
    return false;
  }

  /// Construye la lista de botones de precios sugeridos según el modo activo.
  static List<ComboPriceSuggestion> buildSuggestions({
    required double baseTotal,
    required bool isFractionMode,
  }) {
    if (baseTotal <= 0) return const [];
    final baseRounded = ProductPricingCalculator.roundMoney(baseTotal);
    final specs = isFractionMode ? _fractionFactors : _comboFactors;

    final result = <ComboPriceSuggestion>[];
    double lastPrice = baseRounded;
    for (final spec in specs) {
      final target = ProductPricingCalculator.roundMoney(baseTotal * spec.$2);
      if (target > 0 && (target - lastPrice).abs() >= 0.01) {
        result.add(
          ComboPriceSuggestion(
            keySuffix: spec.$1,
            factor: spec.$2,
            shortTag: spec.$3,
            targetPrice: target,
          ),
        );
        lastPrice = target;
      }
    }
    return result;
  }

  /// Calcula el rendimiento estimado al vender por porciones/fracciones vs el entero.
  static WholeUnitYieldSummary? computeWholeUnitYield({
    required List<Map<String, dynamic>> ingredients,
    required double appliedPrice,
    required double proportionalBaseTotal,
  }) {
    if (appliedPrice <= 0 || ingredients.isEmpty) return null;

    final activeIngredients = ingredients
        .where((ing) => ((ing['quantity'] as num?)?.toDouble() ?? 0.0) > 0)
        .toList();
    if (activeIngredients.isEmpty) return null;

    if (activeIngredients.length == 1) {
      final ing = activeIngredients.first;
      final qty = (ing['quantity'] as num).toDouble();
      final wholeSell = (ing['selling_price'] as num?)?.toDouble() ?? 0.0;
      if (qty > 0 && qty < 0.9995 && wholeSell > 0) {
        // Rescata denominadores exactos cuando qty fue redondeado a 3 decimales (ej. 1/6 = 0.167 -> 6)
        final rawPortions = 1.0 / qty;
        final nearestInt = rawPortions.round();
        final double effectivePortions =
            (nearestInt >= 2 && (qty - (1.0 / nearestInt)).abs() <= 0.001)
                ? nearestInt.toDouble()
                : rawPortions;
        final projected =
            ProductPricingCalculator.roundMoney(appliedPrice * effectivePortions);
        final deltaPct = ((projected - wholeSell) / wholeSell) * 100.0;
        return WholeUnitYieldSummary(
          portionsPerWholeUnit: effectivePortions,
          projectedRevenue: projected,
          referenceWholePrice: wholeSell,
          percentVsReference: deltaPct,
          isSingleFractionReference: true,
        );
      }
    }

    if (proportionalBaseTotal > 0) {
      final deltaPct =
          ((appliedPrice - proportionalBaseTotal) / proportionalBaseTotal) *
              100.0;
      return WholeUnitYieldSummary(
        portionsPerWholeUnit: null,
        projectedRevenue: appliedPrice,
        referenceWholePrice: proportionalBaseTotal,
        percentVsReference: deltaPct,
        isSingleFractionReference: false,
      );
    }
    return null;
  }

  /// Toggle manual compacto entre modo Fracción (+%) y Combo (-%).
  static Widget buildModeToggle({
    required bool isFractionMode,
    required ValueChanged<bool> onChanged,
  }) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: Colors.deepPurple.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.deepPurple.shade200),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ModeChipButton(
              label: 'Fracción (+%)',
              selected: isFractionMode,
              onTap: () => onChanged(true),
            ),
            _ModeChipButton(
              label: 'Combo (-%)',
              selected: !isFractionMode,
              onTap: () => onChanged(false),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeChipButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ModeChipButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: selected ? Colors.deepPurple.shade700 : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : Colors.deepPurple.shade800,
          ),
        ),
      ),
    );
  }
}
