import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/expense_category_model.dart';
import '../../../core/network/api_client.dart';

class ExpenseCategoryProvider extends ChangeNotifier {
  final String baseUrl;
  final ApiClient client;

  bool _isLoading = false;
  List<ExpenseCategory> _categories = [];

  bool get isLoading => _isLoading;
  List<ExpenseCategory> get categories => _categories;

  ExpenseCategoryProvider({required this.baseUrl, required this.client});

  Future<void> fetchCategories() async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await client.get(Uri.parse('$baseUrl/expense-categories'));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        _categories = data.map((e) => ExpenseCategory.fromJson(e)).toList();
      }
    } catch (e) {
      debugPrint("Error fetchCategories: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> createCategory(String name) async {
    final response = await client.post(
      Uri.parse('$baseUrl/expense-categories'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'name': name, 'is_active': true}),
    );
    if (response.statusCode == 201) {
      await fetchCategories();
    } else {
      throw Exception('Error al crear categoría');
    }
  }

  Future<void> updateCategory(int id, String name, bool isActive) async {
    final response = await client.put(
      Uri.parse('$baseUrl/expense-categories/$id'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'name': name, 'is_active': isActive}),
    );
    if (response.statusCode == 200) {
      await fetchCategories();
    } else {
      throw Exception('Error al actualizar categoría');
    }
  }

  Future<void> deleteCategory(int id) async {
    final response = await client.delete(Uri.parse('$baseUrl/expense-categories/$id'));
    if (response.statusCode == 200 || response.statusCode == 204) {
      await fetchCategories();
    } else {
      throw Exception('Error al eliminar categoría');
    }
  }
}
