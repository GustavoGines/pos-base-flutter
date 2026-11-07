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
  bool isTemporary; // Ítem/Combo temporal creado en POS (sin descuento de stock)
  bool saveToCatalog; // Si es true, el backend creará el producto en el catálogo con needs_catalog_review=true
  String? customDescription; // Sobrescritura temporal del nombre para Factura/Ticket
  String? customDetails; // Notas o desglose adicional para Factura/Ticket
  
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
    this.isTemporary = false,
    this.saveToCatalog = false,
    this.customDescription,
    this.customDetails,
  });

  /// Nombre efectivo a mostrar en el carrito, ticket térmico, PDF A4 y factura electrónica AFIP
  String get effectiveDisplayName {
    final cleanCustom = customDescription?.trim();
    if (cleanCustom != null && cleanCustom.isNotEmpty) {
      return cleanCustom;
    }
    return product.name;
  }

  /// Indica si el ítem tiene un alias/renombrado temporal distinto al nombre original del catálogo
  bool get isRenamed {
    final cleanCustom = customDescription?.trim();
    return cleanCustom != null && cleanCustom.isNotEmpty && cleanCustom != product.name;
  }

  /// Serializa la línea del carrito al payload esperado por ProcessSaleRequest / PaySaleRequest
  Map<String, dynamic> toSalePayload() {
    final isUnregisteredProduct = product.id <= 0;
    final cleanDesc = customDescription?.trim();
    final cleanDetails = customDetails?.trim();
    return {
      'product_id': (isTemporary || isUnregisteredProduct) ? null : product.id,
      'product_name': effectiveDisplayName,
      'custom_description': (cleanDesc != null && cleanDesc.isNotEmpty) ? cleanDesc : null,
      'custom_details': (cleanDetails != null && cleanDetails.isNotEmpty) ? cleanDetails : null,
      'is_temporary': isTemporary && !saveToCatalog,
      'save_to_catalog': saveToCatalog,
      'cost_price': product.costPrice,
      'iva_rate': product.ivaRate,
      'is_combo': product.isCombo,
      'is_sold_by_weight': product.isSoldByWeight,
      'unit_type': product.unitType,
      'quantity': quantity,
      'unit_price': unitPrice,
      'subtotal': subtotal,
    };
  }

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
        if ((customFactor - 1.0).abs() > 0.0001) {
          calculated = baseVolumetric * customFactor;
        } else {
          calculated = baseVolumetric;
        }
        break;
    }

    // Si hay una oferta promocional y es menor al precio calculado, aplicarla
    if (promotionalPrice != null && promotionalPrice! > 0 && promotionalPrice! < calculated) {
      return (promotionalPrice! * 100).roundToDouble() / 100.0;
    }
    return (calculated * 100).roundToDouble() / 100.0;
  }

  double get subtotal => ((unitPrice * quantity) * 100).roundToDouble() / 100.0;

  /// Subtotal de lista regular (sin descuentos ni listas especiales)
  double get regularSubtotal => product.sellingPrice * quantity;

  /// Monto de descuento ahorrado en este ítem
  double get discountSavings => (regularSubtotal - subtotal).clamp(0.0, double.infinity);

  /// Monto de recargo aplicado a este ítem (por lista de precios tarjeta/custom con incremento)
  double get surchargeAmount => (subtotal - regularSubtotal).clamp(0.0, double.infinity);

  /// Indica si este ítem tiene algún descuento aplicado respecto al precio de lista
  bool get hasDiscount => subtotal < regularSubtotal - 0.001;

  /// Indica si este ítem tiene un recargo aplicado respecto al precio de lista
  bool get hasSurcharge => subtotal > regularSubtotal + 0.001;

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
