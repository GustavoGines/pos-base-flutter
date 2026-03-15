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
  final Category? category;

  Product({
    required this.id,
    required this.name,
    this.barcode,
    required this.internalCode,
    required this.costPrice,
    required this.sellingPrice,
    required this.stock,
    required this.active,
    required this.isSoldByWeight,
    this.category,
  });
}
