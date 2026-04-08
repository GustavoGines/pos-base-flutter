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
    double? priceWholesale, // [hardware_store]
    double? priceCard,      // [hardware_store]
    required double stock,
    double? minStock,
    required bool active,
    required bool isSoldByWeight,
    int salesCount = 0,
    int? vencimientoDias,
    String unitType = 'un',
    CategoryModel? category,
  }) : super(
          id: id,
          name: name,
          barcode: barcode,
          internalCode: internalCode,
          costPrice: costPrice,
          sellingPrice: sellingPrice,
          priceWholesale: priceWholesale, // [hardware_store]
          priceCard: priceCard,           // [hardware_store]
          stock: stock,
          minStock: minStock,
          active: active,
          isSoldByWeight: isSoldByWeight,
          salesCount: salesCount,
          vencimientoDias: vencimientoDias,
          unitType: unitType,
          category: category,
        );

  @override
  ProductModel copyWith({
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
    int? salesCount,
    int? vencimientoDias,
    String? unitType,
    covariant CategoryModel? category,
  }) {
    return ProductModel(
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
      salesCount: salesCount ?? this.salesCount,
      vencimientoDias: vencimientoDias ?? this.vencimientoDias,
      unitType: unitType ?? this.unitType,
      category: category ?? (this.category as CategoryModel?),
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
      // [hardware_store] Precios opcionales — null si no vienen del backend
      priceWholesale: json['price_wholesale'] != null && json['price_wholesale'].toString() != 'null'
          ? double.tryParse(json['price_wholesale'].toString())
          : null,
      priceCard: json['price_card'] != null && json['price_card'].toString() != 'null'
          ? double.tryParse(json['price_card'].toString())
          : null,
      stock: double.tryParse(json['stock']?.toString() ?? '0') ?? 0.0,
      minStock: (json['min_stock'] != null && json['min_stock'].toString().toLowerCase() != 'null') 
          ? double.tryParse(json['min_stock'].toString()) 
          : null,
      active: json['active'] == 1 || json['active'] == true || json['active'] == '1' || json['active'] == 'true',
      isSoldByWeight: json['is_sold_by_weight'] == 1 || json['is_sold_by_weight'] == true || json['is_sold_by_weight'] == '1' || json['is_sold_by_weight'] == 'true',
      salesCount: json['sales_count'] != null 
          ? (int.tryParse(json['sales_count'].toString()) ?? 0) 
          : 0,
      vencimientoDias: json['vencimiento_dias'] != null
          ? int.tryParse(json['vencimiento_dias'].toString())
          : null,
      unitType: json['unit_type']?.toString() ?? 'un',
      category: json['category'] != null && json['category'] is Map<String, dynamic> 
          ? CategoryModel.fromJson(json['category'] as Map<String, dynamic>) 
          : null,
    );
  }
}
