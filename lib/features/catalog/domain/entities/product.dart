import 'category.dart';
import 'brand.dart';
import 'package:frontend_desktop/features/suppliers/models/supplier_model.dart';

class Product {
  final int id;
  final String name;
  final String? barcode;
  final String internalCode;
  final double costPrice;
  final double sellingPrice;
  // [hardware_store] Listas de Precio — null en clientes retail
  final double? priceWholesale;
  final double? priceCard;
  final double stock;
  final bool active;
  final bool isSoldByWeight;
  final bool isCombo;
  final bool isService;
  final List<Map<String, dynamic>>? comboIngredients;
  final List<Map<String, dynamic>>? priceTiers;
  final int? vencimientoDias;
  final String? expirationDate;
  final int? expiryAlertDays;
  final bool trackBatches;
  final String lotDeductionPolicy;
  final bool allowSellExpired;
  final bool hasProductionRecipe;
  final double recipeYieldQuantity;
  final List<Map<String, dynamic>>? recipeIngredients;
  final double? minStock;
  final int salesCount;
  final String unitType;
  final String? supplierSku;
  final String? storageLocation;
  final String? technicalSpec;
  final String? purchasePackageName;
  final double? conversionFactor;
  final Map<String, dynamic>? calcConfig;
  final double ivaRate;
  final bool needsCatalogReview;
  final String? imageUrl;
  final Category? category;
  final List<Category>? categories;
  final Brand? brand;
  final Supplier? supplier;

  Product({
    required this.id,
    required this.name,
    this.barcode,
    required this.internalCode,
    required this.costPrice,
    required this.sellingPrice,
    this.priceWholesale, // [hardware_store]
    this.priceCard,      // [hardware_store]
    required this.stock,
    this.minStock,
    required this.active,
    required this.isSoldByWeight,
    this.isCombo = false,
    this.isService = false,
    this.comboIngredients,
    this.priceTiers,
    this.salesCount = 0,
    this.vencimientoDias,
    this.expirationDate,
    this.expiryAlertDays,
    this.trackBatches = false,
    this.lotDeductionPolicy = 'fefo',
    this.allowSellExpired = false,
    this.hasProductionRecipe = false,
    this.recipeYieldQuantity = 1.0,
    this.recipeIngredients,
    this.unitType = 'un',
    this.supplierSku,
    this.storageLocation,
    this.technicalSpec,
    this.purchasePackageName,
    this.conversionFactor,
    this.calcConfig,
    this.ivaRate = 21.0,
    this.needsCatalogReview = false,
    this.imageUrl,
    this.category,
    this.categories,
    this.brand,
    this.supplier,
  });

  static const Set<String> discreteUnitTypes = {
    'un',
    'bolsa',
    'rollo',
    'caja',
    'par',
  };

  static const Set<String> metricOrLiquidUnitTypes = {
    'mt',
    'm2',
    'm3',
    'lt',
  };

  bool get isDiscreteUnit =>
      discreteUnitTypes.contains(unitType.trim().toLowerCase());

  bool get isMetricOrLiquidUnit =>
      metricOrLiquidUnitTypes.contains(unitType.trim().toLowerCase());

  String get unitShortLabel => shortLabelFor(unitType);

  /// Etiqueta corta de unidad efectiva para cantidades/stock/precios fraccionados:
  /// Si `unitType` es explícito y distinto de `'un'` (ej. `'mt'`, `'m2'`, `'m3'`, `'lt'`, `'kg'`, `'g'`, `'bolsa'`, `'rollo'`, `'caja'`, `'par'`),
  /// devuelve `shortLabelFor(unitType)`. Si es `'un'` (o vacío), devuelve `'Kg'` cuando `isSoldByWeight == true` o `'un.'` cuando es `false`.
  String get effectiveQuantityUnitLabel =>
      resolveQuantityUnitLabel(unitType: unitType, isSoldByWeight: isSoldByWeight);

