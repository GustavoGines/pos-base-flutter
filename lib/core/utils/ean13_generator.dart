/// Generador de EAN-13 de uso interno (Prefijo '2').
///
/// Formato: 2 + PLU (5 dígitos, relleno con ceros) + relleno (6 dígitos ceros) + dígito verificador
/// Ejemplo: PLU 58 → "2000058000001" (13 dígitos)
///
/// El prefijo '2' está reservado por GS1 para uso interno de la empresa.
class Ean13Generator {
  /// Genera un EAN-13 interno a partir del ID del producto (PLU).
  /// Si el producto ya tiene un barcode propio de fábrica, lo retorna tal cual.
  static String generate({required int plu, String? existingBarcode}) {
    // Si ya tiene código guardado en base de datos, lo usamos SIEMPRE.
    if (existingBarcode != null && existingBarcode.isNotEmpty && existingBarcode.length == 13) {
      return existingBarcode;
    }

    // Formato: "20" + relleno 5 dígitos ceros + PLU 5 dígitos + check digit
    // Alineándolo con el motor avanzado del backend
    final rawPlu = plu.toString();
    final pluStr = rawPlu.length > 5 ? rawPlu.substring(rawPlu.length - 5) : rawPlu.padLeft(5, '0');
    final body = '2000000$pluStr'; // 12 dígitos

    final checkDigit = _calculateCheckDigit(body);
    return '$body$checkDigit';
  }

  /// Genera un EAN-13 para balanza con el precio codificado en pesos enteros.
  /// Formato equilibrado compatible con visual display (1-5-6-1): 
  /// "2" (prefijo) + PLU (5 dígitos) + PRECIO (6 dígitos enterados) + check digit
  /// Ejemplo: PLU 31, Precio $1500 → "2 00031 001500 C"
  static String generateForScale(int plu, double priceInPesos) {
    // BLINDAJE SENIOR: No importa el tamaño del PLU, tomamos solo los últimos 5 dígitos 
    // para cumplir con el estándar EAN-13 de balanza.
    final rawPlu = plu.toString();
    final pluStr = rawPlu.length > 5 ? rawPlu.substring(rawPlu.length - 5) : rawPlu.padLeft(5, '0');
    
    // Lo mismo para el precio (máximo 6 dígitos pesos)
    final rawPrice = priceInPesos.round().toString();
    final priceStr = rawPrice.length > 6 ? rawPrice.substring(rawPrice.length - 6) : rawPrice.padLeft(6, '0');

    final body = '2$pluStr$priceStr'; // 1 (prefijo) + 5 (plu) + 6 (precio) = 12 dígitos

    final checkDigit = _calculateCheckDigit(body);
    return '$body$checkDigit';
  }

  /// Algoritmo estándar GS1 para el dígito verificador del EAN-13.
  /// Alterna multiplicadores 1 y 3 sobre los 12 dígitos base.
  static int _calculateCheckDigit(String twelveDigits) {
    assert(twelveDigits.length == 12, 'El cuerpo debe tener 12 dígitos');

    int sum = 0;
    for (int i = 0; i < 12; i++) {
      final digit = int.parse(twelveDigits[i]);
      sum += (i.isEven) ? digit : digit * 3;
    }
    final remainder = sum % 10;
    return remainder == 0 ? 0 : 10 - remainder;
  }

  /// Formatea el EAN-13 con el separador visual estándar (para display).
  /// Retorna: "2 00005 800000 1"
  static String format(String ean13) {
    if (ean13.length != 13) return ean13;
    return '${ean13[0]} ${ean13.substring(1, 6)} ${ean13.substring(6, 12)} ${ean13[12]}';
  }

  /// Valida que un string sea un EAN-13 correcto (dígito verificador).
  static bool isValid(String code) {
    if (code.length != 13) return false;
    if (!RegExp(r'^\d{13}$').hasMatch(code)) return false;
    final check = _calculateCheckDigit(code.substring(0, 12));
    return check == int.parse(code[12]);
  }
}
