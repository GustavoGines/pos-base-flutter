import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';

class CartItem {
  final Product product;
  double quantity;
  
  CartItem({
    required this.product,
    this.quantity = 1.0,
  });

  /// El precio unitario se calcula dinámicamente según la cantidad (Tramos de Precio)
  double get unitPrice => product.getBestPrice(quantity);

  double get subtotal => unitPrice * quantity;
}
