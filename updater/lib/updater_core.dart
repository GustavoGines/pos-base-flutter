import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

/// Resultado estadístico de una operación de extracción diferencial OTA.
class OtaExtractionStats {
  final bool extractionOk;
  final int filesExtracted;
  final int filesUnchanged;
  final int filesSkipped;
  final bool wroteBinaries;
  final Uint8List? deferredVersionTxtBytes;
  final Uint8List? newManifestBytes;

  const OtaExtractionStats({
    required this.extractionOk,
    required this.filesExtracted,
    required this.filesUnchanged,
    required this.filesSkipped,
    required this.wroteBinaries,
    this.deferredVersionTxtBytes,
    this.newManifestBytes,
  });
}

/// Logger: escribe en stdout Y en updater_log.txt del directorio destino.
/// Soporta bufferización opcional durante loops intensivos (ej. 8.000+ archivos)
/// para evitar miles de open/append/close síncronos en NTFS.
class OtaLogger {
  final File _file;
  final String _sessionId;
  final StringBuffer _buffer = StringBuffer();
  DateTime _lastFlush = DateTime.now();
  bool _bufferedMode = false;

  OtaLogger(String targetDir)
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
      'Caja4U — Actualizador de OTA',
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
      _file.writeAsStringSync(header, mode: FileMode.write);
    } catch (e) {
      stdout.writeln('[Logger] No se pudo crear el log: $e');
    }
  }

  void setBufferedMode(bool enabled) {
    if (!enabled) {
      flush();
    }
    _bufferedMode = enabled;
  }

  void flush() {
    if (_buffer.isEmpty) return;
    try {
      _file.writeAsStringSync(_buffer.toString(), mode: FileMode.append);
      _buffer.clear();
      _lastFlush = DateTime.now();
    } catch (_) {}
  }

  void log(String msg, {bool isError = false, bool forceFlush = false}) {
    final prefix = isError ? '[ERROR]' : '[INFO ]';
    final line = '$prefix [${_ts()}] $msg';
    stdout.writeln(line);
    _buffer.writeln(line);

    final now = DateTime.now();
    if (!_bufferedMode ||
        isError ||
        forceFlush ||
        now.difference(_lastFlush).inMilliseconds >= 900) {
      flush();
    }
  }

  void err(String msg) => log(msg, isError: true, forceFlush: true);

  String _ts() {
    final n = DateTime.now();
    return '${_pad(n.hour)}:${_pad(n.minute)}:${_pad(n.second)}.${n.millisecond.toString().padLeft(3, '0')}';
  }

  String _pad(int v) => v.toString().padLeft(2, '0');

  void writeResult(bool success, {String? detail}) {
    flush();
    final line = success
        ? '\n✅ RESULTADO FINAL: SUCCESS${detail != null ? ' — $detail' : ''}'
        : '\n❌ RESULTADO FINAL: FAILED${detail != null ? ' — $detail' : ''}';
    stdout.writeln(line);
    try {
      _file.writeAsStringSync('$line\n', mode: FileMode.append);
    } catch (_) {}
  }
}

/// Normaliza una ruta relativa dentro de un ZIP o manifiesto OTA:
/// - Convierte `\` en `/`
/// - Elimina prefijos `./` o `/` iniciales
/// - Elimina barras finales
String normalizeRelativeOtaPath(String rawPath) {
  var normalized = rawPath.trim().replaceAll('\\', '/');
  while (normalized.startsWith('./')) {
    normalized = normalized.substring(2);
  }
  while (normalized.startsWith('/')) {
    normalized = normalized.substring(1);
  }
  while (normalized.endsWith('/') && normalized.length > 1) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}

/// Verifica si una ruta relativa intenta escapar del directorio destino (Zip-Slip).
bool isSafeRelativeOtaPath(String targetDir, String relativePath) {
  final norm = normalizeRelativeOtaPath(relativePath);
  if (norm.isEmpty) return false;
  if (norm.contains(':')) return false;
  final segments = norm.split('/');
  if (segments.any((s) => s == '..')) return false;

  final fullPath = p.normalize(p.join(targetDir, norm));
  final normalizedTarget = p.normalize(targetDir);
  return p.equals(normalizedTarget, fullPath) ||
      p.isWithin(normalizedTarget, fullPath);
}

