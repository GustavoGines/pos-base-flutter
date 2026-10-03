import '../../domain/entities/rubro.dart';

class RubroModel extends Rubro {
  RubroModel({
    required super.id,
    required super.name,
    super.description,
    super.isSystem = false,
    super.categoriesCount = 0,
    super.createdAt,
  });

  factory RubroModel.fromJson(Map<String, dynamic> json) {
    return RubroModel(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      name: json['name']?.toString() ?? 'Sin nombre',
      description: json['description']?.toString(),
      isSystem: json['is_system'] == true ||
          json['is_system'] == 1 ||
          json['is_system']?.toString() == '1' ||
          json['is_system']?.toString() == 'true',
      categoriesCount: json['categories_count'] != null
          ? (json['categories_count'] is int
              ? json['categories_count']
              : int.tryParse(json['categories_count'].toString()) ?? 0)
          : 0,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      if (description != null) 'description': description,
      'is_system': isSystem,
      'categories_count': categoriesCount,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
    };
  }
}
