import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

// ─────────────────────────────────────────────────────────
// Logger: escribe en stdout Y en updater_log.txt del dir
// ─────────────────────────────────────────────────────────
class _Logger {
  final File _file;
  final String _sessionId;

  _Logger(String targetDir)
      : _file = File(p.join(targetDir, 'updater_log.txt')),
        _sessionId = DateTime.now().millisecondsSinceEpoch.toString();

  void writeHeader({
    required String component,
    required String version,
    required String zipPath,
    required String targetDir,
  }) {
    final sep = '=' * 60;
    final header = [
      sep,
      'Sistema POS — Actualizador de OTA',
      'Sesión ID  : $_sessionId',
      'Fecha/Hora : ${DateTime.now()}',
      'Componente : $component',
      'Versión    : $version',
      'ZIP        : $zipPath',
      'Destino    : $targetDir',
      sep,
      '',
    ].join('\n');

    try {
      // Overwrite el log anterior — solo conservamos el último intento
      _file.writeAsStringSync(header, mode: FileMode.write);
    } catch (e) {
      stdout.writeln('[Logger] No se pudo crear el log: $e');
    }
  }

  void log(String msg, {bool isError = false}) {
    final prefix = isError ? '[ERROR]' : '[INFO ]';
    final line = '$prefix [${_ts()}] $msg';
    stdout.writeln(line);
    try {
      _file.writeAsStringSync('$line\n', mode: FileMode.append);
    } catch (_) {}
  }

  void err(String msg) => log(msg, isError: true);

  String _ts() {
    final n = DateTime.now();
    return '${_pad(n.hour)}:${_pad(n.minute)}:${_pad(n.second)}.${n.millisecond.toString().padLeft(3, '0')}';
  }

  String _pad(int v) => v.toString().padLeft(2, '0');

  void writeResult(bool success, {String? detail}) {
    final line = success
        ? '\n✅ RESULTADO FINAL: SUCCESS${detail != null ? ' — $detail' : ''}'
        : '\n❌ RESULTADO FINAL: FAILED${detail != null ? ' — $detail' : ''}';
    stdout.writeln(line);
    try {
      _file.writeAsStringSync('$line\n', mode: FileMode.append);
    } catch (_) {}
  }
}

