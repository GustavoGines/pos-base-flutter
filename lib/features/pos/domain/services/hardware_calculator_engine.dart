import 'dart:convert';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';

/// Tipos de pestaña de la Calculadora Ferretera V1.
enum HardwareCalcTab {
  wood,  // 🪵 Machimbre / Maderas / Deck
  roof,  // 🏠 Chapas / Techos
  paint, // 🎨 Pintura / Membrana Líquida
}

/// Modalidades de precio de catálogo para Machimbre / Maderas.
enum WoodPricingMode {
  perBoard,       // Precio cargado por Tabla individual
  perM2,          // Precio cargado por m²
  perLinearMeter, // Precio cargado por Metro Lineal (ml)
  perPack,        // Precio cargado por Paquete
}

/// Criterio de facturación cuando el precio del catálogo está por m²:
/// - [nominal]: cobra los m² nominales de las tablas entregadas (Estándar Maderera, no pierde el macho/encastre).
/// - [useful]: cobra únicamente los m² útiles cubiertos por las tablas.
enum M2BillingBasis {
  nominal,
  useful,
}

/// Modalidades de precio de catálogo para Chapas / Techos.
enum RoofPricingMode {
  perSheet,       // Precio por Chapa individual
  perLinearMeter, // Precio por Metro Lineal
  perM2,          // Precio por m² (ancho total x largo)
}

/// Modo de rendimiento en Pintura / Membrana:
/// - [perCoat]: el rendimiento cargado es por mano -> Litros = (Superficie * Manos) / Rendimiento.
/// - [finalTotal]: el rendimiento cargado ya es trabajo terminado (todas las manos incluidas, típico en Membrana Líquida) -> Litros = Superficie / Rendimiento.
enum PaintYieldMode {
  perCoat,
  finalTotal,
}

class ComplementSuggestion {
  final String title;
  final String quantityLabel;
  final String searchKeyword;
  final String detailHint;

  const ComplementSuggestion({
    required this.title,
    required this.quantityLabel,
    required this.searchKeyword,
    required this.detailHint,
  });
}

class WoodCalculationResult {
  final bool isValid;
  final String? errorMessage;
  final double requestedAreaM2;
  final double areaWithWasteM2;
  final double wastePercent;
  final int boardsNeeded;
  final int packsNeeded;
  final int looseBoardsRemainder;
  final int totalBoardsDelivered;
  final double totalLinearMeters;
  final double usefulAreaCoveredM2;
  final double nominalAreaDeliveredM2;
  final double billingQuantity;
  final String billingUnitLabel;
  final String customDetailsNote;
  final List<ComplementSuggestion> complements;

  const WoodCalculationResult({
    required this.isValid,
    this.errorMessage,
    this.requestedAreaM2 = 0,
    this.areaWithWasteM2 = 0,
    this.wastePercent = 0,
    this.boardsNeeded = 0,
    this.packsNeeded = 0,
    this.looseBoardsRemainder = 0,
    this.totalBoardsDelivered = 0,
    this.totalLinearMeters = 0,
    this.usefulAreaCoveredM2 = 0,
    this.nominalAreaDeliveredM2 = 0,
    this.billingQuantity = 0,
    this.billingUnitLabel = 'tablas',
    this.customDetailsNote = '',
    this.complements = const [],
  });
}

class RoofCalculationResult {
  final bool isValid;
  final String? errorMessage;
  final bool isAreaEstimate;
  final double wastePercent;
  final double roofWidthM;
  final double roofSlopeLengthM;
  final double roofAreaM2;
  final double usefulAreaCoveredM2;
  final int columnsAcrossWidth;
  final int rowsAlongSlope;
  final double coveredSlopeLengthM;
  final double surplusPerColumnM;
  final int totalSheetsNeeded;
  final double totalLinearMeters;
  final double totalNominalM2;
  final double billingQuantity;
  final String billingUnitLabel;
  final String customDetailsNote;
  final List<ComplementSuggestion> complements;

  const RoofCalculationResult({
    required this.isValid,
    this.errorMessage,
    this.isAreaEstimate = false,
    this.wastePercent = 0,
    this.roofWidthM = 0,
    this.roofSlopeLengthM = 0,
    this.roofAreaM2 = 0,
    this.usefulAreaCoveredM2 = 0,
    this.columnsAcrossWidth = 0,
    this.rowsAlongSlope = 0,
    this.coveredSlopeLengthM = 0,
    this.surplusPerColumnM = 0,
    this.totalSheetsNeeded = 0,
    this.totalLinearMeters = 0,
    this.totalNominalM2 = 0,
    this.billingQuantity = 0,
    this.billingUnitLabel = 'chapas',
    this.customDetailsNote = '',
    this.complements = const [],
  });
}

class PaintCalculationResult {
  final bool isValid;
  final String? errorMessage;
  final double surfaceAreaM2;
  final int coats;
  final PaintYieldMode yieldMode;
  final double yieldM2PerLiter;
  final double containerLiters;
  final double totalLitersNeeded;
  final int containersNeeded;
  final double totalLitersDelivered;
  final double billingQuantity;
  final String billingUnitLabel;
  final String customDetailsNote;
  final List<ComplementSuggestion> complements;

  const PaintCalculationResult({
    required this.isValid,
    this.errorMessage,
    this.surfaceAreaM2 = 0,
    this.coats = 2,
    this.yieldMode = PaintYieldMode.perCoat,
    this.yieldM2PerLiter = 10,
    this.containerLiters = 4,
    this.totalLitersNeeded = 0,
    this.containersNeeded = 0,
    this.totalLitersDelivered = 0,
    this.billingQuantity = 0,
    this.billingUnitLabel = 'envases',
    this.customDetailsNote = '',
    this.complements = const [],
  });
}

/// Resultado del auto-detector inteligente de medidas F7.
class HardwareAutoDetectResult {
  final Map<String, dynamic> config;
  final bool missingWidthWarning;
  final String? detectedThicknessLabel;
  final bool detectedLength;

  const HardwareAutoDetectResult({
    required this.config,
    this.missingWidthWarning = false,
    this.detectedThicknessLabel,
    this.detectedLength = false,
  });
}

/// Preset técnico de pulgada para Machimbre / Tablas.
class WoodInchPreset {
  final String key;
  final String label;
  final double nominalWidthM;
  final double usefulWidthM;

  const WoodInchPreset({
    required this.key,
    required this.label,
    required this.nominalWidthM,
    required this.usefulWidthM,
  });
}

