import 'dart:convert';

class IibbTaxableLine {
  final double subtotal;
  final double ivaRate;

  const IibbTaxableLine({
    required this.subtotal,
    required this.ivaRate,
  });
}

class IibbFiscalBreakdown {
  final double grossMerchandise;
  final double extraAmount;
  final double netAmount;
  final double ivaAmount;
  final double tributeBaseImp;
  final double iibbRate;
  final double iibbAmount;
  final double grandTotal;

  const IibbFiscalBreakdown({
    required this.grossMerchandise,
    required this.extraAmount,
    required this.netAmount,
    required this.ivaAmount,
    required this.tributeBaseImp,
    required this.iibbRate,
    required this.iibbAmount,
    required this.grandTotal,
  });
}

class AgreedTotalSolution {
  final double merchandiseTotal;
  final IibbFiscalBreakdown breakdown;
  final bool isExactMatch;
  final double requestedGrandTotal;

  const AgreedTotalSolution({
    required this.merchandiseTotal,
    required this.breakdown,
    required this.isExactMatch,
    required this.requestedGrandTotal,
  });
}

/// Motor unificado de cálculo fiscal para Percepciones de Ingresos Brutos (IIBB)
/// espejado al centavo con `AfipWsfeService.php` para garantizar el invariante
/// ARCA/AFIP WSFEv1: `ImpTotal == ImpNeto + ImpIVA + ImpTrib`.
class IibbFiscalCalculator {
  static const String baseNetWithoutVat = 'net_without_vat';
  static const String baseGrossWithVat = 'gross_with_vat';

  static const List<String> allowedSubjectConditions = [
    'responsable_inscripto',
    'monotributo',
    'exento',
  ];

  static const List<String> defaultSubjectConditions = [
    'responsable_inscripto',
  ];

  static const String issuerResponsableInscripto = 'IVA Responsable Inscripto';
  static const String issuerMonotributo = 'Responsable Monotributo';
  static const String issuerExento = 'IVA Exento';

  static const List<String> validIssuerTaxConditions = [
    issuerResponsableInscripto,
    issuerMonotributo,
    issuerExento,
  ];

  /// Retorna `true` si la condición IVA guardada para el comercio emisor es
  /// un valor legado inválido (ej. `'Consumidor Final'` o desconocido).
  static bool isLegacyInvalidIssuerCondition(String? raw) {
    if (raw == null) return false;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return false;
    final norm =
        trimmed.toLowerCase().replaceAll('_', ' ').replaceAll('-', ' ');
    if (norm.contains('consumidor')) return true;
    return !norm.contains('inscripto') &&
        !norm.contains('monotributo') &&
        !norm.contains('exento');
  }

