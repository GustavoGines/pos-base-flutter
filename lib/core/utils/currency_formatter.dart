import 'package:intl/intl.dart';

extension CurrencyFormatter on num {
  /// Devuelve el valor formateado con separadores de miles y 2 decimales
  /// usando el paquete intl
  String toCurrency() {
    final format = NumberFormat.currency(
      locale: 'es_AR', // Or your default locale
      symbol: '',      // Already prefixed with \$ in UI usually
      decimalDigits: this == toInt() ? 0 : 2,
    );
    return format.format(this).trim();
  }

  /// Alias para cantidades
  String toQty() {
    if (this == toInt()) {
      return toInt().toString();
    }
    // Para peso balanza podríamos dejar hasta 3
    return toStringAsFixed(3).replaceAll(RegExp(r'0*$'), '').replaceAll(RegExp(r'\.$'), '');
  }
}