class HardwareCalculatorEngine {
  static const String _prefsKeyPrefix = 'hw_calc_config_v1_';

  /// Presets estándar de aserradero / ferretería para Maderas, Machimbre y Tirantes.
  static const List<WoodInchPreset> woodInchPresets = [
    WoodInchPreset(
      key: '1',
      label: '1" (Nom: 2.54 cm · Útil: 2.2 cm)',
      nominalWidthM: 0.0254,
      usefulWidthM: 0.022,
    ),
    WoodInchPreset(
      key: '2',
      label: '2" (Nom: 5.08 cm · Útil: 4.5 cm)',
      nominalWidthM: 0.0508,
      usefulWidthM: 0.045,
    ),
    WoodInchPreset(
      key: '3',
      label: '3" (Nom: 7.6 cm · Útil: 6.5 cm)',
      nominalWidthM: 0.0762,
      usefulWidthM: 0.065,
    ),
    WoodInchPreset(
      key: '4',
      label: '4" (Nom: 10.16 cm · Útil: 8.8 cm)',
      nominalWidthM: 0.1016,
      usefulWidthM: 0.088,
    ),
    WoodInchPreset(
      key: '5',
      label: '5" (Nom: 12.7 cm · Útil: 11.2 cm)',
      nominalWidthM: 0.127,
      usefulWidthM: 0.112,
    ),
    WoodInchPreset(
      key: '6',
      label: '6" (Nom: 15.24 cm · Útil: 13.7 cm)',
      nominalWidthM: 0.1524,
      usefulWidthM: 0.137,
    ),
    WoodInchPreset(
      key: '8',
      label: '8" (Nom: 20.32 cm · Útil: 18.8 cm)',
      nominalWidthM: 0.2032,
      usefulWidthM: 0.188,
    ),
    WoodInchPreset(
      key: '10',
      label: '10" (Nom: 25.4 cm · Útil: 23.8 cm)',
      nominalWidthM: 0.254,
      usefulWidthM: 0.238,
    ),
    WoodInchPreset(
      key: '12',
      label: '12" (Nom: 30.48 cm · Útil: 28.8 cm)',
      nominalWidthM: 0.3048,
      usefulWidthM: 0.288,
    ),
  ];

  // ── 1. GESTIÓN DE CACHÉ OFFLINE CON PRECEDENCIA DEL SERVIDOR ──────────────

  /// Versión extendida de [resolveConfigForProduct] que también informa si falta
  /// el ancho de la madera cuando el ítem aún no tiene `calcConfig` ni caché local.
  static Future<HardwareAutoDetectResult> resolveAutoDetectForProduct(
    Product product, {
    SharedPreferences? prefs,
  }) async {
    final sp = prefs ?? await SharedPreferences.getInstance();
    final cacheKey = '$_prefsKeyPrefix${product.id}';

    if (product.calcConfig != null && product.calcConfig!.isNotEmpty) {
      final serverConfig = Map<String, dynamic>.from(product.calcConfig!);
      if (product.id > 0) {
        await sp.setString(cacheKey, jsonEncode(serverConfig));
      }
      return HardwareAutoDetectResult(
        config: serverConfig,
        missingWidthWarning: false,
      );
    }

    if (product.id > 0) {
      final cachedRaw = sp.getString(cacheKey);
      if (cachedRaw != null && cachedRaw.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(cachedRaw);
          if (decoded is Map && decoded.isNotEmpty) {
            return HardwareAutoDetectResult(
              config: Map<String, dynamic>.from(decoded),
              missingWidthWarning: false,
            );
          }
        } catch (_) {}
      }
    }

