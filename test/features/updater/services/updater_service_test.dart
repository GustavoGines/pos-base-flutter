import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_desktop/features/updater/data/services/ota_startup_checker.dart';
import 'dart:io';
import 'package:path/path.dart' as p;

void main() {
  group('Updater State Machine (OTA Startup Checker)', () {
    final installPath = File(Platform.resolvedExecutable).parent.path;
    final resultFile = File(p.join(installPath, 'ota_result.txt'));

    tearDown(() {
      if (resultFile.existsSync()) {
        resultFile.deleteSync();
      }
    });

    test('Transición: Verifica estado de instalación tras reiniciar (SUCCESS)', () {
      // Simulamos que el actualizador externo terminó y escribió el archivo de éxito
      final jsonSuccess = '{"status":"SUCCESS","version":"1.4.5","component":"frontend"}';
      resultFile.writeAsStringSync(jsonSuccess);

      // El OtaStartupChecker lee este archivo al iniciar la app
      final result = OtaStartupChecker.check();

      expect(result, isNotNull);
      expect(result!.success, true);
      expect(result.component, 'frontend');
      expect(result.version, '1.4.5');
    });

    test('Transición: Verifica limpieza tras leer el estado de actualización', () {
      resultFile.writeAsStringSync('SUCCESS');
      
      final result = OtaStartupChecker.check();
      expect(result?.success, true);

      // Una vez consumido el mensaje, la app debe limpiar el estado para no mostrarlo de nuevo
      OtaStartupChecker.clearState();
      
      expect(resultFile.existsSync(), false);
      expect(OtaStartupChecker.check(), null);
    });
  });
}
