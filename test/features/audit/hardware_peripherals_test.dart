import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import 'package:frontend_desktop/core/utils/scale_serial_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ScaleSerialService Frame Parser & Hardening Tests', () {
    test('Parsea tramas estándar con signo y unidades (Systel Cuora / Toledo)', () {
      const raw = 'ST,GS,+0001.250kg\r\n';
      final weight = ScaleSerialService.parseWeightString(raw);
      expect(weight, equals(1.250));
    });

    test('Parsea tramas inestables con decimales (Kretz Report / Aura) en fallback final', () {
      const raw = 'US,GS,+0000.500kg\r\n';
      final weight = ScaleSerialService.parseWeightString(raw);
      expect(weight, equals(0.500));
    });

    test('En modo requireCompleteFrame=true ignora tramas US inestables hasta recibir una estable ST', () {
      const onlyUnstable = 'US,GS,+0001.210kg\r\n';
      expect(
        ScaleSerialService.parseWeightString(onlyUnstable, requireCompleteFrame: true),
        isNull,
      );

      const unstableThenStable = 'US,GS,+0001.210kg\r\nST,GS,+0001.258kg\r\n';
      expect(
        ScaleSerialService.parseWeightString(unstableThenStable, requireCompleteFrame: true),
        equals(1.258),
      );
    });

    test('Descarta colas truncadas al final del buffer serial continuo (anti-corte de 3er decimal)', () {
      const truncatedStream = '01.258\r\n01.258\r\n01.2';
      final weight = ScaleSerialService.parseWeightString(truncatedStream);
      expect(weight, equals(1.258));
    });

    test('Descarta tanto cabeza como cola truncadas cuando se abre el puerto en medio de una ráfaga', () {
      const noisyStream = '58\r\n01.258\r\n01.25';
      final weight = ScaleSerialService.parseWeightString(noisyStream);
      expect(weight, equals(1.258));
    });

    test('En modo requireCompleteFrame=true retorna null si el paquete aún no tiene delimitador CR/LF', () {
      const partialChunk = '01.25';
      expect(
        ScaleSerialService.parseWeightString(partialChunk, requireCompleteFrame: true),
        isNull,
      );
      expect(
        ScaleSerialService.parseWeightString(partialChunk, requireCompleteFrame: false),
        equals(1.25),
      );
    });

    test('Parsea formato con coma decimal (Argentina)', () {
      const raw = '001,450\r\n';
      final weight = ScaleSerialService.parseWeightString(raw);
      expect(weight, equals(1.450));
    });

    test('Parsea tramas continuas simples', () {
      const raw = '01.250\r\n';
      final weight = ScaleSerialService.parseWeightString(raw);
      expect(weight, equals(1.250));
    });

    test('Parsea formato comando P (Systel Croma / Bumerang / Moretti)', () {
      const raw = 'P 002.300\r';
      final weight = ScaleSerialService.parseWeightString(raw);
      expect(weight, equals(2.300));
    });

    test('Parsea tramas con prefijo igual (=)', () {
      const raw = '=00.750\r';
      final weight = ScaleSerialService.parseWeightString(raw);
      expect(weight, equals(0.750));
    });

    test('Parsea formato con espacios entre signo y número', () {
      const raw = '+  1.250 kg\r\n';
      final weight = ScaleSerialService.parseWeightString(raw);
      expect(weight, equals(1.250));
    });

    test('Detecta correctamente balanza en cero', () {
      const raw = 'ST,GS,+0000.000kg\r\n';
      final weight = ScaleSerialService.parseWeightString(raw);
      expect(weight, equals(0.0));
    });

    test('Retorna null ante tramas vacías o solo texto sin números', () {
      expect(ScaleSerialService.parseWeightString(''), isNull);
      expect(ScaleSerialService.parseWeightString('ERROR'), isNull);
      expect(ScaleSerialService.parseWeightString('\r\n'), isNull);
    });

    test('Extrae la última lectura completa si el stream acumuló múltiples tramas continuas', () {
      const streamAccum = '01.200\r\n01.230\r\n01.250\r\n';
      final weight = ScaleSerialService.parseWeightString(streamAccum);
      expect(weight, equals(1.250));
    });
  });

  group('Bloque 2 - LocalTerminalProvider Peripherals Persistence & v1.8.5 Compatibility', () {
    test('Mantiene valores por defecto retrocompatibles con clientes v1.8.5 (autoOpenCashDrawer=true, scaleComPort="")', () async {
      SharedPreferences.setMockInitialValues({
        'local_printer_format': 'thermal_80',
        'local_printer_connection': 'usb',
        'local_printer_name_or_ip': 'POS-80',
      });

      final provider = LocalTerminalProvider();
      await Future.delayed(const Duration(milliseconds: 50));

      expect(provider.isInitialized, isTrue);
      expect(provider.printerFormat, equals('thermal_80'));
      expect(provider.printerConnection, equals('usb'));
      expect(provider.printerNameOrIp, equals('POS-80'));
      expect(provider.autoOpenCashDrawer, isTrue);
      expect(provider.scaleComPort, isEmpty);
      expect(provider.mpPointDeviceId, isEmpty);
    });

    test('Persiste correctamente scaleComPort, autoOpenCashDrawer y mpPointDeviceId en SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});

      final provider = LocalTerminalProvider();
      await Future.delayed(const Duration(milliseconds: 50));

      await provider.setScaleComPort('COM4');
      await provider.setAutoOpenCashDrawer(false);
      await provider.setMpPointDeviceId('PAX_A910__SMARTPOS999');

      expect(provider.scaleComPort, equals('COM4'));
      expect(provider.autoOpenCashDrawer, isFalse);
      expect(provider.mpPointDeviceId, equals('PAX_A910__SMARTPOS999'));

      // Verificar que una nueva instancia recupere los valores persistidos
      final reloaded = LocalTerminalProvider();
      await Future.delayed(const Duration(milliseconds: 50));

      expect(reloaded.scaleComPort, equals('COM4'));
      expect(reloaded.autoOpenCashDrawer, isFalse);
      expect(reloaded.mpPointDeviceId, equals('PAX_A910__SMARTPOS999'));
    });
  });
}