/// Lista dura (Hard-Protected Blacklist) de archivos y directorios que el
/// actualizador OTA jamás debe eliminar durante la limpieza de obsoletos,
/// incluso si por error hubieran figurado en un manifiesto previo.
bool isProtectedFromOtaPruning(String relativePath) {
  final norm = normalizeRelativeOtaPath(relativePath).toLowerCase();
  if (norm.isEmpty) return true;

  // Archivos raíz de configuración, estado OTA o ejecutables críticos
  const exactProtected = <String>{
    '.env',
    '.env.example',
    '.env.backup',
    '.env.production',
    'public/version.txt',
    'updater.exe',
    'updater_old.exe',
    'sistema_pos.exe',
    'updater_log.txt',
    'ota_result.txt',
    'ota_pending.json',
    '.ota_manifest.json',
    'ota_manifest.json',
    '.branding_caja4u_migrated',
  };
  if (exactProtected.contains(norm)) return true;

  // Cualquier variante de .env.*
  final baseName = p.posix.basename(norm);
  if (baseName == '.env' || baseName.startsWith('.env.')) return true;

  // Directorios de datos del cliente, certificados AFIP, imágenes, logs, cachés y APKs
  const protectedPrefixes = <String>[
    'storage/',
    'public/storage/',
    'public/mobile/',
    'public/hot',
    'bootstrap/cache/',
    '.git/',
  ];
  for (final prefix in protectedPrefixes) {
    if (norm.startsWith(prefix)) return true;
  }

  // APKs en public/ o raíz
  if (norm.endsWith('.apk')) return true;

  // Bases de datos SQLite locales
  if (norm.startsWith('database/') &&
      (norm.endsWith('.sqlite') ||
          norm.contains('.sqlite-') ||
          norm.endsWith('.db'))) {
    return true;
  }

  return false;
}

/// Verifica si el binario `updater.exe` dentro del Archive cambió respecto al
/// que ya existe en `targetDir/updater.exe` comparando `size` y `crc32` sin
/// necesidad de descomprimir si son iguales.
bool hasUpdaterExeChangedInArchive(Archive archive, String targetDir) {
  final localUpdater = File(p.join(targetDir, 'updater.exe'));
  if (!localUpdater.existsSync()) {
    return true;
  }

  ArchiveFile? archiveUpdater;
  for (final entry in archive) {
    if (!entry.isFile) continue;
    final norm = normalizeRelativeOtaPath(entry.name).toLowerCase();
    if (norm == 'updater.exe') {
      archiveUpdater = entry;
      break;
    }
  }

  // Si el ZIP no trae updater.exe, no debemos renombrar el local
  if (archiveUpdater == null) {
    return false;
  }

  try {
    final localSize = localUpdater.lengthSync();
    if (localSize != archiveUpdater.size) {
      return true;
    }
    if (archiveUpdater.crc32 != null) {
      final localCrc = getCrc32(localUpdater.readAsBytesSync());
      return localCrc != archiveUpdater.crc32;
    }
  } catch (_) {
    return true;
  }

  return true;
}

