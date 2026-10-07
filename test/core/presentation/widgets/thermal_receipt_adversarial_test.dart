import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:frontend_desktop/core/presentation/widgets/thermal_receipt_widget.dart';
import 'package:frontend_desktop/core/presentation/widgets/ticket_preview_dialog.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/pos/domain/entities/cart_item.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';

void main() {
  // ── Fixtures de prueba adversarial ──
  final extremeSettings = BusinessSettings(
    companyName:
        'ESTABLECIMIENTOS METALÚRGICOS Y CORRALÓN GENERAL DE MATERIALES INDUSTRIALES DE LA REPÚBLICA ARGENTINA SOCIEDAD ANÓNIMA',
    taxId: '30-99999999-9',
    address:
        'Avenida Brigadier General Don Juan Manuel de Rosas 123456 Piso 18 Departamento 402 Complejo Logístico Norte',
    phone: '+54 11 4455-6677 / +54 11 9988-7766 / Cel: +54 9 11 3322-1100',
  );

  final standardSettings = BusinessSettings(
    companyName: 'Ferretería El Progreso',
    taxId: '30-71234567-8',
    address: 'Av. San Martín 123',
    phone: '11-4455-6677',
  );

  final astronomicalItems = [
    CartItem(
      product: Product(
        id: 101,
        name:
            'PERFIL IPN HIERRO ACERO NORMALIZADO 300MM X 12 METROS LARGO PESADO ESTRUCTURAL', // 81 chars
        internalCode: 'IPN300-EXTREME-HEAVY-DUTY-STEEL-BEAM-001',
        costPrice: 500000000.0,
        sellingPrice: 999999999.99,
        stock: 500.0,
        active: true,
        isSoldByWeight: false,
      ),
      quantity: 1.0,
    ),
    CartItem(
      product: Product(
        id: 102,
        name:
            'VIBRADOR INDUSTRIAL DE HORMIGÓN ALTA FRECUENCIA CON TRIPODE REFORZADO Y MOTOR', // 81 chars
        internalCode: 'VIB999',
        costPrice: 200000000.0,
        sellingPrice: 450000000.50,
        stock: 20.0,
        active: true,
        isSoldByWeight: true,
      ),
      quantity: 999.875,
    ),
  ];

  final astronomicalPayments = [
    {
      'name': 'TRANSFERENCIA INTERBANCARIA DIRECTA SANTANDER RIO CUENTA CORRIENTE EMPRESAS',
      'amount': 999999999.99,
    },
    {
      'name': 'MERCADO PAGO QR POINT SMART COBRO DIGITAL TARJETA CORPORATIVA PLATINUM',
      'amount': 850000000.00,
    },
  ];

  final astronomicalFiscalInvoice = {
    'voucher_type': 1,
    'voucher_letter': 'A',
    'point_of_sale': 4,
    'voucher_number': 99999999,
    'formatted_number': '00004-99999999',
    'cae': '99887766554433',
    'cae_expiration': '2026-12-31',
    'qr_data':
        'https://www.afip.gob.ar/fe/qr/?p=eyJ2ZXIiOjEsImZjaGEiOiIyMDI2LTEwLTA3IiwidG90YWwiOjk5OTk5OTk5OS45OX0=',
    'net_amount': 826446280.98,
    'iva_amount': 173553719.01,
    'receiver_name':
        'CONSORCIO DE COPROPIETARIOS EDIFICIO TORRE DEL PARQUE INTERCONTINENTAL SOCIEDAD ANÓNIMA',
    'doc_type': 80,
    'doc_number': '30-99887766-5',
    'receiver_tax_condition':
        'IVA RESPONSABLE INSCRIPTO AGENTE DE RETENCIÓN ESPECIAL ARBA',
  };

  final extremeDeliveryNote = {
    'id': 999999,
    'sale': {
      'delivery_address':
          'Ruta Provincial 88 Kilómetro 14 Parque Industrial General Savio Parcela 34 Manzana 12 Galpón 5 Nave B',
    },
  };

  Widget buildWrapper({required Widget child, double? width}) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SingleChildScrollView(
          child: width != null
              ? SizedBox(
                  width: width,
                  child: child,
                )
              : child,
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // GRUPO 1: ESPECTRO DE ANCHOS EXTREMOS (180px, 200px, 210px, 250px, 280px, 290px)
  // ═════════════════════════════════════════════════════════════════════════
  group('Adversarial Spectrum: Tight Widths (180px - 290px)', () {
    final widths = [180.0, 200.0, 210.0, 250.0, 280.0, 290.0];

    for (final width in widths) {
      testWidgets(
          'ADV-W-58mm: Fiscal receipt renders at ${width.toInt()}px width without RenderFlex overflow',
          (tester) async {
        tester.view.physicalSize = Size(width, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          buildWrapper(
            width: width,
            child: ThermalReceiptWidget(
              paperWidth: ThermalPaperWidth.mm58,
              businessSettings: extremeSettings,
              items: astronomicalItems,
              payments: astronomicalPayments,
              total: 999999999.99,
              surchargeAmount: 50000000.00,
              shippingCost: 25000000.00,
              tenderedAmount: 1000000000.00,
              changeAmount: 1.00,
              electronicInvoice: astronomicalFiscalInvoice,
              deliveryNote: extremeDeliveryNote,
              saleNumber: '999999',
              cashierName: 'Maximiliano de la Santísima Trinidad Rodríguez',
              customerName:
                  'Consorcio de Copropietarios Edificio Torre del Parque Intercontinental',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull,
            reason: 'Zero RenderFlex overflow allowed at width ${width.toInt()}px (58mm profile)');
        expect(find.byType(ThermalReceiptWidget), findsOneWidget);
        expect(find.byType(QrImageView), findsOneWidget);
      });

      testWidgets(
          'ADV-W-80mm: Fiscal receipt renders at ${width.toInt()}px width without RenderFlex overflow',
          (tester) async {
        tester.view.physicalSize = Size(width, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          buildWrapper(
            width: width,
            child: ThermalReceiptWidget(
              paperWidth: ThermalPaperWidth.mm80,
              businessSettings: extremeSettings,
              items: astronomicalItems,
              payments: astronomicalPayments,
              total: 999999999.99,
              surchargeAmount: 50000000.00,
              shippingCost: 25000000.00,
              tenderedAmount: 1000000000.00,
              changeAmount: 1.00,
              electronicInvoice: astronomicalFiscalInvoice,
              deliveryNote: extremeDeliveryNote,
              saleNumber: '999999',
              cashierName: 'Maximiliano de la Santísima Trinidad Rodríguez',
              customerName:
                  'Consorcio de Copropietarios Edificio Torre del Parque Intercontinental',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull,
            reason: 'Zero RenderFlex overflow allowed at width ${width.toInt()}px (80mm profile)');
        expect(find.byType(ThermalReceiptWidget), findsOneWidget);
        expect(find.byType(QrImageView), findsOneWidget);
      });
    }
  });

  // ═════════════════════════════════════════════════════════════════════════
  // GRUPO 2: NOMBRES DE PRODUCTOS EXTREMOS (>= 80 y 120 CARACTERES)
  // ═════════════════════════════════════════════════════════════════════════
  group('Adversarial Stress: Extreme Product Names (80+ characters)', () {
    testWidgets(
        'ADV-PROD-80: 80-char and 120-char product names wrap cleanly without horizontal overflow at 180px',
        (tester) async {
      tester.view.physicalSize = const Size(180, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final longNameItems = [
        CartItem(
          product: Product(
            id: 201,
            // 85 characters:
            name:
                'AMOLADORA ANGULAR DEWALT DWE4020 800W 115MM 12000RPM INDUSTRIAL ERGONÓMICA CON TRABA',
            internalCode: 'DWE4020',
            costPrice: 45000.0,
            sellingPrice: 89999.99,
            stock: 10.0,
            active: true,
            isSoldByWeight: false,
          ),
          quantity: 2.0,
        ),
        CartItem(
          product: Product(
            id: 202,
            // 120 characters:
            name:
                'SET DE HERRAMIENTAS MECÁNICAS PROFESIONALES EN VALIJA METÁLICA CROMO VANADIO 150 PIEZAS CON BOCALLAVES Y LLAVES COMBINADAS',
            internalCode: 'SET150',
            costPrice: 120000.0,
            sellingPrice: 249999.00,
            stock: 5.0,
            active: true,
            isSoldByWeight: false,
          ),
          quantity: 1.0,
        ),
        // Item passing as Map<String, dynamic> with 95 characters:
        {
          'product_name':
              'PINTURA LÁTEX PROFESIONAL PARA EXTERIORES E INTERIORES ANTIHONGOS SUPER LAVABLE BALDE 20 LITROS BLANCO',
          'quantity': 3.5,
          'unit_price': 158900.00,
          'subtotal': 556150.00,
          'is_sold_by_weight': true,
        },
      ];

      await tester.pumpWidget(
        buildWrapper(
          width: 180,
          child: ThermalReceiptWidget(
            paperWidth: ThermalPaperWidth.mm58,
            businessSettings: standardSettings,
            items: longNameItems,
            total: 895998.98,
            saleNumber: '000555',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull,
          reason: '80+ char product names must wrap with zero overflow');
    });

    testWidgets(
        'ADV-PROD-UNBROKEN: Single unbroken word tokens (e.g. 60+ chars) do not crash or produce RenderFlex overflow',
        (tester) async {
      tester.view.physicalSize = const Size(180, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final unbrokenItems = [
        {
          'product_name': 'WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW',
          'quantity': 1.0,
          'unit_price': 100.0,
          'subtotal': 100.0,
          'is_sold_by_weight': false,
        },
      ];

      await tester.pumpWidget(
        buildWrapper(
          width: 180,
          child: ThermalReceiptWidget(
            paperWidth: ThermalPaperWidth.mm58,
            businessSettings: standardSettings,
            items: unbrokenItems,
            total: 100.0,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // GRUPO 3: CIFRAS MONETARIAS ASTRONÓMICAS ($999.999.999,99)
  // ═════════════════════════════════════════════════════════════════════════
  group('Adversarial Stress: Astronomical Currency Figures', () {
    testWidgets(
        'ADV-CURR-ASTRO: \$999.999.999,99 figures in unit prices, subtotals, tender & change do not overflow at 180px',
        (tester) async {
      tester.view.physicalSize = const Size(180, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final astroItems = [
        {
          'product': {'name': 'TRACTOR ORUGA PESADO INDUSTRIAL'},
          'quantity': '1',
          'unit_price': '999999999.99',
          'subtotal': '999999999.99',
          'is_sold_by_weight': false,
        },
        {
          'product': {'name': 'CARGAMENTO DE COBRE PURO EN BARRAS'},
          'quantity': '99999.99',
          'unit_price': '999999999.99',
          'subtotal': '99999999999.99',
          'is_sold_by_weight': true,
        },
      ];

      await tester.pumpWidget(
        buildWrapper(
          width: 180,
          child: ThermalReceiptWidget(
            paperWidth: ThermalPaperWidth.mm58,
            businessSettings: extremeSettings,
            items: astroItems,
            total: 999999999.99,
            surchargeAmount: 999999999.99,
            shippingCost: 999999999.99,
            tenderedAmount: 999999999.99,
            changeAmount: 999999999.99,
            payments: [
              {'name': 'TRANSFERENCIA DÓLARES CABLE', 'amount': 999999999.99},
              {'name': 'CHEQUE ELECTRONICO ECHEQ DIFERIDO', 'amount': 999999999.99},
            ],
            electronicInvoice: astronomicalFiscalInvoice,
            deliveryNote: extremeDeliveryNote,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull,
          reason: 'FittedBox and layout constraints must prevent overflow with astronomical figures');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // GRUPO 4: DATOS DEL CLIENTE Y DIRECCIONES EXTREMADAMENTE LARGAS
  // ═════════════════════════════════════════════════════════════════════════
  group('Adversarial Stress: Extreme Customer & Address Strings', () {
    testWidgets(
        'ADV-CUST-LONG: Customer name (100 chars) and long addresses wrap gracefully at 180px and 210px',
        (tester) async {
      tester.view.physicalSize = const Size(180, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const extremeCustomer =
          'MARÍA DE LOS ÁNGELES DE LA SANTÍSIMA CONCEPCIÓN GONZÁLEZ Y FERNÁNDEZ DE LA PUERTA SOCIEDAD DE HECHO';

      await tester.pumpWidget(
        buildWrapper(
          width: 180,
          child: ThermalReceiptWidget(
            paperWidth: ThermalPaperWidth.mm58,
            businessSettings: extremeSettings,
            items: [
              {
                'product_name': 'CLAVOS 2 PULGADAS',
                'quantity': 1,
                'unit_price': 1500,
                'subtotal': 1500,
              }
            ],
            total: 1500,
            customerName: extremeCustomer,
            electronicInvoice: {
              ...astronomicalFiscalInvoice,
              'receiver_name': extremeCustomer,
              'doc_number': '30-1234567890123-9',
              'receiver_tax_condition':
                  'RESPONSABLE INSCRIPTO EXENTO DE INGRESOS BRUTOS Y SELLOS PROVINCIALES',
            },
            deliveryNote: {
              'id': 123456,
              'sale': {
                'delivery_address':
                    'Calle de las Tres Cruces entre Pasaje del Milagro y Boulevard Juan Bautista Alberdi Nro 45678 Piso 12 Dpto C Timbre 4',
              },
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // GRUPO 5: MANEJO DEFENSIVO DE CAMPOS NULOS Y MAPAS VACÍOS (NULL SAFETY)
  // ═════════════════════════════════════════════════════════════════════════
  group('Adversarial Stress: Null Safety & Empty Field Handling', () {
    testWidgets(
        'ADV-NULL-MINIMAL: Completely empty/null configuration produces zero crashes or exceptions',
        (tester) async {
      tester.view.physicalSize = const Size(210, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        buildWrapper(
          child: const ThermalReceiptWidget(
            paperWidth: ThermalPaperWidth.mm58,
            businessSettings: null,
            items: [],
            payments: [],
            total: 0.0,
            electronicInvoice: null,
            deliveryNote: null,
            saleNumber: null,
            cashierName: null,
            customerName: null,
            dateTime: null,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('MI NEGOCIO'), findsOneWidget);
      expect(find.text('COMPROBANTE DE VENTA'), findsOneWidget);
    });

    testWidgets(
        'ADV-NULL-EMPTY-MAPS: Items, invoice, and deliveryNote with empty maps {} render safely',
        (tester) async {
      tester.view.physicalSize = const Size(210, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final emptyMapItems = [
        <String, dynamic>{},
        {
          'product': null,
          'product_name': null,
          'quantity': null,
          'unit_price': null,
          'subtotal': null,
          'is_sold_by_weight': null,
        },
      ];

      final emptyFiscalInvoice = <String, dynamic>{
        'voucher_type': null,
        'voucher_letter': null,
        'point_of_sale': null,
        'voucher_number': null,
        'formatted_number': null,
        'cae': null,
        'cae_expiration': null,
        'qr_data': null,
        'net_amount': null,
        'iva_amount': null,
        'receiver_name': null,
        'doc_number': null,
        'receiver_tax_condition': null,
      };

      final emptyDeliveryNote = <String, dynamic>{
        'id': null,
        'sale': null,
      };

      await tester.pumpWidget(
        buildWrapper(
          child: ThermalReceiptWidget(
            paperWidth: ThermalPaperWidth.mm58,
            businessSettings: null,
            items: emptyMapItems,
            payments: const [
              <String, dynamic>{},
              {'name': null, 'amount': null},
            ],
            total: 0.0,
            electronicInvoice: emptyFiscalInvoice,
            deliveryNote: emptyDeliveryNote,
            saleNumber: '',
            cashierName: '',
            customerName: '',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('PRODUCTO'), findsNWidgets(4));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // GRUPO 6: TICKET PREVIEW DIALOG CHROME EN VIEWPORTS ESTRECHOS (280px)
  // ═════════════════════════════════════════════════════════════════════════
  group('Adversarial Stress: TicketPreviewDialog Narrow Viewports (280px)', () {
    testWidgets(
        'ADV-DLG-280-MODAL: TicketPreviewDialog via showDialog at 280x600 viewport does not overflow dialog chrome',
        (tester) async {
      tester.view.physicalSize = const Size(280, 600);
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
                      title:
                          'Vista Previa — Ticket Fiscal Térmico de Venta con Remito Asociado y Facturación Electrónica AFIP', // Very long title
                      paperWidth: ThermalPaperWidth.mm58,
                      receiptWidget: ThermalReceiptWidget(
                        paperWidth: ThermalPaperWidth.mm58,
                        businessSettings: standardSettings,
                        items: astronomicalItems,
                        total: 999999999.99,
                        electronicInvoice: astronomicalFiscalInvoice,
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

      // Open dialog
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull,
          reason: 'TicketPreviewDialog chrome must not overflow at 280x600');
      expect(find.byType(TicketPreviewDialog), findsOneWidget);
      expect(find.byType(OutlinedButton), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);

      // Verify button tap dismisses dialog
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(find.byType(TicketPreviewDialog), findsNothing);
    });

    testWidgets(
        'ADV-DLG-280-COMPACT: TicketPreviewDialog at 280x480 ultra-narrow & short screen does not overflow',
        (tester) async {
      tester.view.physicalSize = const Size(280, 480);
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
                      title: 'Ticket 58mm',
                      paperWidth: ThermalPaperWidth.mm58,
                      receiptWidget: ThermalReceiptWidget(
                        paperWidth: ThermalPaperWidth.mm58,
                        businessSettings: standardSettings,
                        items: [
                          {
                            'product_name': 'ARTÍCULO DE PRUEBA',
                            'quantity': 1,
                            'unit_price': 100,
                            'subtotal': 100,
                          }
                        ],
                        total: 100.0,
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull,
          reason: 'TicketPreviewDialog must fit within 280x480 without overflow');
      expect(find.byType(TicketPreviewDialog), findsOneWidget);
    });

    testWidgets(
        'ADV-DLG-DIRECT-WIDGET: TicketPreviewDialog direct widget rendering at 280px with legacy lines',
        (tester) async {
      tester.view.physicalSize = const Size(280, 500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final lines = [
        const TicketLine('EMPRESA CON NOMBRE EXTRAORDINARIAMENTE EXTENSO DE MUCHOS CARACTERES',
            isBold: true, isLarge: true, align: TicketAlign.center),
        const TicketLine.hr(),
        const TicketLine('99999 un x \$999.999.999,99', rightText: '\$999.999.999.999,99'),
        const TicketLine(
            'DESCRIPCION MUY LARGA DE UN PRODUCTO VENDIDO CON DETALLE DETALLADO Y ESPECIFICACIONES TECNICAS'),
        const TicketLine.hr(bold: true),
        const TicketLine('TOTAL COBRADO:', rightText: '\$999.999.999.999,99', isBold: true),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TicketPreviewDialog(
              title: 'Vista Previa — Ticket Térmico Directo Legacy',
              lines: lines,
              paperWidth: ThermalPaperWidth.mm80,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull,
          reason: 'Legacy lines mode in TicketPreviewDialog must not overflow at 280px');
      expect(find.text('TOTAL COBRADO:'), findsOneWidget);
    });

    testWidgets(
        'ADV-DLG-CONFIRM: Confirm print callback executes cleanly in TicketPreviewDialog at 280px',
        (tester) async {
      tester.view.physicalSize = const Size(280, 500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      bool printConfirmed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TicketPreviewDialog(
              title: 'Impresión Ticket',
              paperWidth: ThermalPaperWidth.mm58,
              onConfirmPrint: () {
                printConfirmed = true;
              },
              lines: const [
                TicketLine('TEST TICKET', align: TicketAlign.center),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Imprimir'));
      await tester.pumpAndSettle();

      expect(printConfirmed, isTrue);
    });

    testWidgets(
        'ADV-DLG-80MM-280PX-MODAL: TicketPreviewDialog with 80mm receipt at 280x600 viewport fits cleanly',
        (tester) async {
      tester.view.physicalSize = const Size(280, 600);
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
                      title: 'Ticket 80mm Fiscal',
                      paperWidth: ThermalPaperWidth.mm80,
                      receiptWidget: ThermalReceiptWidget(
                        paperWidth: ThermalPaperWidth.mm80,
                        businessSettings: standardSettings,
                        items: astronomicalItems,
                        total: 999999999.99,
                        electronicInvoice: astronomicalFiscalInvoice,
                        deliveryNote: extremeDeliveryNote,
                      ),
                    );
                  },
                  child: const Text('Open 80mm Dialog'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open 80mm Dialog'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(TicketPreviewDialog), findsOneWidget);
    });

    testWidgets(
        'ADV-DLG-CLOSE-BTN: Close icon button in TicketPreviewDialog header dismisses dialog at 280px',
        (tester) async {
      tester.view.physicalSize = const Size(280, 500);
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
                      title: 'Preview',
                      lines: const [TicketLine('TEST')],
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

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.byType(TicketPreviewDialog), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.byType(TicketPreviewDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // GRUPO 7: CASOS LIMÍTROFES ADVERSARIALES AVANZADOS
  // ═════════════════════════════════════════════════════════════════════════
  group('Adversarial Advanced Edge Cases: Malformed Data, Large QR, Many Items', () {
    testWidgets(
        'ADV-EDGE-MALFORMED-STRINGS: Non-numeric strings in numeric fields handled without throwing',
        (tester) async {
      tester.view.physicalSize = const Size(210, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final malformedItems = [
        {
          'product_name': 'ITEM MALFORMADO',
          'quantity': 'not_a_number',
          'unit_price': 'invalid_price',
          'subtotal': 'bad_subtotal',
          'is_sold_by_weight': 'not_a_bool',
        },
      ];

      final malformedInvoice = {
        'voucher_type': 'invalid',
        'voucher_letter': 'A',
        'point_of_sale': 'not_pos',
        'voucher_number': 'not_nro',
        'net_amount': 'abc',
        'iva_amount': 'xyz',
        'cae': '777888999',
        'cae_expiration': '2026-12-31',
      };

      await tester.pumpWidget(
        buildWrapper(
          child: ThermalReceiptWidget(
            paperWidth: ThermalPaperWidth.mm58,
            businessSettings: standardSettings,
            items: malformedItems,
            total: 0.0,
            electronicInvoice: malformedInvoice,
            payments: [
              {'name': 'PAYMENT_TEST', 'amount': 'bad_amount'},
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('ITEM MALFORMADO'), findsOneWidget);
    });

    testWidgets(
        'ADV-EDGE-LARGE-QR: 1000-character ARCA AFIP JWT URL renders in QrImageView without overflow',
        (tester) async {
      tester.view.physicalSize = const Size(180, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final giantQrData =
          'https://www.afip.gob.ar/fe/qr/?p=${'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9' * 25}';

      await tester.pumpWidget(
        buildWrapper(
          width: 180,
          child: ThermalReceiptWidget(
            paperWidth: ThermalPaperWidth.mm58,
            businessSettings: standardSettings,
            items: const [],
            total: 100.0,
            electronicInvoice: {
              'voucher_letter': 'B',
              'formatted_number': '00001-00000001',
              'cae': '12345678901234',
              'cae_expiration': '2026-10-30',
              'qr_data': giantQrData,
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(QrImageView), findsOneWidget);
    });

    testWidgets(
        'ADV-EDGE-100-ITEMS: 100-item fiscal receipt renders cleanly without memory leak or overflow',
        (tester) async {
      tester.view.physicalSize = const Size(210, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final hundredItems = List.generate(
        100,
        (i) => {
          'product_name': 'ARTÍCULO DE FERRETERÍA NÚMERO $i MODELO ESTÁNDAR',
          'quantity': i + 1,
          'unit_price': (i + 1) * 150.50,
          'subtotal': (i + 1) * (i + 1) * 150.50,
        },
      );

      await tester.pumpWidget(
        buildWrapper(
          child: ThermalReceiptWidget(
            paperWidth: ThermalPaperWidth.mm58,
            businessSettings: standardSettings,
            items: hundredItems,
            total: 500000.0,
            electronicInvoice: astronomicalFiscalInvoice,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'ADV-EDGE-REPRINT-FLAG: Reprint indicator and delivery item with huge weight render cleanly',
        (tester) async {
      tester.view.physicalSize = const Size(180, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final deliveryItems = [
        {
          'product_name': 'ARENA GRUESA A GRANEL EMBOLSADA',
          'quantity': 99999.875,
          'is_sold_by_weight': true,
        },
      ];

      await tester.pumpWidget(
        buildWrapper(
          width: 180,
          child: ThermalReceiptWidget(
            paperWidth: ThermalPaperWidth.mm58,
            businessSettings: standardSettings,
            items: deliveryItems,
            total: 25000.0,
            isReprint: true,
            deliveryNote: {
              'id': 1234,
              'sale': {'delivery_address': 'Av. Mitre 500'},
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('[ REIMPRESIÓN ]'), findsOneWidget);
    });
  });
}
