import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend_desktop/core/presentation/widgets/thermal_receipt_widget.dart';
import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/quotes/data/quote_repository.dart';
import 'package:frontend_desktop/features/quotes/presentation/widgets/quote_thermal_receipt_widget.dart';
import 'package:frontend_desktop/features/quotes/presentation/widgets/quote_thermal_preview_dialog.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Quote sampleQuote;
  late BusinessSettings sampleSettings;

  setUp(() {
    SharedPreferences.setMockInitialValues({});

    sampleQuote = Quote(
      id: 2,
      quoteNumber: 'PRES-0002',
      status: 'pending',
      subtotal: 1109900.0,
      total: 1109900.0,
      customerName: 'CROSSFIT CENTRAL FORMOSA',
      customerPhone: '3704-551122',
      notes:
          'Presupuesto por equipamiento para alumnos - Válido 15 días con precio congelado.',
      validUntil: '2026-11-16',
      createdAt: '2026-11-01 12:08:00',
      priceList: 'base',
      items: [
        QuoteItem(
          productId: 101,
          productName:
              'BOTELLA PARA AGUA FLIP GO BOTTLE 709 ML - BLANCO / FROST - 129',
          unitPrice: 91300.0,
          quantity: 5,
          subtotal: 456500.0,
          product: Product(
            id: 101,
            internalCode: 'G3-0334',
            name: 'BOTELLA PARA AGUA FLIP GO BOTTLE 709 ML',
            sellingPrice: 91300.0,
            costPrice: 50000.0,
            stock: 20,
            active: true,
            isSoldByWeight: false,
          ),
        ),
        QuoteItem(
          productId: 102,
          productName: 'CONSERVADORA STANLEY ADVENTURE 15.1 LITROS - CREMA',
          unitPrice: 326700.0,
          quantity: 2,
          subtotal: 653400.0,
          product: Product(
            id: 102,
            internalCode: 'G3-0350',
            name: 'CONSERVADORA STANLEY ADVENTURE 15.1 LITROS',
            sellingPrice: 326700.0,
            costPrice: 200000.0,
            stock: 10,
            active: true,
            isSoldByWeight: false,
          ),
        ),
      ],
    );

    sampleSettings = BusinessSettings(
      companyName: 'Dev4U',
      taxId: '20-39606329-9',
      address: 'Jujuy 152',
      phone: '3704787285',
      taxCondition: 'IVA Responsable Inscripto',
      iibb: '20-39606329-9',
      activityStartDate: '20/03/2022',
    );
  });

  group('QuoteThermalReceiptWidget Tests', () {
    testWidgets('renders 80mm thermal receipt correctly without price freeze text',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: QuoteThermalReceiptWidget(
                paperWidth: ThermalPaperWidth.mm80,
                quote: sampleQuote,
                businessSettings: sampleSettings,
                vendorName: 'ADMINISTRADOR',
              ),
            ),
          ),
        ),
      );

      // Header emisor
      expect(find.text('DEV4U'), findsOneWidget);
      expect(find.text('CUIT: 20-39606329-9'), findsOneWidget);
      expect(find.text('Jujuy 152'), findsOneWidget);
      expect(find.text('IVA RESPONSABLE INSCRIPTO'), findsOneWidget);

      // Tipo de comprobante
      expect(find.text('PRESUPUESTO (X)'), findsOneWidget);
      expect(find.text('Nro: PRES-0002'), findsOneWidget);
      expect(find.text('*** NO VALIDO COMO FACTURA ***'), findsNWidgets(2));

      // Items
      expect(
        find.textContaining('[G3-0334] BOTELLA PARA AGUA FLIP GO BOTTLE'),
        findsOneWidget,
      );
      expect(
        find.textContaining('[G3-0350] CONSERVADORA STANLEY ADVENTURE'),
        findsOneWidget,
      );

      // Totales
      expect(find.text('TOTAL PRESUPUESTO:'), findsOneWidget);
      expect(find.text('UNIDADES COTIZADAS:'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);

      // Barcode data
      expect(find.text('PRES-0002'), findsOneWidget);

      // Observaciones: NO DEBE decir "precio congelado"
      expect(find.textContaining('precio congelado'), findsNothing);
      expect(find.textContaining('con precio congelado'), findsNothing);
      expect(
        find.textContaining('Presupuesto por equipamiento para alumnos'),
        findsOneWidget,
      );
    });

    testWidgets('renders 58mm thermal receipt correctly with compact labels',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: QuoteThermalReceiptWidget(
                paperWidth: ThermalPaperWidth.mm58,
                quote: sampleQuote,
                businessSettings: sampleSettings,
                vendorName: 'ADMINISTRADOR',
              ),
            ),
          ),
        ),
      );

      // 58mm utiliza etiquetas más compactas
      expect(find.text('TOTAL:'), findsOneWidget);
      expect(find.text('UNIDADES:'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
      expect(find.text('PRES-0002'), findsOneWidget);
    });
  });

  group('QuoteThermalPreviewDialog Tests', () {
    testWidgets('shows dialog with 58mm and 80mm format switcher and switches live',
        (tester) async {
      final terminalProvider = LocalTerminalProvider();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<LocalTerminalProvider>.value(
              value: terminalProvider,
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: QuoteThermalPreviewDialog(
                quote: sampleQuote,
                settings: sampleSettings,
                vendorName: 'ADMINISTRADOR',
                initialPaperWidth: ThermalPaperWidth.mm80,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verificar que el diálogo se muestra
      expect(find.text('Ticket PRES-0002'), findsOneWidget);
      expect(find.text('58mm'), findsOneWidget);
      expect(find.text('80mm'), findsOneWidget);
      expect(find.text('Imprimir Ticket (80mm)'), findsOneWidget);
      expect(find.text('TOTAL PRESUPUESTO:'), findsOneWidget);

      // Conmutar a 58mm
      await tester.tap(find.text('58mm'));
      await tester.pumpAndSettle();

      // El botón de acción debe actualizarse dinámicamente a 58mm
      expect(find.text('Imprimir Ticket (58mm)'), findsOneWidget);
      expect(find.text('TOTAL:'), findsOneWidget);

      // Conmutar nuevamente a 80mm
      await tester.tap(find.text('80mm'));
      await tester.pumpAndSettle();

      expect(find.text('Imprimir Ticket (80mm)'), findsOneWidget);
      expect(find.text('TOTAL PRESUPUESTO:'), findsOneWidget);

      // Si la impresora está en 'none', tocar Imprimir no debe dar falso positivo de envío
      await tester.tap(find.text('Imprimir Ticket (80mm)'));
      await tester.pump();
      expect(
        find.textContaining('impresora térmica está desactivada'),
        findsOneWidget,
      );
      expect(find.textContaining('enviado a la impresora'), findsNothing);
    });
  });
}
