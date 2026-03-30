import '../../domain/entities/category.dart';

class CategoryModel extends Category {
  CategoryModel({
    required int id,
    required String name,
    String? description,
  }) : super(id: id, name: name, description: description);

  factory CategoryModel.fromJson(Map<String, dynamic> json) {
    return CategoryModel(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      name: json['name']?.toString() ?? 'Sin nombre',
      description: json['description']?.toString(),
    );
  }
}
