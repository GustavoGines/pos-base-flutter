import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:frontend_desktop/core/presentation/widgets/thermal_receipt_widget.dart';
import 'package:frontend_desktop/core/presentation/widgets/ticket_preview_dialog.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/pos/domain/entities/cart_item.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'thermal_receipt_adversarial_test.dart' as adversarial_thermal;

void main() {
  adversarial_thermal.main();
  final testSettings = BusinessSettings(
    companyName: 'Ferretería & Corralón El Progreso S.A.',
    taxId: '30-71234567-8',
    address: 'Av. Libertador San Martín 4567, Piso 2, Dpto B, Buenos Aires',
    phone: '+54 11 4455-6677 / 4455-8899',
  );

  final testItems = [
    CartItem(
      product: Product(
        id: 1,
        name: 'Bolsa de Cemento Loma Negra Portland 50kg CPC 40 Especial',
        internalCode: 'CEM001',
        costPrice: 8500.0,
        sellingPrice: 12500.0,
        stock: 150.0,
        active: true,
        isSoldByWeight: false,
      ),
      quantity: 10.0,
    ),
    CartItem(
      product: Product(
        id: 2,
        name: 'Arena Fina Especial para Revoque a Granel (x Tonelada)',
        internalCode: 'ARE002',
        costPrice: 15000.0,
        sellingPrice: 22450.50,
        stock: 50.0,
        active: true,
        isSoldByWeight: true,
      ),
      quantity: 2.75,
    ),
  ];

  final testPayments = [
    {'name': 'EFECTIVO', 'amount': 100000.0},
    {'name': 'TARJETA DE DÉBITO', 'amount': 86738.88},
  ];

  final testFiscalInvoice = {
    'voucher_type': 1,
    'voucher_letter': 'A',
    'point_of_sale': 3,
    'voucher_number': 142,
    'formatted_number': '00003-00000142',
    'cae': '74239847120394',
    'cae_expiration': '2026-10-25',
    'qr_data':
        'https://www.afip.gob.ar/fe/qr/?p=eyJ2ZXIiOjEsImZjaGEiOiIyMDI2LTEwLTA3In0=',
    'net_amount': 154329.65,
    'iva_amount': 32409.23,
    'receiver_name': 'CONSTRUCTORA DEL SUR S.R.L.',
    'doc_type': 80,
    'doc_number': '30-79876543-1',
    'receiver_tax_condition': 'Responsable Inscripto',
  };

  final testDeliveryNote = {
    'id': 789,
    'sale': {
      'delivery_address': 'Calle Falsa 123, Parque Industrial Módulo 4',
    },
  };

  Widget buildAppWrapper({required Widget child}) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SingleChildScrollView(
          child: child,
        ),
      ),
    );
  }

  group('ThermalReceiptWidget Layout & Fiscal Rendering Tests', () {
    testWidgets(
        'R3.1: Fiscal ticket renders cleanly at 58mm (210px logical width) with ZERO overflow',
        (tester) async {
      tester.view.physicalSize = const Size(210, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        buildAppWrapper(
          child: ThermalReceiptWidget(
            paperWidth: ThermalPaperWidth.mm58,
            businessSettings: testSettings,
            items: testItems,
            payments: testPayments,
            total: 186738.88,
            electronicInvoice: testFiscalInvoice,
            saleNumber: '000142',
            cashierName: 'Gines Gustavo',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Zero exceptions / zero RenderFlex overflow
      expect(tester.takeException(), isNull);

      // Verify AFIP fiscal elements exist
      expect(find.text('FACTURA A Nro 00003-00000142'), findsOneWidget);
      expect(find.text('PUNTO DE VENTA: 00003'), findsOneWidget);
      expect(find.text('CAE: 74239847120394'), findsOneWidget);
      expect(find.text('VTO. CAE: 25/10/2026'), findsOneWidget);
      expect(find.text('Comprobante Autorizado por AFIP'), findsOneWidget);
      expect(find.byType(QrImageView), findsOneWidget);
    });

    testWidgets(
        'R3.2: Fiscal ticket renders cleanly at 80mm (290px logical width) with ZERO overflow',
        (tester) async {
      tester.view.physicalSize = const Size(290, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        buildAppWrapper(
          child: ThermalReceiptWidget(
            paperWidth: ThermalPaperWidth.mm80,
            businessSettings: testSettings,
            items: testItems,
            payments: testPayments,
            total: 186738.88,
            electronicInvoice: testFiscalInvoice,
            saleNumber: '000142',
            cashierName: 'Gines Gustavo',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Zero exceptions / zero RenderFlex overflow
      expect(tester.takeException(), isNull);

      // Verify AFIP fiscal elements
      expect(find.text('FACTURA A Nro 00003-00000142'), findsOneWidget);
      expect(find.text('PUNTO DE VENTA: 00003'), findsOneWidget);
      expect(find.text('CAE: 74239847120394'), findsOneWidget);
      expect(find.text('VTO. CAE: 25/10/2026'), findsOneWidget);
      expect(find.text('Comprobante Autorizado por AFIP'), findsOneWidget);
      expect(find.byType(QrImageView), findsOneWidget);
    });

    testWidgets(
        'R3.3: Boundary stress test at ultra-narrow 190px logical width with long descriptions & figures',
        (tester) async {
      tester.view.physicalSize = const Size(190, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final extremeItems = [
        CartItem(
          product: Product(
            id: 99,
            name:
                'PERFIL IPN HIERRO ACERO NORMALIZADO 240MM X 12 METROS LARGO BARRA PESADA',
            internalCode: 'IPN240EXTREMELONGCODE001',
            costPrice: 999999.99,
            sellingPrice: 1459850.75,
            stock: 999.0,
            active: true,
            isSoldByWeight: true,
          ),
          quantity: 125.875,
        ),
        CartItem(
          product: Product(
            id: 100,
            name:
                'TORNILLO AUTOPERFORANTE CABEZA HEXAGONAL CON ARANDELA DE VULCANIZADO 14X2',
            internalCode: 'TORN002',
            costPrice: 50.0,
            sellingPrice: 120.0,
            stock: 5000.0,
            active: true,
            isSoldByWeight: false,
          ),
          quantity: 2500.0,
        ),
      ];

      await tester.pumpWidget(
        buildAppWrapper(
          child: SizedBox(
            width: 190,
            child: ThermalReceiptWidget(
              paperWidth: ThermalPaperWidth.mm58,
              businessSettings: testSettings,
              items: extremeItems,
              payments: [
                {'name': 'TRANSFERENCIA BANCARIA INTERDEPOSITOS', 'amount': 184063713.16},
              ],
              total: 184063713.16,
              surchargeAmount: 1840637.13,
              shippingCost: 500000.0,
              tenderedAmount: 190000000.0,
              changeAmount: 4095649.71,
              electronicInvoice: testFiscalInvoice,
              saleNumber: '999999',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Zero exceptions / zero RenderFlex overflow even under stress
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'R3.4: Non-fiscal receipt renders correctly at 58mm and 80mm with no QR code',
        (tester) async {
      tester.view.physicalSize = const Size(210, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        buildAppWrapper(
          child: ThermalReceiptWidget(
            paperWidth: ThermalPaperWidth.mm58,
            businessSettings: testSettings,
            items: testItems,
            total: 186738.88,
            electronicInvoice: null,
            customerName: 'Juan Pérez',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('COMPROBANTE DE VENTA'), findsOneWidget);
      expect(find.text('*** NO VALIDO COMO FACTURA ***'), findsWidgets);
      expect(find.byType(QrImageView), findsNothing);
    });

    testWidgets(
        'R3.5: Delivery note / Remito section renders with items and signature lines',
        (tester) async {
      tester.view.physicalSize = const Size(290, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        buildAppWrapper(
          child: ThermalReceiptWidget(
            paperWidth: ThermalPaperWidth.mm80,
            businessSettings: testSettings,
            items: testItems,
            total: 186738.88,
            electronicInvoice: testFiscalInvoice,
            deliveryNote: testDeliveryNote,
            customerName: 'Constructora del Sur S.R.L.',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('ORDEN DE RETIRO / REMITO'), findsOneWidget);
      expect(find.text('REMITO N°: 000789'), findsOneWidget);
      expect(find.text('FIRMA DESPACHANTE:'), findsOneWidget);
      expect(find.text('FIRMA CLIENTE / RETIRA:'), findsOneWidget);
    });

    testWidgets(
        'R3.6: TicketPreviewDialog renders ThermalReceiptWidget with zero RenderFlex overflow',
        (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => Center(
                child: ElevatedButton(
                  onPressed: () {
                    TicketPreviewDialog.show(
                      ctx,
                      title: 'Vista Previa — Ticket Térmico 58mm Fiscal',
                      paperWidth: ThermalPaperWidth.mm58,
                      receiptWidget: ThermalReceiptWidget(
                        paperWidth: ThermalPaperWidth.mm58,
                        businessSettings: testSettings,
                        items: testItems,
                        total: 186738.88,
                        electronicInvoice: testFiscalInvoice,
                      ),
                    );
                  },
                  child: const Text('Open Dialog'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap button to show dialog
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Verify dialog is open and no RenderFlex overflow
      expect(tester.takeException(), isNull);
      expect(find.byType(TicketPreviewDialog), findsOneWidget);
      expect(find.byType(ThermalReceiptWidget), findsOneWidget);
      expect(find.text('Imprimir'), findsOneWidget);
      expect(find.text('Cancelar'), findsOneWidget);
    });

    testWidgets(
        'R3.7: TicketPreviewDialog legacy lines mode renders with zero RenderFlex overflow on narrow viewport',
        (tester) async {
      tester.view.physicalSize = const Size(280, 500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final legacyLines = [
        const TicketLine('MI NEGOCIO', isBold: true, isLarge: true, align: TicketAlign.center),
        const TicketLine.hr(),
        const TicketLine('10 un x \$12.500,00', rightText: '\$125.000,00'),
        const TicketLine('CEMENTO LOMA NEGRA PORTLAND 50KG'),
        const TicketLine.hr(),
        const TicketLine('TOTAL GENERAL:', rightText: '\$125.000,00', isBold: true),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TicketPreviewDialog(
              title: 'Vista Previa — Ticket 58mm Roll Very Long Title',
              lines: legacyLines,
              paperWidth: ThermalPaperWidth.mm58,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('MI NEGOCIO'), findsOneWidget);
      expect(find.text('TOTAL GENERAL:'), findsOneWidget);
    });

    testWidgets(
        'R3.8: Factura B fiscal thermal receipt renders RG 5614 (Ley 27.743) IVA Contenido and RG 5616 receiver condition at 58mm & 80mm with zero overflow',
        (tester) async {
      tester.view.physicalSize = const Size(210, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final facturaBInvoice = {
        'voucher_type': 6,
        'voucher_letter': 'B',
        'point_of_sale': 1,
        'voucher_number': 35,
        'formatted_number': '00001-00000035',
        'cae': '86441034905904',
        'cae_expiration': '09/11/2026',
        'qr_data': 'https://www.afip.gob.ar/fe/qr/?p=TEST_QR_B',
        'receiver_name': 'CONSUMIDOR FINAL',
        'doc_type': 96,
        'doc_number': '39606329',
        'receiver_tax_condition': 'consumidor_final',
        'receiver_address': '25 DE MAYO 161 - FORMOSA',
      };

      await tester.pumpWidget(
        buildAppWrapper(
          child: ThermalReceiptWidget(
            paperWidth: ThermalPaperWidth.mm58,
            businessSettings: testSettings,
            items: testItems,
            payments: testPayments,
            total: 186738.88,
            electronicInvoice: facturaBInvoice,
            saleNumber: '000035',
            cashierName: 'ADMINISTRADOR',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('FACTURA B Nro 00001-00000035'), findsOneWidget);
      expect(find.text('COD. 006'), findsOneWidget);
      expect(find.text('IVA RESPONSABLE INSCRIPTO'), findsOneWidget);
      expect(find.text('A CONSUMIDOR FINAL'), findsOneWidget);
      expect(find.textContaining('25 DE MAYO 161 - FORMOSA'), findsOneWidget);
      expect(find.text('Régimen Trans. Fiscal al Consumidor (Ley 27.743)'), findsOneWidget);
      expect(find.textContaining('Precio s/imp:'), findsOneWidget);
      expect(find.textContaining('- IVA Contenido:'), findsOneWidget);
      expect(find.text('Otros Imp. Nac. Indirectos:'), findsOneWidget);
      expect(find.byType(QrImageView), findsOneWidget);
    });

    testWidgets('R3.9: Non-fiscal thermal receipt with offers & discounts renders savings breakdown & banner at 58mm & 80mm', (WidgetTester tester) async {
      final discountItems = [
        {
          'product_name': 'CONSOLA PLAY STATION 5 PRO DIGITAL 2TB',
          'quantity': 1.0,
          'unit_price': 2155120.0,
          'regular_price': 2693900.0,
          'subtotal': 2155120.0,
          'discount_amount': 538780.0,
          'discount_label': 'Oferta Semanal',
          'has_discount': true,
          'product': {
            'name': 'CONSOLA PLAY STATION 5 PRO DIGITAL 2TB',
            'internal_code': 'G3-1455',
            'selling_price': 2693900.0,
          },
        },
      ];

      await tester.pumpWidget(
        buildAppWrapper(
          child: ThermalReceiptWidget(
            paperWidth: ThermalPaperWidth.mm58,
            businessSettings: testSettings,
            items: discountItems,
            payments: const [
              {'name': 'Efectivo', 'amount': 2155120.0},
            ],
            total: 2155120.0,
            discountAmount: 538780.0,
            discountLabel: 'Ahorro / Descuento',
            tenderedAmount: 2155120.0,
            changeAmount: 0.0,
            saleNumber: '000075',
            cashierName: 'ADMINISTRADOR',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('COMPROBANTE DE VENTA'), findsOneWidget);
      expect(find.text('(Oferta Semanal)'), findsOneWidget);
      expect(find.text('SUBTOTAL LISTA:'), findsOneWidget);
      expect(find.text('AHORRO / DESCUENTO:'), findsOneWidget);
      expect(find.text('TOTAL COBRADO:'), findsOneWidget);
      expect(find.text('*** ¡USTED AHORRÓ: \$2.155.120! ***'), findsNothing); // sanity check
      expect(find.textContaining('¡USTED AHORRÓ:'), findsOneWidget);
    });

    testWidgets('R3.10: Item quantity displays "X x \$price" without "un" suffix for space optimization', (WidgetTester tester) async {
      await tester.pumpWidget(
        buildAppWrapper(
          child: ThermalReceiptWidget(
            paperWidth: ThermalPaperWidth.mm58,
            businessSettings: testSettings,
            items: testItems, // 10 units of cement (non-weight) and 2.75 kg of sand (weight)
            payments: testPayments,
            total: 186738.88,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // Unit item (non-weight): should be "10 x $12.500", NOT "10 un x $12.500"
      expect(find.textContaining('10 x \$12.500'), findsOneWidget);
      expect(find.textContaining('un x'), findsNothing);

      // Weight item: should retain "kg" unit
      expect(find.textContaining('2.75 kg x \$22.450,50'), findsOneWidget);
    });

    testWidgets(
        'R3.11: Long ARCA Padron address wraps cleanly in Fiscal & Non-Fiscal at 58mm & 80mm without FittedBox squishing',
        (WidgetTester tester) async {
      const longAddress =
          'YRIGOYEN HIPOLITO 201 PISO 2 DPTO B, CIUDAD AUTONOMA DE BUENOS AIRES';

      // ── 1. Fiscal Receipt at 58mm (210px viewport) ──
      tester.view.physicalSize = const Size(210, 1500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fiscalInvoiceWithLongAddress = Map<String, dynamic>.from(testFiscalInvoice)
        ..['receiver_name'] = 'PRUEBA F713 WEB 2'
        ..['doc_number'] = '33-69345023-9'
        ..['receiver_address'] = longAddress;

      await tester.pumpWidget(
        buildAppWrapper(
          child: ThermalReceiptWidget(
            paperWidth: ThermalPaperWidth.mm58,
            businessSettings: testSettings,
            items: testItems,
            payments: testPayments,
            total: 186738.88,
            electronicInvoice: fiscalInvoiceWithLongAddress,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('PRUEBA F713 WEB 2'), findsOneWidget);
      expect(find.textContaining('DOMICILIO:'), findsOneWidget);
      expect(find.textContaining(longAddress), findsOneWidget);

      // Verify that DOMICILIO text is NOT inside a FittedBox (which would squish it)
      final addressFinder = find.textContaining(longAddress);
      final fittedBoxAncestor = find.ancestor(
        of: addressFinder,
        matching: find.byType(FittedBox),
      );
      expect(fittedBoxAncestor, findsNothing,
          reason: 'Address must wrap naturally without FittedBox downscaling');

      // ── 2. Non-Fiscal Receipt at 58mm with customerDoc and customerAddress ──
      await tester.pumpWidget(
        buildAppWrapper(
          child: const ThermalReceiptWidget(
            paperWidth: ThermalPaperWidth.mm58,
            items: [],
            total: 5000.0,
            customerName: 'PRUEBA F713 WEB 2',
            customerDoc: '33-69345023-9',
            customerAddress: longAddress,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('COMPROBANTE DE VENTA'), findsOneWidget);
      expect(find.textContaining('PRUEBA F713 WEB 2'), findsOneWidget);
      expect(find.textContaining('DOC / CUIT:'), findsOneWidget);
      expect(find.textContaining('DOMICILIO:'), findsOneWidget);
      expect(find.textContaining(longAddress), findsOneWidget);

      final nonFiscalFittedBoxAncestor = find.ancestor(
        of: find.textContaining(longAddress),
        matching: find.byType(FittedBox),
      );
      expect(nonFiscalFittedBoxAncestor, findsNothing);

      // ── 3. Fiscal Receipt at 80mm (290px viewport) ──
      tester.view.physicalSize = const Size(290, 1500);
      await tester.pumpWidget(
        buildAppWrapper(
          child: ThermalReceiptWidget(
            paperWidth: ThermalPaperWidth.mm80,
            businessSettings: testSettings,
            items: testItems,
            payments: testPayments,
            total: 186738.88,
            electronicInvoice: fiscalInvoiceWithLongAddress,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.textContaining(longAddress), findsOneWidget);
    });

    testWidgets(
        'R3.12: Delivery note / Remito with long delivery address wraps multiline at 58mm without overflow',
        (WidgetTester tester) async {
      const longDeliveryAddress =
          'AV. PTE. ROQUE SAENZ PENA 1145 PISO 8 DPTO 14, CIUDAD AUTONOMA DE BUENOS AIRES';

      tester.view.physicalSize = const Size(210, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final deliveryNoteLong = {
        'id': 991,
        'status': 'delivered',
        'sale': {
          'delivery_address': longDeliveryAddress,
          'customer': {
            'name': 'SOCIEDAD COMERCIAL E INDUSTRIAL DEL SUR SOCIEDAD ANONIMA',
            'document_number': '30-71122334-5',
          },
        },
      };

      await tester.pumpWidget(
        buildAppWrapper(
          child: ThermalReceiptWidget(
            paperWidth: ThermalPaperWidth.mm58,
            businessSettings: testSettings,
            items: testItems,
            total: 50000.0,
            deliveryNote: deliveryNoteLong,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('REMITO — ENTREGA INMEDIATA'), findsOneWidget);
      expect(find.textContaining('ENTREGA:'), findsOneWidget);
      expect(find.textContaining(longDeliveryAddress), findsOneWidget);

      final deliveryFittedBoxAncestor = find.ancestor(
        of: find.textContaining(longDeliveryAddress),
        matching: find.byType(FittedBox),
      );
      expect(deliveryFittedBoxAncestor, findsNothing,
          reason: 'Delivery address must wrap naturally without FittedBox');
    });
  });
}
