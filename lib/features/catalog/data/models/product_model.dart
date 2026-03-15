import '../../domain/entities/product.dart';
import 'category_model.dart';

class ProductModel extends Product {
  ProductModel({
    required int id,
    required String name,
    String? barcode,
    required String internalCode,
    required double costPrice,
    required double sellingPrice,
    required double stock,
    required bool active,
    required bool isSoldByWeight,
    CategoryModel? category,
  }) : super(
          id: id,
          name: name,
          barcode: barcode,
          internalCode: internalCode,
          costPrice: costPrice,
          sellingPrice: sellingPrice,
          stock: stock,
          active: active,
          isSoldByWeight: isSoldByWeight,
          category: category,
        );

  factory ProductModel.fromJson(Map<String, dynamic> json) {
    return ProductModel(
      id: json['id'],
      name: json['name'],
      barcode: json['barcode'],
      internalCode: json['internal_code'],
      costPrice: double.parse(json['cost_price'].toString()),
      sellingPrice: double.parse(json['selling_price'].toString()),
      stock: double.parse(json['stock'].toString()),
      active: json['active'] == 1 || json['active'] == true,
      isSoldByWeight: json['is_sold_by_weight'] == 1 || json['is_sold_by_weight'] == true,
      category: json['category'] != null ? CategoryModel.fromJson(json['category']) : null,
    );
  }
}
