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
  
  CartItem({
    required this.product,
    this.quantity = 1.0,
    this.activeTier = PriceTier.base,
    this.wholesaleFactor = 0.85, // Default -15%
    this.cardFactor = 1.15,      // Default +15%
    this.customFactor = 1.0,
    this.customTierLabel,
  });

  /// Motor de precio híbrido: prioriza overrides fijos → multiplicadores globales/custom → precio base volumétrico
  double get unitPrice {
    final baseVolumetric = product.getBestPrice(quantity);
    switch (activeTier) {
      case PriceTier.wholesale:
        if (product.priceWholesale != null && product.priceWholesale! > 0) return product.priceWholesale!;
        return baseVolumetric * wholesaleFactor;
      case PriceTier.card:
        if (product.priceCard != null && product.priceCard! > 0) return product.priceCard!;
        return baseVolumetric * cardFactor;
      case PriceTier.custom:
        return baseVolumetric * customFactor;
      case PriceTier.base:
        return baseVolumetric;
    }
  }

  double get subtotal => unitPrice * quantity;
}
