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
    double? minStock,
    required bool active,
    required bool isSoldByWeight,
    int? vencimientoDias,
    CategoryModel? category,
  }) : super(
          id: id,
          name: name,
          barcode: barcode,
          internalCode: internalCode,
          costPrice: costPrice,
          sellingPrice: sellingPrice,
          stock: stock,
          minStock: minStock,
          active: active,
          isSoldByWeight: isSoldByWeight,
          vencimientoDias: vencimientoDias,
          category: category,
        );

  @override
  ProductModel copyWithStock(double newStock) {
    return ProductModel(
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
      category: category != null
          ? CategoryModel(id: category!.id, name: category!.name, description: category!.description)
          : null,
    );
  }

  factory ProductModel.fromJson(Map<String, dynamic> json) {
    return ProductModel(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      name: json['name']?.toString() ?? 'Sin nombre',
      barcode: json['barcode']?.toString(),
      internalCode: json['internal_code']?.toString() ?? '',
      costPrice: double.tryParse(json['cost_price']?.toString() ?? '0') ?? 0.0,
      sellingPrice: double.tryParse(json['selling_price']?.toString() ?? '0') ?? 0.0,
      stock: double.tryParse(json['stock']?.toString() ?? '0') ?? 0.0,
      minStock: (json['min_stock'] != null && json['min_stock'].toString().toLowerCase() != 'null') 
          ? double.tryParse(json['min_stock'].toString()) 
          : null,
      active: json['active'] == 1 || json['active'] == true || json['active'] == '1' || json['active'] == 'true',
      isSoldByWeight: json['is_sold_by_weight'] == 1 || json['is_sold_by_weight'] == true || json['is_sold_by_weight'] == '1' || json['is_sold_by_weight'] == 'true',
      vencimientoDias: json['vencimiento_dias'] != null
          ? int.tryParse(json['vencimiento_dias'].toString())
          : null,
      category: json['category'] != null && json['category'] is Map<String, dynamic> 
          ? CategoryModel.fromJson(json['category'] as Map<String, dynamic>) 
          : null,
    );
  }
}