  /// Normaliza la condición frente al IVA del comercio emisor a uno de los
  /// 3 valores válidos (`IVA Responsable Inscripto`, `Responsable Monotributo`,
  /// `IVA Exento`). Retorna `null` si tenía un valor legado inválido como
  /// `Consumidor Final` para que la UI pida seleccionar una opción válida.
  static String? normalizeIssuerTaxConditionOrNull(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return issuerResponsableInscripto;
    }
    final norm =
        raw.trim().toLowerCase().replaceAll('_', ' ').replaceAll('-', ' ');
    if (norm.contains('monotributo')) return issuerMonotributo;
    if (norm.contains('exento')) return issuerExento;
    if (norm.contains('inscripto')) return issuerResponsableInscripto;
    return null;
  }

  /// True únicamente cuando el comercio emisor es elegible para operar como
  /// Agente de Percepción IIBB (`IVA Responsable Inscripto`).
  static bool isIssuerEligibleForIibb(String? rawIssuerTaxCondition) {
    if (rawIssuerTaxCondition == null ||
        rawIssuerTaxCondition.trim().isEmpty) {
      return true;
    }
    return normalizeIssuerTaxConditionOrNull(rawIssuerTaxCondition) ==
        issuerResponsableInscripto;
  }

  static double round2(double value) => (value * 100.0).roundToDouble() / 100.0;

  static String normalizeCalculationBase(String? raw) {
    final norm = (raw ?? '').trim().toLowerCase();
    return norm == baseGrossWithVat ? baseGrossWithVat : baseNetWithoutVat;
  }

  static String normalizeTaxConditionKey(String? raw) {
    final norm = (raw ?? '')
        .trim()
        .toLowerCase()
        .replaceAll('_', ' ')
        .replaceAll('-', ' ');
    if (norm.contains('inscripto')) return 'responsable_inscripto';
    if (norm.contains('monotributo')) return 'monotributo';
    if (norm.contains('exento')) return 'exento';
    return 'consumidor_final';
  }

  /// Normaliza la lista de condiciones frente al IVA sujetas a percepción IIBB por defecto.
  /// `consumidor_final` queda SIEMPRE excluido.
  static List<String> normalizeSubjectConditions(dynamic raw) {
    if (raw == null) return List<String>.from(defaultSubjectConditions);

    List<dynamic> items;
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return const [];
      try {
        final decoded = jsonDecode(trimmed);
        items = decoded is List ? decoded : trimmed.split(',');
      } catch (_) {
        items = trimmed.split(',');
      }
    } else if (raw is List) {
      items = raw;
    } else {
      return List<String>.from(defaultSubjectConditions);
    }

    final result = <String>[];
    for (final entry in items) {
      final key = entry
          .toString()
          .trim()
          .toLowerCase()
          .replaceAll('-', '_')
          .replaceAll(' ', '_');
      if (allowedSubjectConditions.contains(key) && !result.contains(key)) {
        result.add(key);
      }
    }
    return result;
  }

  /// Determina si una condición frente al IVA está alcanzada por la regla general de IIBB.
  /// Consumidor Final retorna `false` de manera incondicional.
  static bool isConditionSubjectToIibb(
    String? rawTaxCondition,
    List<String> subjectConditions,
  ) {
    final key = normalizeTaxConditionKey(rawTaxCondition);
    if (key == 'consumidor_final') return false;
    return subjectConditions.contains(key);
  }

  static double _normalizeAliquotRate(double rate) {
    final normalized = round2(rate);
    if (normalized == 0.0 ||
        normalized == 2.5 ||
        normalized == 5.0 ||
        normalized == 10.5 ||
        normalized == 21.0 ||
        normalized == 27.0) {
      return normalized;
    }
    return 21.0;
  }

  static ({double net, double iva}) _calculateNetAndIva(
    double grossSubtotal,
    double ivaRate,
  ) {
    final gross = round2(grossSubtotal);
    final rate = round2(ivaRate);
    if (rate <= 0.0) {
      return (net: gross, iva: 0.0);
    }
    final net = round2(gross / (1.0 + (rate / 100.0)));
    final iva = round2(gross - net);
    return (net: net, iva: iva);
  }

  /// Calcula el desglose fiscal exacto agrupando por alícuota de IVA (idéntico a `AfipWsfeService.php`).
  static IibbFiscalBreakdown calculateBreakdown({
    required List<IibbTaxableLine> lines,
    double extraAmount = 0.0,
    double iibbRate = 0.0,
    String calculationBase = baseNetWithoutVat,
    bool isFacturaC = false,
  }) {
    final normalizedExtra = extraAmount > 0 ? round2(extraAmount) : 0.0;
    final grossMerch = round2(
      lines.fold<double>(0.0, (sum, l) => sum + l.subtotal),
    );
    final baseSale = round2(grossMerch + normalizedExtra);
    final normalizedBase = normalizeCalculationBase(calculationBase);
    final effectiveRate = iibbRate > 0 ? iibbRate : 0.0;

    if (baseSale <= 0.0) {
      return IibbFiscalBreakdown(
        grossMerchandise: 0.0,
        extraAmount: 0.0,
        netAmount: 0.0,
        ivaAmount: 0.0,
        tributeBaseImp: 0.0,
        iibbRate: effectiveRate,
        iibbAmount: 0.0,
        grandTotal: 0.0,
      );
    }

    double netAmount;
    double ivaAmount;
    double tributeBaseImp;

    if (isFacturaC) {
      // Monotributo (Factura C): ImpIVA = 0, BaseImp = subtotal bruto
      netAmount = baseSale;
      ivaAmount = 0.0;
      tributeBaseImp = baseSale;
    } else {
      final grouped = <double, double>{};
      for (final line in lines) {
        final rate = _normalizeAliquotRate(line.ivaRate);
        grouped[rate] = (grouped[rate] ?? 0.0) + line.subtotal;
      }
      if (normalizedExtra > 0.0) {
        grouped[21.0] = (grouped[21.0] ?? 0.0) + normalizedExtra;
      }
      if (grouped.isEmpty) {
        grouped[21.0] = baseSale;
      }

      final aliquotKeys = grouped.keys.toList();
      final aliquotNets = <double, double>{};
      final aliquotIvas = <double, double>{};
      double totalNet = 0.0;
      double totalIva = 0.0;

      for (final rate in aliquotKeys) {
        final calc = _calculateNetAndIva(grouped[rate]!, rate);
        aliquotNets[rate] = calc.net;
        aliquotIvas[rate] = calc.iva;
        totalNet += calc.net;
        totalIva += calc.iva;
      }

      netAmount = round2(totalNet);
      ivaAmount = round2(totalIva);

      final diff = round2(baseSale - (netAmount + ivaAmount));
      if (diff != 0.0 && diff.abs() < 1.0 && aliquotKeys.isNotEmpty) {
        final firstRate = aliquotKeys.first;
        final adjustedGross = round2(grouped[firstRate]! + diff);
        final recalc = _calculateNetAndIva(adjustedGross, firstRate);
        aliquotNets[firstRate] = recalc.net;
        aliquotIvas[firstRate] = recalc.iva;
        netAmount = round2(aliquotNets.values.fold(0.0, (a, b) => a + b));
        ivaAmount = round2(aliquotIvas.values.fold(0.0, (a, b) => a + b));
      }

      tributeBaseImp = normalizedBase == baseGrossWithVat
          ? round2(netAmount + ivaAmount)
          : netAmount;
    }

    final iibbAmount = effectiveRate > 0.0
        ? round2(tributeBaseImp * (effectiveRate / 100.0))
        : 0.0;
    final grandTotal = round2(netAmount + ivaAmount + iibbAmount);

    return IibbFiscalBreakdown(
      grossMerchandise: grossMerch,
      extraAmount: normalizedExtra,
      netAmount: netAmount,
      ivaAmount: ivaAmount,
      tributeBaseImp: tributeBaseImp,
      iibbRate: effectiveRate,
      iibbAmount: iibbAmount,
      grandTotal: grandTotal,
    );
  }

  /// Prorratea `targetCents` en centavos enteros proporcionales al subtotal de cada línea
  /// (misma regla que `PosProvider.applyAgreedTotalRounding`).
  static List<int> allocateCentsProportionally(
    List<double> currentSubtotals,
    int targetCents,
  ) {
    if (currentSubtotals.isEmpty || targetCents <= 0) {
      return List<int>.filled(currentSubtotals.length, 0);
    }
    final currentTotal = currentSubtotals.fold<double>(0.0, (a, b) => a + b);
    if (currentTotal <= 0.0) {
      return List<int>.filled(currentSubtotals.length, 0);
    }

    int largestIdx = 0;
    double largestSub = -1.0;
    for (int i = 0; i < currentSubtotals.length; i++) {
      if (currentSubtotals[i] > largestSub) {
        largestSub = currentSubtotals[i];
        largestIdx = i;
      }
    }

    final newCentsList = List<int>.filled(currentSubtotals.length, 0);
    int allocatedCents = 0;
    for (int i = 0; i < currentSubtotals.length; i++) {
      final lineSub = currentSubtotals[i];
      int lineCents = ((lineSub / currentTotal) * targetCents).round();
      if (targetCents >= currentSubtotals.length && lineSub > 0 && lineCents < 1) {
        lineCents = 1;
      }
      newCentsList[i] = lineCents;
      allocatedCents += lineCents;
    }

    final diffCents = targetCents - allocatedCents;
    if (newCentsList[largestIdx] + diffCents >= 1) {
      newCentsList[largestIdx] += diffCents;
    } else {
      int remaining = targetCents;
      for (int i = 0; i < currentSubtotals.length; i++) {
        if (i == largestIdx) continue;
        final share = ((currentSubtotals[i] / currentTotal) * targetCents).floor();
        newCentsList[i] = share;
        remaining -= share;
      }
      newCentsList[largestIdx] = remaining > 0 ? remaining : 0;
    }

    return newCentsList;
  }

  /// Despeje inverso discreto al centavo para "Pactar / Absorber Total Final con IIBB".
  /// Busca el subtotal de mercadería exacto `M` (en centavos enteros) tal que, tras prorratear
  /// cada línea y aplicar la fórmula oficial de ARCA, `ImpNeto + ImpIVA + ImpTrib == targetGrandTotal`.
  /// En el caso matemático infrecuente (~3%) de salto de 2 centavos en el redondeo de `round(base * r%)`,
  /// devuelve el mayor subtotal válido con `grandTotal <= targetGrandTotal` (`isExactMatch = false`)
  /// garantizando SIEMPRE que el comprobante ARCA cierre al centavo exacto (`0.00` de desvío).
  static AgreedTotalSolution solveAgreedGrandTotal({
    required List<IibbTaxableLine> lines,
    required double targetGrandTotal,
    double extraAmount = 0.0,
    double iibbRate = 0.0,
    String calculationBase = baseNetWithoutVat,
    bool isFacturaC = false,
  }) {
    final targetCents = (round2(targetGrandTotal) * 100.0).round();
    final normalizedExtra = extraAmount > 0 ? round2(extraAmount) : 0.0;
    final subtotals = lines.map((l) => l.subtotal).toList();
    final normalizedBase = normalizeCalculationBase(calculationBase);

    IibbFiscalBreakdown evaluate(int merchCents) {
      final safeCents = merchCents < 1 ? 1 : merchCents;
      final allocated = allocateCentsProportionally(subtotals, safeCents);
      final candidateLines = <IibbTaxableLine>[
        for (int i = 0; i < lines.length; i++)
          IibbTaxableLine(
            subtotal: allocated[i] / 100.0,
            ivaRate: lines[i].ivaRate,
          ),
      ];
      return calculateBreakdown(
        lines: candidateLines,
        extraAmount: normalizedExtra,
        iibbRate: iibbRate,
        calculationBase: normalizedBase,
        isFacturaC: isFacturaC,
      );
    }

    if (lines.isEmpty || targetCents <= 0) {
      return AgreedTotalSolution(
        merchandiseTotal: 0.0,
        breakdown: calculateBreakdown(
          lines: const [],
          extraAmount: normalizedExtra,
          iibbRate: iibbRate,
          calculationBase: normalizedBase,
          isFacturaC: isFacturaC,
        ),
        isExactMatch: false,
        requestedGrandTotal: round2(targetGrandTotal),
      );
    }

    final double rateFactor = iibbRate > 0 ? (iibbRate / 100.0) : 0.0;
    double estMerch;
    if (rateFactor <= 0.0) {
      estMerch = targetGrandTotal - normalizedExtra;
    } else if (isFacturaC || normalizedBase == baseGrossWithVat) {
      estMerch = (targetGrandTotal / (1.0 + rateFactor)) - normalizedExtra;
    } else {
      final currentMerchOnly = calculateBreakdown(
        lines: lines,
        extraAmount: 0.0,
        iibbRate: 0.0,
        calculationBase: normalizedBase,
        isFacturaC: false,
      );
      final alpha = currentMerchOnly.grossMerchandise > 0
          ? (currentMerchOnly.netAmount / currentMerchOnly.grossMerchandise)
          : (1.0 / 1.21);
      final extraNet = normalizedExtra / 1.21;
      estMerch = (targetGrandTotal - normalizedExtra - (extraNet * rateFactor)) /
          (1.0 + (alpha * rateFactor));
    }

    int centerCents = (estMerch * 100.0).round();
    if (centerCents < 1) centerCents = 1;

    // Si la estimación inicial quedó lejos (ej. extra grande), acotar con búsqueda binaria
    final initialEval = evaluate(centerCents);
    final initialGrandCents = (initialEval.grandTotal * 100.0).round();
    if ((initialGrandCents - targetCents).abs() > 25) {
      int lo = 1;
      int hi = targetCents > 1 ? targetCents : 1;
      while (lo < hi) {
        final mid = (lo + hi) >> 1;
        final gCents = (evaluate(mid).grandTotal * 100.0).round();
        if (gCents < targetCents) {
          lo = mid + 1;
        } else {
          hi = mid;
        }
      }
      centerCents = lo;
    }

    final int scanStart = (centerCents - 30) < 1 ? 1 : (centerCents - 30);
    final int scanEnd = centerCents + 30;

    int? exactMerchCents;
    IibbFiscalBreakdown? exactBreakdown;
    int? bestUnderMerchCents;
    IibbFiscalBreakdown? bestUnderBreakdown;
    int bestUnderGrandCents = -1;

    for (int m = scanStart; m <= scanEnd; m++) {
      final br = evaluate(m);
      final gCents = (br.grandTotal * 100.0).round();
      if (gCents == targetCents) {
        if (exactMerchCents == null ||
            (m - centerCents).abs() < (exactMerchCents - centerCents).abs()) {
          exactMerchCents = m;
          exactBreakdown = br;
        }
      } else if (gCents < targetCents && gCents >= bestUnderGrandCents) {
        bestUnderGrandCents = gCents;
        bestUnderMerchCents = m;
        bestUnderBreakdown = br;
      }
    }

    if (exactMerchCents != null && exactBreakdown != null) {
      return AgreedTotalSolution(
        merchandiseTotal: exactMerchCents / 100.0,
        breakdown: exactBreakdown,
        isExactMatch: true,
        requestedGrandTotal: round2(targetGrandTotal),
      );
    }

    final fallbackMerchCents = bestUnderMerchCents ?? centerCents;
    final fallbackBreakdown = bestUnderBreakdown ?? evaluate(fallbackMerchCents);
    return AgreedTotalSolution(
      merchandiseTotal: fallbackMerchCents / 100.0,
      breakdown: fallbackBreakdown,
      isExactMatch:
          (fallbackBreakdown.grandTotal * 100.0).round() == targetCents,
      requestedGrandTotal: round2(targetGrandTotal),
    );
  }
}
