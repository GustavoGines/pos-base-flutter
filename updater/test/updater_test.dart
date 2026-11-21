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
}
