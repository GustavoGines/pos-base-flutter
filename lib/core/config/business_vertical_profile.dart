import 'package:flutter/material.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/rubro.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';

/// Perfil operativo y visual de Caja4U según el Rubro Comercial del negocio
/// (`business_type`, `secondary_business_types` o `Rubro` específico en modo `multi_rubro`).
class BusinessVerticalProfile {
  static const String retail = 'retail';
  static const String butcher = 'butcher';
  static const String hardwareStore = 'hardware_store';
  static const String apparel = 'apparel';
  static const String tech = 'tech';
  static const String general = 'general';

  static const List<String> allVerticalCodes = [
    retail,
    butcher,
    hardwareStore,
    apparel,
    tech,
    general,
  ];

  static const Map<String, String> selectorLabels = {
    retail: '🛒 Minimercado / Kiosco / Almacén',
    butcher: '🥩 Carnicería / Pollería / Verdulería (Kg)',
    hardwareStore: '🔨 Ferretería / Maderera / Pinturería',
    apparel: '👕 Indumentaria / Ropería / Calzado',
    tech: '💻 Tecnología / Celulares / Repuestos (Motos)',
    general: '🏪 Bazar / Librería / Juguetería',
  };

  static const Map<String, String> shortBadgeLabels = {
    retail: 'Minimercado',
    butcher: 'Carnicería / Kg',
    hardwareStore: 'Ferretería',
    apparel: 'Indumentaria',
    tech: 'Tecnología',
    general: 'Bazar / General',
  };

  final String primaryType;
  final List<String> secondaryTypes;
  final bool isRubroScoped;

  // Etiquetas de pestañas y campos en Ficha Producto
  final String productTabLabel;
  final String serviceTabLabel;
  final String comboTabLabel;
  final String productNameFieldLabel;
  final String serviceNameFieldLabel;
  final String barcodeHelperText;
  final String supplierSkuHint;
  final String specFieldLabel;
  final String specFieldHint;
  final String locationFieldLabel;
  final String locationFieldHint;
  final String detailsToggleLabel;

  // Visibilidad y comportamiento en Ficha Producto
  final bool showDetailsExpandedInForm;
  final bool showPackageConversionInForm;
  final List<String> packagePresets;
  final bool showFractionSwitchInForm;
  final String weightSwitchLabelWide;
  final String weightSwitchLabelNarrow;
  final bool showFractionalExplanationBanner;

  // Columnas en Tabla de Catálogo
  final bool showSupplierSkuColumnInCatalog;
  final bool showLocationColumnInCatalog;
  final bool showSpecColumnInCatalog;
  final String specColumnHeader;
  final bool showUnitColumnInCatalog;
  final bool showBalColumnInCatalog;

  // Unidades y defaults de alta rápida
  final List<String> allowedUnitKeys;
  final String defaultUnitType;
  final bool defaultSoldByWeight;

  // Grilla Rápida por Proveedor
  final String quickGridSpecHeader;
  final String quickGridSpecHint;
  final String quickGridLocationHeader;
  final String quickGridLocationHint;
  final String quickGridFracHeader;
  final String quickGridFracTooltip;

  // Capacidades transversales
  final bool _nativeScaleWeight;
  final bool _nativeFractionalCut;

  const BusinessVerticalProfile({
    required this.primaryType,
    this.secondaryTypes = const [],
    this.isRubroScoped = false,
    required this.productTabLabel,
    required this.serviceTabLabel,
    required this.comboTabLabel,
    required this.productNameFieldLabel,
    required this.serviceNameFieldLabel,
    required this.barcodeHelperText,
    required this.supplierSkuHint,
    required this.specFieldLabel,
    required this.specFieldHint,
    required this.locationFieldLabel,
    required this.locationFieldHint,
    required this.detailsToggleLabel,
    required this.showDetailsExpandedInForm,
    required this.showPackageConversionInForm,
    required this.packagePresets,
    required this.showFractionSwitchInForm,
    required this.weightSwitchLabelWide,
    required this.weightSwitchLabelNarrow,
    required this.showFractionalExplanationBanner,
    required this.showSupplierSkuColumnInCatalog,
    required this.showLocationColumnInCatalog,
    required this.showSpecColumnInCatalog,
    required this.specColumnHeader,
    required this.showUnitColumnInCatalog,
    required this.showBalColumnInCatalog,
    required this.allowedUnitKeys,
    required this.defaultUnitType,
    required this.defaultSoldByWeight,
    required this.quickGridSpecHeader,
    required this.quickGridSpecHint,
    required this.quickGridLocationHeader,
    required this.quickGridLocationHint,
    required this.quickGridFracHeader,
    required this.quickGridFracTooltip,
    required bool nativeScaleWeight,
    required bool nativeFractionalCut,
  })  : _nativeScaleWeight = nativeScaleWeight,
        _nativeFractionalCut = nativeFractionalCut;