  /// Sufijo corto para tickets/recibos UI o PDF (ej. `'mt'`, `'m²'`, `'m³'`, `'Lt'`, `'kg'`, `'g'`, `'un'`).
  String get effectiveReceiptUnitSuffix =>
      resolveReceiptUnitSuffix(unitType: unitType, isSoldByWeight: isSoldByWeight);

  /// Sufijo ASCII puro para impresoras térmicas ESC/POS (ej. `'mt'`, `'m2'`, `'m3'`, `'lt'`, `'kg'`, `'g'`, `'un'`).
  String get effectiveAsciiReceiptUnitSuffix =>
      resolveReceiptUnitSuffix(
        unitType: unitType,
        isSoldByWeight: isSoldByWeight,
        asciiOnly: true,
      );

  static String resolveQuantityUnitLabel({
    String? unitType,
    required bool isSoldByWeight,
  }) {
    final norm = (unitType ?? '').trim().toLowerCase();
    if (norm.isNotEmpty && norm != 'un') {
      return shortLabelFor(norm);
    }
    return isSoldByWeight ? 'Kg' : 'un.';
  }

  static String resolveReceiptUnitSuffix({
    String? unitType,
    required bool isSoldByWeight,
    bool asciiOnly = false,
  }) {
    final norm = (unitType ?? '').trim().toLowerCase();
    if (norm.isNotEmpty && norm != 'un') {
      switch (norm) {
        case 'mt':
          return 'mt';
        case 'm2':
          return asciiOnly ? 'm2' : 'm²';
        case 'm3':
          return asciiOnly ? 'm3' : 'm³';
        case 'kg':
          return 'kg';
        case 'g':
          return 'g';
        case 'lt':
          return asciiOnly ? 'lt' : 'Lt';
        default:
          return norm;
      }
    }
    return isSoldByWeight ? 'kg' : 'un';
  }

  static String shortLabelFor(String rawUnitType) {
    switch (rawUnitType.trim().toLowerCase()) {
      case 'un':
        return 'un.';
      case 'mt':
        return 'mt';
      case 'm2':
        return 'm²';
      case 'm3':
        return 'm³';
      case 'kg':
        return 'Kg';
      case 'g':
        return 'g';
      case 'lt':
        return 'Lt';
      case 'bolsa':
        return 'bolsa';
      case 'rollo':
        return 'rollo';
      case 'caja':
        return 'caja';
      case 'par':
        return 'par';
      default:
        return rawUnitType.isNotEmpty ? rawUnitType : 'un.';
    }
  }