/// Ejecuta la extracción diferencial de un `Archive` sobre `targetDir`:
/// - Compara `size` y `crc32` del Central Directory contra el archivo local
///   ANTES de acceder a `file.content` (evitando descompresión ZLib y escrituras
///   NTFS en archivos idénticos).
/// - En `component == 'backend'`, retiene `public/version.txt` en memoria para
///   escribirlo recién cuando `php artisan migrate --force` termine sin errores.
/// - Retiene `ota_manifest.json` en memoria para ejecutar la poda diferencial
///   segura al finalizar.
OtaExtractionStats extractArchiveDifferentially({
  required Archive archive,
  required String targetDir,
  required String component,
  required OtaLogger log,
  bool skipUpdaterExe = false,
}) {
  int filesExtracted = 0;
  int filesUnchanged = 0;
  int filesSkipped = 0;
  bool wroteBinaries = false;
  Uint8List? deferredVersionTxtBytes;
  Uint8List? newManifestBytes;

  log.setBufferedMode(true);

  try {
    for (final file in archive) {
      final rawName = file.name;
      final normName = normalizeRelativeOtaPath(rawName);
      if (normName.isEmpty) {
        file.clear();
        continue;
      }

      if (!isSafeRelativeOtaPath(targetDir, normName)) {
        log.err('Ruta insegura bloqueada (Zip-Slip protection): $rawName');
        file.clear();
        continue;
      }

      final lowerName = normName.toLowerCase();

      if (file.isFile) {
        // 1. Retener manifiesto OTA en memoria (no escribir como archivo suelto)
        if (lowerName == 'ota_manifest.json' ||
            lowerName == '.ota_manifest.json') {
          newManifestBytes = Uint8List.fromList(file.content);
          file.clear();
          continue;
        }

        // 2. En Backend: retener public/version.txt hasta que las migraciones pasen
        if (component == 'backend' && lowerName == 'public/version.txt') {
          deferredVersionTxtBytes = Uint8List.fromList(file.content);
          file.clear();
          continue;
        }

        // 3. Si es Frontend y updater.exe no cambió, omitirlo sin tocarlo
        if (component == 'frontend' &&
            skipUpdaterExe &&
            lowerName == 'updater.exe') {
          filesUnchanged++;
          file.clear();
          continue;
        }

        final filePath = p.join(targetDir, normName);
        final outFile = File(filePath);

        // 4. Comparación diferencial rápida por tamaño + CRC-32 ANTES de descomprimir
        if (outFile.existsSync() && file.crc32 != null) {
          try {
            if (outFile.lengthSync() == file.size) {
              final localCrc = getCrc32(outFile.readAsBytesSync());
              if (localCrc == file.crc32) {
                filesUnchanged++;
                file.clear();
                continue;
              }
            }
          } catch (_) {
            // Si no se pudo leer para CRC, continuamos con extracción normal
          }
        }

        // 5. El archivo es nuevo o cambió -> descomprimir y escribir en disco
        final data = file.content;
        final isBinary =
            lowerName.endsWith('.exe') || lowerName.endsWith('.dll');

        bool written = false;
        Object? lastWriteErr;

        // En Windows con antivirus activos (Avast File Shield / CyberCapture / Defender),
        // el handle de un archivo recién creado o inspeccionado puede quedar bloqueado
        // durante 150-500 ms. Reintentamos hasta 3 veces antes de usar el fallback .bak.
        for (int attempt = 1; attempt <= 3; attempt++) {
          try {
            outFile.createSync(recursive: true);
            outFile.writeAsBytesSync(data);
            written = true;
            break;
          } catch (e) {
            lastWriteErr = e;
            if (attempt < 3) {
              sleep(Duration(milliseconds: 250 * attempt));
            }
          }
        }

        if (written) {
          filesExtracted++;
          if (isBinary) {
            wroteBinaries = true;
          }
          if (filesExtracted % 25 == 0) {
            log.log('  → $filesExtracted archivos actualizados/nuevos...');
          }
        } else {
          log.log(
              '  Archivo bloqueado ($lastWriteErr): $normName — intentando fallback de renombre...');
          try {
            if (outFile.existsSync()) {
              final backupPath =
                  '$filePath.bak-${DateTime.now().millisecondsSinceEpoch}';
              outFile.renameSync(backupPath);
              File(backupPath).delete().ignore();
            }
            outFile.createSync(recursive: true);
            outFile.writeAsBytesSync(data);
            filesExtracted++;
            if (isBinary) {
              wroteBinaries = true;
            }
            log.log('  ✓ $normName extraído vía fallback.');
          } catch (fallbackErr) {
            log.err('  BLOQUEADO SIN SOLUCIÓN: $normName ($fallbackErr)');
            filesSkipped++;
          }
        }
        file.clear();
      } else {
        // Es un directorio
        final dirPath = p.join(targetDir, normName);
        try {
          Directory(dirPath).createSync(recursive: true);
        } catch (e) {
          log.err('Error creando directorio $normName: $e');
        }
      }
    }
  } finally {
    log.setBufferedMode(false);
  }

  log.log(
    'Extracción diferencial completada: '
    '$filesExtracted actualizados/nuevos, '
    '$filesUnchanged sin cambios (omitidos por CRC-32), '
    '$filesSkipped fallidos.',
    forceFlush: true,
  );

  return OtaExtractionStats(
    extractionOk: filesSkipped == 0,
    filesExtracted: filesExtracted,
    filesUnchanged: filesUnchanged,
    filesSkipped: filesSkipped,
    wroteBinaries: wroteBinaries,
    deferredVersionTxtBytes: deferredVersionTxtBytes,
    newManifestBytes: newManifestBytes,
  );
}

