import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';

enum PriceTier { base, wholesale, card, custom }

class CartItem {
  Product product;
  double quantity;
  PriceTier activeTier;
  double wholesaleFactor;
  double cardFactor;
  double customFactor; // Para listas personalizadas ("Jubilados -5%", "Gremio -10%")
  String? customTierLabel; // Nombre de la lista personalizada para mostrar en UI
  double? promotionalPrice; // Ofertas / Promociones temporales
  String? promotionalLabel;
  
  CartItem({
    required this.product,
    this.quantity = 1.0,
    this.activeTier = PriceTier.base,
    this.wholesaleFactor = 1.0, // Hardcodes limpios, dependen de setting global
    this.cardFactor = 1.0,      // Hardcodes limpios, dependen de setting global
    this.customFactor = 1.0,
    this.customTierLabel,
    this.promotionalPrice,
    this.promotionalLabel,
  });

  /// Motor de precio híbrido: prioriza precio de oferta → overrides fijos → multiplicadores globales/custom → precio base volumétrico
  double get unitPrice {
    final baseVolumetric = product.getBestPrice(quantity);
    double calculated;
    switch (activeTier) {
      case PriceTier.wholesale:
        if (product.priceWholesale != null && product.priceWholesale! > 0) {
          calculated = product.priceWholesale!;
        } else {
          calculated = baseVolumetric * wholesaleFactor;
        }
        break;
      case PriceTier.card:
        if (product.priceCard != null && product.priceCard! > 0) {
          calculated = product.priceCard!;
        } else {
          calculated = baseVolumetric * cardFactor;
        }
        break;
      case PriceTier.custom:
        calculated = baseVolumetric * customFactor;
        break;
      case PriceTier.base:
        calculated = baseVolumetric;
        break;
    }

    // Si hay una oferta promocional y es menor al precio calculado, aplicarla
    if (promotionalPrice != null && promotionalPrice! > 0 && promotionalPrice! < calculated) {
      return promotionalPrice!;
    }
    return calculated;
  }

  double get subtotal => unitPrice * quantity;

  /// Subtotal de lista regular (sin descuentos ni listas especiales)
  double get regularSubtotal => product.sellingPrice * quantity;

  /// Monto de descuento ahorrado en este ítem
  double get discountSavings => (regularSubtotal - subtotal).clamp(0.0, double.infinity);

  /// Indica si este ítem tiene algún descuento aplicado respecto al precio de lista
  bool get hasDiscount => subtotal < regularSubtotal - 0.001;
}

