import '../../domain/entities/brand.dart';

class BrandModel extends Brand {
  BrandModel({
    required int id,
    required String name,
    String? description,
  }) : super(id: id, name: name, description: description);

  factory BrandModel.fromJson(Map<String, dynamic> json) {
    return BrandModel(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      name: json['name']?.toString() ?? 'Sin nombre',
      description: json['description']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (description != null) 'description': description,
  };
}
