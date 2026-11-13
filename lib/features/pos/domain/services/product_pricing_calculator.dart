import '../../../catalog/domain/entities/product.dart';

/// Listas de precios soportadas por la Terminal POS.
enum PriceTier { base, wholesale, card, custom }

/// Estrategia de interacción cuando se aplica una lista con recargo (Tarjeta o lista +X%)
/// sobre un producto que tiene una Oferta promocional activa.
enum CardSurchargeOnOffersMode {
  /// Aplica el % de recargo sobre el precio de oferta vigente.
  surchargeOnOffer,

  /// Ignora la oferta promocional y cobra el precio normal de la lista con recargo.
  cardOverridesOffer,

  /// Respeta el precio de oferta sin aplicar recargo de tarjeta/lista.
  offerNoSurcharge;

  String get apiValue {
    switch (this) {
      case CardSurchargeOnOffersMode.surchargeOnOffer:
        return 'surcharge_on_offer';
      case CardSurchargeOnOffersMode.cardOverridesOffer:
        return 'card_overrides_offer';
      case CardSurchargeOnOffersMode.offerNoSurcharge:
        return 'offer_no_surcharge';
    }
  }

  static CardSurchargeOnOffersMode fromApiString(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'card_overrides_offer':
        return CardSurchargeOnOffersMode.cardOverridesOffer;
      case 'offer_no_surcharge':
        return CardSurchargeOnOffersMode.offerNoSurcharge;
      case 'surcharge_on_offer':
      default:
        return CardSurchargeOnOffersMode.surchargeOnOffer;
    }
  }
}

/// Resultado unificado del motor de precios para un producto (Carrito, Acceso Rápido,
/// Consultor de Precios y Diálogo de Edición/Renombrado).
class CalculatedProductPrice {
  final double finalUnitPrice;
  final double regularUnitPrice;
  final double tierCalculatedUnitPrice;
  final double preSurchargeUnitPrice;
  final double? crossedOutPrice;
  final bool hasActiveOffer;
  final bool hasSurchargeOnOffer;
  final bool isOfferSurchargeExempt;
  final bool hasTierDiscount;
  final bool hasTierSurcharge;
  final bool hasVolumeScale;
  final bool hasAgreedPrice;
  final double? appliedSurchargeFactor;

  const CalculatedProductPrice({
    required this.finalUnitPrice,
    required this.regularUnitPrice,
    required this.tierCalculatedUnitPrice,
    required this.preSurchargeUnitPrice,
    required this.crossedOutPrice,
    required this.hasActiveOffer,
    required this.hasSurchargeOnOffer,
    required this.isOfferSurchargeExempt,
    required this.hasTierDiscount,
    required this.hasTierSurcharge,
    required this.hasVolumeScale,
    required this.hasAgreedPrice,
    required this.appliedSurchargeFactor,
  });
}

/// Motor único de cálculo de precios del POS.
/// Garantiza que Carrito, Grilla de Acceso Rápido, Consultor de Precios y Diálogo de Edición
/// muestren exactamente los mismos importes, redondeos y tachados.
class ProductPricingCalculator {
  ProductPricingCalculator._();

  /// Redondea a 2 decimales monetarios para evitar ruido binario de punto flotante
  /// (por ej. 55000 * 1.15 = 63249.99999999999 -> 63250.0).
  static double roundMoney(double value) {
    if (!value.isFinite) return 0.0;
    return (value * 100.0).roundToDouble() / 100.0;
  }

