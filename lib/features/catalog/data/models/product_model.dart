import 'dart:convert';
import '../../domain/entities/product.dart';
import 'package:frontend_desktop/core/utils/image_url_resolver.dart';
import 'category_model.dart';
import 'brand_model.dart';
import 'package:frontend_desktop/features/suppliers/models/supplier_model.dart';

class ProductModel extends Product {
  ProductModel({
    required super.id,
    required super.name,
    super.barcode,
    required super.internalCode,
    required super.costPrice,
    required super.sellingPrice,
    super.priceWholesale, // [hardware_store]
    super.priceCard,      // [hardware_store]
    required super.stock,
    super.minStock,
    required super.active,
    required super.isSoldByWeight,
    super.isCombo,
    super.isService,
    super.comboIngredients,
    super.priceTiers,
    super.salesCount,
    super.vencimientoDias,
    super.expirationDate,
    super.expiryAlertDays,
    super.trackBatches,
    super.lotDeductionPolicy,
    super.allowSellExpired,
    super.hasProductionRecipe,
    super.recipeYieldQuantity,
    super.recipeIngredients,
    super.unitType,
    super.supplierSku,
    super.storageLocation,
    super.technicalSpec,
    super.purchasePackageName,
    super.conversionFactor,
    super.calcConfig,
    super.ivaRate,
    super.needsCatalogReview,
    super.imageUrl,
    CategoryModel? super.category,
    List<CategoryModel>? super.categories,
    BrandModel? super.brand,
    super.supplier,
  });

  @override
  ProductModel copyWith({
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
    covariant CategoryModel? category,
    bool clearCategory = false,
    covariant List<CategoryModel>? categories,
    covariant BrandModel? brand,
    bool clearBrand = false,
    covariant dynamic supplier,
    bool clearSupplier = false,
  }) {
    return ProductModel(
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
      category: clearCategory ? null : (category ?? this.category as CategoryModel?),
      categories: categories ?? (this.categories as List<CategoryModel>?),
      brand: clearBrand ? null : (brand ?? this.brand as BrandModel?),
      supplier: clearSupplier ? null : (supplier ?? this.supplier),
    );
  }

  factory ProductModel.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>>? parsedCombo;
    if (json['children'] != null && json['children'] is List) {
      parsedCombo = (json['children'] as List).map((child) {
        return {
          'id': child['id'],
          'name': child['name'],
          'quantity': child['pivot']?['quantity'] != null 
              ? double.tryParse(child['pivot']['quantity'].toString()) ?? 1.0 
              : 1.0,
          'cost_price': double.tryParse(child['cost_price']?.toString() ?? '0') ?? 0.0,
          'selling_price': double.tryParse(child['selling_price']?.toString() ?? '0') ?? 0.0,
          'stock': double.tryParse(child['stock']?.toString() ?? '0') ?? 0.0,
          'unit_type': child['unit_type']?.toString() ?? 'un',
          'is_sold_by_weight': child['is_sold_by_weight'] == 1 ||
              child['is_sold_by_weight'] == true ||
              child['is_sold_by_weight'] == '1' ||
              child['is_sold_by_weight'] == 'true',
        };
      }).toList();
    }

    List<Map<String, dynamic>>? parsedPriceTiers;
    if (json['price_tiers'] != null && json['price_tiers'] is List) {
      parsedPriceTiers = (json['price_tiers'] as List).map((tier) {
        return {
          'min_quantity': double.tryParse(tier['min_quantity'].toString()) ?? 1.0,
          'unit_price': double.tryParse(tier['unit_price'].toString()) ?? 0.0,
        };
      }).toList();
    }

    List<CategoryModel>? parsedCategories;
    if (json['categories'] != null && json['categories'] is List) {
      parsedCategories = (json['categories'] as List)
          .whereType<Map>()
          .map((c) => CategoryModel.fromJson(Map<String, dynamic>.from(c)))
          .toList();
    }