/// Elimina de forma segura únicamente los archivos que estaban explícitamente
/// listados en el `.ota_manifest.json` anterior y ya no existen en el nuevo
/// `ota_manifest.json`, respetando:
/// 1) Hard-Protected Blacklist (`.env`, `storage/`, `public/storage/`, etc.)
/// 2) Comparación case-insensitive para NTFS Windows
/// 3) Protección de `vendor/` cuando se aplica un paquete liviano (`"scope": "app"`)
/// 4) Finalmente persiste el manifiesto actualizado en `.ota_manifest.json`
///    (conservando las entradas de `vendor/` del manifiesto previo si el paquete fue `app`).
int pruneDeletedFilesAndSaveManifest({
  required String targetDir,
  required Uint8List? newManifestBytes,
  required OtaLogger log,
}) {
  if (newManifestBytes == null || newManifestBytes.isEmpty) {
    return 0;
  }

  Map<String, dynamic> newManifest;
  try {
    final decoded = jsonDecode(utf8.decode(newManifestBytes));
    if (decoded is! Map<String, dynamic>) return 0;
    newManifest = decoded;
  } catch (e) {
    log.log('Advertencia: No se pudo parsear el nuevo ota_manifest.json: $e');
    return 0;
  }

  final rawNewFiles = newManifest['files'];
  if (rawNewFiles is! List) return 0;

  final String scope =
      (newManifest['scope']?.toString().trim().toLowerCase() ?? 'full');
  final bool isAppScope = scope == 'app';

  final newFilesNormalized = <String>[];
  final newFilesLowerSet = <String>{};

  for (final item in rawNewFiles) {
    if (item is! String) continue;
    final norm = normalizeRelativeOtaPath(item);
    if (norm.isEmpty) continue;
    newFilesNormalized.add(norm);
    newFilesLowerSet.add(norm.toLowerCase());
  }

  final prevManifestFile = File(p.join(targetDir, '.ota_manifest.json'));
  int deletedCount = 0;
  final preservedVendorFiles = <String>[];

  if (prevManifestFile.existsSync()) {
    try {
      final prevDecoded = jsonDecode(prevManifestFile.readAsStringSync());
      if (prevDecoded is Map<String, dynamic> && prevDecoded['files'] is List) {
        final prevList = prevDecoded['files'] as List;

        for (final rawOld in prevList) {
          if (rawOld is! String) continue;
          final normOld = normalizeRelativeOtaPath(rawOld);
          if (normOld.isEmpty) continue;
          final lowerOld = normOld.toLowerCase();

          // Si el paquete aplicado es liviano ("scope": "app"), sólo incluye
          // código de la app y vendor/composer/*. El resto de vendor/* NO viene
          // en el ZIP liviano y JAMÁS debe podarse; además lo preservamos en el
          // manifiesto local resultante.
          final isVendorOutsideComposer = lowerOld.startsWith('vendor/') &&
              !lowerOld.startsWith('vendor/composer/');
          if (isAppScope && isVendorOutsideComposer) {
            preservedVendorFiles.add(normOld);
            continue;
          }

          if (!newFilesLowerSet.contains(lowerOld)) {
            if (isProtectedFromOtaPruning(normOld)) {
              continue;
            }
            if (!isSafeRelativeOtaPath(targetDir, normOld)) {
              continue;
            }

            final candidateFile = File(p.join(targetDir, normOld));
            if (candidateFile.existsSync()) {
              try {
                candidateFile.deleteSync();
                deletedCount++;
                log.log('  🗑️ Archivo obsoleto eliminado: $normOld');
              } catch (e) {
                log.log(
                    '  Advertencia: No se pudo eliminar obsoleto $normOld: $e');
              }
            }
          }
        }
      }
    } catch (e) {
      log.log('Advertencia leyendo .ota_manifest.json previo: $e');
    }
  }

  // Persistir el nuevo .ota_manifest.json consolidado
  try {
    final mergedFiles = <String>[
      ...newFilesNormalized,
      ...preservedVendorFiles,
    ];
    final manifestToSave = <String, dynamic>{
      'version': newManifest['version'] ?? '',
      'component': newManifest['component'] ?? '',
      'scope': isAppScope && preservedVendorFiles.isNotEmpty ? 'full' : scope,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'files': mergedFiles,
    };
    prevManifestFile.writeAsStringSync(jsonEncode(manifestToSave));
  } catch (e) {
    log.log('Advertencia guardando .ota_manifest.json: $e');
  }

  if (deletedCount > 0) {
    log.log('Limpieza OTA: $deletedCount archivo(s) obsoleto(s) eliminado(s).');
  }

  return deletedCount;
}

