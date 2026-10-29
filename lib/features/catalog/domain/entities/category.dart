import 'rubro.dart';

class Category {
  final int id;
  final String name;
  final String? description;
  final int? rubroId;
  final Rubro? rubro;
  final int? productsCount;

  Category({
    required this.id,
    required this.name,
    this.description,
    this.rubroId,
    this.rubro,
    this.productsCount,
  });

  Category copyWith({
    int? id,
    String? name,
    String? description,
    int? rubroId,
    Rubro? rubro,
    int? productsCount,
  }) {
    return Category(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      rubroId: rubroId ?? this.rubroId,
      rubro: rubro ?? this.rubro,
      productsCount: productsCount ?? this.productsCount,
    );
  }
}
