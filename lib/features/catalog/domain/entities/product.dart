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
    this.vencimientoDias,
    this.category,
  });
  Product copyWithStock(double newStock) {
    return Product(
      id: id,
      name: name,
      barcode: barcode,
      internalCode: internalCode,
      costPrice: costPrice,
      sellingPrice: sellingPrice,
      stock: newStock,
      minStock: minStock,
      active: active,
      isSoldByWeight: isSoldByWeight,
      vencimientoDias: vencimientoDias,
      category: category,
    );
  }
}