// ─────────────────────────────────────────────────────────
// MAIN
// ─────────────────────────────────────────────────────────
void main(List<String> args) async {
  String? component;
  String? targetDir;
  String? zipPath;

  // Parser de argumentos con soporte --flag=valor
  for (final arg in args) {
    if (arg.startsWith('--component=')) {
      component = arg.split('=')[1];
    } else if (arg.startsWith('--target-dir=')) {
      targetDir = arg.substring('--target-dir='.length).replaceAll('"', '');
    } else if (arg.startsWith('--zip-path=')) {
      zipPath = arg.substring('--zip-path='.length).replaceAll('"', '');
    }
  }

  // Fallback para versiones muy antiguas (2 args posicionales)
  if (component == null && args.length >= 2 && !args[0].startsWith('--')) {
    component = 'frontend';
    zipPath = args[0].replaceAll('"', '');
    targetDir = args[1].replaceAll('"', '');
  }

  // Validación de argumentos mínimos
  if (component == null || targetDir == null || zipPath == null) {
    stdout.writeln('Uso: updater.exe --component=<frontend|backend> --target-dir=<ruta> --zip-path=<ruta>');
    stdout.writeln('Args recibidos: ${args.join(' | ')}');
    exit(1);
  }

  // Normalizar rutas (trim espacios residuales)
  targetDir = targetDir.trim();
  zipPath = zipPath.trim();
  component = component.trim().toLowerCase();

  // Inicializar logger ANTES de cualquier operación
  final log = _Logger(targetDir);
  log.writeHeader(
    component: component,
    version: _extractVersion(zipPath),
    zipPath: zipPath,
    targetDir: targetDir,
  );

  log.log('Updater iniciado correctamente.');
  log.log('PID del proceso: ${pid}');
  log.log('Plataforma: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');

  // ── PASO 1: Verificar que el ZIP existe ─────────────────
  final zipFile = File(zipPath);
  if (!zipFile.existsSync()) {
    log.err('El archivo ZIP no existe en: $zipPath');
    log.err('Es posible que la descarga no se completó o el archivo fue eliminado.');
    log.writeResult(false, detail: 'ZIP no encontrado');
    _writeOtaResult(targetDir, false);
    exit(1);
  }
  log.log('ZIP verificado (${(zipFile.lengthSync() / 1024 / 1024).toStringAsFixed(2)} MB)');

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
      log.log('Advertencia: El exe sigue bloqueado después de 20s — intentando de todas formas.');
    }
  } else {
    log.log('Esperando 3 segundos para que el backend libere archivos...');
    await Future.delayed(const Duration(seconds: 3));
  }

  // ── PASO 3: Auto-renombrado del updater para poder sobreescribirse ──
  if (component == 'frontend') {
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
        log.log('updater.exe renombrado a updater_old.exe (self-update listo).');
      }
    } catch (e) {
      log.log('Advertencia: No se pudo renombrar updater.exe: $e');
    }
  }

  // ── PASO 4: Extracción del ZIP ───────────────────────────
  log.log('Iniciando extracción del ZIP...');
  bool extractionOk = false;
  int filesExtracted = 0;
  int filesSkipped = 0;

  try {
    final bytes = zipFile.readAsBytesSync();
    log.log('ZIP leído en memoria (${bytes.length} bytes).');
    final archive = ZipDecoder().decodeBytes(bytes);
    log.log('ZIP decodificado: ${archive.length} entradas encontradas.');

    for (final file in archive) {
      final filename = file.name;

      if (file.isFile) {
        final data = file.content as List<int>;
        final filePath = p.join(targetDir, filename);
        final outFile = File(filePath);

        try {
          outFile.createSync(recursive: true);
          outFile.writeAsBytesSync(data);
          filesExtracted++;
          // Log cada 10 archivos para no saturar el log
          if (filesExtracted % 10 == 0) {
            log.log('  → $filesExtracted archivos extraídos...');
          }
        } catch (fileError) {
          log.log('  Archivo bloqueado: $filename — intentando fallback de renombre...');
          try {
            if (outFile.existsSync()) {
              final backupPath = '$filePath.bak-${DateTime.now().millisecondsSinceEpoch}';
              outFile.renameSync(backupPath);
              File(backupPath).delete().ignore();
            }
            outFile.createSync(recursive: true);
            outFile.writeAsBytesSync(data);
            filesExtracted++;
            log.log('  ✓ $filename extraído vía fallback.');
          } catch (fallbackErr) {
            log.err('  BLOQUEADO SIN SOLUCIÓN: $filename ($fallbackErr)');
            filesSkipped++;
          }
        }
      } else {
        // Es un directorio
        final dirPath = p.join(targetDir, filename);
        try {
          Directory(dirPath).createSync(recursive: true);
        } catch (e) {
          log.err('Error creando directorio $filename: $e');
        }
      }
    }

    log.log('Extracción completada: $filesExtracted archivos extraídos, $filesSkipped omitidos.');
    extractionOk = filesSkipped == 0;

    if (filesSkipped > 0) {
      log.err('$filesSkipped archivos no pudieron extraerse. La actualización puede estar incompleta.');
    }
  } catch (e) {
    log.err('Error fatal decodificando el ZIP: $e');
    log.writeResult(false, detail: 'ZIP corrupto o ilegible');
    _writeOtaResult(targetDir, false, component: component, version: _extractVersion(zipPath));
    exit(1);
  }

  // ── PASO 5: Lógica post-extracción por componente ────────
  if (component == 'backend') {
    final commands = [
      ['artisan', 'optimize:clear'],
      ['artisan', 'migrate', '--force'],
      ['artisan', 'optimize'],
    ];

    bool hasError = false;

    for (final cmd in commands) {
      final cmdString = 'php ${cmd.join(' ')}';
      log.log('Ejecutando: $cmdString');
      try {
        final result = Process.runSync('php', cmd, workingDirectory: targetDir);
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

    // Eliminar ZIP temporal
    try {
      zipFile.deleteSync();
      log.log('ZIP temporal eliminado correctamente.');
    } catch (e) {
      log.log('No se pudo eliminar el ZIP: $e');
    }

    final success = extractionOk && !hasError;
    log.writeResult(success);
    _writeOtaResult(targetDir, success, component: component, version: _extractVersion(zipPath));

  } else if (component == 'frontend') {

    // 1. Desbloquear Mark-of-the-Web (SmartScreen) en todos los archivos extraídos
    log.log('Ejecutando Unblock-File para remover Mark-of-the-Web (SmartScreen)...');
    try {
      final unblockResult = Process.runSync('powershell', [
        '-ExecutionPolicy', 'Bypass',
        '-Command',
        'Get-ChildItem -Path "${targetDir.replaceAll(r'\', r'\\')}" -Recurse | Unblock-File -ErrorAction SilentlyContinue',
      ]);
      if (unblockResult.exitCode == 0) {
        log.log('Unblock-File ejecutado correctamente.');
      } else {
        log.log('Unblock-File retornó código ${unblockResult.exitCode} (puede ser normal si no había streams).');
      }
    } catch (e) {
      log.log('Advertencia: No se pudo ejecutar Unblock-File: $e');
    }

    // 2. Eliminar ZIP (ya en el dir de instalación, no en temp)
    try {
      zipFile.deleteSync();
      log.log('ZIP eliminado del directorio de instalación.');
    } catch (e) {
      log.log('No se pudo eliminar el ZIP: $e');
    }

    // 3. Escribir resultado ANTES de relanzar la app
    log.writeResult(extractionOk);
    _writeOtaResult(targetDir, extractionOk, component: component, version: _extractVersion(zipPath));

    // 4. Relanzar la app
    final exePath = p.join(targetDir, 'Sistema_POS.exe');
    if (File(exePath).existsSync()) {
      log.log('Relanzando Sistema_POS.exe...');
      try {
        // Start-Process sin -Verb RunAs: la app debe correr como usuario normal,
        // no heredar el token elevado del updater.
        Process.runSync('powershell', [
          '-ExecutionPolicy', 'Bypass',
          '-Command',
          'Start-Process -FilePath "${exePath.replaceAll(r'\', r'\\')}" -WorkingDirectory "${targetDir.replaceAll(r'\', r'\\')}"',
        ]);
        log.log('Sistema_POS.exe relanzado exitosamente.');
      } catch (e) {
        log.err('No se pudo relanzar Sistema_POS.exe: $e');
      }
    } else {
      log.err('No se encontró $exePath — el exe no fue extraído correctamente.');
    }
  }

  log.log('Proceso de actualización finalizado. Cerrando updater.');
  exit(0);
}

/// Escribe ota_result.txt en el directorio destino como JSON.
/// Formato: {"status":"SUCCESS","version":"1.3.0","component":"frontend"}
/// La app Flutter lo lee al arrancar para mostrar el resultado.
void _writeOtaResult(
  String targetDir,
  bool success, {
  String component = 'frontend',
  String version = 'desconocida',
}) {
  try {
    final json = '{"status":"${success ? 'SUCCESS' : 'FAILED'}","version":"$version","component":"$component"}';
    File(p.join(targetDir, 'ota_result.txt')).writeAsStringSync(json);
  } catch (_) {}
}

/// Extrae la versión del nombre del ZIP para el header del log.
String _extractVersion(String zipPath) {
  final name = p.basename(zipPath);
  final match = RegExp(r'v([\d.]+)').firstMatch(name);
  return match?.group(1) ?? 'desconocida';
}