    return analyzeProductText(
      name: product.name,
      technicalSpec: product.technicalSpec,
    );
  }

  /// Resuelve la configuración técnica para un producto respetando la regla:
  /// 1° Si el producto trae `calcConfig` desde el servidor, TIENE PRECEDENCIA y actualiza la caché local.
  /// 2° Si no tiene `calcConfig` en servidor pero hay una guardada en `SharedPreferences` local (modo offline), usa esa.
  /// 3° Si no existe ninguna, auto-detecta medidas inteligentemente desde el nombre del producto.
  static Future<Map<String, dynamic>> resolveConfigForProduct(
    Product product, {
    SharedPreferences? prefs,
  }) async {
    final result = await resolveAutoDetectForProduct(product, prefs: prefs);
    return result.config;
  }

  /// Guarda la configuración en la caché local inmediatamente (0 ms, offline-ready).
  static Future<void> saveLocalCacheForProduct(
    int productId,
    Map<String, dynamic> config, {
    SharedPreferences? prefs,
  }) async {
    if (productId <= 0) return;
    final sp = prefs ?? await SharedPreferences.getInstance();
    await sp.setString('$_prefsKeyPrefix$productId', jsonEncode(config));
  }

  /// Elimina la configuración guardada en caché local cuando se desactiva la calculadora F7.
  static Future<void> clearLocalCacheForProduct(
    int productId, {
    SharedPreferences? prefs,
  }) async {
    if (productId <= 0) return;
    final sp = prefs ?? await SharedPreferences.getInstance();
    await sp.remove('$_prefsKeyPrefix$productId');
  }

  // ── 2. AUTO-DETECTOR INTELIGENTE POR NOMBRE DE CATÁLOGO ───────────────────

  static bool _looksLikeHardwareCalcSubject(String lowerText) {
    const keywords = [
      'pintura',
      'latex',
      'látex',
      'sintetico',
      'sintético',
      'esmalte',
      'membrana',
      'impermeabilizante',
      'barniz',
      'impregnante',
      'chapa',
      'acanalada',
      'trapezoidal',
      'techo',
      'zingueria',
      'policarbonato',
      'machimbre',
      'deck',
      'tirante',
      'alfajia',
      'alfajía',
      'tabla',
      'tablon',
      'tablón',
      'madera',
      'liston',
      'listón',
      'viga',
    ];
    return keywords.any(lowerText.contains);
  }

  /// Analiza solo si el texto corresponde explícitamente a un ítem calculable
  /// (Maderas, Chapas, Pintura). Devuelve `null` para tornillos/bulones/etc.
  static Map<String, dynamic>? tryInferExplicitConfig({
    required String name,
    String? technicalSpec,
  }) {
    final combined = [
      name.trim(),
      if (technicalSpec != null && technicalSpec.trim().isNotEmpty)
        technicalSpec.trim(),
    ].join(' ').trim().toLowerCase();
    if (combined.isEmpty || !_looksLikeHardwareCalcSubject(combined)) {
      return null;
    }
    final result = analyzeProductText(name: name, technicalSpec: technicalSpec);
    if (result.missingWidthWarning) {
      return null;
    }
    return result.config;
  }

  /// Analiza el nombre del producto (y opcionalmente su `technicalSpec`, ej: `1" / 4m`
  /// o `1" x 6" x 4m`) para auto-detectar pestaña F7, ancho nominal, largo y avisos
  /// cuando falta el ancho de la tabla.
  static HardwareAutoDetectResult analyzeProductText({
    required String name,
    String? technicalSpec,
  }) {
    final combined = [
      name.trim(),
      if (technicalSpec != null && technicalSpec.trim().isNotEmpty)
        technicalSpec.trim(),
    ].join(' ').trim();
    final text = combined.toLowerCase();

    // Detectar qué pestaña corresponde: 1. Pintura / Membrana
    if (text.contains('pintura') ||
        text.contains('latex') ||
        text.contains('látex') ||
        text.contains('sintetico') ||
        text.contains('sintético') ||
        text.contains('esmalte') ||
        text.contains('membrana') ||
        text.contains('impermeabilizante') ||
        text.contains('barniz') ||
        text.contains('impregnante')) {
      final isMembrane = text.contains('membrana') ||
          text.contains('impermeabilizante') ||
          text.contains('fibrado');

      double containerLiters = 4.0;
      final capMatch = RegExp(
        r'(\d+(?:[.,]\d+)?)\s*(?:lt?s?|litros?|kg|kilos?)\b',
        caseSensitive: false,
      ).firstMatch(text);
      if (capMatch != null) {
        final parsed =
            double.tryParse(capMatch.group(1)!.replaceAll(',', '.'));
        if (parsed != null && parsed > 0) {
          containerLiters = parsed;
        }
      } else if (isMembrane) {
        containerLiters = 20.0;
      }

      return HardwareAutoDetectResult(
        config: {
          'type': 'paint',
          'yield_m2_per_liter': isMembrane ? 1.0 : 10.0,
          'yield_mode': isMembrane ? 'final_total' : 'per_coat',
          'container_liters': containerLiters,
          'default_coats': isMembrane ? 3 : 2,
        },
        detectedLength: capMatch != null,
      );
    }

    final looksLikeWood = text.contains('machimbre') ||
        text.contains('deck') ||
        text.contains('tirante') ||
        text.contains('alfajia') ||
        text.contains('alfajía') ||
        text.contains('tabla') ||
        text.contains('tablon') ||
        text.contains('tablón') ||
        text.contains('madera') ||
        text.contains('liston') ||
        text.contains('listón') ||
        text.contains('viga');

    final meterRegex = RegExp(
      r'(\d+(?:[.,]\d+)?)\s*(?:m|mts|metros?)\b(?!\s*[²³23]|l\b)',
      caseSensitive: false,
    );

    // 2. Chapas / Techos
    if (!looksLikeWood &&
        (text.contains('chapa') ||
            text.contains('acanalada') ||
            text.contains('trapezoidal') ||
            text.contains('techo') ||
            text.contains('zingueria') ||
            text.contains('policarbonato'))) {
      double nominalWidthM = 1.10;
      double usefulWidthM = 1.00;
      double lengthM = 3.0;
      bool detectedLen = false;

      final pairMatch = RegExp(
        r'(\d+(?:[.,]\d+)?)\s*m?\s*[x×]\s*(\d+(?:[.,]\d+)?)\s*(?:m|mts|metros?)\b(?!\s*[²³23]|l\b)',
        caseSensitive: false,
      ).firstMatch(text);
      if (pairMatch != null) {
        final w = double.tryParse(pairMatch.group(1)!.replaceAll(',', '.'));
        final l = double.tryParse(pairMatch.group(2)!.replaceAll(',', '.'));
        if (w != null && w >= 0.40 && w <= 3.0) {
          nominalWidthM = w;
          usefulWidthM = math.max(0.30, _round3(w - 0.10));
        }
        if (l != null && l >= 1.0 && l <= 16.0) {
          lengthM = l;
          detectedLen = true;
        }
      }

      if (!detectedLen) {
        for (final m in meterRegex.allMatches(text)) {
          final parsed = double.tryParse(m.group(1)!.replaceAll(',', '.'));
          if (parsed != null && parsed >= 1.0 && parsed <= 16.0) {
            lengthM = parsed;
            detectedLen = true;
            break;
          }
        }
      }

      final isPerLinearMeter = text.contains('x metro') ||
          text.contains('por metro') ||
          text.contains('(ml)') ||
          text.contains('/ml');

      return HardwareAutoDetectResult(
        config: {
          'type': 'roof',
          'nominal_width_m': nominalWidthM,
          'useful_width_m': usefulWidthM,
          'length_m': lengthM,
          'longitudinal_overlap_m': 0.20,
          'pricing_mode': isPerLinearMeter ? 'per_linear_meter' : 'per_sheet',
        },
        detectedLength: detectedLen,
      );
    }

    // 3. Madera / Machimbre / Tirante / Deck
    double lengthM = 3.00;
    bool detectedLength = false;
    for (final m in meterRegex.allMatches(text)) {
      final val = double.tryParse(m.group(1)!.replaceAll(',', '.'));
      if (val != null && val >= 0.80 && val <= 16.0) {
        lengthM = val;
        detectedLength = true;
        break;
      }
    }

    final textWithoutMeters = text.replaceAll(meterRegex, ' ');

    String inchPreset = '4';
    double nominalW = 0.1016;
    double usefulW = 0.088;
    bool resolvedWidth = false;
    String? detectedThicknessLabel;

    WoodInchPreset? findWoodPreset(String rawKey) {
      return woodInchPresets.where((p) => p.key == rawKey).firstOrNull;
    }

    void applyPresetOrCustomInch(double inchVal) {
      final keyStr = _fmtNum(inchVal, decimals: 2);
      final preset = findWoodPreset(keyStr);
      if (preset != null) {
        inchPreset = preset.key;
        nominalW = preset.nominalWidthM;
        usefulW = preset.usefulWidthM;
        resolvedWidth = true;
      } else if (inchVal > 0 && inchVal <= 36) {
        inchPreset = 'custom';
        nominalW = _round3(inchVal * 0.0254);
        usefulW = math.max(0.005, _round3(nominalW - 0.012));
        resolvedWidth = true;
      }
    }

    // Paso A: Buscar par explícito "Espesor x Ancho" (ej: 1" x 6", 1 1/2" x 6", 1/2 x 4, 1" / 6", 2" x 2")
    final twoDimMatch = RegExp(
      r'(\d+(?:\s+\d+\s*/\s*\d+|\s*/\s*\d+|[.,]\d+)?)\s*(?:(?:"|pulg(?:adas?)?)\s*[x×/]|[x×])\s*(\d+(?:[.,]\d+)?)\s*(?:"|pulg(?:adas?)?)?(?![.,\d/\w])',
      caseSensitive: false,
    ).firstMatch(textWithoutMeters);

    if (twoDimMatch != null) {
      final rawThickness = twoDimMatch
          .group(1)!
          .replaceAll(',', '.')
          .replaceAll(RegExp(r'\s*/\s*'), '/')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      detectedThicknessLabel = '$rawThickness"';
      final widthVal = double.tryParse(
        twoDimMatch.group(2)!.replaceAll(',', '.'),
      );
      if (widthVal != null) {
        applyPresetOrCustomInch(widthVal);
      }
    }

    // Paso B: Si no hubo par Espesor x Ancho, buscar ancho explícito o espesor solitario
    if (!resolvedWidth) {
      final textWithoutFractions = textWithoutMeters.replaceAll(
        RegExp(r'\b\d+\s*/\s*\d+\s*"?'),
        ' ',
      );

      final afterXMatch = RegExp(
        r'(?:^|[\s,"])(?:x|de)\s*(10|12|[1234568])(?:\s*(?:"|pulg(?:adas?)?))?(?![.,\d/\w])',
        caseSensitive: false,
      ).firstMatch(textWithoutFractions);
      final afterXRaw = afterXMatch?.group(1);
      final afterXVal =
          afterXRaw != null ? double.tryParse(afterXRaw) : null;

      // Si dice "x 4" o "de 6" (>= 3") es un ancho claro. Si dice "de 1\"", en madera suele ser espesor.
      final isExplicitSmallWidthAfterX = afterXMatch != null &&
          afterXMatch.group(0)!.toLowerCase().contains('x') &&
          afterXVal != null;
      if (isExplicitSmallWidthAfterX ||
          (afterXVal != null && afterXVal >= 3.0)) {
        applyPresetOrCustomInch(afterXVal);
      } else {
        final standaloneInchMatch = RegExp(
          r'(?<![\d.,/])(\d+(?:[.,]\d+)?)\s*(?:"|pulg(?:adas?)?)',
          caseSensitive: false,
        ).firstMatch(textWithoutFractions);
        final standaloneVal = standaloneInchMatch != null
            ? double.tryParse(
                standaloneInchMatch.group(1)!.replaceAll(',', '.'),
              )
            : null;

        if (standaloneVal != null && standaloneVal >= 3.0) {
          applyPresetOrCustomInch(standaloneVal);
        } else if (standaloneVal != null && standaloneVal > 0) {
          // Medida chica solitaria (ej. 1" / 4m o 2" 4m) -> se interpreta como grosor/espesor
          detectedThicknessLabel ??= '${_fmtNum(standaloneVal, decimals: 2)}"';
        } else {
          final fracMatch = RegExp(r'\b(\d+\s*/\s*\d+)\s*"?')
              .firstMatch(textWithoutMeters);
          if (fracMatch != null) {
            detectedThicknessLabel ??=
                '${fracMatch.group(1)!.replaceAll(RegExp(r'\s+'), '')}"';
          }
        }
      }
    }

    String pricingMode = 'per_board';
    if (text.contains('m2') || text.contains('m²')) {
      pricingMode = 'per_m2';
    } else if (text.contains('paq') || text.contains('paquete')) {
      pricingMode = 'per_pack';
    } else if (text.contains('lineal') ||
        text.contains('/ml') ||
        text.contains('x ml')) {
      pricingMode = 'per_linear_meter';
    }

    return HardwareAutoDetectResult(
      config: {
        'type': 'wood',
        'inch_preset': inchPreset,
        'nominal_width_m': nominalW,
        'useful_width_m': usefulW,
        'length_m': lengthM,
        'pricing_mode': pricingMode,
        'm2_billing_basis': 'nominal',
        'boards_per_pack': 10,
        'round_to_full_pack': false,
        'default_waste_pct': 10.0,
      },
      missingWidthWarning: !resolvedWidth,
      detectedThicknessLabel: detectedThicknessLabel,
      detectedLength: detectedLength,
    );
  }

  /// Analiza el nombre de un producto (ej. "Machimbre Pino 1/2 x 4 x 3.00m",
  /// "Chapa Acanalada C27 1.10 x 4.50m", "Membrana Líquida 20Kg", "Látex Interior 4L")
  /// y sugiere la pestaña y parámetros iniciales.
  static Map<String, dynamic> inferConfigFromName(String rawName) {
    return analyzeProductText(name: rawName).config;
  }

  // ── 3. MOTOR DE CÁLCULO: MACHIMBRE / MADERAS ──────────────────────────────

  static WoodCalculationResult calculateWood({
    required double targetAreaM2,
    required double nominalWidthM,
    required double usefulWidthM,
    required double boardLengthM,
    double wastePercent = 0.0,
    WoodPricingMode pricingMode = WoodPricingMode.perBoard,
    M2BillingBasis m2BillingBasis = M2BillingBasis.nominal,
    int boardsPerPack = 10,
    bool roundToFullPack = false,
    String? inchLabel,
  }) {
    if (!targetAreaM2.isFinite ||
        !nominalWidthM.isFinite ||
        !usefulWidthM.isFinite ||
        !boardLengthM.isFinite ||
        !wastePercent.isFinite) {
      return const WoodCalculationResult(
        isValid: false,
        errorMessage: 'Ingresá valores numéricos válidos.',
      );
    }
    if (targetAreaM2 <= 0) {
      return const WoodCalculationResult(
        isValid: false,
        errorMessage: 'Ingresá las medidas o los m² a cubrir.',
      );
    }
    if (usefulWidthM <= 0 || nominalWidthM <= 0) {
      return const WoodCalculationResult(
        isValid: false,
        errorMessage: 'El ancho útil y nominal deben ser mayores a 0.',
      );
    }
    if (boardLengthM <= 0) {
      return const WoodCalculationResult(
        isValid: false,
        errorMessage: 'El largo de la tabla debe ser mayor a 0.',
      );
    }
    if (targetAreaM2 > 1000000 ||
        boardLengthM > 100 ||
        nominalWidthM > 50 ||
        usefulWidthM > 50) {
      return const WoodCalculationResult(
        isValid: false,
        errorMessage: 'Las medidas ingresadas superan el rango máximo permitido.',
      );
    }
    if (usefulWidthM > nominalWidthM + 1e-6) {
      return const WoodCalculationResult(
        isValid: false,
        errorMessage: 'El ancho útil no puede ser mayor al ancho nominal.',
      );
    }
    if (pricingMode == WoodPricingMode.perPack &&
        (boardsPerPack < 1 || boardsPerPack > 500)) {
      return const WoodCalculationResult(
        isValid: false,
        errorMessage: 'Las tablas por paquete deben estar entre 1 y 500.',
      );
    }

    final safeWaste = wastePercent.clamp(0.0, 100.0);
    final areaWithWaste = targetAreaM2 * (1.0 + (safeWaste / 100.0));
    final usefulAreaPerBoard = boardLengthM * usefulWidthM;
    final nominalAreaPerBoard = boardLengthM * nominalWidthM;

    if (!usefulAreaPerBoard.isFinite || usefulAreaPerBoard <= 0) {
      return const WoodCalculationResult(
        isValid: false,
        errorMessage: 'El área cubierta por tabla es inválida.',
      );
    }

    final rawBoardsNeeded = (areaWithWaste - 1e-9) / usefulAreaPerBoard;
    if (!rawBoardsNeeded.isFinite || rawBoardsNeeded > 10000000) {
      return const WoodCalculationResult(
        isValid: false,
        errorMessage: 'La cantidad calculada supera el límite permitido.',
      );
    }
    final boardsNeeded = math.max(1, rawBoardsNeeded.ceil());

    final safePackSize = math.max(1, boardsPerPack);
    final int packsNeeded;
    final int looseRemainder;
    final int totalBoardsDelivered;

    if (pricingMode == WoodPricingMode.perPack && roundToFullPack) {
      packsNeeded = (boardsNeeded / safePackSize).ceil();
      looseRemainder = 0;
      totalBoardsDelivered = packsNeeded * safePackSize;
    } else {
      packsNeeded = boardsNeeded ~/ safePackSize;
      looseRemainder = boardsNeeded % safePackSize;
      totalBoardsDelivered = boardsNeeded;
    }

    final totalLinearMeters =
        _round3(totalBoardsDelivered * boardLengthM);
    final usefulAreaCoveredM2 =
        _round3(totalBoardsDelivered * usefulAreaPerBoard);
    final nominalAreaDeliveredM2 =
        _round3(totalBoardsDelivered * nominalAreaPerBoard);

    late final double billingQty;
    late final String billingUnit;

    switch (pricingMode) {
      case WoodPricingMode.perBoard:
        billingQty = totalBoardsDelivered.toDouble();
        billingUnit = totalBoardsDelivered == 1 ? 'tabla' : 'tablas';
        break;
      case WoodPricingMode.perPack:
        if (roundToFullPack) {
          billingQty = packsNeeded.toDouble();
        } else {
          billingQty = _round3(totalBoardsDelivered / safePackSize);
        }
        billingUnit = billingQty == 1 ? 'paquete' : 'paquetes';
        break;
      case WoodPricingMode.perLinearMeter:
        billingQty = totalLinearMeters;
        billingUnit = 'ml';
        break;
      case WoodPricingMode.perM2:
        billingQty = m2BillingBasis == M2BillingBasis.nominal
            ? nominalAreaDeliveredM2
            : usefulAreaCoveredM2;
        billingUnit = m2BillingBasis == M2BillingBasis.nominal
            ? 'm² nom.'
            : 'm² útiles';
        break;
    }

    // Construir nota clara con símbolos ASCII seguros para PDF (Type1) e impresora térmica (ESC/POS)
    final lenStr = _fmtNum(boardLengthM, decimals: 2);
    final areaStr = _fmtNum(targetAreaM2, decimals: 2);
    final usefulCovStr = _fmtNum(usefulAreaCoveredM2, decimals: 2);
    final inchText = (inchLabel != null && inchLabel.isNotEmpty) ? ' $inchLabel"' : '';
    final wasteText = safeWaste > 0 ? ' - +${_fmtNum(safeWaste, decimals: 0)}% desp.' : '';
    final packText = (pricingMode == WoodPricingMode.perPack)
        ? ' ($packsNeeded paq.${looseRemainder > 0 ? " + $looseRemainder sueltas" : ""})'
        : '';
    final m2BillingUnitNote =
        m2BillingBasis == M2BillingBasis.nominal ? 'm2 nom.' : 'm2 útiles';
    final m2BillingText = (pricingMode == WoodPricingMode.perM2)
        ? ' - Facturado: ${_fmtNum(billingQty, decimals: 2)} $m2BillingUnitNote'
        : '';

    final note =
        'Cálculo:$inchText $totalBoardsDelivered tablas de ${lenStr}m$packText '
        '(p/ $areaStr m2 -> cubre $usefulCovStr m2 útiles - ${_fmtNum(totalLinearMeters, decimals: 1)} ml$m2BillingText$wasteText)';

    // Complementos orientativos:
    // 1. Alfajías / Tirantes (clavaderas cada 0.50m -> ~2.1 ml por m² de superficie)
    final battenMeters = (usefulAreaCoveredM2 * 2.1).ceil();
    // 2. Clavos / Grampas (~2 fijaciones cada 0.50m por tabla)
    final supportsPerBoard = (boardLengthM / 0.50).ceil() + 1;
    final nailsCount = totalBoardsDelivered * supportsPerBoard * 2;

    final complements = <ComplementSuggestion>[
      ComplementSuggestion(
        title: 'Tirantes / Alfajías (clavaderas c/ 50cm)',
        quantityLabel: '~$battenMeters ml',
        searchKeyword: 'Tirante',
        detailHint: 'Aprox. $battenMeters metros lineales de clavaderas',
      ),
      ComplementSuggestion(
        title: 'Clavos / Grampas p/ Machimbre',
        quantityLabel: '~$nailsCount u.',
        searchKeyword: 'Clavo',
        detailHint: 'Aprox. $nailsCount fijaciones (2 por apoyo)',
      ),
    ];

    return WoodCalculationResult(
      isValid: true,
      requestedAreaM2: targetAreaM2,
      areaWithWasteM2: areaWithWaste,
      wastePercent: safeWaste,
      boardsNeeded: boardsNeeded,
      packsNeeded: packsNeeded,
      looseBoardsRemainder: looseRemainder,
      totalBoardsDelivered: totalBoardsDelivered,
      totalLinearMeters: totalLinearMeters,
      usefulAreaCoveredM2: usefulAreaCoveredM2,
      nominalAreaDeliveredM2: nominalAreaDeliveredM2,
      billingQuantity: billingQty,
      billingUnitLabel: billingUnit,
      customDetailsNote: note,
      complements: complements,
    );
  }

  // ── 4. MOTOR DE CÁLCULO: CHAPAS / TECHOS ──────────────────────────────────

  static RoofCalculationResult calculateRoof({
    required double roofWidthM,
    required double roofSlopeLengthM,
    required double sheetNominalWidthM,
    required double sheetUsefulWidthM,
    required double sheetLengthM,
    double longitudinalOverlapM = 0.20,
    RoofPricingMode pricingMode = RoofPricingMode.perSheet,
  }) {
    if (!roofWidthM.isFinite ||
        !roofSlopeLengthM.isFinite ||
        !sheetNominalWidthM.isFinite ||
        !sheetUsefulWidthM.isFinite ||
        !sheetLengthM.isFinite ||
        !longitudinalOverlapM.isFinite) {
      return const RoofCalculationResult(
        isValid: false,
        errorMessage: 'Ingresá valores numéricos válidos.',
      );
    }
    if (roofWidthM <= 0 || roofSlopeLengthM <= 0) {
      return const RoofCalculationResult(
        isValid: false,
        errorMessage: 'Ingresá el ancho del techo y el largo de la caída.',
      );
    }
    if (sheetUsefulWidthM <= 0 || sheetNominalWidthM <= 0) {
      return const RoofCalculationResult(
        isValid: false,
        errorMessage: 'El ancho útil y total de la chapa deben ser mayores a 0.',
      );
    }
    if (sheetLengthM <= 0) {
      return const RoofCalculationResult(
        isValid: false,
        errorMessage: 'El largo de la chapa debe ser mayor a 0.',
      );
    }
    if (roofWidthM > 10000 ||
        roofSlopeLengthM > 10000 ||
        sheetLengthM > 50 ||
        sheetNominalWidthM > 50 ||
        sheetUsefulWidthM > 50) {
      return const RoofCalculationResult(
        isValid: false,
        errorMessage: 'Las medidas ingresadas superan el rango máximo permitido.',
      );
    }
    if (sheetUsefulWidthM > sheetNominalWidthM + 1e-6) {
      return const RoofCalculationResult(
        isValid: false,
        errorMessage: 'El ancho útil de la chapa no puede superar al ancho total.',
      );
    }

    final safeOverlap = math.max(0.0, longitudinalOverlapM);

    // Validación crítica cuando la caída supera el largo de 1 chapa y requiere empalme longitudinal:
    if (roofSlopeLengthM > sheetLengthM + 1e-6 &&
        sheetLengthM <= safeOverlap + 0.05) {
      return const RoofCalculationResult(
        isValid: false,
        errorMessage:
            'El largo de la chapa debe ser mayor al solape longitudinal para poder cubrir la caída.',
      );
    }

    final rawColumns = (roofWidthM - 1e-9) / sheetUsefulWidthM;
    if (!rawColumns.isFinite || rawColumns > 1000000) {
      return const RoofCalculationResult(
        isValid: false,
        errorMessage: 'La cantidad de hiladas supera el límite permitido.',
      );
    }
    final columns = math.max(1, rawColumns.ceil());

    final int rows;
    if (roofSlopeLengthM <= sheetLengthM + 1e-6) {
      rows = 1;
    } else {
      final effectiveStep = sheetLengthM - safeOverlap;
      final rawRows = ((roofSlopeLengthM - safeOverlap) - 1e-9) / effectiveStep;
      if (!rawRows.isFinite || rawRows > 1000000) {
        return const RoofCalculationResult(
          isValid: false,
          errorMessage: 'La cantidad de tramos supera el límite permitido.',
        );
      }
      rows = math.max(1, rawRows.ceil());
    }

    final totalSheets = columns * rows;
    if (totalSheets > 10000000) {
      return const RoofCalculationResult(
        isValid: false,
        errorMessage: 'La cantidad total de chapas supera el límite permitido.',
      );
    }
    final coveredSlopeLengthM = _round3(
      rows <= 1
          ? sheetLengthM
          : sheetLengthM + (rows - 1) * (sheetLengthM - safeOverlap),
    );
    final surplusPerColumnM = _round3(
      math.max(0.0, coveredSlopeLengthM - roofSlopeLengthM),
    );
    final totalLinearMeters = _round3(totalSheets * sheetLengthM);
    final totalNominalM2 =
        _round3(totalSheets * sheetLengthM * sheetNominalWidthM);
    final roofAreaM2 = _round3(roofWidthM * roofSlopeLengthM);

    late final double billingQty;
    late final String billingUnit;
    switch (pricingMode) {
      case RoofPricingMode.perSheet:
        billingQty = totalSheets.toDouble();
        billingUnit = totalSheets == 1 ? 'chapa' : 'chapas';
        break;
      case RoofPricingMode.perLinearMeter:
        billingQty = totalLinearMeters;
        billingUnit = 'ml';
        break;
      case RoofPricingMode.perM2:
        billingQty = totalNominalM2;
        billingUnit = 'm²';
        break;
    }

    final lenStr = _fmtNum(sheetLengthM, decimals: 2);
    final wStr = _fmtNum(roofWidthM, decimals: 2);
    final sStr = _fmtNum(roofSlopeLengthM, decimals: 2);
    final layoutText = rows > 1
        ? '$columns hiladas x $rows tramos (solape ${_fmtNum(safeOverlap * 100, decimals: 0)}cm)'
        : '$columns chapas en 1 tramo';

    final note =
        'Cálculo Techo ${wStr}x${sStr}m (${_fmtNum(roofAreaM2, decimals: 1)} m2): '
        '$totalSheets chapas de ${lenStr}m ($layoutText - ${_fmtNum(totalLinearMeters, decimals: 1)} ml)';

    // Complementos orientativos:
    // 1. Tornillos autoperforantes (~7 por m² de techo)
    final screwsCount = math.max(totalSheets * 6, (roofAreaM2 * 7).ceil());
    // 2. Perfiles C / Clavaderas (1 cada ~1.00m de caída + cumbrera/alero)
    final purlinLines = (roofSlopeLengthM / 1.0).ceil() + 1;
    final purlinLinearMeters = (purlinLines * roofWidthM).ceil();

    final complements = <ComplementSuggestion>[
      ComplementSuggestion(
        title: 'Tornillos Autoperforantes p/ Techo',
        quantityLabel: '~$screwsCount u.',
        searchKeyword: 'Autoperforante',
        detailHint: 'Aprox. 6-7 autoperforantes por m²',
      ),
      ComplementSuggestion(
        title: 'Perfiles / Clavaderas ($purlinLines líneas)',
        quantityLabel: '~$purlinLinearMeters ml',
        searchKeyword: 'Perfil',
        detailHint: '$purlinLines líneas de ${wStr}m (c/ ~1.0m de caída)',
      ),
    ];

    return RoofCalculationResult(
      isValid: true,
      roofWidthM: roofWidthM,
      roofSlopeLengthM: roofSlopeLengthM,
      roofAreaM2: roofAreaM2,
      usefulAreaCoveredM2: _round3(totalSheets * sheetLengthM * sheetUsefulWidthM),
      columnsAcrossWidth: columns,
      rowsAlongSlope: rows,
      coveredSlopeLengthM: coveredSlopeLengthM,
      surplusPerColumnM: surplusPerColumnM,
      totalSheetsNeeded: totalSheets,
      totalLinearMeters: totalLinearMeters,
      totalNominalM2: totalNominalM2,
      billingQuantity: billingQty,
      billingUnitLabel: billingUnit,
      customDetailsNote: note,
      complements: complements,
    );
  }

  /// Estimación rápida de chapas por superficie total (`m² Directos`) + margen
  /// por cortes/solapes. Útil cuando el cliente aún no trae Ancho × Caída.
  static RoofCalculationResult calculateRoofByArea({
    required double targetAreaM2,
    required double sheetNominalWidthM,
    required double sheetUsefulWidthM,
    required double sheetLengthM,
    double wastePercent = 10.0,
    RoofPricingMode pricingMode = RoofPricingMode.perSheet,
  }) {
    if (!targetAreaM2.isFinite ||
        !sheetNominalWidthM.isFinite ||
        !sheetUsefulWidthM.isFinite ||
        !sheetLengthM.isFinite ||
        !wastePercent.isFinite) {
      return const RoofCalculationResult(
        isValid: false,
        isAreaEstimate: true,
        errorMessage: 'Ingresá valores numéricos válidos.',
      );
    }
    if (targetAreaM2 <= 0) {
      return const RoofCalculationResult(
        isValid: false,
        isAreaEstimate: true,
        errorMessage: 'Ingresá la superficie total del techo en m².',
      );
    }
    if (targetAreaM2 > 10000000) {
      return const RoofCalculationResult(
        isValid: false,
        isAreaEstimate: true,
        errorMessage: 'La superficie ingresada supera el rango máximo permitido.',
      );
    }
    if (sheetUsefulWidthM <= 0 || sheetNominalWidthM <= 0) {
      return const RoofCalculationResult(
        isValid: false,
        isAreaEstimate: true,
        errorMessage: 'El ancho útil y total de la chapa deben ser mayores a 0.',
      );
    }
    if (sheetLengthM <= 0) {
      return const RoofCalculationResult(
        isValid: false,
        isAreaEstimate: true,
        errorMessage: 'El largo de la chapa debe ser mayor a 0.',
      );
    }
    if (sheetLengthM > 50 ||
        sheetNominalWidthM > 50 ||
        sheetUsefulWidthM > 50) {
      return const RoofCalculationResult(
        isValid: false,
        isAreaEstimate: true,
        errorMessage: 'Las medidas ingresadas superan el rango máximo permitido.',
      );
    }
    if (sheetUsefulWidthM > sheetNominalWidthM + 1e-6) {
      return const RoofCalculationResult(
        isValid: false,
        isAreaEstimate: true,
        errorMessage: 'El ancho útil de la chapa no puede superar al ancho total.',
      );
    }

    final safeWaste = wastePercent.clamp(0.0, 50.0);
    final areaWithWaste = targetAreaM2 * (1.0 + safeWaste / 100.0);
    final usefulAreaPerSheet = sheetUsefulWidthM * sheetLengthM;
    final rawSheets = (areaWithWaste - 1e-9) / usefulAreaPerSheet;
    if (!rawSheets.isFinite || rawSheets > 10000000) {
      return const RoofCalculationResult(
        isValid: false,
        isAreaEstimate: true,
        errorMessage: 'La cantidad total de chapas supera el límite permitido.',
      );
    }

    final totalSheets = math.max(1, rawSheets.ceil());
    final totalLinearMeters = _round3(totalSheets * sheetLengthM);
    final usefulAreaCoveredM2 = _round3(totalSheets * usefulAreaPerSheet);
    final totalNominalM2 =
        _round3(totalSheets * sheetLengthM * sheetNominalWidthM);
    final roofAreaM2 = _round3(targetAreaM2);

    late final double billingQty;
    late final String billingUnit;
    switch (pricingMode) {
      case RoofPricingMode.perSheet:
        billingQty = totalSheets.toDouble();
        billingUnit = totalSheets == 1 ? 'chapa' : 'chapas';
        break;
      case RoofPricingMode.perLinearMeter:
        billingQty = totalLinearMeters;
        billingUnit = 'ml';
        break;
      case RoofPricingMode.perM2:
        billingQty = totalNominalM2;
        billingUnit = 'm²';
        break;
    }

    final lenStr = _fmtNum(sheetLengthM, decimals: 2);
    final areaStr = _fmtNum(roofAreaM2, decimals: 1);
    final wasteText = safeWaste > 0 ? ' +${_fmtNum(safeWaste, decimals: 0)}%' : '';
    final note =
        'Estimado Techo $areaStr m2$wasteText: '
        '$totalSheets chapas de ${lenStr}m '
        '(cubre ${_fmtNum(usefulAreaCoveredM2, decimals: 1)} m2 útiles - ${_fmtNum(totalLinearMeters, decimals: 1)} ml)';

    final screwsCount = math.max(totalSheets * 6, (roofAreaM2 * 7).ceil());
    final purlinLinearMeters = math.max(1, (roofAreaM2 * 1.25).ceil());

    final complements = <ComplementSuggestion>[
      ComplementSuggestion(
        title: 'Tornillos Autoperforantes p/ Techo',
        quantityLabel: '~$screwsCount u.',
        searchKeyword: 'Autoperforante',
        detailHint: 'Aprox. 6-7 autoperforantes por m²',
      ),
      ComplementSuggestion(
        title: 'Perfiles / Clavaderas (estimado)',
        quantityLabel: '~$purlinLinearMeters ml',
        searchKeyword: 'Perfil',
        detailHint: 'Estimado ~1.25 ml de clavaderas por m² de techo',
      ),
    ];

    return RoofCalculationResult(
      isValid: true,
      isAreaEstimate: true,
      wastePercent: safeWaste,
      roofAreaM2: roofAreaM2,
      usefulAreaCoveredM2: usefulAreaCoveredM2,
      totalSheetsNeeded: totalSheets,
      totalLinearMeters: totalLinearMeters,
      totalNominalM2: totalNominalM2,
      billingQuantity: billingQty,
      billingUnitLabel: billingUnit,
      customDetailsNote: note,
      complements: complements,
    );
  }

  // ── 5. MOTOR DE CÁLCULO: PINTURA Y MEMBRANA LÍQUIDA ──────────────────────

  static PaintCalculationResult calculatePaint({
    required double surfaceAreaM2,
    required int coats,
    required double yieldM2PerLiter,
    required double containerLiters,
    PaintYieldMode yieldMode = PaintYieldMode.perCoat,
    double wastePercent = 0.0,
  }) {
    if (!surfaceAreaM2.isFinite ||
        !yieldM2PerLiter.isFinite ||
        !containerLiters.isFinite ||
        !wastePercent.isFinite) {
      return const PaintCalculationResult(
        isValid: false,
        errorMessage: 'Ingresá valores numéricos válidos.',
      );
    }
    if (surfaceAreaM2 <= 0) {
      return const PaintCalculationResult(
        isValid: false,
        errorMessage: 'Ingresá los m² o medidas de la superficie a pintar.',
      );
    }
    if (coats <= 0 || coats > 20) {
      return const PaintCalculationResult(
        isValid: false,
        errorMessage: 'La cantidad de manos debe estar entre 1 y 20.',
      );
    }
    if (yieldM2PerLiter <= 0) {
      return const PaintCalculationResult(
        isValid: false,
        errorMessage: 'El rendimiento (m²/L) debe ser mayor a 0.',
      );
    }
    if (containerLiters <= 0) {
      return const PaintCalculationResult(
        isValid: false,
        errorMessage: 'La capacidad del envase debe ser mayor a 0.',
      );
    }
    if (surfaceAreaM2 > 1000000 ||
        yieldM2PerLiter > 10000 ||
        containerLiters > 10000) {
      return const PaintCalculationResult(
        isValid: false,
        errorMessage: 'Las medidas ingresadas superan el rango máximo permitido.',
      );
    }

    final safeWaste = wastePercent.clamp(0.0, 100.0);
    final areaWithWaste = surfaceAreaM2 * (1.0 + (safeWaste / 100.0));

    // Corrección crítica Punto 1:
    // - Si yieldMode == perCoat (Látex, Sintético, Barniz): multiplica por la cantidad de manos.
    // - Si yieldMode == finalTotal (Membrana Líquida / Impermeabilizante rendimiento final): NO multiplica por manos.
    final effectiveAreaToCover = yieldMode == PaintYieldMode.perCoat
        ? areaWithWaste * coats
        : areaWithWaste;

    final totalLitersNeeded = _round3(effectiveAreaToCover / yieldM2PerLiter);
    final rawContainers = (totalLitersNeeded - 1e-9) / containerLiters;
    if (!totalLitersNeeded.isFinite ||
        !rawContainers.isFinite ||
        rawContainers > 1000000) {
      return const PaintCalculationResult(
        isValid: false,
        errorMessage: 'La cantidad de envases supera el límite permitido.',
      );
    }
    final containersNeeded = math.max(1, rawContainers.ceil());
    final totalLitersDelivered = _round3(containersNeeded * containerLiters);

    final capStr = _fmtNum(containerLiters, decimals: 1);
    final areaStr = _fmtNum(surfaceAreaM2, decimals: 1);
    final litersStr = _fmtNum(totalLitersNeeded, decimals: 1);
    final modeNote = yieldMode == PaintYieldMode.finalTotal
        ? 'rend. final ${_fmtNum(yieldM2PerLiter, decimals: 1)} m2/L ($coats manos)'
        : '$coats ${coats == 1 ? "mano" : "manos"} - rend. ${_fmtNum(yieldM2PerLiter, decimals: 1)} m2/L';

    final note =
        'Cálculo Pintura: $containersNeeded env. de ${capStr}L/Kg '
        '(necesita ${litersStr}L p/ $areaStr m2 - $modeNote)';

    final complements = <ComplementSuggestion>[
      const ComplementSuggestion(
        title: 'Rodillo / Pincel',
        quantityLabel: '1-2 u.',
        searchKeyword: 'Rodillo',
        detailHint: 'Rodillo o pincel para aplicación',
      ),
      const ComplementSuggestion(
        title: 'Cinta de Enmascarar / Papel',
        quantityLabel: '1-2 rollos',
        searchKeyword: 'Cinta',
        detailHint: 'Cinta de pintor para bordes y zócalos',
      ),
      if (yieldMode == PaintYieldMode.finalTotal)
        ComplementSuggestion(
          title: 'Venda / Manta Geotextil',
          quantityLabel: '~${(surfaceAreaM2 * 0.35).ceil()} ml',
          searchKeyword: 'Venda',
          detailHint: 'Para juntas, grietas y encuentros de carga',
        ),
    ];

    return PaintCalculationResult(
      isValid: true,
      surfaceAreaM2: surfaceAreaM2,
      coats: coats,
      yieldMode: yieldMode,
      yieldM2PerLiter: yieldM2PerLiter,
      containerLiters: containerLiters,
      totalLitersNeeded: totalLitersNeeded,
      containersNeeded: containersNeeded,
      totalLitersDelivered: totalLitersDelivered,
      billingQuantity: containersNeeded.toDouble(),
      billingUnitLabel: containersNeeded == 1 ? 'envase' : 'envases',
      customDetailsNote: note,
      complements: complements,
    );
  }

  static double _round3(double val) => (val * 1000).roundToDouble() / 1000.0;

  static String _fmtNum(double val, {int decimals = 2}) {
    if ((val - val.roundToDouble()).abs() < 0.005) {
      return val.round().toString();
    }
    return val
        .toStringAsFixed(decimals)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }
}