  /// Calcula el precio efectivo para [product] según lista activa, cantidad,
  /// oferta vigente, precio pactado de orden recuperada y regla de recargo sobre ofertas.
  static CalculatedProductPrice calculate({
    required Product product,
    double quantity = 1.0,
    PriceTier activeTier = PriceTier.base,
    double wholesaleFactor = 0.85,
    double cardFactor = 1.15,
    double customFactor = 1.0,
    double? promotionalPrice,
    bool hasExplicitOffer = false,
    double? agreedUnitPrice,
    CardSurchargeOnOffersMode cardSurchargeOnOffersMode =
        CardSurchargeOnOffersMode.surchargeOnOffer,
  }) {
    final regularUnit = roundMoney(product.sellingPrice);
    final rawVolumetric = product.getBestPrice(quantity);
    final baseVolumetric = roundMoney(rawVolumetric);
    final hasVolumeScale = baseVolumetric < regularUnit - 0.009;

    // 1. Precio base de la lista seleccionada (antes de ofertas)
    late final double rawTierPrice;
    switch (activeTier) {
      case PriceTier.wholesale:
        if (product.priceWholesale != null && product.priceWholesale! > 0) {
          rawTierPrice = product.priceWholesale!;
        } else {
          rawTierPrice = baseVolumetric * wholesaleFactor;
        }
        break;
      case PriceTier.card:
        if (product.priceCard != null && product.priceCard! > 0) {
          rawTierPrice = product.priceCard!;
        } else {
          rawTierPrice = baseVolumetric * cardFactor;
        }
        break;
      case PriceTier.custom:
        rawTierPrice = baseVolumetric * customFactor;
        break;
      case PriceTier.base:
        if ((customFactor - 1.0).abs() > 0.0001) {
          rawTierPrice = baseVolumetric * customFactor;
        } else {
          rawTierPrice = baseVolumetric;
        }
        break;
    }
    final tierPrice = roundMoney(rawTierPrice);

    final bool isSurchargeTier = activeTier == PriceTier.card ||
        (activeTier == PriceTier.custom && customFactor > 1.0001);
    final double activeSurchargeFactor = isSurchargeTier
        ? (activeTier == PriceTier.card ? cardFactor : customFactor)
        : 1.0;

    final double? validPromo =
        (promotionalPrice != null && promotionalPrice > 0)
            ? roundMoney(promotionalPrice)
            : null;
    final double? validAgreed =
        (agreedUnitPrice != null && agreedUnitPrice > 0)
            ? roundMoney(agreedUnitPrice)
            : null;

    // 2. Verificar si una oferta promocional real aplica en este contexto
    final bool hasOfferCandidate = validPromo != null && hasExplicitOffer;

    double finalUnit = tierPrice;
    double preSurchargeUnit = tierPrice;
    bool hasActiveOffer = false;
    bool hasSurchargeOnOffer = false;
    bool isOfferSurchargeExempt = false;
    bool hasAgreedPrice = false;
    double? appliedSurchargeFactor;

    if (validAgreed != null &&
        (!hasOfferCandidate || validAgreed <= validPromo)) {
      // Precio congelado al recuperar orden/presupuesto (prevalece si no hay oferta menor)
      finalUnit = validAgreed;
      preSurchargeUnit = validAgreed;
      hasAgreedPrice = true;
    } else if (hasOfferCandidate) {
      if (isSurchargeTier) {
        final bool promoDiscountExists =
            validPromo < baseVolumetric - 0.009 ||
                validPromo < regularUnit - 0.009;
        if (promoDiscountExists) {
          switch (cardSurchargeOnOffersMode) {
            case CardSurchargeOnOffersMode.surchargeOnOffer:
              preSurchargeUnit = validPromo;
              if (activeSurchargeFactor > 1.0001) {
                finalUnit = roundMoney(validPromo * activeSurchargeFactor);
                hasSurchargeOnOffer = true;
                appliedSurchargeFactor = activeSurchargeFactor;
              } else {
                finalUnit = validPromo;
              }
              hasActiveOffer = true;
              break;
            case CardSurchargeOnOffersMode.cardOverridesOffer:
              finalUnit = tierPrice;
              preSurchargeUnit = tierPrice;
              hasActiveOffer = false;
              break;
            case CardSurchargeOnOffersMode.offerNoSurcharge:
              if (validPromo < tierPrice - 0.001) {
                finalUnit = validPromo;
                preSurchargeUnit = validPromo;
                hasActiveOffer = true;
                if (activeSurchargeFactor > 1.0001) {
                  isOfferSurchargeExempt = true;
                }
              }
              break;
          }
        }
      } else {
        // Lista Minorista / Mayorista / Custom con descuento: gana el precio más bajo (sin apilar)
        if (validPromo < tierPrice - 0.001) {
          finalUnit = validPromo;
          preSurchargeUnit = validPromo;
          hasActiveOffer = true;
        }
      }
    }

    // 3. Regla de precio tachado: siempre comparar contra el precio de lista regular del catálogo
    //    (solo se tacha cuando el precio final al cliente es efectivamente menor al precio de lista).
    final double? crossedOutPrice =
        (regularUnit > 0 && finalUnit < regularUnit - 0.009)
            ? regularUnit
            : null;

    final bool hasTierDiscount = !hasActiveOffer &&
        !hasAgreedPrice &&
        !hasVolumeScale &&
        activeTier != PriceTier.base &&
        finalUnit < regularUnit - 0.009;

    final bool hasTierSurcharge = !hasActiveOffer &&
        !hasAgreedPrice &&
        isSurchargeTier &&
        finalUnit > regularUnit + 0.009;

    return CalculatedProductPrice(
      finalUnitPrice: finalUnit,
      regularUnitPrice: regularUnit,
      tierCalculatedUnitPrice: tierPrice,
      preSurchargeUnitPrice: preSurchargeUnit,
      crossedOutPrice: crossedOutPrice,
      hasActiveOffer: hasActiveOffer,
      hasSurchargeOnOffer: hasSurchargeOnOffer,
      isOfferSurchargeExempt: isOfferSurchargeExempt,
      hasTierDiscount: hasTierDiscount,
      hasTierSurcharge: hasTierSurcharge,
      hasVolumeScale:
          hasVolumeScale && !hasActiveOffer && !hasAgreedPrice && !isSurchargeTier,
      hasAgreedPrice: hasAgreedPrice,
      appliedSurchargeFactor: appliedSurchargeFactor,
    );
  }
}
