import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:updater/updater_core.dart';

// ─────────────────────────────────────────────────────────
// MAIN
// ─────────────────────────────────────────────────────────
void main(List<String> args) async {
  String? component;
  String? targetDir;
  String? zipPath;

  // Log de diagnóstico: mostrar TODOS los args recibidos para auditar
  stdout.writeln('[ARGS] Total recibidos: ${args.length}');
  for (int i = 0; i < args.length; i++) {
    stdout.writeln('[ARGS]   [$i] = "${args[i]}"');
  }

  // Parser de argumentos con soporte --flag=valor
  // IMPORTANTE: usar substring(), NO split('=')[1].
  // split() corta en todos los '=', substring() preserva la ruta completa.
  for (final arg in args) {
    if (arg.startsWith('--component=')) {
      component = arg.substring('--component='.length).trim();
    } else if (arg.startsWith('--target-dir=')) {
      targetDir = arg.substring('--target-dir='.length).trim();
    } else if (arg.startsWith('--zip-path=')) {
      zipPath = arg.substring('--zip-path='.length).trim();
    }
  }

  // Fallback para versiones muy antiguas (2 args posicionales)
  if (component == null && args.length >= 2 && !args[0].startsWith('--')) {
    component = 'frontend';
    zipPath = args[0].trim();
    targetDir = args[1].trim();
  }

  // Validación de argumentos mínimos
  if (component == null || targetDir == null || zipPath == null) {
    stdout.writeln(
        'Uso: updater.exe --component=<frontend|backend> --target-dir=<ruta> --zip-path=<ruta>');
    stdout.writeln('Args recibidos: ${args.join(' | ')}');
    exit(1);
  }

  // Normalizar rutas (trim espacios residuales)
  targetDir = targetDir.trim();
  zipPath = zipPath.trim();
  component = component.trim().toLowerCase();
  final version = extractVersionFromZipPath(zipPath);

  // Inicializar logger ANTES de cualquier operación
  final log = OtaLogger(targetDir);
  log.writeHeader(
    component: component,
    version: version,
    zipPath: zipPath,
    targetDir: targetDir,
  );

  log.log('Updater iniciado correctamente.');
  log.log('PID del proceso: $pid');
  log.log(
      'Plataforma: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');

  // ── PASO 1: Verificar que el ZIP existe ─────────────────
  final zipFile = File(zipPath);
  if (!zipFile.existsSync()) {
    log.err('El archivo ZIP no existe en: $zipPath');
    log.err(
        'Es posible que la descarga no se completó o el archivo fue eliminado.');
    log.writeResult(false, detail: 'ZIP no encontrado');
    _writeOtaResult(targetDir, false, component: component, version: version);
    exit(1);
  }
  log.log(
      'ZIP verificado (${(zipFile.lengthSync() / 1024 / 1024).toStringAsFixed(2)} MB)');

  // ── PASO 2: Espera inteligente (solo frontend) ───────────
  if (component == 'frontend') {
    log.log('Esperando a que Sistema_POS.exe libere el lock de archivo...');
    final exeFile = File(p.join(targetDir, 'Sistema_POS.exe'));
    bool isLocked = true;
    int retries = 0;
    while (isLocked && retries < 20) {
      try {
        if (exeFile.existsSync()) {
          final f = exeFile.openSync(mode: FileMode.append);
          f.closeSync();
        }
        isLocked = false;
        log.log('Archivo desbloqueado tras $retries segundo(s).');
      } catch (_) {
        await Future.delayed(const Duration(seconds: 1));
        retries++;
        if (retries % 5 == 0) {
          log.log('Aún esperando liberación del exe... ($retries/20 seg)');
        }
      }
    }
    if (isLocked) {
      log.log(
          'Advertencia: El exe sigue bloqueado después de 20s — intentando de todas formas.');
    }
  } else {
    log.log('Esperando 2 segundos para que el backend libere archivos...');
    await Future.delayed(const Duration(seconds: 2));
  }

  // ── PASO 3 y 4: Decodificación del Central Directory y Extracción Diferencial ──
  log.log('Iniciando lectura del directorio central del ZIP...');
  late final Archive archive;
  try {
    final bytes = zipFile.readAsBytesSync();
    log.log('ZIP leído en memoria (${bytes.length} bytes).');
    archive = ZipDecoder().decodeBytes(bytes);
    log.log('ZIP decodificado: ${archive.length} entradas encontradas.');
  } catch (e) {
    log.err('Error fatal decodificando el ZIP: $e');
    log.writeResult(false, detail: 'ZIP corrupto o ilegible');
    _writeOtaResult(targetDir, false, component: component, version: version);
    exit(1);
  }

  // ── PASO 3: Self-update condicional de updater.exe (Solo Frontend) ──
  bool skipUpdaterExe = false;
  if (component == 'frontend') {
    final updaterChanged = hasUpdaterExeChangedInArchive(archive, targetDir);
    if (!updaterChanged) {
      skipUpdaterExe = true;
      log.log(
          'updater.exe sin cambios respecto al ZIP (CRC-32 idéntico) — se conserva sin renombrar.');
    } else {
      try {
        final updaterPath = p.join(targetDir, 'updater.exe');
        final updaterOldPath = p.join(targetDir, 'updater_old.exe');
        final updaterFile = File(updaterPath);
        if (updaterFile.existsSync()) {
          if (File(updaterOldPath).existsSync()) {
            File(updaterOldPath).deleteSync();
            log.log('updater_old.exe anterior eliminado.');
          }
          updaterFile.renameSync(updaterOldPath);
          log.log(
              'updater.exe renombrado a updater_old.exe (self-update listo).');
        }
      } catch (e) {
        log.log('Advertencia: No se pudo renombrar updater.exe: $e');
      }
    }
  }

  // ── PASO 4: Extracción Diferencial por Tamaño + CRC-32 ──
  log.log('Iniciando extracción diferencial...');
  final stats = extractArchiveDifferentially(
    archive: archive,
    targetDir: targetDir,
    component: component,
    log: log,
    skipUpdaterExe: skipUpdaterExe,
  );

  // Salvaguarda crítica post-extracción para Frontend: garantizar que updater.exe siempre exista
  if (component == 'frontend') {
    final updaterFile = File(p.join(targetDir, 'updater.exe'));
    final updaterOldFile = File(p.join(targetDir, 'updater_old.exe'));
    if (!updaterFile.existsSync() && updaterOldFile.existsSync()) {
      try {
        updaterOldFile.renameSync(updaterFile.path);
        log.log(
            'Salvaguarda activada: updater_old.exe restaurado como updater.exe.');
      } catch (e) {
        log.err('No se pudo restaurar updater_old.exe: $e');
      }
    }
  }

  final bool extractionOk = stats.extractionOk;
  if (!extractionOk) {
    log.err(
        '${stats.filesSkipped} archivos no pudieron extraerse. La actualización puede estar incompleta.');
  }

  // ── PASO 5: Lógica post-extracción por componente ────────
  if (component == 'backend') {
    // 1. Saneamiento idempotente de variables .env nuevas (para clientes que suben desde v1.8.5)
    ensureBackendEnvVariables(targetDir: targetDir, log: log);

    // 2. Resolver la ruta absoluta de php.exe
    String phpExe = 'php';
    String phpDir = '';

    try {
      final whereResult =
          Process.runSync('where.exe', ['php'], runInShell: false);
      if (whereResult.exitCode == 0) {
        final found =
            whereResult.stdout.toString().trim().split('\n').first.trim();
        if (found.isNotEmpty && File(found).existsSync()) {
          phpExe = found;
          phpDir = p.dirname(found);
          log.log('PHP encontrado via where.exe: $phpExe');
        }
      }
    } catch (_) {}

    if (phpDir.isEmpty) {
      final laragonPhpBase = Directory(r'C:\laragon\bin\php');
      if (laragonPhpBase.existsSync()) {
        try {
          final phpDirs = laragonPhpBase
              .listSync()
              .whereType<Directory>()
              .toList()
            ..sort((a, b) => b.path.compareTo(a.path));
          for (final dir in phpDirs) {
            final candidate = File(p.join(dir.path, 'php.exe'));
            if (candidate.existsSync()) {
              phpExe = candidate.path;
              phpDir = dir.path;
              log.log('PHP encontrado en Laragon: $phpExe');
              break;
            }
          }
        } catch (e) {
          log.log('Advertencia buscando Laragon PHP: $e');
        }
      }
    }

    if (phpDir.isEmpty) {
      log.log(
          'Advertencia: PHP no encontrado en rutas conocidas. Usando "php" del PATH.');
    }

    final Map<String, String> phpEnv = {};
    if (phpDir.isNotEmpty) {
      final currentPath = Platform.environment['PATH'] ?? '';
      phpEnv['PATH'] = '$phpDir;$currentPath';
    }

    final artisanPath = p.join(targetDir, 'artisan');
    final commands = [
      [phpExe, artisanPath, 'optimize:clear'],
      [phpExe, artisanPath, 'migrate', '--force'],
      [phpExe, artisanPath, 'optimize'],
    ];

    bool hasError = false;

    for (final cmd in commands) {
      final cmdString = cmd.join(' ');
      log.log('Ejecutando: $cmdString');
      try {
        final result = Process.runSync(
          cmd.first,
          cmd.sublist(1),
          workingDirectory: targetDir,
          environment: phpEnv.isNotEmpty ? phpEnv : null,
        );
        if (result.stdout.toString().trim().isNotEmpty) {
          log.log('  STDOUT: ${result.stdout.toString().trim()}');
        }
        if (result.stderr.toString().trim().isNotEmpty) {
          log.err('  STDERR: ${result.stderr.toString().trim()}');
        }
        if (result.exitCode != 0) {
          hasError = true;
          log.err('  $cmdString retornó exitCode=${result.exitCode}');
        } else {
          log.log('  $cmdString: OK');
        }
      } catch (e) {
        hasError = true;
        log.err('  Excepción ejecutando $cmdString: $e');
      }
    }

    // 3. Reiniciar workers de cola y WebSockets Reverb en segundo plano (no bloqueante)
    if (!hasError) {
      for (final bgCmd in ['queue:restart', 'reverb:restart']) {
        try {
          final qResult = Process.runSync(
            phpExe,
            [artisanPath, bgCmd],
            workingDirectory: targetDir,
            environment: phpEnv.isNotEmpty ? phpEnv : null,
          );
          if (qResult.exitCode == 0) {
            log.log('  $bgCmd: OK');
          }
        } catch (e) {
          log.log('  Advertencia ejecutando $bgCmd (no bloqueante): $e');
        }
      }

      // Asegurar que las tareas programadas de Windows (Reverb, Queue, Schedule) vuelvan a
      // levantar inmediatamente si se detuvieron al recibir la señal de restart.
      for (final taskName in [
        'SistemaPOS_Reverb',
        'SistemaPOS_Queue',
        'SistemaPOS_Schedule',
      ]) {
        try {
          Process.runSync('schtasks', ['/run', '/tn', taskName]);
        } catch (_) {}
      }
    }

    final success = extractionOk && !hasError;

    // 4. Commit atómico final: escribir public/version.txt y podar obsoletos
    // ÚNICAMENTE si la extracción y las migraciones fueron 100% exitosas.
    if (success) {
      if (stats.deferredVersionTxtBytes != null) {
        try {
          final versionFile = File(p.join(targetDir, 'public', 'version.txt'));
          versionFile.createSync(recursive: true);
          versionFile.writeAsBytesSync(stats.deferredVersionTxtBytes!);
          log.log(
              'public/version.txt actualizado tras migración exitosa (${utf8.decode(stats.deferredVersionTxtBytes!).trim()}).');
        } catch (e) {
          log.err('No se pudo escribir public/version.txt final: $e');
        }
      }

      pruneDeletedFilesAndSaveManifest(
        targetDir: targetDir,
        newManifestBytes: stats.newManifestBytes,
        log: log,
      );
    } else {
      log.err(
          'Se omitió la actualización de public/version.txt y la poda de obsoletos debido a errores previos (permite reintentar OTA).');
    }

    // 5. Eliminar ZIP temporal
    try {
      zipFile.deleteSync();
      log.log('ZIP temporal eliminado correctamente.');
    } catch (e) {
      log.log('No se pudo eliminar el ZIP: $e');
    }

    log.writeResult(success);
    _writeOtaResult(targetDir, success, component: component, version: version);
  } else if (component == 'frontend') {
    // 1. Poda de archivos obsoletos y guardado de manifiesto si la extracción fue exitosa
    if (extractionOk) {
      pruneDeletedFilesAndSaveManifest(
        targetDir: targetDir,
        newManifestBytes: stats.newManifestBytes,
        log: log,
      );
    }

    // 2. Desbloquear Mark-of-the-Web (SmartScreen) solo si se escribieron binarios (.exe / .dll)
    if (stats.wroteBinaries) {
      log.log(
          'Ejecutando Unblock-File para remover Mark-of-the-Web (SmartScreen)...');
      try {
        final unblockResult = Process.runSync('powershell', [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          'Get-ChildItem -LiteralPath "$targetDir" -Recurse | Unblock-File -ErrorAction SilentlyContinue',
        ]);
        if (unblockResult.exitCode == 0) {
          log.log('Unblock-File ejecutado correctamente.');
        } else {
          log.log(
              'Unblock-File retornó código ${unblockResult.exitCode} (normal si no había streams).');
        }
      } catch (e) {
        log.log('Advertencia: No se pudo ejecutar Unblock-File: $e');
      }
    } else {
      log.log(
          'No se escribieron binarios nuevos (.exe/.dll) — Unblock-File omitido.');
    }

    // 3. Migrar preferencias locales y accesos directos (solo si aún no se migró)
    _migrateBrandingAndPrefs(targetDir, log);

    // 4. Eliminar ZIP
    try {
      zipFile.deleteSync();
      log.log('ZIP temporal eliminado.');
    } catch (e) {
      log.log('No se pudo eliminar el ZIP: $e');
    }

    // 5. Escribir resultado ANTES de relanzar la app
    log.writeResult(extractionOk);
    _writeOtaResult(targetDir, extractionOk,
        component: component, version: version);

    // 6. Relanzar la app (con reintentos por si el antivirus Avast/Defender retiene el lock 1-3s tras extraer el nuevo .exe)
    final exePath = p.join(targetDir, 'Sistema_POS.exe');
    if (File(exePath).existsSync()) {
      log.log('Relanzando Sistema_POS.exe...');
      bool relaunched = false;
      for (int attempt = 1; attempt <= 4; attempt++) {
        try {
          final res = Process.runSync('powershell', [
            '-NoProfile',
            '-NonInteractive',
            '-ExecutionPolicy',
            'Bypass',
            '-Command',
            'Start-Process -FilePath "$exePath" -WorkingDirectory "$targetDir" -ErrorAction Stop',
          ]);
          if (res.exitCode == 0) {
            relaunched = true;
            log.log('Sistema_POS.exe relanzado exitosamente (intento $attempt).');
            break;
          }
          log.log(
              'Intento $attempt de relanzar Sistema_POS.exe retornó código ${res.exitCode}: ${res.stderr.toString().trim()}');
        } catch (e) {
          log.log('Intento $attempt de relanzar Sistema_POS.exe falló: $e');
        }
        if (attempt < 4) {
          await Future.delayed(Duration(seconds: attempt));
        }
      }
      if (!relaunched) {
        log.err('No se pudo relanzar Sistema_POS.exe tras 4 intentos.');
      }
    } else {
      log.err(
          'No se encontró $exePath — el exe no fue extraído correctamente.');
    }
  }

  log.log('Proceso de actualización finalizado. Cerrando updater.');
  exit(0);
}

