import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import '../services/product_pricing_calculator.dart';

export '../services/product_pricing_calculator.dart'
    show
        PriceTier,
        CardSurchargeOnOffersMode,
        DiscountTierOnOffersMode,
        CalculatedProductPrice,
        ProductPricingCalculator;

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
  double? agreedUnitPrice; // Precio congelado pactado (ej. Orden en espera / Presupuesto recuperado)
  CardSurchargeOnOffersMode cardSurchargeOnOffersMode;
  DiscountTierOnOffersMode discountTierOnOffersMode;
  bool ignoreFixedPrices;
  bool isTemporary; // Ítem/Combo temporal creado en POS (sin descuento de stock)
  bool saveToCatalog; // Si es true, el backend creará el producto en el catálogo con needs_catalog_review=true
  String? customDescription; // Sobrescritura temporal del nombre para Factura/Ticket
  String? customDetails; // Notas o desglose adicional para Factura/Ticket
  double? manualUnitPrice; // Precio de venta unitario sobrescrito manualmente para esta venta
  double? manualCostPrice; // Precio de costo unitario sobrescrito manualmente para esta venta
  double? manualSubtotal; // Subtotal final pactado por lote (ej. "3 por $10.000") para evitar pérdida de centavos por división
  bool hasManualIvaOverride; // Alícuota IVA modificada manualmente en el carrito para esta venta
  int? batchId; // Lote explícito escaneado en mostrador (ej. etiqueta térmica L#<id>)
  String? batchCode; // Código legible del lote escaneado
  String? batchExpirationDate; // Vencimiento YYYY-MM-DD del lote escaneado

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
    this.agreedUnitPrice,
    this.cardSurchargeOnOffersMode = CardSurchargeOnOffersMode.surchargeOnOffer,
    this.discountTierOnOffersMode = DiscountTierOnOffersMode.bestPriceWins,
    this.ignoreFixedPrices = false,
    this.isTemporary = false,
    this.saveToCatalog = false,
    this.customDescription,
    this.customDetails,
    this.manualUnitPrice,
    this.manualCostPrice,
    this.manualSubtotal,
    this.hasManualIvaOverride = false,
    this.batchId,
    this.batchCode,
    this.batchExpirationDate,
  });

  /// Costo unitario efectivo en esta venta (respeta override manual si existe)
  double get effectiveCostPrice => manualCostPrice ?? product.costPrice;

  /// Indica si el precio de venta fue ajustado manualmente solo para esta venta
  bool get hasManualSellingPriceOverride =>
      (manualUnitPrice != null && manualUnitPrice! > 0) ||
      (manualSubtotal != null && manualSubtotal! > 0);

  /// Indica si el costo fue ajustado manualmente solo para esta venta
  bool get hasManualCostOverride =>
      manualCostPrice != null && manualCostPrice! >= 0;

  /// Indica si tiene un precio de venta o costo ajustado manualmente solo para esta venta
  bool get hasManualPriceOverride =>
      hasManualSellingPriceOverride || hasManualCostOverride;

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
    final cleanBarcode = product.barcode?.trim();
    return {
      'product_id': (isTemporary || isUnregisteredProduct) ? null : product.id,
      'product_name': effectiveDisplayName,
      'custom_description': (cleanDesc != null && cleanDesc.isNotEmpty) ? cleanDesc : null,
      'custom_details': (cleanDetails != null && cleanDetails.isNotEmpty) ? cleanDetails : null,
      'is_temporary': isTemporary && !saveToCatalog,
      'save_to_catalog': saveToCatalog,
      if (saveToCatalog &&
          !product.isService &&
          cleanBarcode != null &&
          cleanBarcode.isNotEmpty)
        'barcode': cleanBarcode,
      'cost_price': effectiveCostPrice,
      if (manualCostPrice != null && !isTemporary && !isUnregisteredProduct)
        'custom_cost_price': manualCostPrice,
      if (isTemporary || isUnregisteredProduct || saveToCatalog || hasManualIvaOverride)
        'iva_rate': product.ivaRate,
      'is_combo': product.isCombo,
      if (product.isCombo &&
          product.comboIngredients != null &&
          product.comboIngredients!.isNotEmpty)
        'combo_ingredients': product.comboIngredients!
            .where((ing) => ing['id'] != null)
            .map((ing) => {
                  'id': (ing['id'] as num).toInt(),
                  'quantity': ((ing['quantity'] as num?)?.toDouble() ?? 1.0),
                })
            .toList(),
      'is_service': product.isService,
      'is_sold_by_weight': product.isSoldByWeight,
      'unit_type': product.unitType,
      'quantity': quantity,
      'unit_price': unitPrice,
      'subtotal': subtotal,
      if (batchId != null) 'batch_id': batchId,
    };
  }

  bool get _hasExplicitOfferMetadata =>
      (promotionalLabel != null && promotionalLabel!.trim().isNotEmpty) ||
      (promotionalPeriodType != null && promotionalPeriodType!.trim().isNotEmpty);

  /// Snapshot unificado del cálculo de precios para esta línea (sin override manual).
  CalculatedProductPrice get calculatedPrice =>
      ProductPricingCalculator.calculate(
        product: product,
        quantity: quantity,
        activeTier: activeTier,
        wholesaleFactor: wholesaleFactor,
        cardFactor: cardFactor,
        customFactor: customFactor,
        promotionalPrice: promotionalPrice,
        hasExplicitOffer: _hasExplicitOfferMetadata ||
            (activeTier == PriceTier.base &&
                promotionalPrice != null &&
                promotionalPrice! > 0 &&
                agreedUnitPrice == null),
        agreedUnitPrice: agreedUnitPrice,
        cardSurchargeOnOffersMode: cardSurchargeOnOffersMode,
        discountTierOnOffersMode: discountTierOnOffersMode,
        ignoreFixedPrices: ignoreFixedPrices,
      );

  /// Precio unitario calculado automáticamente por lista/oferta (sin override manual)
  double get defaultCalculatedUnitPrice => calculatedPrice.finalUnitPrice;

  /// Motor de precio híbrido: prioriza override manual de mostrador → precio pactado / oferta → overrides fijos → multiplicadores globales/custom → precio base volumétrico
  double get unitPrice {
    if (manualUnitPrice != null && manualUnitPrice! > 0) {
      return ProductPricingCalculator.roundMoney(manualUnitPrice!);
    }
    return defaultCalculatedUnitPrice;
  }

  double get subtotal {
    final calculated = ProductPricingCalculator.roundMoney(unitPrice * quantity);
    if (manualSubtotal != null && manualSubtotal! > 0) {
      final roundedManual = ProductPricingCalculator.roundMoney(manualSubtotal!);
      final maxRoundingTolerance = (0.02 * quantity.abs()) > 0.05 ? (0.02 * quantity.abs()) : 0.05;
      if ((roundedManual - calculated).abs() <= maxRoundingTolerance + 0.001) {
        return roundedManual;
      }
    }
    return calculated;
  }

  /// Precio unitario regular efectivo para el comprobante (si hubo suba manual para esta venta,
  /// se toma como el nuevo precio regular de ese ticket para no mostrar recargo ni tachado invertido).
  double get effectiveRegularUnitPrice =>
      (manualUnitPrice != null && manualUnitPrice! > product.sellingPrice)
          ? ProductPricingCalculator.roundMoney(manualUnitPrice!)
          : ProductPricingCalculator.roundMoney(product.sellingPrice);

  /// Subtotal de lista regular (sin descuentos ni listas especiales)
  double get regularSubtotal =>
      ProductPricingCalculator.roundMoney(effectiveRegularUnitPrice * quantity);

  /// Monto de descuento ahorrado en este ítem.
  /// Si una oferta tiene recargo de Tarjeta/Lista encima, se preserva íntegro el
  /// ahorro real respecto al precio de lista (sin netearlo contra el recargo).
  double get discountSavings {
    if (!hasManualSellingPriceOverride && calculatedPrice.hasSurchargeOnOffer) {
      final preSurchargeSub = ProductPricingCalculator.roundMoney(
        calculatedPrice.preSurchargeUnitPrice * quantity,
      );
      if (regularSubtotal > preSurchargeSub + 0.001) {
        return ProductPricingCalculator.roundMoney(
          regularSubtotal - preSurchargeSub,
        );
      }
    }
    return ProductPricingCalculator.roundMoney(
      (regularSubtotal - subtotal).clamp(0.0, double.infinity),
    );
  }

  /// Monto de recargo aplicado a este ítem (por lista de precios tarjeta/custom con incremento).
  /// Si recae sobre un ítem en oferta, mide el recargo real desde el precio promocional.
  double get surchargeAmount {
    if (!hasManualSellingPriceOverride && calculatedPrice.hasSurchargeOnOffer) {
      final preSurchargeSub = ProductPricingCalculator.roundMoney(
        calculatedPrice.preSurchargeUnitPrice * quantity,
      );
      if (subtotal > preSurchargeSub + 0.001) {
        return ProductPricingCalculator.roundMoney(
          subtotal - preSurchargeSub,
        );
      }
    }
    return ProductPricingCalculator.roundMoney(
      (subtotal - regularSubtotal).clamp(0.0, double.infinity),
    );
  }

  /// Indica si este ítem tiene algún descuento aplicado respecto al precio de lista
  bool get hasDiscount => discountSavings > 0.001;

  /// Indica si este ítem tiene un recargo aplicado respecto al precio de lista
  bool get hasSurcharge => surchargeAmount > 0.001;

  /// Indica si este ítem tiene una oferta promocional activa aplicada.
  bool get hasActiveOffer =>
      !hasManualSellingPriceOverride && calculatedPrice.hasActiveOffer;

  /// Indica si sobre la oferta promocional activa se aplicó recargo de Tarjeta / Lista +%.
  bool get hasSurchargeOnOffer =>
      !hasManualSellingPriceOverride && calculatedPrice.hasSurchargeOnOffer;

  /// Indica si la oferta vigente ignoró el recargo de la lista activa por configuración del comercio.
  bool get isOfferSurchargeExempt =>
      !hasManualSellingPriceOverride && calculatedPrice.isOfferSurchargeExempt;

  /// Indica si la oferta promocional vigente ganó frente a una lista con descuento (ej. Mayorista).
  bool get offerBeatDiscountTier =>
      !hasManualSellingPriceOverride && calculatedPrice.offerBeatDiscountTier;

  /// Indica si se aplica un precio pactado congelado (orden recuperada o presupuesto).
  bool get hasAgreedPrice =>
      !hasManualSellingPriceOverride && calculatedPrice.hasAgreedPrice;

  /// Indica si se aplica una bonificación pura de Lista Especial (Mayorista / Custom -%).
  bool get hasTierDiscount =>
      !hasManualSellingPriceOverride && calculatedPrice.hasTierDiscount;

  /// Indica si se aplica un recargo puro de Lista Especial (Tarjeta / Custom +%).
  bool get hasTierSurcharge =>
      !hasManualSellingPriceOverride && calculatedPrice.hasTierSurcharge;

  /// Indica si aplica un tramo por escala/volumen del catálogo.
  bool get hasVolumeScale =>
      !hasManualSellingPriceOverride && calculatedPrice.hasVolumeScale;

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
        if (agreedUnitPrice != null && agreedUnitPrice! > 0) {
          return 'Precio Pactado';
        }
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
