import 'category.dart';

class Product {
  final int id;
  final String name;
  final String? barcode;
  final String internalCode;
  final double costPrice;
  final double sellingPrice;
  final double stock;
  final bool active;
  final bool isSoldByWeight;
  final int? vencimientoDias; // Shelf life — días hasta la caducidad
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
    required this.stock,
    this.minStock,
    required this.active,
    required this.isSoldByWeight,
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
    double? stock,
    double? minStock,
    bool? active,
    bool? isSoldByWeight,
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
      stock: stock ?? this.stock,
      minStock: minStock ?? this.minStock,
      active: active ?? this.active,
      isSoldByWeight: isSoldByWeight ?? this.isSoldByWeight,
      salesCount: salesCount ?? this.salesCount,
      vencimientoDias: vencimientoDias ?? this.vencimientoDias,
      unitType: unitType ?? this.unitType,
      category: category ?? this.category,
    );
  }
}
