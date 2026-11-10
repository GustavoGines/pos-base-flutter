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
