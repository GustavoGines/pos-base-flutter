import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:updater/updater_core.dart';

Archive _buildDecodedZipArchive(Map<String, List<int>> files) {
  final rawArchive = Archive();
  for (final entry in files.entries) {
    rawArchive.addFile(ArchiveFile.bytes(entry.key, entry.value));
  }
  final zipBytes = ZipEncoder().encode(rawArchive);
  return ZipDecoder().decodeBytes(zipBytes);
}

void main() {
  group('Extracción Diferencial por Tamaño + CRC-32', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('ota_updater_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test(
        'salta archivos con tamaño y CRC-32 idénticos sin reescribirlos y extrae sólo los modificados/nuevos',
        () {
      final unchangedFile = File(p.join(tempDir.path, 'vendor', 'pkg', 'a.php'))
        ..createSync(recursive: true)
        ..writeAsStringSync('<?php echo "same";');
      final modifiedFile =
          File(p.join(tempDir.path, 'app', 'Services', 'B.php'))
            ..createSync(recursive: true)
            ..writeAsStringSync('<?php echo "old";');

      // Fijamos una fecha de modificación en el pasado para comprobar que el archivo sin cambios no fue tocado
      final oldTimestamp = DateTime.utc(2024, 1, 1, 12, 0, 0);
      unchangedFile.setLastModifiedSync(oldTimestamp);

      final archive = _buildDecodedZipArchive({
        'vendor/pkg/a.php': utf8.encode('<?php echo "same";'),
        'app/Services/B.php': utf8.encode('<?php echo "new";'),
        'app/Models/NewModel.php': utf8.encode('<?php class NewModel {}'),
      });

      final log = OtaLogger(tempDir.path);
      final stats = extractArchiveDifferentially(
        archive: archive,
        targetDir: tempDir.path,
        component: 'backend',
        log: log,
      );

      expect(stats.extractionOk, isTrue);
      expect(stats.filesUnchanged, equals(1));
      expect(stats.filesExtracted, equals(2));
      expect(stats.filesSkipped, equals(0));
      expect(modifiedFile.readAsStringSync(), equals('<?php echo "new";'));
      expect(
        File(p.join(tempDir.path, 'app', 'Models', 'NewModel.php'))
            .readAsStringSync(),
        equals('<?php class NewModel {}'),
      );
      expect(
        unchangedFile.lastModifiedSync().toUtc(),
        equals(oldTimestamp),
        reason:
            'El archivo con CRC-32 idéntico no debe ser abierto ni reescrito en disco.',
      );
    });

    test(
        'en Backend retiene public/version.txt y ota_manifest.json en memoria sin escribirlos prematuramente en Paso 4',
        () {
      final versionFile = File(p.join(tempDir.path, 'public', 'version.txt'))
        ..createSync(recursive: true)
        ..writeAsStringSync('1.8.5');

      final manifestJson = jsonEncode({
        'version': '2.2.0',
        'component': 'backend',
        'scope': 'app',
        'files': ['app/Http/Controllers/Controller.php', 'public/version.txt'],
      });

      final archive = _buildDecodedZipArchive({
        'public/version.txt': utf8.encode('2.2.0\n'),
        'ota_manifest.json': utf8.encode(manifestJson),
        'app/Http/Controllers/Controller.php':
            utf8.encode('<?php class Controller {}'),
      });

      final log = OtaLogger(tempDir.path);
      final stats = extractArchiveDifferentially(
        archive: archive,
        targetDir: tempDir.path,
        component: 'backend',
        log: log,
      );

      expect(stats.extractionOk, isTrue);
      // Durante el Paso 4, public/version.txt sigue siendo 1.8.5 hasta que pasen las migraciones
      expect(versionFile.readAsStringSync(), equals('1.8.5'));
      expect(stats.deferredVersionTxtBytes, isNotNull);
      expect(utf8.decode(stats.deferredVersionTxtBytes!).trim(),
          equals('2.2.0'));

      // ota_manifest.json tampoco se escribe como archivo suelto
      expect(
          File(p.join(tempDir.path, 'ota_manifest.json')).existsSync(), isFalse);
      expect(stats.newManifestBytes, isNotNull);
    });

    test('detecta correctamente si updater.exe cambió o no en el ZIP', () {
      final updaterFile = File(p.join(tempDir.path, 'updater.exe'))
        ..writeAsBytesSync([10, 20, 30, 40, 50]);

      final sameArchive = _buildDecodedZipArchive({
        'updater.exe': [10, 20, 30, 40, 50],
        'Sistema_POS.exe': [1, 2, 3],
      });
      expect(hasUpdaterExeChangedInArchive(sameArchive, tempDir.path), isFalse);

      final changedArchive = _buildDecodedZipArchive({
        'updater.exe': [10, 20, 30, 40, 99],
        'Sistema_POS.exe': [1, 2, 3],
      });
      expect(
          hasUpdaterExeChangedInArchive(changedArchive, tempDir.path), isTrue);

      updaterFile.deleteSync();
      expect(hasUpdaterExeChangedInArchive(sameArchive, tempDir.path), isTrue);
    });

    test(
        'extracción atómica no deja archivos temporales (.ota_tmp_ / .ota_bak_) tras completar con éxito y espeja el log persistente',
        () {
      final persistentLogDir =
          Directory(p.join(tempDir.path, 'persistent_logs'))
            ..createSync(recursive: true);
      final targetFile = File(p.join(tempDir.path, 'vendor', 'pkg', ' safe.php'))
        ..createSync(recursive: true)
        ..writeAsStringSync('<?php // v1');

      final archive = _buildDecodedZipArchive({
        'vendor/pkg/ safe.php': utf8.encode('<?php // v2'),
        'vendor/pkg/new_helper.php': utf8.encode('<?php // helper'),
      });

      final log =
          OtaLogger(tempDir.path, persistentLogDir: persistentLogDir.path);
      log.writeHeader(
        component: 'backend',
        version: '2.1.2',
        zipPath: 'update_backend_v2.1.2.zip',
        targetDir: tempDir.path,
      );

      final stats = extractArchiveDifferentially(
        archive: archive,
        targetDir: tempDir.path,
        component: 'backend',
        log: log,
      );
      log.writeResult(stats.extractionOk);

      expect(stats.extractionOk, isTrue);
      expect(stats.filesExtracted, equals(2));
      expect(stats.filesRolledBack, equals(0));
      expect(targetFile.readAsStringSync(), equals('<?php // v2'));

      // Verificar que no quedaron archivos .ota_tmp_ ni .ota_bak_ residuales
      final remainingTempOrBak = Directory(p.join(tempDir.path, 'vendor'))
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) =>
              f.path.contains('.ota_tmp_') || f.path.contains('.ota_bak_'))
          .toList();
      expect(remainingTempOrBak, isEmpty);

      // Verificar que updater_history.log persistente fue escrito
      final historyFile =
          File(p.join(persistentLogDir.path, 'updater_history.log'));
      expect(historyFile.existsSync(), isTrue);
      expect(historyFile.readAsStringSync(),
          contains('RESULTADO FINAL: SUCCESS'));
    });

    test(
        'rollback transaccional revierte archivos modificados y nuevos si un archivo posterior falla',
        () {
      final firstFile =
          File(p.join(tempDir.path, 'vendor', 'pkg', 'first.php'))
            ..createSync(recursive: true)
            ..writeAsStringSync('<?php // original_first');

      // Creamos un DIRECTORIO donde el ZIP espera un ARCHIVO ('vendor/pkg/conflict.php')
      // para forzar de forma determinista y multiplataforma que renameSync falle en el 3er archivo
      Directory(p.join(tempDir.path, 'vendor', 'pkg', 'conflict.php'))
          .createSync(recursive: true);

      final archive = _buildDecodedZipArchive({
        'vendor/pkg/first.php': utf8.encode('<?php // updated_first'),
        'vendor/pkg/brand_new.php': utf8.encode('<?php // brand_new'),
        'vendor/pkg/conflict.php': utf8.encode('<?php // fails_to_replace_dir'),
      });

      final log = OtaLogger(tempDir.path);
      final stats = extractArchiveDifferentially(
        archive: archive,
        targetDir: tempDir.path,
        component: 'backend',
        log: log,
        rollbackOnPartialFailure: true,
      );

      expect(stats.extractionOk, isFalse);
      expect(stats.filesSkipped, equals(1));
      expect(stats.filesRolledBack, equals(1));

      // first.php debe haber vuelto a su contenido original intacto
      expect(firstFile.readAsStringSync(), equals('<?php // original_first'));
      // brand_new.php debe haberse limpiado durante el rollback
      expect(
          File(p.join(tempDir.path, 'vendor', 'pkg', 'brand_new.php'))
              .existsSync(),
          isFalse);
    });
  });

  group('Poda Segura de Archivos Eliminados (pruneDeletedFilesAndSaveManifest)',
      () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('ota_prune_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test(
        'elimina archivos obsoletos del manifiesto anterior, respeta case-insensitivity de Windows y protege la Blacklist y vendor/ en scope=app',
        () {
      // Crear archivos simulados en targetDir
      final envFile = File(p.join(tempDir.path, '.env'))
        ..writeAsStringSync('APP_KEY=secret');
      final storageCert =
          File(p.join(tempDir.path, 'storage', 'app', 'afip', 'cert.crt'))
            ..createSync(recursive: true)
            ..writeAsStringSync('CERT');
      final vendorFrameworkFile = File(p.join(
          tempDir.path, 'vendor', 'laravel', 'framework', 'src', 'Core.php'))
        ..createSync(recursive: true)
        ..writeAsStringSync('<?php // core');
      final vendorComposerOld =
          File(p.join(tempDir.path, 'vendor', 'composer', 'old_helper.php'))
            ..createSync(recursive: true)
            ..writeAsStringSync('<?php // obsolete composer file');
      final obsoleteService =
          File(p.join(tempDir.path, 'app', 'Services', 'LegacyService.php'))
            ..createSync(recursive: true)
            ..writeAsStringSync('<?php // legacy');
      final renamedCaseService =
          File(p.join(tempDir.path, 'app', 'Services', 'AFIPService.php'))
            ..createSync(recursive: true)
            ..writeAsStringSync('<?php // renamed case');

      // Manifiesto anterior (scope: full)
      final prevManifest = {
        'version': '2.1.0',
        'component': 'backend',
        'scope': 'full',
        'files': [
          '.env', // Aunque por error estuviera en un manifiesto, la blacklist lo protege
          'storage/app/afip/cert.crt', // Protegido por blacklist
          'vendor/laravel/framework/src/Core.php', // Protegido cuando el nuevo ZIP es scope=app
          'vendor/composer/old_helper.php', // Debe borrarse porque vendor/composer/* sí entra en scope=app
          'app/Services/LegacyService.php', // Debe borrarse
          'app/Services/AfipService.php', // Solo cambió casing a AFIPService.php -> NO debe borrarse en NTFS
        ],
      };
      File(p.join(tempDir.path, '.ota_manifest.json'))
          .writeAsStringSync(jsonEncode(prevManifest));

      // Nuevo manifiesto liviano (scope: app)
      final newManifestBytes = Uint8List.fromList(utf8.encode(jsonEncode({
        'version': '2.2.0',
        'component': 'backend',
        'scope': 'app',
        'files': [
          'app/Services/AFIPService.php',
          'vendor/composer/autoload_classmap.php',
        ],
      })));

      final log = OtaLogger(tempDir.path);
      final deleted = pruneDeletedFilesAndSaveManifest(
        targetDir: tempDir.path,
        newManifestBytes: newManifestBytes,
        log: log,
      );

      expect(deleted, equals(2));
      expect(obsoleteService.existsSync(), isFalse,
          reason: 'LegacyService.php debía eliminarse');
      expect(vendorComposerOld.existsSync(), isFalse,
          reason: 'vendor/composer/old_helper.php debía eliminarse');

      // Archivos que DEBEN sobrevivir intactos:
      expect(envFile.existsSync(), isTrue, reason: '.env es intocable');
      expect(storageCert.existsSync(), isTrue,
          reason: 'storage/** es intocable');
      expect(vendorFrameworkFile.existsSync(), isTrue,
          reason: 'vendor/* fuera de vendor/composer/* no se toca en scope=app');
      expect(renamedCaseService.existsSync(), isTrue,
          reason:
              'Un cambio de mayúsculas/minúsculas no debe borrar el archivo en Windows NTFS');

      // El nuevo .ota_manifest.json debe haber preservado la entrada de vendor/laravel/...
      final savedManifest = jsonDecode(
              File(p.join(tempDir.path, '.ota_manifest.json'))
                  .readAsStringSync())
          as Map<String, dynamic>;
      final savedFiles = (savedManifest['files'] as List).cast<String>();
      expect(
          savedFiles, contains('vendor/laravel/framework/src/Core.php'));
    });
  });

  group('Saneamiento Idempotente de .env (ensureBackendEnvVariables)', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('ota_env_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test(
        'inyecta variables faltantes o comentadas sin tocar credenciales existentes',
        () {
      final envFile = File(p.join(tempDir.path, '.env'))
        ..writeAsStringSync([
          'APP_NAME=MiComercio',
          'APP_KEY=base64:existente123',
          'DB_DATABASE=pos_cliente',
          '# REVERB_HOST=127.0.0.1',
          'QUEUE_CONNECTION=database',
        ].join('\n'));

      final log = OtaLogger(tempDir.path);
      final addedCount = ensureBackendEnvVariables(
        targetDir: tempDir.path,
        log: log,
      );

      // Faltaban 7 de las 8 variables (QUEUE_CONNECTION ya estaba activa, REVERB_HOST estaba comentada)
      expect(addedCount, equals(7));

      final updatedContent = envFile.readAsStringSync();
      expect(updatedContent, contains('APP_KEY=base64:existente123'));
      expect(updatedContent, contains('DB_DATABASE=pos_cliente'));
      expect(updatedContent, contains('BROADCAST_CONNECTION=reverb'));
      expect(updatedContent, contains('\nREVERB_HOST=127.0.0.1'));

      // Segunda ejecución debe ser 100% idempotente (0 agregadas)
      final secondRunCount = ensureBackendEnvVariables(
        targetDir: tempDir.path,
        log: log,
      );
      expect(secondRunCount, equals(0));
    });
  });

  group('extractVersionFromZipPath', () {
    test('extrae semver de ZIPs full y app', () {
      expect(extractVersionFromZipPath(r'C:\Temp\update_v2.2.0.zip'),
          equals('2.2.0'));
      expect(extractVersionFromZipPath(r'C:\Temp\update_backend_v2.2.0.zip'),
          equals('2.2.0'));
      expect(
          extractVersionFromZipPath(r'C:\Temp\update_backend_app_v2.2.1.zip'),
          equals('2.2.1'));
    });
  });

  group('Consola Win32 — Desactivación de QuickEdit Mode', () {
    test(
        'computeQuickEditDisabledConsoleMode aplica exactamente (mode & ~0x0040) | 0x0080 preservando el resto de flags',
        () {
      expect(kWin32StdInputHandle, equals(-10));
      expect(kWin32EnableQuickEditMode, equals(0x0040));
      expect(kWin32EnableExtendedFlags, equals(0x0080));

      // Caso típico Windows 11: QuickEdit (0x0040) + Insert (0x0020) + Echo/Line/Processed (0x0007) = 0x0067
      const int typicalWindowsMode = 0x0067;
      final int updated = computeQuickEditDisabledConsoleMode(typicalWindowsMode);

      expect(updated & 0x0040, equals(0),
          reason: 'ENABLE_QUICK_EDIT_MODE (0x0040) debe quedar apagado');
      expect(updated & 0x0080, equals(0x0080),
          reason: 'ENABLE_EXTENDED_FLAGS (0x0080) debe quedar encendido');
      expect(updated & 0x0027, equals(0x0027),
          reason: 'Los demás flags de consola deben conservarse intactos');
    });

    test(
        'disableWindowsConsoleQuickEdit no arroja excepción en entorno sin consola interactiva (tests/CI)',
        () {
      expect(
        () => disableWindowsConsoleQuickEdit(
          consoleTitle: 'Test Caja4U Updater',
        ),
        returnsNormally,
      );
    });
  });

  group('Ciclo /disable + finally /enable de servicios en OTA de Backend', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('ota_bg_tasks_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test(
        'deshabilita las 3 tareas antes de extraer y en éxito ejecuta /enable + instalar_tareas_bg.bat',
        () async {
      File(p.join(tempDir.path, 'artisan')).writeAsStringSync('<?php // artisan');
      File(p.join(tempDir.path, 'instalar_tareas_bg.bat'))
          .writeAsStringSync('@echo off');

      final calls = <String>[];
      final log = OtaLogger(tempDir.path);

      final ok = await runWithBackendServicesSuspended<bool>(
        targetDir: tempDir.path,
        phpExe: 'php',
        phpEnv: const {},
        log: log,
        postStopDelay: Duration.zero,
        isActionSuccessful: (r) => r,
        processRunner: (exe, args, {workingDirectory, environment}) {
          calls.add('$exe ${args.join(' ')}');
          return ProcessResult(1, 0, '', '');
        },
        action: () async {
          calls.add('=== EXTRACT_AND_MIGRATE ===');
          return true;
        },
      );

      expect(ok, isTrue);
      final extractIdx = calls.indexOf('=== EXTRACT_AND_MIGRATE ===');
      expect(extractIdx, greaterThan(0));

      // Antes de extraer, las 3 tareas deben haberse deshabilitado (/disable) y detenido (/end)
      for (final task in kBackendScheduledTasks) {
        final disableIdx =
            calls.indexOf('schtasks /change /tn $task /disable');
        final endIdx = calls.indexOf('schtasks /end /tn $task');
        expect(disableIdx, greaterThanOrEqualTo(0));
        expect(disableIdx, lessThan(extractIdx));
        expect(endIdx, greaterThan(disableIdx));
        expect(endIdx, lessThan(extractIdx));
      }

      // Después de extraer, las 3 tareas deben haberse re-habilitado (/enable) y refrescado vía bat
      for (final task in kBackendScheduledTasks) {
        final enableIdx = calls.indexOf('schtasks /change /tn $task /enable');
        expect(enableIdx, greaterThan(extractIdx));
      }
      expect(
        calls.any((c) => c.startsWith('cmd.exe /c ') && c.endsWith('instalar_tareas_bg.bat')),
        isTrue,
      );
    });

    test(
        'garantiza /enable + schtasks /run en bloque finally incluso si la extracción/migración lanza excepción o instalar_tareas_bg.bat falla',
        () async {
      File(p.join(tempDir.path, 'instalar_tareas_bg.bat'))
          .writeAsStringSync('@echo off');
      final log = OtaLogger(tempDir.path);

      // Caso A: Excepción fatal durante decodificación/extracción -> finally igual reactiva y relanza las 3 tareas
      final callsOnThrow = <String>[];
      await expectLater(
        () => runWithBackendServicesSuspended<bool>(
          targetDir: tempDir.path,
          phpExe: 'php',
          phpEnv: const {},
          log: log,
          postStopDelay: Duration.zero,
          processRunner: (exe, args, {workingDirectory, environment}) {
            callsOnThrow.add('$exe ${args.join(' ')}');
            return ProcessResult(1, 0, '', '');
          },
          action: () async {
            callsOnThrow.add('=== FATAL_ZIP_ERROR ===');
            throw const FormatException('ZIP truncado');
          },
        ),
        throwsA(isA<FormatException>()),
      );

      final errIdx = callsOnThrow.indexOf('=== FATAL_ZIP_ERROR ===');
      for (final task in kBackendScheduledTasks) {
        final enableIdx =
            callsOnThrow.indexOf('schtasks /change /tn $task /enable');
        final runIdx = callsOnThrow.indexOf('schtasks /run /tn $task');
        expect(enableIdx, greaterThan(errIdx),
            reason: '$task no puede quedar deshabilitada tras fallo fatal');
        expect(runIdx, greaterThan(enableIdx),
            reason: '$task debe relanzarse tras re-habilitarse');
      }

      // Caso B: Acción exitosa pero instalar_tareas_bg.bat retorna exitCode=1 -> fallback ejecuta /enable + /run directo
      final callsOnBatFail = <String>[];
      final resBatFail = await runWithBackendServicesSuspended<bool>(
        targetDir: tempDir.path,
        phpExe: 'php',
        phpEnv: const {},
        log: log,
        postStopDelay: Duration.zero,
        isActionSuccessful: (r) => r,
        processRunner: (exe, args, {workingDirectory, environment}) {
          callsOnBatFail.add('$exe ${args.join(' ')}');
          if (exe == 'cmd.exe') {
            return ProcessResult(1, 1, '', 'Access denied');
          }
          return ProcessResult(1, 0, '', '');
        },
        action: () async => true,
      );

      expect(resBatFail, isTrue);
      for (final task in kBackendScheduledTasksStartOrder) {
        expect(callsOnBatFail, contains('schtasks /run /tn $task'));
      }
    });
  });
}
