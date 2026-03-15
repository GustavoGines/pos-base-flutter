import 'package:flutter/material.dart';
import '../../domain/entities/product.dart';
import '../../domain/usecases/get_products_usecase.dart';

class CatalogProvider with ChangeNotifier {
  final GetProductsUseCase getProductsUseCase;

  List<Product> _products = [];
  List<Product> get products => _products;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  CatalogProvider({required this.getProductsUseCase});

  Future<void> loadProducts() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _products = await getProductsUseCase();
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
