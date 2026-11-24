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
    'docena',
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

  /// Indica si este producto pertenece a un rubro o configuración F7 de Ferretería / Maderera.
  bool get hasHardwareCalcAccess {
    if (calcConfig != null && calcConfig!.isNotEmpty) return true;
    final rubroVert = category?.rubro?.verticalType?.trim().toLowerCase() ?? '';
    final rubroName = category?.rubro?.name.trim().toLowerCase() ?? '';
    return rubroVert == 'hardware_store' ||
        RegExp(r'ferret|mader|corral').hasMatch(rubroName);
  }

  /// Determina si un producto fraccionable con `unitType == 'un'` representa
  /// una unidad entera fraccionable (ej. tabla de madera, metro/pieza sin balanza)
  /// en lugar de un ítem pesable legado de verdulería/carnicería en Kg.
  bool isDiscreteFractionalItem({bool businessUsesScaleWeight = true}) {
    if (!isSoldByWeight) return false;
    final norm = unitType.trim().toLowerCase();
    if (norm.isNotEmpty && norm != 'un') return false;
    if (calcConfig != null && calcConfig!.isNotEmpty) return true;
    final rubroVert = category?.rubro?.verticalType?.trim().toLowerCase() ?? '';
    final rubroName = category?.rubro?.name.trim().toLowerCase() ?? '';
    if (rubroVert == 'hardware_store' ||
        RegExp(r'ferret|mader|corral').hasMatch(rubroName)) {
      return true;
    }
    if (rubroVert == 'retail' ||
        rubroVert == 'butcher' ||
        RegExp(r'verdul|carnic|fiambr|poller|supermerc|kiosc|almac|minimerc|panad')
            .hasMatch(rubroName)) {
      return false;
    }
    return !businessUsesScaleWeight;
  }

  String get unitShortLabel => shortLabelFor(unitType);

  /// Etiqueta corta de unidad efectiva para cantidades/stock/precios fraccionados:
  /// Si `unitType` es explícito y distinto de `'un'` (ej. `'mt'`, `'m2'`, `'m3'`, `'lt'`, `'kg'`, `'g'`, `'bolsa'`, `'rollo'`, `'caja'`, `'par'`, `'docena'`),
  /// devuelve `shortLabelFor(unitType)`. Si es `'un'` (o vacío), devuelve `'un.'` cuando
  /// `isSoldByWeight == false` o es un ítem discreto fraccionable (`calcConfig` o rubro ferretería),
  /// y `'Kg'` solo para pesables legados de balanza.
  String get effectiveQuantityUnitLabel => resolveQuantityUnitLabel(
        unitType: unitType,
        isSoldByWeight: isSoldByWeight,
        preferDiscreteUn: isDiscreteFractionalItem(businessUsesScaleWeight: true),
      );

  /// Sufijo corto para tickets/recibos UI o PDF (ej. `'mt'`, `'m²'`, `'m³'`, `'Lt'`, `'kg'`, `'g'`, `'un'`).
  String get effectiveReceiptUnitSuffix => resolveReceiptUnitSuffix(
        unitType: unitType,
        isSoldByWeight: isSoldByWeight,
        preferDiscreteUn: isDiscreteFractionalItem(businessUsesScaleWeight: true),
      );

  /// Sufijo ASCII puro para impresoras térmicas ESC/POS (ej. `'mt'`, `'m2'`, `'m3'`, `'lt'`, `'kg'`, `'g'`, `'un'`).
  String get effectiveAsciiReceiptUnitSuffix => resolveReceiptUnitSuffix(
        unitType: unitType,
        isSoldByWeight: isSoldByWeight,
        asciiOnly: true,
        preferDiscreteUn: isDiscreteFractionalItem(businessUsesScaleWeight: true),
      );

  static String resolveQuantityUnitLabel({
    String? unitType,
    required bool isSoldByWeight,
    bool preferDiscreteUn = false,
  }) {
    final norm = (unitType ?? '').trim().toLowerCase();
    if (norm.isNotEmpty && norm != 'un') {
      return shortLabelFor(norm);
    }
    if (!isSoldByWeight || preferDiscreteUn) {
      return 'un.';
    }
    return 'Kg';
  }

  static String resolveReceiptUnitSuffix({
    String? unitType,
    required bool isSoldByWeight,
    bool asciiOnly = false,
    bool preferDiscreteUn = false,
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
    if (!isSoldByWeight || preferDiscreteUn) {
      return 'un';
    }
    return 'kg';
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
      case 'docena':
        return 'doc.';
      default:
        return rawUnitType.isNotEmpty ? rawUnitType : 'un.';
    }
  }

  static String _normalizeForReceiptComparison(String input) {
    const fold = {
      'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a',
      'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
      'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
      'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o',
      'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
      'ñ': 'n',
      '×': 'x',
      '·': ' ',
      '•': ' ',
      '–': ' ',
      '—': ' ',
      '-': ' ',
      '/': ' ',
    };
    final out = StringBuffer();
    for (final rune in input.toLowerCase().runes) {
      final ch = String.fromCharCode(rune);
      out.write(fold[ch] ?? ch);
    }
    return out.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Convierte símbolos Unicode no soportados por ESC/POS (`×`, `·`, acentos, emojis)
  /// en ASCII plano seguro (`x`, `-`, etc.).
  static String sanitizeAsciiReceiptText(String text) {
    if (text.isEmpty) return text;
    const Map<String, String> replacements = {
      'Á': 'A', 'À': 'A', 'Â': 'A', 'Ä': 'A', 'Ã': 'A', 'Å': 'A',
      'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a',
      'Ó': 'O', 'Ò': 'O', 'Ô': 'O', 'Ö': 'O', 'Õ': 'O', 'Ø': 'O',
      'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o', 'ø': 'o',
      'É': 'E', 'È': 'E', 'Ê': 'E', 'Ë': 'E',
      'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
      'Ç': 'C', 'ç': 'c',
      'Í': 'I', 'Ì': 'I', 'Î': 'I', 'Ï': 'I',
      'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
      'Ú': 'U', 'Ù': 'U', 'Û': 'U', 'Ü': 'U',
      'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
      'Ñ': 'N', 'ñ': 'n',
      '°': 'o', 'º': 'o', 'ª': 'a',
      '¡': '', '¿': '',
      '→': '->', '←': '<-',
      '²': '2', '³': '3',
      '·': '-', '•': '-', '×': 'x',
      '–': '-', '—': '-',
      '“': '"', '”': '"', '‘': "'", '’': "'",
    };
    final out = StringBuffer();
    for (final rune in text.runes) {
      final char = String.fromCharCode(rune);
      final mapped = replacements[char];
      if (mapped != null) {
        out.write(mapped);
      } else if (rune >= 0x20 && rune <= 0x7E) {
        out.write(char);
      }
    }
    return out.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Combina `technicalSpec` y `customDetails` sin duplicar datos que ya aparezcan
  /// en `displayName` ni repetir `technicalSpec` dentro de `customDetails`.
  static String? resolveEffectiveReceiptDetails({
    required String displayName,
    String? technicalSpec,
    String? customDetails,
    bool asciiOnly = false,
  }) {
    final cleanCustom = customDetails?.trim() ?? '';
    final cleanSpec = technicalSpec?.trim() ?? '';

    final normDisplay = _normalizeForReceiptComparison(displayName);
    final normCustom = _normalizeForReceiptComparison(cleanCustom);
    final normSpec = _normalizeForReceiptComparison(cleanSpec);

    final includeSpec = cleanSpec.isNotEmpty &&
        normSpec.isNotEmpty &&
        !normDisplay.contains(normSpec) &&
        !normCustom.contains(normSpec);

    final parts = <String>[
      if (includeSpec) cleanSpec,
      if (cleanCustom.isNotEmpty) cleanCustom,
    ];
    if (parts.isEmpty) return null;

    final joined = parts.join(' - ');
    return asciiOnly ? sanitizeAsciiReceiptText(joined) : joined;
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