/// Garantiza de forma idempotente que el archivo `.env` de un cliente que
/// actualiza por OTA desde `v1.8.5` tenga definidas las variables críticas de
/// colas y WebSockets Reverb introducidas en `v2.1.0+`, sin alterar ninguna
/// variable existente del comercio (`DB_*`, `APP_KEY`, etc.).
int ensureBackendEnvVariables({
  required String targetDir,
  required OtaLogger log,
}) {
  final envFile = File(p.join(targetDir, '.env'));
  if (!envFile.existsSync()) {
    return 0;
  }

  try {
    final content = envFile.readAsStringSync();
    const requiredDefaults = <String, String>{
      'QUEUE_CONNECTION': 'database',
      'BROADCAST_CONNECTION': 'reverb',
      'REVERB_APP_ID': '110434',
      'REVERB_APP_KEY': 'kz786cdfeldnzispymxq',
      'REVERB_APP_SECRET': 'eizqkp4itcvqit97npqn',
      'REVERB_HOST': '127.0.0.1',
      'REVERB_PORT': '8080',
      'REVERB_SCHEME': 'http',
    };

    final missingLines = <String>[];

    for (final entry in requiredDefaults.entries) {
      final key = entry.key;
      // Verifica si la variable existe descomentada al inicio de alguna línea
      final regex = RegExp(
        r'^\s*' + RegExp.escape(key) + r'\s*=',
        multiLine: true,
      );
      if (!regex.hasMatch(content)) {
        missingLines.add('${entry.key}=${entry.value}');
      }
    }

    if (missingLines.isEmpty) {
      return 0;
    }

    final separator = content.endsWith('\n') ? '' : '\n';
    final block = [
      '$separator# Variables agregadas automáticamente por OTA Updater',
      ...missingLines,
      '',
    ].join('\n');

    envFile.writeAsStringSync(block, mode: FileMode.append);
    log.log(
        'Saneamiento .env: ${missingLines.length} variable(s) nueva(s) agregada(s) (${missingLines.map((l) => l.split('=').first).join(', ')}).');
    return missingLines.length;
  } catch (e) {
    log.log('Advertencia verificando variables de .env: $e');
    return 0;
  }
}

/// Extrae la versión semver del nombre del archivo ZIP para el log y ota_result.txt.
/// Soporta formatos:
/// - update_v2.2.0.zip
/// - update_backend_v2.2.0.zip
/// - update_backend_app_v2.2.0.zip
String extractVersionFromZipPath(String zipPath) {
  final name = p.basename(zipPath);
  final match = RegExp(r'v(\d+\.\d+[\.\d]*)').firstMatch(name);
  if (match == null) return 'desconocida';
  return match.group(1)!.replaceAll(RegExp(r'\.$'), '');
}
