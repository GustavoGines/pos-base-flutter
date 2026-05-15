import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';

void main() {
  group('LocalTerminalProvider (Hardware)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('Persistencia correcta del puerto y formato de impresora', () async {
      final provider = LocalTerminalProvider();
      
      // Esperamos que lea los valores iniciales por defecto (mock = vacío)
      await Future.delayed(Duration.zero);
      expect(provider.printerFormat, 'thermal_80');
      expect(provider.printerConnection, 'none');

      // Cambiamos configuración de impresora (Ej. COM3 y A4)
      await provider.setPrinterFormat('a4');
      await provider.setPrinterNameOrIp('COM3');
      await provider.setPrinterConnection('usb');

      // Validamos que el estado en memoria se actualizó
      expect(provider.printerFormat, 'a4');
      expect(provider.printerNameOrIp, 'COM3');
      expect(provider.printerConnection, 'usb');

      // Validamos que se guardó correctamente en SharedPreferences simuladas
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('local_printer_format'), 'a4');
      expect(prefs.getString('local_printer_name_or_ip'), 'COM3');
      expect(prefs.getString('local_printer_connection'), 'usb');
    });
  });
}
