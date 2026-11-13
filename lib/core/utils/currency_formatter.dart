import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

extension CurrencyFormatter on num {
  /// Devuelve el valor formateado con separadores de miles y 2 decimales (solo si tiene decimales)
  /// usando el paquete intl (ej: 3000000 -> "3.000.000")
  String toCurrency() {
    final format = NumberFormat.currency(
      locale: 'es_AR', // Or your default locale
      symbol: '',      // Already prefixed with \$ in UI usually
      decimalDigits: this == toInt() ? 0 : 2,
    );
    return format.format(this).trim();
  }

  /// Devuelve el monto en pesos argentinos con puntos de miles y sin decimales (.00)
  /// Ej: 3000000.0 -> "3.000.000" (y si tiene centavos reales como 1245.50 -> "1.245,50")
  String toArsInput() {
    if ((this - roundToDouble()).abs() < 0.005) {
      final rounded = round();
      if (rounded == 0) return '0';
      return NumberFormat.decimalPattern('es_AR').format(rounded);
    }
    final format = NumberFormat.currency(
      locale: 'es_AR',
      symbol: '',
      decimalDigits: 2,
    );
    return format.format(this).trim();
  }

  /// Formatea un porcentaje de margen sin decimales innecesarios (ej: 50.0 -> "50", 33.33 -> "33.3")
  String toCleanMargin() {
    final roundedOne = (this * 10).round() / 10.0;
    if (roundedOne == roundedOne.roundToDouble()) {
      return roundedOne.round().toString();
    }
    return roundedOne.toStringAsFixed(1);
  }

  /// Alias para cantidades
  String toQty() {
    if (this == toInt()) {
      return toInt().toString();
    }
    // Para peso balanza podríamos dejar hasta 3
    return toStringAsFixed(3).replaceAll(RegExp(r'0*$'), '').replaceAll(RegExp(r'\.$'), '');
  }

  /// Devuelve el valor numérico en formato válido para un TextInput (sin separador de miles)
  /// Ej: 3700.5 -> "3700,50"
  String toInputFormat() {
    if (this == toInt()) {
      return toInt().toString();
    }
    return toStringAsFixed(2).replaceAll('.', ',');
  }

  /// Formatea el stock de manera amigable sin redondear fracciones al entero superior.
  /// - Peso: usa decimales reales seguidos de `kg` (ej: "1,875 kg" o "1.875 kg").
  /// - Unidad entera / porciones: detecta fracciones culinarias comunes (1/8, 1/6, etc.)
  ///   sobresaliendo como "1 un. + 7/8" o "7/8 un.", o fallback con `toQty()`.
  String toUnitStockDisplay({
    bool isSoldByWeight = false,
    String unitSuffix = 'u',
  }) {
    if (isSoldByWeight) {
      return '${toQty()} kg';
    }

    if (this < 0) {
      final rounded = roundToDouble();
      if ((this - rounded).abs() < 0.001) {
        return '${rounded.toInt()} $unitSuffix';
      }
      return '${toQty()} $unitSuffix';
    }

    final intPart = floor();
    final double frac = (this - intPart).toDouble();

    if (frac < 0.004) {
      return '$intPart $unitSuffix';
    }
    if (frac > 0.996) {
      return '${intPart + 1} $unitSuffix';
    }

    final fractionLabel = _matchCulinaryFraction(frac);
    if (fractionLabel != null) {
      if (intPart == 0) {
        return '$fractionLabel $unitSuffix';
      }
      return '$intPart $unitSuffix + $fractionLabel';
    }

    return '${toQty()} $unitSuffix';
  }
}

String? _matchCulinaryFraction(double frac) {
  const denominators = [2, 3, 4, 5, 6, 8, 10, 12, 16];
  for (final den in denominators) {
    final num = (frac * den).round();
    if (num < 1 || num >= den) continue;
    final target = num / den;
    if ((frac - target).abs() <= 0.006) {
      return '$num/$den';
    }
  }
  return null;
}

/// Parsea una cantidad ingresada por teclado ya sea en formato decimal (`"0.0625"`, `"1,5"`)
/// o en formato fracción (`"1/16"`, `"3/16"`, `"2/8"`).
/// Devuelve `null` si el texto es inválido o está fuera de rango.
double? parseQuantityOrFraction(String input, {bool allowZero = false}) {
  final raw = input.trim().replaceAll(',', '.');
  if (raw.isEmpty) return null;

  if (raw.contains('/')) {
    final parts = raw.split('/');
    if (parts.length != 2) return null;
    final numerator = double.tryParse(parts[0].trim());
    final denominator = double.tryParse(parts[1].trim());
    if (numerator == null ||
        denominator == null ||
        !numerator.isFinite ||
        !denominator.isFinite ||
        denominator <= 0) {
      return null;
    }
    if (allowZero ? numerator < 0 : numerator <= 0) return null;
    return numerator / denominator;
  }

  final value = double.tryParse(raw);
  if (value == null || !value.isFinite) return null;
  if (allowZero ? value < 0 : value <= 0) return null;
  return value;
}

/// Redondea una cantidad a 3 decimales para compatibilidad estricta con `decimal(10,3)` en SQL (v1.8.5).
double roundQtyForStorage(double qty) => ((qty * 1000).round()) / 1000.0;