    List<Map<String, dynamic>>? parsedRecipe;
    final rawRecipe = json['recipe_items'] ?? json['recipe_ingredients'];
    if (rawRecipe != null && rawRecipe is List) {
      parsedRecipe = rawRecipe.whereType<Map>().map((raw) {
        final item = Map<String, dynamic>.from(raw);
        final ing = item['ingredient'] is Map
            ? Map<String, dynamic>.from(item['ingredient'] as Map)
            : null;
        final ingId = (item['ingredient_product_id'] as num?)?.toInt() ??
            (ing?['id'] as num?)?.toInt() ??
            (item['id'] as num?)?.toInt() ??
            0;
        return {
          'id': ingId,
          'ingredient_product_id': ingId,
          'name': ing?['name']?.toString() ?? item['name']?.toString() ?? 'Ingrediente',
          'internal_code': ing?['internal_code']?.toString() ?? item['internal_code']?.toString() ?? '',
          'quantity': double.tryParse(item['quantity']?.toString() ?? '1') ?? 1.0,
          'waste_pct': double.tryParse(item['waste_pct']?.toString() ?? '0') ?? 0.0,
          'cost_price': double.tryParse((ing?['cost_price'] ?? item['cost_price'])?.toString() ?? '0') ?? 0.0,
          'stock': double.tryParse((ing?['stock'] ?? item['stock'])?.toString() ?? '0') ?? 0.0,
          'unit_type': (ing?['unit_type'] ?? item['unit_type'])?.toString() ?? 'un',
          'is_sold_by_weight': ing?['is_sold_by_weight'] == true ||
              ing?['is_sold_by_weight'] == 1 ||
              item['is_sold_by_weight'] == true ||
              item['is_sold_by_weight'] == 1,
          'track_batches': ing?['track_batches'] == true ||
              ing?['track_batches'] == 1 ||
              item['track_batches'] == true ||
              item['track_batches'] == 1,
        };
      }).toList();
    }

