import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend_desktop/core/utils/receipt_printer_service.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/pos/data/datasources/pos_remote_datasource.dart';
import 'package:frontend_desktop/features/pos/data/repositories/pos_repository_impl.dart';
import 'package:frontend_desktop/features/pos/domain/entities/cart_item.dart';
import 'package:frontend_desktop/features/pos/domain/services/hardware_calculator_engine.dart';
import 'package:frontend_desktop/features/pos/domain/usecases/process_sale_usecase.dart';
import 'package:frontend_desktop/features/pos/domain/usecases/search_products_usecase.dart';
import 'package:frontend_desktop/features/pos/presentation/providers/pos_provider.dart';
import 'package:frontend_desktop/features/quotes/data/quote_repository.dart';
import 'package:frontend_desktop/features/quotes/services/quote_pdf_service.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HardwareCalculatorEngine — Machimbre / Maderas', () {
    test('Calcula tablas con ancho útil vs ancho nominal y protege facturación por m² nominal', () {
      // Habitación 4x3 = 12 m², +10% desperdicio = 13.20 m²
      // Machimbre 4" x 3.00m: Ancho útil = 0.088m (área útil/tabla = 0.264 m²), Ancho nominal = 0.1016m (área nom/tabla = 0.3048 m²)
      // Tablas necesarias = ceil(13.20 / 0.264) = 50 tablas
      final resNominal = HardwareCalculatorEngine.calculateWood(
        targetAreaM2: 12.0,
        nominalWidthM: 0.1016,
        usefulWidthM: 0.088,
        boardLengthM: 3.00,
        wastePercent: 10.0,
        pricingMode: WoodPricingMode.perM2,
        m2BillingBasis: M2BillingBasis.nominal,
        inchLabel: '4',
      );

      expect(resNominal.isValid, isTrue);
      expect(resNominal.boardsNeeded, 50);
      expect(resNominal.totalBoardsDelivered, 50);
      expect(resNominal.usefulAreaCoveredM2, closeTo(13.20, 0.01));
      // 50 tablas * 3.00m * 0.1016m = 15.24 m² nominales a facturar (no subfactura)
      expect(resNominal.nominalAreaDeliveredM2, closeTo(15.24, 0.01));
      expect(resNominal.billingQuantity, closeTo(15.24, 0.01));
      expect(resNominal.customDetailsNote, contains('50 tablas de 3m'));

      // Si el comercio elige facturar por m² útiles:
      final resUseful = HardwareCalculatorEngine.calculateWood(
        targetAreaM2: 12.0,
        nominalWidthM: 0.1016,
        usefulWidthM: 0.088,
        boardLengthM: 3.00,
        wastePercent: 10.0,
        pricingMode: WoodPricingMode.perM2,
        m2BillingBasis: M2BillingBasis.useful,
      );
      expect(resUseful.billingQuantity, closeTo(13.20, 0.01));
    });

    test('Soporta redondeo a paquete cerrado', () {
      // 45 tablas necesarias con paquetes de 10 -> 5 paquetes (50 tablas entregadas)
      final res = HardwareCalculatorEngine.calculateWood(
        targetAreaM2: 11.5,
        nominalWidthM: 0.10,
        usefulWidthM: 0.088,
        boardLengthM: 3.00,
        wastePercent: 0.0,
        pricingMode: WoodPricingMode.perPack,
        boardsPerPack: 10,
        roundToFullPack: true,
      );

      expect(res.isValid, isTrue);
      expect(res.boardsNeeded, 44);
      expect(res.packsNeeded, 5);
      expect(res.totalBoardsDelivered, 50);
      expect(res.billingQuantity, 5.0);
    });
  });

  group('HardwareCalculatorEngine — Chapas / Techos', () {
    test('Calcula hiladas por ancho útil y tramos con solape longitudinal', () {
      // Techo 6.0m ancho x 7.5m caída, usando chapas de 4.00m (ancho total 1.10m, útil 1.00m) y solape long. 0.20m
      // Columnas = ceil(6.0 / 1.0) = 6
      // Tramos = ceil((7.5 - 0.20) / (4.0 - 0.20)) = ceil(7.3 / 3.8) = 2 tramos
      // Total chapas = 6 * 2 = 12 chapas
      final res = HardwareCalculatorEngine.calculateRoof(
        roofWidthM: 6.0,
        roofSlopeLengthM: 7.5,
        sheetNominalWidthM: 1.10,
        sheetUsefulWidthM: 1.00,
        sheetLengthM: 4.00,
        longitudinalOverlapM: 0.20,
        pricingMode: RoofPricingMode.perSheet,
      );

      expect(res.isValid, isTrue);
      expect(res.columnsAcrossWidth, 6);
      expect(res.rowsAlongSlope, 2);
      expect(res.totalSheetsNeeded, 12);
      expect(res.totalLinearMeters, 48.0);
      expect(res.billingQuantity, 12.0);
    });

    test('Previene división o bucle inválido si largoChapa <= solapeLongitudinal en caída larga', () {
      final invalid = HardwareCalculatorEngine.calculateRoof(
        roofWidthM: 5.0,
        roofSlopeLengthM: 4.0,
        sheetNominalWidthM: 1.10,
        sheetUsefulWidthM: 1.00,
        sheetLengthM: 0.20,
        longitudinalOverlapM: 0.20,
      );

      expect(invalid.isValid, isFalse);
      expect(invalid.errorMessage, isNotNull);
    });
  });

  group('HardwareCalculatorEngine — Pintura y Membrana Líquida (Fix Punto 1)', () {
    test('En Látex (perCoat) multiplica superficie por manos, pero en Membrana (finalTotal) NO multiplica por manos', () {
      // 30 m², 3 manos:
      // 1) Látex (10 m²/L por mano): (30 * 3) / 10 = 9 Litros -> 3 latas de 4L
      final latex = HardwareCalculatorEngine.calculatePaint(
        surfaceAreaM2: 30.0,
        coats: 3,
        yieldM2PerLiter: 10.0,
        containerLiters: 4.0,
        yieldMode: PaintYieldMode.perCoat,
      );
      expect(latex.isValid, isTrue);
      expect(latex.totalLitersNeeded, closeTo(9.0, 0.001));
      expect(latex.containersNeeded, 3);

      // 2) Membrana Líquida (rendimiento final terminado 1.5 m²/Kg en 3 manos):
      // 30 / 1.5 = 20 Kg totales (NO 60 Kg) -> 1 balde de 20Kg
      final membrane = HardwareCalculatorEngine.calculatePaint(
        surfaceAreaM2: 30.0,
        coats: 3,
        yieldM2PerLiter: 1.5,
        containerLiters: 20.0,
        yieldMode: PaintYieldMode.finalTotal,
      );
      expect(membrane.isValid, isTrue);
      expect(membrane.totalLitersNeeded, closeTo(20.0, 0.001));
      expect(membrane.containersNeeded, 1);
    });
  });

  group('Precedencia de Caché Offline y Gating por Rubro/Plan (Punto 5)', () {
    test('calc_config del servidor tiene precedencia y actualiza SharedPreferences local', () async {
      SharedPreferences.setMockInitialValues({
        'hw_calc_config_v1_42': '{"type":"wood","useful_width_m":0.080,"length_m":2.40}',
      });
      final prefs = await SharedPreferences.getInstance();

      final productFromServer = Product(
        id: 42,
        name: 'Machimbre Pino 1/2 x 4 x 3.60m',
        internalCode: '00042',
        costPrice: 1000,
        sellingPrice: 2000,
        stock: 50,
        active: true,
        isSoldByWeight: false,
        calcConfig: const {
          'type': 'wood',
          'useful_width_m': 0.090,
          'length_m': 3.60,
        },
      );

      final resolved = await HardwareCalculatorEngine.resolveConfigForProduct(
        productFromServer,
        prefs: prefs,
      );

      expect(resolved['useful_width_m'], 0.090);
      expect(resolved['length_m'], 3.60);
      expect(prefs.getString('hw_calc_config_v1_42'), contains('3.6'));
    });

    test('canUseHardwareCalculator habilita solo hardware_store con plan Básico/Premium activo y bloquea retail', () {
      const hwBasic = BusinessSettings(
        businessType: 'hardware_store',
        licenseStatus: 'active',
        licensePlanType: 'basic',
      );
      const hwPremium = BusinessSettings(
        businessType: 'hardware_store',
        licenseStatus: 'active',
        licensePlanType: 'premium',
      );
      const retailPremium = BusinessSettings(
        businessType: 'retail',
        licenseStatus: 'active',
        licensePlanType: 'premium',
      );
      const hwExpired = BusinessSettings(
        businessType: 'hardware_store',
        licenseStatus: 'expired',
        licensePlanType: 'basic',
      );

      expect(hwBasic.canUseHardwareCalculator, isTrue);
      expect(hwPremium.canUseHardwareCalculator, isTrue);
      expect(retailPremium.canUseHardwareCalculator, isFalse);
      expect(hwExpired.canUseHardwareCalculator, isFalse);
    });
  });

  group('Regresión Plan 4.2 — PDF + ESC/POS ASCII & Decimales sin Peso', () {
    test('customDetailsNote son ASCII puro (<= 0x7E) y buildQuoteTicketBytes + PDF soportan decimales sin product sin kg ni crash', () async {
      final wood = HardwareCalculatorEngine.calculateWood(
        targetAreaM2: 12.0,
        nominalWidthM: 0.1016,
        usefulWidthM: 0.088,
        boardLengthM: 3.0,
        wastePercent: 10.0,
        pricingMode: WoodPricingMode.perM2,
      );
      final roof = HardwareCalculatorEngine.calculateRoof(
        roofWidthM: 6.0,
        roofSlopeLengthM: 4.0,
        sheetNominalWidthM: 1.10,
        sheetUsefulWidthM: 1.00,
        sheetLengthM: 4.50,
        longitudinalOverlapM: 0.20,
      );
      final paint = HardwareCalculatorEngine.calculatePaint(
        surfaceAreaM2: 30.0,
        coats: 2,
        yieldM2PerLiter: 10.0,
        containerLiters: 4.0,
      );

      for (final note in [
        wood.customDetailsNote,
        roof.customDetailsNote,
        paint.customDetailsNote,
      ]) {
        expect(note.isNotEmpty, isTrue);
        expect(note, isNot(contains('→')));
        expect(note, isNot(contains('²')));
        expect(note, isNot(contains('·')));
        expect(note, isNot(contains('×')));
        for (final rune in note.runes) {
          expect(rune, lessThanOrEqualTo(0xFF),
              reason: 'Carácter fuera de Latin-1/WinAnsi en "$note": $rune');
        }
      }

      final quote = Quote(
        id: 77,
        quoteNumber: 'PRE-0077',
        status: 'pending',
        subtotal: 13710,
        total: 13710,
        notes: 'Entrega en obra → verificar accesos • 20m²',
        items: [
          QuoteItem(
            productId: 500,
            productName: 'Machimbre Pino 1/2 x 4"',
            customDetails: wood.customDetailsNote,
            unitPrice: 1000,
            quantity: 13.71,
            subtotal: 13710,
            product: null, // Simula fallback v1.8.5 sin relación product
          ),
        ],
      );

      final escBytes = await ReceiptPrinterService.instance.buildQuoteTicketBytes(
        quote: quote,
        settings: const BusinessSettings(companyName: 'Corralón Test'),
        vendorName: 'Carlos',
      );
      final escText = latin1.decode(escBytes);
      expect(escText, contains('13.71 x'));
      expect(escText, isNot(contains('13.71 kg')));
      expect(escText, contains('50 tablas de 3m'));

      final pdfBytes = await QuotePdfService.generateQuotePdf(
        quote: quote,
        businessName: 'Corralón Test',
        vendorName: 'Carlos',
      );
      expect(pdfBytes.length, greaterThan(400));
      expect(latin1.decode(pdfBytes.take(5).toList()), '%PDF-');
    });
  });

  group('Regresión Plan 4.2 — Auto-detección de Nombre', () {
    test('Detecta tipo, pulgadas y largo evitando falsos positivos de techo/madera', () {
      final deck = HardwareCalculatorEngine.inferConfigFromName(
          'Deck Pino Impregnado 1" x 4" x 3.00m');
      expect(deck['type'], 'wood');
      expect(deck['inch_preset'], '4');
      expect(deck['length_m'], closeTo(3.0, 0.001));

      final machimbre6 = HardwareCalculatorEngine.inferConfigFromName(
          'Machimbre Eucalipto 3/4" x 6" x 4.00m');
      expect(machimbre6['type'], 'wood');
      expect(machimbre6['inch_preset'], '6');
      expect(machimbre6['length_m'], closeTo(4.0, 0.001));

      final machimbreTecho = HardwareCalculatorEngine.inferConfigFromName(
          'Machimbre 1/2 x 4 para techo');
      expect(machimbreTecho['type'], 'wood');
      expect(machimbreTecho['inch_preset'], '4');

      final impregnante = HardwareCalculatorEngine.inferConfigFromName(
          'Impregnante para madera 4L');
      expect(impregnante['type'], 'paint');

      // Nuevas pulgadas de madera (1", 2", 8") además de 3", 4", 5", 6"
      final presetKeys = HardwareCalculatorEngine.woodInchPresets
          .map((p) => p.key)
          .toList();
      expect(presetKeys, containsAll(['1', '2', '3', '4', '5', '6', '8']));

      final tirante2 = HardwareCalculatorEngine.inferConfigFromName(
          'Tirante Pino 2" x 2" x 3.00m (Alfajía)');
      expect(tirante2['type'], 'wood');
      expect(tirante2['inch_preset'], '2');
      expect(tirante2['nominal_width_m'], closeTo(0.0508, 0.0005));

      final liston1 = HardwareCalculatorEngine.inferConfigFromName(
          'Listón Yesero Pino 1/2 x 1" x 3.00m');
      expect(liston1['type'], 'wood');
      expect(liston1['inch_preset'], '1');
      expect(liston1['nominal_width_m'], closeTo(0.0254, 0.0005));

      final tabla8 = HardwareCalculatorEngine.inferConfigFromName(
          'Tabla Encofrado Saligna 1" x 8" x 3.00m');
      expect(tabla8['type'], 'wood');
      expect(tabla8['inch_preset'], '8');
      expect(tabla8['nominal_width_m'], closeTo(0.2032, 0.0005));
    });
  });

  group('Regresión Plan 4.2 — Guardas Matemáticas', () {
    test('Rechaza usefulWidthM > nominalWidthM, boardsPerPack <= 0 y dimensiones 1e300 sin NaN/Infinity', () {
      final badWoodWidth = HardwareCalculatorEngine.calculateWood(
        targetAreaM2: 10.0,
        nominalWidthM: 0.08,
        usefulWidthM: 0.10,
        boardLengthM: 3.0,
      );
      expect(badWoodWidth.isValid, isFalse);

      final badRoofWidth = HardwareCalculatorEngine.calculateRoof(
        roofWidthM: 6.0,
        roofSlopeLengthM: 4.0,
        sheetNominalWidthM: 0.90,
        sheetUsefulWidthM: 1.10,
        sheetLengthM: 4.0,
      );
      expect(badRoofWidth.isValid, isFalse);

      final zeroPack = HardwareCalculatorEngine.calculateWood(
        targetAreaM2: 10.0,
        nominalWidthM: 0.10,
        usefulWidthM: 0.088,
        boardLengthM: 3.0,
        pricingMode: WoodPricingMode.perPack,
        boardsPerPack: 0,
      );
      expect(zeroPack.isValid, isFalse);

      final hugeWood = HardwareCalculatorEngine.calculateWood(
        targetAreaM2: 1e300,
        nominalWidthM: 0.10,
        usefulWidthM: 0.088,
        boardLengthM: 3.0,
      );
      expect(hugeWood.isValid, isFalse);

      final hugeRoof = HardwareCalculatorEngine.calculateRoof(
        roofWidthM: 1e300,
        roofSlopeLengthM: 4.0,
        sheetNominalWidthM: 1.10,
        sheetUsefulWidthM: 1.00,
        sheetLengthM: 4.0,
      );
      expect(hugeRoof.isValid, isFalse);

      final hugePaint = HardwareCalculatorEngine.calculatePaint(
        surfaceAreaM2: 1e300,
        coats: 2,
        yieldM2PerLiter: 10.0,
        containerLiters: 4.0,
      );
      expect(hugePaint.isValid, isFalse);
    });
  });

  group('Regresión Plan 4.2 — Gating de Licencia B2B', () {
    test('Bloquea estados vacíos, suspendidos, plan blocked con lifetime y retail; habilita planes válidos', () {
      const emptyStatus = BusinessSettings(
        businessType: 'hardware_store',
        licenseStatus: '',
        licensePlanType: 'pro',
      );
      const suspended = BusinessSettings(
        businessType: 'hardware_store',
        licenseStatus: 'suspended',
        licensePlanType: 'premium',
      );
      const blockedLifetime = BusinessSettings(
        businessType: 'hardware_store',
        licenseStatus: 'active',
        licensePlanType: 'blocked',
        isLifetime: true,
      );
      const retail = BusinessSettings(
        businessType: 'retail',
        licenseStatus: 'active',
        licensePlanType: 'premium',
        isLifetime: true,
      );
      const hwLifetimeValid = BusinessSettings(
        businessType: 'hardware_store',
        licenseStatus: 'active',
        licensePlanType: 'pro',
        isLifetime: true,
      );

      expect(emptyStatus.canUseHardwareCalculator, isFalse);
      expect(suspended.canUseHardwareCalculator, isFalse);
      expect(blockedLifetime.canUseHardwareCalculator, isFalse);
      expect(retail.canUseHardwareCalculator, isFalse);
      expect(hwLifetimeValid.canUseHardwareCalculator, isTrue);
    });
  });

  group('Regresión Plan 4.2 — PosProvider líneas calculadas y reemplazo', () {
    PosProvider buildPos() {
      final mockClient = MockClient((_) async => http.Response('[]', 200));
      final ds = PosRemoteDataSourceImpl(
        baseUrl: 'http://localhost/api',
        client: mockClient,
      );
      final repo = PosRepositoryImpl(remoteDataSource: ds);
      return PosProvider(
        processSaleUseCase: ProcessSaleUseCase(repo),
        searchProductsUseCase: SearchProductsUseCase(repo),
        repository: repo,
        remoteDataSource: ds,
      );
    }

    test('No fusiona líneas con customDetails distinto y replacingItem limpia overrides al cambiar SKU', () {
      SharedPreferences.setMockInitialValues({});
      final pos = buildPos();
      final prod1 = Product(
        id: 101,
        name: 'Machimbre Pino 4"',
        internalCode: 'HW-101',
        costPrice: 1000,
        sellingPrice: 2000,
        stock: 100,
        active: true,
        isSoldByWeight: false,
      );
      final prod2 = Product(
        id: 102,
        name: 'Chapa Sinusoidal 4m',
        internalCode: 'HW-102',
        costPrice: 5000,
        sellingPrice: 9000,
        stock: 50,
        active: true,
        isSoldByWeight: false,
      );

      // Línea simple + dos líneas calculadas con distinto desglose
      expect(pos.requestAddToCartWithPromo(prod1), isTrue);
      pos.addCalculatedHardwareItem(
        prod1,
        quantity: 12.5,
        customDetails: '40 tablas de 3m -> 12.50 m2',
      );
      pos.addCalculatedHardwareItem(
        prod1,
        quantity: 8.25,
        customDetails: '25 tablas de 3m -> 8.25 m2',
      );
      // Agregar otra unidad suelta no debe absorber las líneas calculadas
      expect(pos.requestAddToCartWithPromo(prod1), isTrue);

      expect(pos.cart.length, 3);
      expect(pos.cart[0].quantity, 2.0);
      expect(pos.cart[0].customDetails, isNull);
      expect(pos.cart[1].customDetails, '40 tablas de 3m -> 12.50 m2');
      expect(pos.cart[2].customDetails, '25 tablas de 3m -> 8.25 m2');

      // Simular overrides manuales/lote en la línea a reemplazar y cambiar SKU -> prod2
      final targetLine = pos.cart[1];
      targetLine.manualUnitPrice = 1750;
      targetLine.manualCostPrice = 900;
      targetLine.agreedUnitPrice = 1800;
      targetLine.customDescription = 'Descripción temporal anterior';
      targetLine.batchId = 99;
      targetLine.batchCode = 'L-099';
      targetLine.batchExpirationDate = '2027-01-01';
      targetLine.isTemporary = true;
      targetLine.saveToCatalog = true;
      targetLine.hasManualIvaOverride = true;

      pos.addCalculatedHardwareItem(
        prod2,
        quantity: 6,
        customDetails: '6 chapas de 4m',
        overrideTier: PriceTier.wholesale,
        replacingItem: targetLine,
      );

      expect(pos.cart.length, 3);
      final replaced = pos.cart[1];
      expect(replaced.product.id, prod2.id);
      expect(replaced.quantity, 6.0);
      expect(replaced.customDetails, '6 chapas de 4m');
      expect(replaced.manualUnitPrice, isNull);
      expect(replaced.manualCostPrice, isNull);
      expect(replaced.agreedUnitPrice, isNull);
      expect(replaced.customDescription, isNull);
      expect(replaced.batchId, isNull);
      expect(replaced.batchCode, isNull);
      expect(replaced.batchExpirationDate, isNull);
      expect(replaced.isTemporary, isFalse);
      expect(replaced.saveToCatalog, isFalse);
      expect(replaced.hasManualIvaOverride, isFalse);
    });
  });
}
