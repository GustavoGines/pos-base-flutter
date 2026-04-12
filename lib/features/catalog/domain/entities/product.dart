import 'category.dart';

class Product {
  final int id;
  final String name;
  final String? barcode;
  final String internalCode;
  final double costPrice;
  final double sellingPrice;
  // [hardware_store] Listas de Precio — null en clientes retail
  final double? priceWholesale;
  final double? priceCard;
  final double stock;
  final bool active;
  final bool isSoldByWeight;
  final bool isCombo;
  final List<Map<String, dynamic>>? comboIngredients;
  final List<Map<String, dynamic>>? priceTiers;
  final int? vencimientoDias;
  final double? minStock;
  final int salesCount;
  final String unitType;
  final Category? category;

  Product({
    required this.id,
    required this.name,
    this.barcode,
    required this.internalCode,
    required this.costPrice,
    required this.sellingPrice,
    this.priceWholesale, // [hardware_store]
    this.priceCard,      // [hardware_store]
    required this.stock,
    this.minStock,
    required this.active,
    required this.isSoldByWeight,
    this.isCombo = false,
    this.comboIngredients,
    this.priceTiers,
    this.salesCount = 0,
    this.vencimientoDias,
    this.unitType = 'un',
    this.category,
  });
  Product copyWith({
    int? id,
    String? name,
    String? barcode,
    String? internalCode,
    double? costPrice,
    double? sellingPrice,
    double? priceWholesale, // [hardware_store]
    double? priceCard,      // [hardware_store]
    double? stock,
    double? minStock,
    bool? active,
    bool? isSoldByWeight,
    bool? isCombo,
    List<Map<String, dynamic>>? comboIngredients,
    List<Map<String, dynamic>>? priceTiers,
    int? salesCount,
    int? vencimientoDias,
    String? unitType,
    Category? category,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      barcode: barcode ?? this.barcode,
      internalCode: internalCode ?? this.internalCode,
      costPrice: costPrice ?? this.costPrice,
      sellingPrice: sellingPrice ?? this.sellingPrice,
      priceWholesale: priceWholesale ?? this.priceWholesale, // [hardware_store]
      priceCard: priceCard ?? this.priceCard,                 // [hardware_store]
      stock: stock ?? this.stock,
      minStock: minStock ?? this.minStock,
      active: active ?? this.active,
      isSoldByWeight: isSoldByWeight ?? this.isSoldByWeight,
      isCombo: isCombo ?? this.isCombo,
      comboIngredients: comboIngredients ?? this.comboIngredients,
      priceTiers: priceTiers ?? this.priceTiers,
      salesCount: salesCount ?? this.salesCount,
      vencimientoDias: vencimientoDias ?? this.vencimientoDias,
      unitType: unitType ?? this.unitType,
      category: category ?? this.category,
    );
  }

  /// Devuelve el tramo aplicable para una cantidad dada.
  /// Si no hay tramos o no se supera, retorna null.
  Map<String, dynamic>? getApplicableTier(double quantity) {
    if (priceTiers == null || priceTiers!.isEmpty) return null;
    
    // Buscar todos los tramos que se hayan superado
    var aplicables = priceTiers!.where((t) {
      double minQ = double.tryParse(t['min_quantity'].toString()) ?? 1.0;
      return quantity >= minQ;
    }).toList();

    if (aplicables.isEmpty) return null;

    // Ordenar de mayor a menor y tomar el primero (el tramo más alto alcanzado)
    aplicables.sort((a, b) {
      double minA = double.tryParse(a['min_quantity'].toString()) ?? 1.0;
      double minB = double.tryParse(b['min_quantity'].toString()) ?? 1.0;
      return minB.compareTo(minA); // Descendente
    });

    return aplicables.first;
  }

  /// Devuelve el precio unitario final para una cantidad dada.
  double getBestPrice(double quantity) {
    final tier = getApplicableTier(quantity);
    if (tier != null) {
      return double.tryParse(tier['unit_price'].toString()) ?? sellingPrice;
    }
    return sellingPrice;
  }
}