/// Formatea una cantidad para campos editables (`TextField`) preservando hasta 4 decimales
/// cuando representa una fracción exacta como `1/16 = 0.0625`, y 3 decimales para el resto.
String formatQuantityInput(double qty) {
  if ((qty - qty.roundToDouble()).abs() < 0.00005) {
    return qty.round().toString();
  }
  final rounded3 = (qty * 1000).round() / 1000.0;
  final scaled4 = qty * 10000;
  final isExactFourDecimals = (scaled4 - scaled4.roundToDouble()).abs() < 0.01 &&
      (rounded3 - qty).abs() >= 0.0002;
  final decimals = isExactFourDecimals ? 4 : 3;
  return qty
      .toStringAsFixed(decimals)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

/// Calcula cuántas unidades/combos armables caben dentro de [availStock] consumiendo [qty] por unidad,
/// compensando redondeos de fracciones unitarias `1/N` (`N` de 2 a 32, ej. `1/16 ≈ 0.063` → `16`).
int calcUnitsFitStock(double availStock, double qty) {
  if (availStock <= 0 || qty <= 0) return 0;

  int? bestDen;
  double bestDiff = double.infinity;
  for (int den = 2; den <= 32; den++) {
    final target = 1.0 / den;
    final diff = (qty - target).abs();
    if (diff <= 0.0006 && diff < bestDiff) {
      bestDiff = diff;
      bestDen = den;
    }
  }

  if (bestDen != null) {
    final intWhole = availStock.floor();
    final rem = availStock - intWhole;
    return intWhole * bestDen + (rem * bestDen + 0.14).floor();
  }

  return ((availStock + 0.0005) / qty).floor();
}

/// Formateador de entrada para montos en Pesos Argentinos (ARS):
/// Aplica puntos de miles en vivo mientras el usuario tipea (ej. 3000000 -> 3.000.000)
/// sin decimales (.00) y conservando la posición exacta del cursor.
class ArsThousandsInputFormatter extends TextInputFormatter {
  const ArsThousandsInputFormatter();

  static String formatDigits(String rawDigits) {
    final commaIdx = rawDigits.indexOf(',');
    final String intRaw = commaIdx >= 0 ? rawDigits.substring(0, commaIdx) : rawDigits;
    final String? decRaw = commaIdx >= 0 ? rawDigits.substring(commaIdx + 1) : null;

    final cleanInt = intRaw.replaceAll(RegExp(r'[^0-9]'), '');
    final cleanDec = decRaw?.replaceAll(RegExp(r'[^0-9]'), '');

    if (cleanInt.isEmpty && (cleanDec == null || cleanDec.isEmpty) && commaIdx < 0) {
      return '';
    }

    final parsedInt = cleanInt.isEmpty ? 0 : (int.tryParse(cleanInt) ?? 0);
    final formattedInt = NumberFormat.decimalPattern('es_AR').format(parsedInt);

    if (commaIdx >= 0) {
      final clampedDec = (cleanDec ?? '').length > 2 ? cleanDec!.substring(0, 2) : (cleanDec ?? '');
      return '$formattedInt,$clampedDec';
    }
    return formattedInt;
  }

  static double? tryParse(String? formattedText) {
    if (formattedText == null) return null;
    final trimmed = formattedText.trim();
    if (trimmed.isEmpty) return null;
    if (!trimmed.contains(',') && RegExp(r'^\d+\.\d{1,2}$').hasMatch(trimmed)) {
      return double.tryParse(trimmed);
    }
    final clean = trimmed.replaceAll('.', '').replaceAll(',', '.');
    if (clean.isEmpty) return null;
    return double.tryParse(clean);
  }

  static double parse(String formattedText) {
    return tryParse(formattedText) ?? 0.0;
  }

  static bool _isSignificantChar(int codeUnit) {
    // Dígitos '0'-'9' (48..57) o coma decimal ',' (44)
    return (codeUnit >= 48 && codeUnit <= 57) || codeUnit == 44;
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return const TextEditingValue(text: '');
    }

    String rawSource = newValue.text;
    int selectionEnd = newValue.selection.end.clamp(0, newValue.text.length);

    if (!oldValue.text.contains('.') &&
        !rawSource.contains(',') &&
        RegExp(r'^\d+\.\d{1,2}$').hasMatch(rawSource.trim())) {
      final parts = rawSource.trim().split('.');
      if (RegExp(r'^0+$').hasMatch(parts[1])) {
        rawSource = parts[0];
      } else {
        rawSource = '${parts[0]},${parts[1]}';
      }
      selectionEnd = rawSource.length;
    }

    final formatted = formatDigits(rawSource);
    if (formatted.isEmpty) {
      return const TextEditingValue(text: '');
    }

    // Contar cuántos caracteres significativos (dígitos o coma) había a la izquierda del cursor
    int sigBeforeCursor = 0;
    bool seenComma = false;
    for (int i = 0; i < selectionEnd; i++) {
      final code = rawSource.codeUnitAt(i);
      if (code >= 48 && code <= 57) {
        sigBeforeCursor++;
      } else if (code == 44 && !seenComma) {
        seenComma = true;
        sigBeforeCursor++;
      }
    }

    // Ubicar el cursor después de esa misma cantidad de caracteres significativos en el texto formateado
    int newCursorOffset = 0;
    int seenSig = 0;
    while (newCursorOffset < formatted.length && seenSig < sigBeforeCursor) {
      final code = formatted.codeUnitAt(newCursorOffset);
      if (_isSignificantChar(code)) {
        seenSig++;
      }
      newCursorOffset++;
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: newCursorOffset),
    );
  }
}