  bool get isHardwareStore =>
      primaryType == hardwareStore || secondaryTypes.contains(hardwareStore);

  bool get isButcher => primaryType == butcher;

  bool get isApparel => primaryType == apparel;

  bool get isTech => primaryType == tech;

  String get displayLabel => selectorLabels[primaryType] ?? shortBadgeLabels[primaryType] ?? 'Comercio';

  String get shortLabel => shortBadgeLabels[primaryType] ?? 'Comercio';

  String get locationShortPrefix {
    switch (primaryType) {
      case apparel:
        return 'Perchero';
      case tech:
        return 'Vitrina';
      case butcher:
        return 'Cámara';
      case retail:
        return 'Góndola';
      default:
        return 'Ubic';
    }
  }

  IconData get specBadgeIcon {
    switch (primaryType) {
      case apparel:
        return Icons.checkroom_rounded;
      case tech:
        return Icons.memory_rounded;
      default:
        return Icons.straighten_outlined;
    }
  }

  String get excelImportColumnsHint {
    if (isApparel) {
      return 'Columnas flexibles: nombre, talle, color, perchero, codigo_barras, costo, precio, stock, unidad (un/par/docena)...';
    }
    if (isTech) {
      return 'Columnas flexibles: nombre, cod_proveedor, modelo, vitrina, codigo_barras, costo, precio, stock...';
    }
    if (primaryType == hardwareStore) {
      return 'Columnas flexibles: nombre, cod_proveedor, medida, ubicacion, unidad (un/mt/m2/m3/bolsa/rollo), factor_conversion...';
    }
    if (primaryType == butcher) {
      return 'Columnas flexibles: nombre, corte, camara, unidad (kg/g/un/caja), costo, precio, stock, vencimiento_dias...';
    }
    if (primaryType == general) {
      return 'Columnas flexibles: nombre, variante, ubicacion, unidad (un/caja/docena), presentacion_compra, codigo_barras...';
    }
    return 'Columnas flexibles: nombre, codigo_barras, costo, precio, stock, unidad (un/kg/lt/docena), vencimiento_dias...';
  }

  String get posQuickAccessSubtitle {
    if (isHardwareStore && !canUseScaleWeight) {
      return 'Acceso rápido a materiales fraccionables y de corte';
    }
    if (isApparel) {
      return 'Prendas / artículos fraccionables';
    }
    if (isTech) {
      return 'Cables y repuestos fraccionables';
    }
    if (!canUseScaleWeight) {
      return 'Artículos fraccionables por unidad o metro';
    }
    return 'Productos por peso o medida';
  }

  String get posEmptyFractionalFilterLabel {
    if (isHardwareStore && !canUseScaleWeight) {
      return 'No hay materiales fraccionables o por medida';
    }
    if (!canUseScaleWeight) {
      return 'No hay artículos fraccionables disponibles';
    }
    return 'No hay productos por peso o fraccionables';
  }

  bool get canUseHardwareCalculator => isHardwareStore;

  bool get canUseScaleWeight =>
      _nativeScaleWeight ||
      secondaryTypes.contains(retail) ||
      secondaryTypes.contains(butcher);

  bool get canUseFractionalCut =>
      _nativeFractionalCut || secondaryTypes.contains(hardwareStore);

  bool get showQuickGridFracColumn => canUseScaleWeight || canUseFractionalCut;

  bool get hasNativeBatches => primaryType == retail || primaryType == butcher;

  bool showFractionSwitchForUnit(String rawUnitType) {
    if (showFractionSwitchInForm) return true;
    return isTech && rawUnitType.trim().toLowerCase() == 'mt';
  }

