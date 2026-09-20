class ExpenseCategory {
  final int id;
  final String name;
  final bool isActive;

  ExpenseCategory({
    required this.id,
    required this.name,
    this.isActive = true,
  });

  factory ExpenseCategory.fromJson(Map<String, dynamic> json) {
    return ExpenseCategory(
      id: json['id'],
      name: json['name'],
      isActive: json['is_active'] == 1 || json['is_active'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'is_active': isActive,
    };
  }
}
