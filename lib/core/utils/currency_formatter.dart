// lib/core/utils/currency_formatter.dart
extension CurrencyFormatter on num {
  /// Devuelve el valor con 2 decimales solo si es estrictamente fraccionario,
  /// de lo contrario devuelve el entero (ej. 1500.00 -> 1500)
  String toCurrency() {
    return this.round().toString();
  }

  /// Alias para cantidades
  String toQty() {
    if (this == this.toInt()) {
      return this.toInt().toString();
    }
    // Para peso balanza podríamos dejar hasta 3
    return this.toStringAsFixed(3).replaceAll(RegExp(r'0*$'), '').replaceAll(RegExp(r'\.$'), '');
  }
}