  /// Controla si en `Editar Línea en Carrito (Ctrl+E)` se muestra el selector
  /// rápido de fracciones/porciones (`1/x`). Se habilita en rubros fraccionables
  /// (`retail`, `butcher`, `hardware_store`), o en unidades `docena` / `mt`.
  bool canUseCartQuickFractionsForUnit(String rawUnitType) {
    if (showFractionSwitchForUnit(rawUnitType)) return true;
    final norm = rawUnitType.trim().toLowerCase();
    if (norm == 'docena') return true;
    if (norm == 'mt' && allowedUnitKeys.contains('mt')) return true;
    return false;
  }

  /// Usa terminología de material/corte ("Fracción") en lugar de gastronómica ("Porción").
  bool get usesFractionalMaterialTerminology =>
      primaryType == hardwareStore || primaryType == tech;

  /// Sugerencia contextual para el campo `Notas en línea (Opcional)` del carrito.
  String get cartLineNotesHint {
    switch (primaryType) {
      case apparel:
        return 'Ej: Talle, color, cambio...';
      case hardwareStore:
        return 'Ej: Corte a medida, color, detalle...';
      case tech:
        return 'Ej: N° de serie, IMEI, modelo...';
      case butcher:
        return 'Ej: Corte milanesa, picada, envasado...';
      case general:
        return 'Ej: Variante, color, p/regalo...';
      case retail:
      default:
        return 'Ej: Sabores, cocción, detalle...';
    }
  }

  /// Determina si un [Rubro] de categoría puede cambiar el perfil operativo activo.
  /// En Plan Básico (`hasMultiRubro == false`), solo permite cambiar a verticales
  /// explícitamente incluidos en la licencia (`primaryType` o `secondaryTypes`),
  /// impidiendo que productos demo/legados filtren herramientas de otros rubros.
  bool canScopeToRubro(Rubro? rubro, {required bool hasMultiRubro}) {
    if (rubro == null) return false;
    if (hasMultiRubro) return true;
    final explicit = rubro.verticalType?.trim().toLowerCase();
    final resolved = (explicit != null && allVerticalCodes.contains(explicit))
        ? explicit
        : inferVerticalCodeFromRubroName(rubro.name);
    if (resolved == null) return false;
    return resolved == primaryType || secondaryTypes.contains(resolved);
  }

  /// Resuelve el perfil efectivo de un ítem/categoría respetando `multi_rubro` y el rubro licenciado.
  BusinessVerticalProfile resolveItemProfile(
    Rubro? rubro, {
    required bool hasMultiRubro,
  }) {
    if (!canScopeToRubro(rubro, hasMultiRubro: hasMultiRubro)) {
      return this;
    }
    return forCategoryRubro(rubro);
  }

  /// Controla si se habilita Vencimientos/Lotes según la licencia y, en Polirrubro,
  /// restringido al vertical del rubro del producto (aislando Ferretería/Indumentaria/Tech).
  bool canUseBatchExpiration({
    required bool featureBatchExpiration,
    required bool featureProduction,
    bool storeHasNativeBatchVertical = true,
  }) {
    if (!featureBatchExpiration && !featureProduction) return false;
    // Licencias no-alimentarias con addon batch_expiration explícito (ej. Pinturería)
    if (!storeHasNativeBatchVertical) return true;
    if (!isRubroScoped) return true;
    return hasNativeBatches;
  }

  /// Controla si se habilita Receta de Elaboración Propia (solo Almacén/Carnicería).
  bool canUseProductionForItem({required bool featureProduction}) {
    if (!featureProduction) return false;
    if (!isRubroScoped) {
      return hasNativeBatches ||
          secondaryTypes.any((t) => t == retail || t == butcher);
    }
    return hasNativeBatches;
  }

  static bool isNativeBatchVertical(
    String? primary, [
    List<String> secondary = const [],
  ]) {
    final p = normalizeCode(primary);
    if (p == retail || p == butcher) return true;
    return secondary.any((s) {
      final ns = normalizeCode(s);
      return ns == retail || ns == butcher;
    });
  }

  static String normalizeCode(String? raw) {
    final clean = (raw ?? '').trim().toLowerCase();
    if (allVerticalCodes.contains(clean)) return clean;
    return retail;
  }

