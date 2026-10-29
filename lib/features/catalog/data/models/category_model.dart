import '../../domain/entities/category.dart';
import 'rubro_model.dart';

class CategoryModel extends Category {
  CategoryModel({
    required super.id,
    required super.name,
    super.description,
    super.rubroId,
    super.rubro,
    super.productsCount,
  });

  factory CategoryModel.fromJson(Map<String, dynamic> json) {
    return CategoryModel(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      name: json['name']?.toString() ?? 'Sin nombre',
      description: json['description']?.toString(),
      rubroId: json['rubro_id'] != null
          ? (json['rubro_id'] is int ? json['rubro_id'] : int.tryParse(json['rubro_id'].toString()))
          : null,
      rubro: json['rubro'] != null && json['rubro'] is Map<String, dynamic>
          ? RubroModel.fromJson(json['rubro'] as Map<String, dynamic>)
          : null,
      productsCount: json['products_count'] != null
          ? (json['products_count'] is int ? json['products_count'] : int.tryParse(json['products_count'].toString()))
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      if (description != null) 'description': description,
      if (rubroId != null) 'rubro_id': rubroId,
      if (rubro != null && rubro is RubroModel) 'rubro': (rubro as RubroModel).toJson(),
      if (productsCount != null) 'products_count': productsCount,
    };
  }
}
