/// Utilidades para codificación y decodificación de etiquetas térmicas con lote (`L#<batch_id>`).
class ParsedBatchBarcode {
  final int batchId;
  final double? weightGrams;

  const ParsedBatchBarcode({
    required this.batchId,
    this.weightGrams,
  });

  double? get weightKg =>
      weightGrams != null ? (weightGrams! / 1000.0) : null;
}

class BatchBarcodeHelper {
  BatchBarcodeHelper._();

  static final RegExp _batchPattern =
      RegExp(r'^L#(\d+)(?:#W#(\d+(?:\.\d+)?))?$', caseSensitive: false);

  /// Intenta interpretar un código escaneado con formato de lote (`L#<id>` o `L#<id>#W#<gramos>`).
  static ParsedBatchBarcode? parse(String rawCode) {
    final trimmed = rawCode.trim();
    if (trimmed.isEmpty) return null;
    final match = _batchPattern.firstMatch(trimmed);
    if (match == null) return null;
    final id = int.tryParse(match.group(1) ?? '');
    if (id == null || id <= 0) return null;
    final grams = match.group(2) != null
        ? double.tryParse(match.group(2)!)
        : null;
    return ParsedBatchBarcode(batchId: id, weightGrams: grams);
  }

  /// Construye el string para código de barras Code128 de una etiqueta de lote.
  static String encode({
    required int batchId,
    double? weightGrams,
  }) {
    if (weightGrams != null && weightGrams > 0) {
      final wStr = weightGrams % 1 == 0
          ? weightGrams.toInt().toString()
          : weightGrams.toStringAsFixed(1);
      return 'L#$batchId#W#$wStr';
    }
    return 'L#$batchId';
  }
}
