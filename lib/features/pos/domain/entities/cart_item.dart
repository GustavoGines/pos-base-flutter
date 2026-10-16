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
  String? promotionalPeriodType; // 'daily', 'weekly', 'monthly', 'custom'
  
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
    this.promotionalPeriodType,
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

  /// Indica si este ítem tiene una oferta promocional activa aplicada.
  /// En lista base (Minorista), cualquier promotionalPrice válido es oferta.
  /// En listas especiales (mayorista/card/custom), requiere promotionalLabel o promotionalPeriodType
  /// para distinguir una oferta real de un precio congelado de lista.
  bool get hasActiveOffer =>
      promotionalPrice != null &&
      promotionalPrice! > 0 &&
      (activeTier == PriceTier.base || promotionalLabel != null || promotionalPeriodType != null) &&
      (unitPrice - promotionalPrice!).abs() < 0.01;

  /// Retorna el texto para el badge de oferta según su periodicidad o etiqueta
  String get offerBadgeLabel {
    switch (promotionalPeriodType) {
      case 'daily':
        return 'Oferta Diaria';
      case 'weekly':
        return 'Oferta Semanal';
      case 'monthly':
        return 'Oferta Mensual';
      default:
        if (promotionalLabel != null && promotionalLabel!.trim().isNotEmpty) {
          final clean = promotionalLabel!.trim();
          final lower = clean.toLowerCase();
          if (lower.startsWith('oferta') || lower.startsWith('promo')) {
            return clean;
          }
          return 'Oferta: $clean';
        }
        // Si no hay promotionalLabel ni promotionalPeriodType pero hay promotionalPrice,
        // es un precio de lista especial (mayorista/card/custom) o una oferta recuperada en base
        if (promotionalPrice != null && promotionalPrice! > 0) {
          switch (activeTier) {
            case PriceTier.wholesale:
              return 'Lista Mayorista';
            case PriceTier.card:
              return 'Lista Tarjeta';
            case PriceTier.custom:
              return customTierLabel != null ? 'Lista: $customTierLabel' : 'Lista Personalizada';
            default:
              return 'Oferta';
          }
        }
        return 'Oferta';
    }
  }
}