  static BusinessVerticalProfile fromSettings(BusinessSettings? settings) {
    if (settings == null) {
      return fromType(retail);
    }
    return fromType(
      settings.businessType,
      secondaryTypes: settings.secondaryBusinessTypes,
    );
  }

  static BusinessVerticalProfile fromType(
    String? rawType, {
    List<String> secondaryTypes = const [],
    bool isRubroScoped = false,
  }) {
    final normalizedPrimary = normalizeCode(rawType);
    final normalizedSecondary = secondaryTypes
        .map(normalizeCode)
        .where((t) => t != normalizedPrimary)
        .toSet()
        .toList();

    switch (normalizedPrimary) {
      case hardwareStore:
        return BusinessVerticalProfile(
          primaryType: hardwareStore,
          secondaryTypes: normalizedSecondary,
          isRubroScoped: isRubroScoped,
          productTabLabel: 'Artículo / Material',
          serviceTabLabel: 'Servicio / Flete',
          comboTabLabel: 'Kit / Fracción',
          productNameFieldLabel: 'Nombre del Artículo / Material *',
          serviceNameFieldLabel: 'Nombre del Servicio / Flete *',
          barcodeHelperText: 'Opcional en artículos a granel / corte',
          supplierSkuHint: 'Ej: BRE-4021',
          specFieldLabel: 'Medida / Especificación',
          specFieldHint: 'Ej: Lapacho 1" × 6" × 4.00m · Caño 1/2"',
          locationFieldLabel: 'Ubicación / Estantería',
          locationFieldHint: 'Ej: Pasillo 2 - Gaveta B4',
          detailsToggleLabel: 'Agregar ubicación / medida',
          showDetailsExpandedInForm: true,
          showPackageConversionInForm: true,
          packagePresets: const [
            'Rollo',
            'Caja',
            'Bolsa',
            'Bolsón',
            'Balde',
            'Tambor',
            'Pallet',
            'Pack',
            'Atado',
          ],
          showFractionSwitchInForm: true,
          weightSwitchLabelWide: 'Permite fraccionar',
          weightSwitchLabelNarrow: 'Permite venta fraccionada / corte',
          showFractionalExplanationBanner: true,
          showSupplierSkuColumnInCatalog: true,
          showLocationColumnInCatalog: true,
          showSpecColumnInCatalog: false,
          specColumnHeader: 'Medida',
          showUnitColumnInCatalog: true,
          showBalColumnInCatalog: false,
          allowedUnitKeys: const [
            'un',
            'mt',
            'm2',
            'm3',
            'bolsa',
            'rollo',
            'caja',
            'par',
            'docena',
            'kg',
            'g',
            'lt',
          ],
          defaultUnitType: 'un',
          defaultSoldByWeight: false,
          quickGridSpecHeader: 'Medida / Espec.',
          quickGridSpecHint: '1/2" / 2.5mm',
          quickGridLocationHeader: 'Ubicación',
          quickGridLocationHint: 'Estante / Gav.',
          quickGridFracHeader: 'Fracc.',
          quickGridFracTooltip:
              'Venta fraccionada (permite decimales, ej: 2.5 mt o 0.5 kg)',
          nativeScaleWeight: false,
          nativeFractionalCut: true,
        );

      case butcher:
        return BusinessVerticalProfile(
          primaryType: butcher,
          secondaryTypes: normalizedSecondary,
          isRubroScoped: isRubroScoped,
          productTabLabel: 'Corte / Producto',
          serviceTabLabel: 'Envío / Servicio',
          comboTabLabel: 'Promo / Bolsón',
          productNameFieldLabel: 'Nombre del Corte / Artículo *',
          serviceNameFieldLabel: 'Nombre del Envío / Servicio *',
          barcodeHelperText: 'Opcional en cortes pesables de balanza',
          supplierSkuHint: 'Ej: FRIG-102',
          specFieldLabel: 'Corte / Categoría',
          specFieldHint: 'Ej: Costilla · Novillo · Cajón 20kg',
          locationFieldLabel: 'Cámara / Heladera / Batea',
          locationFieldHint: 'Ej: Cámara 1 · Mostrador',
          detailsToggleLabel: 'Agregar cámara / corte',
          showDetailsExpandedInForm: false,
          showPackageConversionInForm: true,
          packagePresets: const ['Cajón', 'Horma', 'Media Res', 'Maple', 'Bolsa', 'Caja'],
          showFractionSwitchInForm: true,
          weightSwitchLabelWide: 'Venta p/peso',
          weightSwitchLabelNarrow: 'Venta p/peso (balanza)',
          showFractionalExplanationBanner: false,
          showSupplierSkuColumnInCatalog: false,
          showLocationColumnInCatalog: false,
          showSpecColumnInCatalog: false,
          specColumnHeader: 'Corte',
          showUnitColumnInCatalog: false,
          showBalColumnInCatalog: true,
          allowedUnitKeys: const ['kg', 'g', 'un', 'caja', 'bolsa'],
          defaultUnitType: 'kg',
          defaultSoldByWeight: true,
          quickGridSpecHeader: 'Corte / Detalle',
          quickGridSpecHint: 'Fresco / Novillo',
          quickGridLocationHeader: 'Cámara / Batea',
          quickGridLocationHint: 'Cámara 1 / Batea',
          quickGridFracHeader: 'Bal.',
          quickGridFracTooltip: 'Venta por peso en balanza (Kg / g)',
          nativeScaleWeight: true,
          nativeFractionalCut: false,
        );

      case apparel:
        return BusinessVerticalProfile(
          primaryType: apparel,
          secondaryTypes: normalizedSecondary,
          isRubroScoped: isRubroScoped,
          productTabLabel: 'Prenda / Calzado',
          serviceTabLabel: 'Arreglo / Envío',
          comboTabLabel: 'Conjunto / Pack',
          productNameFieldLabel: 'Nombre de la Prenda / Calzado *',
          serviceNameFieldLabel: 'Nombre del Arreglo / Envío *',
          barcodeHelperText: 'Opcional (o imprimir etiqueta propia)',
          supplierSkuHint: 'Ej: MOD-401',
          specFieldLabel: 'Talle / Color',
          specFieldHint: 'Ej: Talle XL - Negro / Calz. 40',
          locationFieldLabel: 'Perchero / Depósito',
          locationFieldHint: 'Ej: Perchero B · Caja 4',
          detailsToggleLabel: 'Agregar perchero / talle',
          showDetailsExpandedInForm: true,
          showPackageConversionInForm: false,
          packagePresets: const ['Curva', 'Docena', 'Pack', 'Caja', 'Bolsa'],
          showFractionSwitchInForm: false,
          weightSwitchLabelWide: 'Venta p/peso',
          weightSwitchLabelNarrow: 'Venta p/peso',
          showFractionalExplanationBanner: false,
          showSupplierSkuColumnInCatalog: false,
          showLocationColumnInCatalog: false,
          showSpecColumnInCatalog: true,
          specColumnHeader: 'Talle / Color',
          showUnitColumnInCatalog: false,
          showBalColumnInCatalog: false,
          allowedUnitKeys: const ['un', 'par', 'docena', 'caja'],
          defaultUnitType: 'un',
          defaultSoldByWeight: false,
          quickGridSpecHeader: 'Talle / Color',
          quickGridSpecHint: 'L · Negro / 41',
          quickGridLocationHeader: 'Perchero / Dep.',
          quickGridLocationHint: 'Perchero A',
          quickGridFracHeader: 'Fracc.',
          quickGridFracTooltip: 'Venta fraccionada',
          nativeScaleWeight: false,
          nativeFractionalCut: false,
        );

      case tech:
        return BusinessVerticalProfile(
          primaryType: tech,
          secondaryTypes: normalizedSecondary,
          isRubroScoped: isRubroScoped,
          productTabLabel: 'Producto / Equipo',
          serviceTabLabel: 'Servicio Técnico',
          comboTabLabel: 'Combo / Kit',
          productNameFieldLabel: 'Nombre del Equipo / Repuesto *',
          serviceNameFieldLabel: 'Nombre del Servicio Técnico *',
          barcodeHelperText: 'EAN / Código de fabricante',
          supplierSkuHint: 'Ej: PART-9081',
          specFieldLabel: 'Modelo / Especificación',
          specFieldHint: 'Ej: Módulo Samsung A15 - Kit Wave 110',
          locationFieldLabel: 'Vitrina / Estante',
          locationFieldHint: 'Ej: Vitrina 2 · Estante A',
          detailsToggleLabel: 'Agregar vitrina / modelo',
          showDetailsExpandedInForm: true,
          showPackageConversionInForm: false,
          packagePresets: const ['Caja', 'Pack', 'Blister', 'Bolsa'],
          showFractionSwitchInForm: false,
          weightSwitchLabelWide: 'Permite fraccionar',
          weightSwitchLabelNarrow: 'Permite venta fraccionada',
          showFractionalExplanationBanner: false,
          showSupplierSkuColumnInCatalog: true,
          showLocationColumnInCatalog: false,
          showSpecColumnInCatalog: true,
          specColumnHeader: 'Modelo / Espec.',
          showUnitColumnInCatalog: false,
          showBalColumnInCatalog: false,
          allowedUnitKeys: const ['un', 'mt', 'caja', 'par'],
          defaultUnitType: 'un',
          defaultSoldByWeight: false,
          quickGridSpecHeader: 'Modelo / Espec.',
          quickGridSpecHint: '256GB / OEM',
          quickGridLocationHeader: 'Vitrina / Box',
          quickGridLocationHint: 'Vitrina 1',
          quickGridFracHeader: 'Fracc.',
          quickGridFracTooltip: 'Venta por metro (cables)',
          nativeScaleWeight: false,
          nativeFractionalCut: false,
        );

      case general:
        return BusinessVerticalProfile(
          primaryType: general,
          secondaryTypes: normalizedSecondary,
          isRubroScoped: isRubroScoped,
          productTabLabel: 'Producto / Artículo',
          serviceTabLabel: 'Servicio / Envío',
          comboTabLabel: 'Combo / Promo',
          productNameFieldLabel: 'Nombre del Artículo *',
          serviceNameFieldLabel: 'Nombre del Servicio / Envío *',
          barcodeHelperText: 'Opcional (o generar etiqueta)',
          supplierSkuHint: 'Ej: LIB-204',
          specFieldLabel: 'Variante / Presentación',
          specFieldHint: 'Ej: A4 Rayado · Azul',
          locationFieldLabel: 'Estante / Góndola',
          locationFieldHint: 'Ej: Góndola 2 · Estante 4',
          detailsToggleLabel: 'Agregar estante / variante',
          showDetailsExpandedInForm: false,
          showPackageConversionInForm: true,
          packagePresets: const ['Caja', 'Docena', 'Resma', 'Pack', 'Bolsa'],
          showFractionSwitchInForm: false,
          weightSwitchLabelWide: 'Venta p/peso',
          weightSwitchLabelNarrow: 'Venta p/peso',
          showFractionalExplanationBanner: false,
          showSupplierSkuColumnInCatalog: false,
          showLocationColumnInCatalog: false,
          showSpecColumnInCatalog: false,
          specColumnHeader: 'Variante',
          showUnitColumnInCatalog: false,
          showBalColumnInCatalog: false,
          allowedUnitKeys: const ['un', 'caja', 'docena', 'par', 'bolsa', 'mt'],
          defaultUnitType: 'un',
          defaultSoldByWeight: false,
          quickGridSpecHeader: 'Variante / Pres.',
          quickGridSpecHint: 'A4 / Color / Set',
          quickGridLocationHeader: 'Estante / Góndola',
          quickGridLocationHint: 'Góndola 2',
          quickGridFracHeader: 'Fracc.',
          quickGridFracTooltip: 'Venta fraccionada',
          nativeScaleWeight: false,
          nativeFractionalCut: false,
        );

      case retail:
      default:
        return BusinessVerticalProfile(
          primaryType: retail,
          secondaryTypes: normalizedSecondary,
          isRubroScoped: isRubroScoped,
          productTabLabel: 'Producto Físico',
          serviceTabLabel: 'Servicio / Honorario',
          comboTabLabel: 'Combo / Fracción',
          productNameFieldLabel: 'Nombre del Producto *',
          serviceNameFieldLabel: 'Nombre del Servicio / Honorario *',
          barcodeHelperText: 'Dejar vacío si es pesable',
          supplierSkuHint: 'Ej: DIST-104',
          specFieldLabel: 'Presentación / Medida',
          specFieldHint: 'Ej: 500ml · Mandioca / Cajón',
          locationFieldLabel: 'Góndola / Ubicación',
          locationFieldHint: 'Ej: Góndola 3',
          detailsToggleLabel: 'Agregar góndola / presentación',
          showDetailsExpandedInForm: false,
          showPackageConversionInForm: true,
          packagePresets: const ['Pack', 'Caja', 'Cajón', 'Maple', 'Bolsa', 'Horma'],
          showFractionSwitchInForm: true,
          weightSwitchLabelWide: 'Venta p/peso',
          weightSwitchLabelNarrow: 'Venta p/peso (balanza)',
          showFractionalExplanationBanner: false,
          showSupplierSkuColumnInCatalog: false,
          showLocationColumnInCatalog: false,
          showSpecColumnInCatalog: false,
          specColumnHeader: 'Presentación',
          showUnitColumnInCatalog: false,
          showBalColumnInCatalog: true,
          allowedUnitKeys: const ['un', 'kg', 'g', 'lt', 'caja', 'bolsa', 'docena'],
          defaultUnitType: 'un',
          defaultSoldByWeight: false,
          quickGridSpecHeader: 'Pres. / Med.',
          quickGridSpecHint: '500ml / Pack x6',
          quickGridLocationHeader: 'Ubicación',
          quickGridLocationHint: 'Góndola / Helad.',
          quickGridFracHeader: 'Bal.',
          quickGridFracTooltip:
              'Venta por peso en balanza (permite decimales, ej: 0.5 kg)',
          nativeScaleWeight: true,
          nativeFractionalCut: false,
        );
    }
  }

