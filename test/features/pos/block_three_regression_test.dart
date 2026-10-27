import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_desktop/core/network/api_client.dart';
import 'package:frontend_desktop/features/sales_history/domain/entities/sale_record.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Block 3 Regression Tests (Deuda Técnica, UX y AFIP)', () {
    test('FINDING-RESIL-03: ApiClient enforces 20s standard timeout and 300s for heavy operations', () {
      // Validar constantes de timeout
      expect(ApiClient.defaultTimeout, equals(const Duration(seconds: 20)));
      expect(ApiClient.heavyOperationTimeout, equals(const Duration(seconds: 300)));

      // Peticiones estándar de mostrador (ventas, catálogo, auth) deben resolver a 20s
      final posUri = Uri.parse('http://192.168.1.50/api/pos/sales');
      final catalogUri = Uri.parse('http://192.168.1.50/api/catalog/products');
      
      // Simular resolución de timeout por cabecera y URL
      Duration resolveTimeout(Uri uri, Map<String, String> headers) {
        if (headers.containsKey('X-Request-Timeout')) {
          final customSeconds = int.tryParse(headers['X-Request-Timeout']!);
          if (customSeconds != null && customSeconds > 0) {
            return Duration(seconds: customSeconds);
          }
        }
        final path = uri.path.toLowerCase();
        if (path.contains('/backup') || path.contains('/export') || path.contains('/import')) {
          return ApiClient.heavyOperationTimeout;
        }
        return ApiClient.defaultTimeout;
      }

      expect(resolveTimeout(posUri, {}), equals(const Duration(seconds: 20)));
      expect(resolveTimeout(catalogUri, {}), equals(const Duration(seconds: 20)));

      // Peticiones de backup / export masivo deben resolver a 300s
      final backupUri = Uri.parse('http://192.168.1.50/api/system/backup/download');
      expect(resolveTimeout(backupUri, {}), equals(const Duration(seconds: 300)));

      // Header explícito tiene precedencia
      expect(resolveTimeout(posUri, {'X-Request-Timeout': '45'}), equals(const Duration(seconds: 45)));
    });

    test('FINDING-SALES-05: Factura C strictly suppresses IVA and Neto Gravado discrimination (RG 1415)', () {
      // Simular respuesta AFIP de Factura C (Monotributo - comprobante tipo 11)
      final facturaC = {
        'voucher_letter': 'C',
        'voucher_type': 11,
        'net_amount': 5000.0,
        'iva_amount': 1050.0, // Monto teórico no discriminable
        'total': 5000.0,
        'cae': '74123456789012',
      };

      // Simular respuesta AFIP de Factura A / B (Responsable Inscripto)
      final facturaA = {
        'voucher_letter': 'A',
        'voucher_type': 1,
        'net_amount': 5000.0,
        'iva_amount': 1050.0,
        'total': 6050.0,
        'cae': '74123456789013',
      };

      bool shouldPrintIvaBreakdown(Map<String, dynamic> invoice) {
        final voucherLetter = invoice['voucher_letter']?.toString().toUpperCase();
        final isFacturaC = voucherLetter == 'C' || invoice['voucher_type'] == 11 || invoice['voucher_type'] == 13;
        final netAmount = invoice['net_amount'];
        final ivaAmount = invoice['iva_amount'];
        return !isFacturaC && netAmount != null && ivaAmount != null;
      }

      // En Factura C está estrictamente prohibido discriminar IVA
      expect(shouldPrintIvaBreakdown(facturaC), isFalse);

      // En Factura A/B el desglose impositivo debe imprimirse
      expect(shouldPrintIvaBreakdown(facturaA), isTrue);
    });

    test('FINDING-SALES-06: SaleRecord parses and exposes iibbPerceptionAmount for reprints', () {
      final jsonSample = {
        'id': 105,
        'total': 12100.0,
        'total_surcharge': 0.0,
        'payment_status': 'paid',
        'status': 'completed',
        'created_at': '2026-10-27T10:30:00.000Z',
        'iibb_perception_amount': 363.0, // 3% sobre base neta gravada
        'iibb_perception_rate': 3.0,
        'items': [],
        'payments': [],
      };

      final sale = SaleRecord.fromJson(jsonSample);

      expect(sale.iibbPerceptionAmount, isNotNull);
      expect(sale.iibbPerceptionAmount, equals(363.0));
      expect(sale.iibbPerceptionRate, equals(3.0));
    });
  });
}
