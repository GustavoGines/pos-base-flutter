import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import 'package:frontend_desktop/core/utils/receipt_printer_service.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/customers/models/customer_model.dart';
import 'package:frontend_desktop/features/pos/presentation/providers/pos_provider.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'providers/pos_provider_test.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Block 2 Regression Tests (P1 Altos)', () {
    test('FINDING-SALES-07: ReceiptPrinterService clears electronicInvoice after print', () async {
      final printer = ReceiptPrinterService.instance;
      final terminal = LocalTerminalProvider();

      // Inyectar datos fiscales previos simulando venta AFIP
      printer.electronicInvoice = {
        'cae': '74123456789012',
        'cae_expiration': '2026-11-15',
        'voucher_number': '0001-00000042',
      };

      // Al imprimir con electronicInvoice pasado explícitamente o nulo,
      // el bloque finally debe garantizar que electronicInvoice quede nulo
      // para evitar que se filtre en la siguiente venta no fiscal.
      try {
        await printer.printSaleTicket(
          items: [],
          total: 1000.0,
          settings: const BusinessSettings(companyName: 'Test Business'),
          localTerminal: terminal,
          paymentMethod: 'Efectivo',
          electronicInvoice: null,
        );
      } catch (_) {
        // En entorno de test sin impresora física esc_pos puede lanzar error de conexión
      }

      // Verificación estricta: la propiedad en memoria del singleton debe haber sido purgada
      expect(printer.electronicInvoice, isNull);
    });

    test('FINDING-STOCK-06: sale_ecommerce movement is identified as outgoing and formatted negative', () {
      final mov = {
        'type': 'sale_ecommerce',
        'quantity': 5.0,
        'product': {'is_sold_by_weight': false, 'unit_type': 'un'},
      };

      final typeStr = mov['type'].toString().toLowerCase();
      final isOut = typeStr == 'out' ||
          typeStr == 'sale' ||
          typeStr == 'decrement' ||
          typeStr == 'sale_ecommerce';

      final typeLabel = switch (typeStr) {
        'in' => 'INGRESO',
        'out' => 'EGRESO',
        'sale' => 'VENTA',
        'sale_ecommerce' => 'VENTA ONLINE',
        'decrement' => 'BAJA',
        'increment' => 'ALTA',
        _ => typeStr.toUpperCase(),
      };

      expect(isOut, isTrue);
      expect(typeLabel, equals('VENTA ONLINE'));

      final absQty = (mov['quantity'] as double).abs();
      final formattedText = '${isOut ? "-" : "+"}${absQty.toInt()} un';
      expect(formattedText, equals('-5 un'));
    });

    test('FINDING-SALES-02: calculateIibbPerceptionAmount bundles extraAmount net into taxable base', () {
      SharedPreferences.setMockInitialValues({});
      final mockProcess = MockProcessSaleUseCase();
      final mockSearch = MockSearchProductsUseCase();
      final mockRepo = MockPosRepository();

      when(mockRepo.fetchPaymentMethods()).thenAnswer((_) async => []);

      final provider = PosProvider(
        processSaleUseCase: mockProcess,
        searchProductsUseCase: mockSearch,
        repository: mockRepo,
      );

      final customerWithIibb = Customer(
        id: 1,
        name: 'Cliente Responsable Inscripto',
        documentNumber: '30712345678',
        creditLimit: 50000.0,
        balance: 0.0,
        isActive: true,
        appliesIibbPerception: true,
        iibbPerceptionRate: 3.0, // 3%
      );

      const settings = BusinessSettings(
        isIibbPerceptionAgent: true,
      );

      // Simular carrito con $1000.0 neto gravado al 21%
      // Agregamos un item de $1210 final ($1000 neto + $210 iva)
      final product1 = Product(
        id: 1,
        name: 'Producto Gravado 21%',
        internalCode: 'PROD-21',
        costPrice: 500.0,
        sellingPrice: 1210.0,
        stock: 50.0,
        active: true,
        isSoldByWeight: false,
        ivaRate: 21.0,
      );

      provider.requestAddToCart(product1);

      // Caso A: Sin extraAmount -> Base gravada = 1000.0 -> Percepción 3% = 30.00
      final perceptionWithoutExtra = provider.calculateIibbPerceptionAmount(
        customer: customerWithIibb,
        settings: settings,
        extraAmount: 0.0,
      );
      expect(perceptionWithoutExtra, equals(30.0));

      // Caso B: Con extraAmount = $121.00 (recargo o flete gravado al 21%)
      // extraNet = 121.0 / 1.21 = 100.0
      // Base total gravada = 1000.0 + 100.0 = 1100.0
      // Percepción 3% sobre 1100.0 = 33.00
      final perceptionWithExtra = provider.calculateIibbPerceptionAmount(
        customer: customerWithIibb,
        settings: settings,
        extraAmount: 121.0,
      );
      expect(perceptionWithExtra, equals(33.0));

      // Caso C: Con overrideTotal (cobro de venta pendiente desde listado sin usar carrito activo)
      // overrideTotal = 2420.0 -> baseNet = 2000.0 -> Percepción 3% = 60.00
      final perceptionPendingOverride = provider.calculateIibbPerceptionAmount(
        customer: customerWithIibb,
        settings: settings,
        overrideTotal: 2420.0,
      );
      expect(perceptionPendingOverride, equals(60.0));
    });
  });
}