/// Escribe ota_result.txt en el directorio destino como JSON.
/// Formato: {"status":"SUCCESS","version":"1.3.0","component":"frontend"}
void _writeOtaResult(
  String targetDir,
  bool success, {
  String component = 'frontend',
  String version = 'desconocida',
}) {
  try {
    final json =
        '{"status":"${success ? 'SUCCESS' : 'FAILED'}","version":"$version","component":"$component"}';
    File(p.join(targetDir, 'ota_result.txt')).writeAsStringSync(json);
  } catch (_) {}
}

/// Migra las preferencias de usuario desde `com.example\frontend_desktop` hacia `Dev4U\Caja4U`
/// en todos los perfiles de Windows (`C:\Users\*`), y actualiza los accesos directos del Escritorio
/// Público y de Usuarios (`Sistema POS.lnk` -> `Caja4U.lnk`, `Servidor POS.lnk` -> `Servidor Caja4U.lnk`).
void _migrateBrandingAndPrefs(String targetDir, OtaLogger log) {
  final markerFile = File(p.join(targetDir, '.branding_caja4u_migrated'));
  final bool alreadyMigratedPrefs = markerFile.existsSync();

  if (!alreadyMigratedPrefs) {
    log.log('Iniciando migración de preferencias de usuario a Caja4U...');

    // A) Migrar shared_preferences.json en todos los perfiles de usuario
    try {
      final usersDir = Directory(r'C:\Users');
      if (usersDir.existsSync()) {
        const networkAndTerminalKeys = <String>{
          'flutter.pos_api',
          'flutter.pos_api_local',
          'flutter.pos_api_remote',
          'flutter.backend_install_path',
          'flutter.assigned_register_id',
        };

        for (final entity in usersDir.listSync()) {
          if (entity is! Directory) continue;
          final legacyFile = File(p.join(
            entity.path,
            'AppData',
            'Roaming',
            'com.example',
            'frontend_desktop',
            'shared_preferences.json',
          ));
          if (!legacyFile.existsSync()) continue;

          final newDir = Directory(p.join(
            entity.path,
            'AppData',
            'Roaming',
            'Dev4U',
            'Caja4U',
          ));
          final newFile = File(p.join(newDir.path, 'shared_preferences.json'));

          try {
            if (!newFile.existsSync()) {
              newDir.createSync(recursive: true);
              legacyFile.copySync(newFile.path);
              log.log('  ✓ Preferencias copiadas a ${newFile.path}');
            } else {
              final legacyMap = jsonDecode(legacyFile.readAsStringSync());
              final newMap = jsonDecode(newFile.readAsStringSync());
              if (legacyMap is Map<String, dynamic> &&
                  newMap is Map<String, dynamic>) {
                bool changed = false;
                final bool legacyIsNewer = legacyFile
                    .lastModifiedSync()
                    .isAfter(newFile.lastModifiedSync());

                for (final entry in legacyMap.entries) {
                  final key = entry.key;
                  final legacyVal = entry.value;
                  if (!newMap.containsKey(key)) {
                    newMap[key] = legacyVal;
                    changed = true;
                  } else if (networkAndTerminalKeys.contains(key) &&
                      legacyVal != null) {
                    final currentNewVal = newMap[key]?.toString() ?? '';
                    final legacyValStr = legacyVal.toString();
                    final bool newIsFactoryDefault =
                        currentNewVal.contains('192.168.1.200');
                    if (legacyValStr.isNotEmpty &&
                        currentNewVal != legacyValStr &&
                        (newIsFactoryDefault || legacyIsNewer)) {
                      newMap[key] = legacyVal;
                      changed = true;
                    }
                  }
                }
                if (changed) {
                  newFile.writeAsStringSync(jsonEncode(newMap));
                  log.log('  ✓ Preferencias fusionadas en ${newFile.path}');
                }
              }
            }
          } catch (e) {
            log.log('  Advertencia migrando preferencias en ${entity.path}: $e');
          }
        }
      }
    } catch (e) {
      log.log('Advertencia escaneando perfiles de usuario: $e');
    }

    // Si en esta PC existe instalar_tareas_bg.bat y la tarea SistemaPOS_Queue aún no fue registrada
    // (ej. cliente v1.8.5 que actualiza sólo por OTA), registrarla automáticamente aprovechando el UAC de Frontend.
    try {
      final bgScript =
          File(r'C:\laragon\www\Sistema_POS\pos-backend\instalar_tareas_bg.bat');
      if (bgScript.existsSync()) {
        final qCheck = Process.runSync(
            'schtasks', ['/query', '/tn', 'SistemaPOS_Queue']);
        if (qCheck.exitCode != 0) {
          log.log(
              'Registrando tareas en segundo plano de Laravel (Reverb/Queue/Schedule)...');
          Process.runSync('cmd.exe', ['/c', bgScript.path]);
        }
      }
    } catch (_) {}
  }

  // B) Actualizar accesos directos (.lnk) en Escritorio Público, Menú Inicio y Perfiles
  //    y refrescar el ícono de Caja4U en caso de que haya quedado algún acceso directo viejo.
  try {
    final exePath = p.join(targetDir, 'Sistema_POS.exe');
    final icoCandidate = p.join(targetDir, 'app_icon.ico');
    final iconTarget =
        File(icoCandidate).existsSync() ? icoCandidate : exePath;

    final psContent = r'''
$ErrorActionPreference = 'SilentlyContinue'
$exePath = $env:CAJA4U_EXE_PATH
$iconPath = $env:CAJA4U_ICON_PATH
$wsh = New-Object -ComObject WScript.Shell

$folders = [System.Collections.Generic.List[string]]::new()
@(
  [Environment]::GetFolderPath('Desktop'),
  [Environment]::GetFolderPath('CommonDesktopDirectory'),
  [Environment]::GetFolderPath('Programs'),
  [Environment]::GetFolderPath('CommonPrograms')
) | ForEach-Object { if ($_) { $folders.Add($_) } }

if (Test-Path -LiteralPath 'C:\Users') {
  Get-ChildItem -LiteralPath 'C:\Users' -Directory | ForEach-Object {
    $uDesk = Join-Path $_.FullName 'Desktop'
    if (Test-Path -LiteralPath $uDesk) { $folders.Add($uDesk) }
  }
}

$uniqueFolders = $folders | Select-Object -Unique

foreach ($dir in $uniqueFolders) {
  if (-not $dir -or -not (Test-Path -LiteralPath $dir)) { continue }
  Get-ChildItem -LiteralPath $dir -Filter '*.lnk' | ForEach-Object {
    $lnk = $_
    $sc = $wsh.CreateShortcut($lnk.FullName)
    if ($sc.TargetPath -and ($sc.TargetPath -ieq $exePath -or $sc.TargetPath -like '*\Sistema_POS.exe')) {
      $sc.Description = 'Caja4U - Punto de Venta'
      if ($iconPath -and (Test-Path -LiteralPath $iconPath)) {
        $sc.IconLocation = "$iconPath,0"
      }
      $sc.Save()
      if ($lnk.Name -ieq 'Sistema POS.lnk') {
        $newPath = Join-Path $lnk.DirectoryName 'Caja4U.lnk'
        if (-not (Test-Path -LiteralPath $newPath)) {
          Rename-Item -LiteralPath $lnk.FullName -NewName 'Caja4U.lnk' -Force
        } else {
          Remove-Item -LiteralPath $lnk.FullName -Force
        }
      }
    } elseif ($lnk.Name -ieq 'Servidor POS.lnk' -or $lnk.Name -ieq 'Servidor Caja4U.lnk') {
      if ($iconPath -and (Test-Path -LiteralPath $iconPath)) {
        $sc.IconLocation = "$iconPath,0"
        $sc.Save()
      }
      if ($lnk.Name -ieq 'Servidor POS.lnk') {
        $newSrvPath = Join-Path $lnk.DirectoryName 'Servidor Caja4U.lnk'
        if (-not (Test-Path -LiteralPath $newSrvPath)) {
          Rename-Item -LiteralPath $lnk.FullName -NewName 'Servidor Caja4U.lnk' -Force
        } else {
          Remove-Item -LiteralPath $lnk.FullName -Force
        }
      }
    }
  }
}
ie4uinit.exe -ClearIconCache
ie4uinit.exe -show
''';

    final tempScript =
        File(p.join(Directory.systemTemp.path, 'caja4u_ota_shortcuts.ps1'));
    tempScript.writeAsStringSync(psContent, flush: true);

    final psResult = Process.runSync(
      'powershell',
      [
        '-NoProfile',
        '-NonInteractive',
        '-WindowStyle',
        'Hidden',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        tempScript.path,
      ],
      environment: {
        'CAJA4U_EXE_PATH': exePath,
        'CAJA4U_ICON_PATH': iconTarget,
      },
    );
    try {
      if (tempScript.existsSync()) tempScript.deleteSync();
    } catch (_) {}

    if (psResult.exitCode == 0) {
      log.log('  ✓ Accesos directos y caché de íconos actualizados a Caja4U.');
      if (!alreadyMigratedPrefs) {
        try {
          markerFile
              .writeAsStringSync(DateTime.now().toUtc().toIso8601String());
        } catch (_) {}
      }
    } else {
      log.log(
          '  Advertencia actualizando accesos directos (exitCode=${psResult.exitCode}).');
    }
  } catch (e) {
    log.log('Advertencia en actualización de accesos directos: $e');
  }
}