  /// Adapta la ficha o grilla al [Rubro] específico de la categoría seleccionada,
  /// aislando estrictamente sus capacidades frente al resto de rubros en Polirrubro.
  BusinessVerticalProfile forCategoryRubro(Rubro? rubro) {
    if (rubro == null) return this;

    final explicit = rubro.verticalType?.trim().toLowerCase();
    if (explicit != null && allVerticalCodes.contains(explicit)) {
      return BusinessVerticalProfile.fromType(
        explicit,
        secondaryTypes: const [],
        isRubroScoped: true,
      );
    }

    final inferred = inferVerticalCodeFromRubroName(rubro.name);
    if (inferred != null) {
      return BusinessVerticalProfile.fromType(
        inferred,
        secondaryTypes: const [],
        isRubroScoped: true,
      );
    }
    return this;
  }

  static String? inferVerticalCodeFromRubroName(String rawName) {
    final name = rawName.trim().toLowerCase();
    if (name.isEmpty) return null;

    if (name.contains('carnic') ||
        name.contains('poller') ||
        name.contains('verdul') ||
        name.contains('fiambr') ||
        name.contains('pescad') ||
        name.contains('frut')) {
      return butcher;
    }
    if (name.contains('ropa') ||
        name.contains('indument') ||
        name.contains('calzad') ||
        name.contains('zapat') ||
        name.contains('lencer') ||
        name.contains('textil') ||
        name.contains('boutique')) {
      return apparel;
    }
    if (name.contains('ferret') ||
        name.contains('mader') ||
        name.contains('pintur') ||
        name.contains('corral') ||
        name.contains('sanitar') ||
        name.contains('electric') ||
        name.contains('construc') ||
        name.contains('buloner') ||
        name.contains('herramient')) {
      return hardwareStore;
    }
    if (name.contains('celular') ||
        name.contains('tecnolog') ||
        name.contains('comput') ||
        name.contains('electro') ||
        name.contains('repuest') ||
        name.contains('moto') ||
        name.contains('accesori') ||
        name.contains('taller')) {
      return tech;
    }
    if (name.contains('bazar') ||
        name.contains('librer') ||
        name.contains('jugueter') ||
        name.contains('regaler') ||
        name.contains('cotill') ||
        name.contains('forraj') ||
        name.contains('escolar')) {
      return general;
    }
    if (name.contains('kiosc') ||
        name.contains('almac') ||
        name.contains('bebid') ||
        name.contains('golosin') ||
        name.contains('supermerc') ||
        name.contains('pastel') ||
        name.contains('panad') ||
        name.contains('confiter') ||
        name.contains('gastron') ||
        name.contains('cocin') ||
        name.contains('rotiser') ||
        name.contains('lacteo') ||
        name.contains('limpiez') ||
        name.contains('perfum') ||
        name.contains('farmac') ||
        name.contains('dietet')) {
      return retail;
    }
    return null;
  }
}