    return ProductModel(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      name: json['name']?.toString() ?? 'Sin nombre',
      barcode: json['barcode']?.toString(),
      internalCode: json['internal_code']?.toString() ?? '',
      costPrice: _resolveComboAwareCost(json, parsedCombo),
      sellingPrice: double.tryParse(json['selling_price']?.toString() ?? '0') ?? 0.0,
      // [hardware_store] Precios opcionales — null si no vienen del backend
      priceWholesale: json['price_wholesale'] != null && json['price_wholesale'].toString() != 'null'
          ? double.tryParse(json['price_wholesale'].toString())
          : null,
      priceCard: json['price_card'] != null && json['price_card'].toString() != 'null'
          ? double.tryParse(json['price_card'].toString())
          : null,
      stock: _resolveComboAwareStock(json, parsedCombo),
      minStock: (json['min_stock'] != null && json['min_stock'].toString().toLowerCase() != 'null') 
          ? double.tryParse(json['min_stock'].toString()) 
          : null,
      active: json['active'] == 1 || json['active'] == true || json['active'] == '1' || json['active'] == 'true',
      isSoldByWeight: json['is_sold_by_weight'] == 1 || json['is_sold_by_weight'] == true || json['is_sold_by_weight'] == '1' || json['is_sold_by_weight'] == 'true',
      isCombo: json['is_combo'] == 1 || json['is_combo'] == true || json['is_combo'] == '1' || json['is_combo'] == 'true',
      isService: json['is_service'] == 1 || json['is_service'] == true || json['is_service'] == '1' || json['is_service'] == 'true',
      comboIngredients: parsedCombo,
      priceTiers: parsedPriceTiers,
      salesCount: json['sales_count'] != null 
          ? (int.tryParse(json['sales_count'].toString()) ?? 0) 
          : 0,
      vencimientoDias: json['vencimiento_dias'] != null
          ? int.tryParse(json['vencimiento_dias'].toString())
          : null,
      expirationDate: json['expiration_date'] != null &&
              json['expiration_date'].toString() != 'null' &&
              json['expiration_date'].toString().trim().isNotEmpty
          ? json['expiration_date'].toString().split('T').first
          : null,
      expiryAlertDays: json['expiry_alert_days'] != null
          ? int.tryParse(json['expiry_alert_days'].toString())
          : 15,
      trackBatches: json['track_batches'] == 1 ||
          json['track_batches'] == true ||
          json['track_batches'] == '1' ||
          json['track_batches'] == 'true',
      lotDeductionPolicy: json['lot_deduction_policy']?.toString() ?? 'fefo',
      allowSellExpired: json['allow_sell_expired'] == 1 ||
          json['allow_sell_expired'] == true ||
          json['allow_sell_expired'] == '1' ||
          json['allow_sell_expired'] == 'true',
      hasProductionRecipe: json['has_production_recipe'] == 1 ||
          json['has_production_recipe'] == true ||
          json['has_production_recipe'] == '1' ||
          json['has_production_recipe'] == 'true',
      recipeYieldQuantity: double.tryParse(json['recipe_yield_quantity']?.toString() ?? '1') ?? 1.0,
      recipeIngredients: parsedRecipe,
      unitType: json['unit_type']?.toString() ?? 'un',
      supplierSku: _parseOptionalString(json['supplier_sku']),
      storageLocation: _parseOptionalString(json['storage_location']),
      technicalSpec: _parseOptionalString(json['technical_spec']),
      purchasePackageName: _parseOptionalString(json['purchase_package_name']),
      conversionFactor: json['conversion_factor'] != null &&
              json['conversion_factor'].toString().toLowerCase() != 'null'
          ? double.tryParse(json['conversion_factor'].toString())
          : null,
      calcConfig: parseCalcConfig(json['calc_config']),
      ivaRate: json['iva_rate'] != null
          ? (double.tryParse(json['iva_rate'].toString()) ?? 21.0)
          : 21.0,
      needsCatalogReview: json['needs_catalog_review'] == 1 ||
          json['needs_catalog_review'] == true ||
          json['needs_catalog_review'] == '1' ||
          json['needs_catalog_review'] == 'true',
      imageUrl: resolveImageUrl(json['image_url']?.toString()) ??
          resolveImageUrl(json['image_path']?.toString()),
      category: json['category'] != null && json['category'] is Map<String, dynamic>
          ? CategoryModel.fromJson(json['category'] as Map<String, dynamic>)
          : (parsedCategories != null && parsedCategories.isNotEmpty ? parsedCategories.first : null),
      categories: parsedCategories,
      brand: json['brand'] != null && json['brand'] is Map<String, dynamic>
          ? BrandModel.fromJson(json['brand'] as Map<String, dynamic>)
          : null,
      supplier: json['supplier'] != null && json['supplier'] is Map<String, dynamic>
          ? Supplier.fromJson(json['supplier'] as Map<String, dynamic>)
          : null,
    );
  }

  static String? _parseOptionalString(dynamic raw) {
    if (raw == null) return null;
    final str = raw.toString().trim();
    if (str.isEmpty || str.toLowerCase() == 'null') return null;
    return str;
  }

  static Map<String, dynamic>? parseCalcConfig(dynamic raw) {
    if (raw == null) return null;
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    if (raw is String && raw.trim().isNotEmpty && raw.trim() != 'null') {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}
    }
    return null;
  }

  static double _resolveComboAwareCost(
    Map<String, dynamic> json,
    List<Map<String, dynamic>>? parsedCombo,
  ) {
    final isCombo = json['is_combo'] == 1 ||
        json['is_combo'] == true ||
        json['is_combo'] == '1' ||
        json['is_combo'] == 'true';
    if (isCombo && parsedCombo != null && parsedCombo.isNotEmpty) {
      double totalCost = 0.0;
      for (final ing in parsedCombo) {
        final c = (ing['cost_price'] as num?)?.toDouble() ?? 0.0;
        final q = (ing['quantity'] as num?)?.toDouble() ?? 1.0;
        totalCost += c * q;
      }
      return totalCost;
    }
    return double.tryParse(json['cost_price']?.toString() ?? '0') ?? 0.0;
  }

  static double _resolveComboAwareStock(
    Map<String, dynamic> json,
    List<Map<String, dynamic>>? parsedCombo,
  ) {
    final isCombo = json['is_combo'] == 1 ||
        json['is_combo'] == true ||
        json['is_combo'] == '1' ||
        json['is_combo'] == 'true';
    if (isCombo && parsedCombo != null && parsedCombo.isNotEmpty) {
      int? limiting;
      for (final ing in parsedCombo) {
        final s = (ing['stock'] as num?)?.toDouble() ?? 0.0;
        final q = (ing['quantity'] as num?)?.toDouble() ?? 1.0;
        if (q <= 0) continue;
        final possible = (s < 0 ? 0 : (s / q).floor());
        if (limiting == null || possible < limiting) {
          limiting = possible;
        }
      }
      return (limiting ?? 0).toDouble();
    }
    return double.tryParse(json['stock']?.toString() ?? '0') ?? 0.0;
  }
}
