import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';

class CartItem {
  final Product product;
  double quantity;
  
  CartItem({
    required this.product,
    this.quantity = 1.0,
  });

  double get subtotal => product.sellingPrice * quantity;
}