  Product copyWith({
    int? id,
    String? name,
    String? barcode,
    String? internalCode,
    double? costPrice,
    double? sellingPrice,
    double? priceWholesale, // [hardware_store]
    double? priceCard,      // [hardware_store]
    double? stock,
    double? minStock,
    bool? active,
    bool? isSoldByWeight,
    bool? isCombo,
    bool? isService,
    List<Map<String, dynamic>>? comboIngredients,
    List<Map<String, dynamic>>? priceTiers,
    int? salesCount,
    int? vencimientoDias,
    String? expirationDate,
    bool clearExpirationDate = false,
    int? expiryAlertDays,
    bool? trackBatches,
    String? lotDeductionPolicy,
    bool? allowSellExpired,
    bool? hasProductionRecipe,
    double? recipeYieldQuantity,
    List<Map<String, dynamic>>? recipeIngredients,
    String? unitType,
    String? supplierSku,
    bool clearSupplierSku = false,
    String? storageLocation,
    bool clearStorageLocation = false,
    String? technicalSpec,
    bool clearTechnicalSpec = false,
    String? purchasePackageName,
    bool clearPurchasePackageName = false,
    double? conversionFactor,
    bool clearConversionFactor = false,
    Map<String, dynamic>? calcConfig,
    bool clearCalcConfig = false,
    double? ivaRate,
    bool? needsCatalogReview,
    String? imageUrl,
    bool clearImageUrl = false,
    Category? category,
    bool clearCategory = false,
    List<Category>? categories,
    Brand? brand,
    bool clearBrand = false,
    Supplier? supplier,
    bool clearSupplier = false,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      barcode: barcode ?? this.barcode,
      internalCode: internalCode ?? this.internalCode,
      costPrice: costPrice ?? this.costPrice,
      sellingPrice: sellingPrice ?? this.sellingPrice,
      priceWholesale: priceWholesale ?? this.priceWholesale, // [hardware_store]
      priceCard: priceCard ?? this.priceCard,                 // [hardware_store]
      stock: stock ?? this.stock,
      minStock: minStock ?? this.minStock,
      active: active ?? this.active,
      isSoldByWeight: isSoldByWeight ?? this.isSoldByWeight,
      isCombo: isCombo ?? this.isCombo,
      isService: isService ?? this.isService,
      comboIngredients: comboIngredients ?? this.comboIngredients,
      priceTiers: priceTiers ?? this.priceTiers,
      salesCount: salesCount ?? this.salesCount,
      vencimientoDias: vencimientoDias ?? this.vencimientoDias,
      expirationDate: clearExpirationDate ? null : (expirationDate ?? this.expirationDate),
      expiryAlertDays: expiryAlertDays ?? this.expiryAlertDays,
      trackBatches: trackBatches ?? this.trackBatches,
      lotDeductionPolicy: lotDeductionPolicy ?? this.lotDeductionPolicy,
      allowSellExpired: allowSellExpired ?? this.allowSellExpired,
      hasProductionRecipe: hasProductionRecipe ?? this.hasProductionRecipe,
      recipeYieldQuantity: recipeYieldQuantity ?? this.recipeYieldQuantity,
      recipeIngredients: recipeIngredients ?? this.recipeIngredients,
      unitType: unitType ?? this.unitType,
      supplierSku: clearSupplierSku ? null : (supplierSku ?? this.supplierSku),
      storageLocation: clearStorageLocation ? null : (storageLocation ?? this.storageLocation),
      technicalSpec: clearTechnicalSpec ? null : (technicalSpec ?? this.technicalSpec),
      purchasePackageName: clearPurchasePackageName
          ? null
          : (purchasePackageName ?? this.purchasePackageName),
      conversionFactor: clearConversionFactor
          ? null
          : (conversionFactor ?? this.conversionFactor),
      calcConfig: clearCalcConfig ? null : (calcConfig ?? this.calcConfig),
      ivaRate: ivaRate ?? this.ivaRate,
      needsCatalogReview: needsCatalogReview ?? this.needsCatalogReview,
      imageUrl: clearImageUrl ? null : (imageUrl ?? this.imageUrl),
      category: clearCategory ? null : (category ?? this.category),
      categories: categories ?? this.categories,
      brand: clearBrand ? null : (brand ?? this.brand),
      supplier: clearSupplier ? null : (supplier ?? this.supplier),
    );
  }

  /// Devuelve el tramo aplicable para una cantidad dada.
  /// Si no hay tramos o no se supera, retorna null.
  Map<String, dynamic>? getApplicableTier(double quantity) {
    if (priceTiers == null || priceTiers!.isEmpty) return null;
    
    // Buscar todos los tramos que se hayan superado
    var aplicables = priceTiers!.where((t) {
      double minQ = double.tryParse(t['min_quantity'].toString()) ?? 1.0;
      return quantity >= minQ;
    }).toList();

    if (aplicables.isEmpty) return null;

    // Ordenar de mayor a menor y tomar el primero (el tramo más alto alcanzado)
    aplicables.sort((a, b) {
      double minA = double.tryParse(a['min_quantity'].toString()) ?? 1.0;
      double minB = double.tryParse(b['min_quantity'].toString()) ?? 1.0;
      return minB.compareTo(minA); // Descendente
    });

    return aplicables.first;
  }

  /// Devuelve el precio unitario final para una cantidad dada.
  double getBestPrice(double quantity) {
    final tier = getApplicableTier(quantity);
    if (tier != null) {
      return double.tryParse(tier['unit_price'].toString()) ?? sellingPrice;
    }
    return sellingPrice;
  }
}
