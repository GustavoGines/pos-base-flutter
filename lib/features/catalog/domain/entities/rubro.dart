class Rubro {
  final int id;
  final String name;
  final String? description;
  final bool isSystem;
  final int categoriesCount;
  final DateTime? createdAt;

  Rubro({
    required this.id,
    required this.name,
    this.description,
    this.isSystem = false,
    this.categoriesCount = 0,
    this.createdAt,
  });

  Rubro copyWith({
    int? id,
    String? name,
    String? description,
    bool? isSystem,
    int? categoriesCount,
    DateTime? createdAt,
  }) {
    return Rubro(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      isSystem: isSystem ?? this.isSystem,
      categoriesCount: categoriesCount ?? this.categoriesCount,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
