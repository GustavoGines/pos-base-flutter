import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive_io.dart';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

/// Constantes Win32 para control de consola (kernel32.dll).
const int kWin32StdInputHandle = -10; // STD_INPUT_HANDLE
const int kWin32EnableQuickEditMode = 0x0040; // ENABLE_QUICK_EDIT_MODE
const int kWin32EnableExtendedFlags = 0x0080; // ENABLE_EXTENDED_FLAGS

typedef _GetStdHandleNative = IntPtr Function(Int32 nStdHandle);
typedef _GetStdHandleDart = int Function(int nStdHandle);

typedef _GetConsoleModeNative = Int32 Function(
  IntPtr hConsoleHandle,
  Pointer<Uint32> lpMode,
);
typedef _GetConsoleModeDart = int Function(
  int hConsoleHandle,
  Pointer<Uint32> lpMode,
);

typedef _SetConsoleModeNative = Int32 Function(
  IntPtr hConsoleHandle,
  Uint32 dwMode,
);
typedef _SetConsoleModeDart = int Function(
  int hConsoleHandle,
  int dwMode,
);

typedef _SetConsoleTitleWNative = Int32 Function(Pointer<Utf16> lpConsoleTitle);
typedef _SetConsoleTitleWDart = int Function(Pointer<Utf16> lpConsoleTitle);

/// Aplica la máscara Win32 `(mode & ~0x0040) | 0x0080`
/// (`~ENABLE_QUICK_EDIT_MODE | ENABLE_EXTENDED_FLAGS`) para desactivar
/// la pausa accidental por clic en la ventana de consola de Windows.
int computeQuickEditDisabledConsoleMode(int mode) {
  return ((mode & ~kWin32EnableQuickEditMode) | kWin32EnableExtendedFlags) &
      0xFFFFFFFF;
}

/// Desactiva `ENABLE_QUICK_EDIT_MODE` sobre `STD_INPUT_HANDLE (-10)` vía
/// `kernel32.dll` para impedir que un clic accidental en la ventana negra
/// ponga la consola en modo "Seleccionar" y congele el actualizador.
/// Opcionalmente actualiza el título de la ventana de consola.
/// Envuelto en `try/catch` para no fallar si no hay consola interactiva o en tests.
bool disableWindowsConsoleQuickEdit({String? consoleTitle}) {
  if (!Platform.isWindows) return false;
  try {
    final kernel32 = DynamicLibrary.open('kernel32.dll');

    if (consoleTitle != null && consoleTitle.isNotEmpty) {
      try {
        final setConsoleTitle = kernel32
            .lookupFunction<_SetConsoleTitleWNative, _SetConsoleTitleWDart>(
          'SetConsoleTitleW',
        );
        final titlePtr = consoleTitle.toNativeUtf16();
        try {
          setConsoleTitle(titlePtr);
        } finally {
          calloc.free(titlePtr);
        }
      } catch (_) {}
    }

    final getStdHandle = kernel32
        .lookupFunction<_GetStdHandleNative, _GetStdHandleDart>('GetStdHandle');
    final getConsoleMode =
        kernel32.lookupFunction<_GetConsoleModeNative, _GetConsoleModeDart>(
      'GetConsoleMode',
    );
    final setConsoleMode =
        kernel32.lookupFunction<_SetConsoleModeNative, _SetConsoleModeDart>(
      'SetConsoleMode',
    );

    final handle = getStdHandle(kWin32StdInputHandle); // -10 (STD_INPUT_HANDLE)
    if (handle == 0 || handle == -1) {
      return false;
    }

    final modePtr = calloc<Uint32>();
    try {
      final okGet = getConsoleMode(handle, modePtr);
      if (okGet == 0) {
        return false;
      }
      final currentMode = modePtr.value;
      final newMode = computeQuickEditDisabledConsoleMode(currentMode);
      final okSet = setConsoleMode(handle, newMode);
      return okSet != 0;
    } finally {
      calloc.free(modePtr);
    }
  } catch (_) {
    return false;
  }
}

/// Resultado estadístico de una operación de extracción diferencial OTA.
class OtaExtractionStats {
  final bool extractionOk;
  final int filesExtracted;
  final int filesUnchanged;
  final int filesSkipped;
  final int filesRolledBack;
  final bool wroteBinaries;
  final Uint8List? deferredVersionTxtBytes;
  final Uint8List? newManifestBytes;

  const OtaExtractionStats({
    required this.extractionOk,
    required this.filesExtracted,
    required this.filesUnchanged,
    required this.filesSkipped,
    this.filesRolledBack = 0,
    required this.wroteBinaries,
    this.deferredVersionTxtBytes,
    this.newManifestBytes,
  });
}

/// Logger: escribe en stdout, en updater_log.txt del directorio destino,
/// y en un historial persistente en C:\ProgramData\Dev4U\Caja4U\logs\updater_history.log
/// que sobrevive a reinstalaciones o desinstalaciones.
class OtaLogger {
  final File _file;
  final File? _persistentFile;
  final String _sessionId;
  final StringBuffer _buffer = StringBuffer();
  DateTime _lastFlush = DateTime.now();
  bool _bufferedMode = false;

  OtaLogger(String targetDir, {String? persistentLogDir})
      : _file = File(p.join(targetDir, 'updater_log.txt')),
        _persistentFile = _resolvePersistentLogFile(persistentLogDir),
        _sessionId = DateTime.now().millisecondsSinceEpoch.toString();

  static File? _resolvePersistentLogFile(String? customDir) {
    try {
      if (customDir != null && customDir.isNotEmpty) {
        final dir = Directory(customDir);
        dir.createSync(recursive: true);
        return File(p.join(dir.path, 'updater_history.log'));
      }
      if (Platform.isWindows) {
        final progData =
            Platform.environment['ProgramData'] ?? r'C:\ProgramData';
        final dir = Directory(p.join(progData, 'Dev4U', 'Caja4U', 'logs'));
        dir.createSync(recursive: true);
        return File(p.join(dir.path, 'updater_history.log'));
      }
    } catch (_) {}
    return null;
  }

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
    try {
      _persistentFile?.writeAsStringSync('\n$header', mode: FileMode.append);
    } catch (_) {}
  }

  void setBufferedMode(bool enabled) {
    if (!enabled) {
      flush();
    }
    _bufferedMode = enabled;
  }

  void flush() {
    if (_buffer.isEmpty) return;
    final chunk = _buffer.toString();
    try {
      _file.writeAsStringSync(chunk, mode: FileMode.append);
    } catch (_) {}
    try {
      _persistentFile?.writeAsStringSync(chunk, mode: FileMode.append);
    } catch (_) {}
    _buffer.clear();
    _lastFlush = DateTime.now();
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
    try {
      _persistentFile?.writeAsStringSync('$line\n', mode: FileMode.append);
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

/// Ejecuta la extracción diferencial y atómica de un `Archive` sobre `targetDir`:
/// - Compara `size` y `crc32` del Central Directory contra el archivo local
///   ANTES de acceder a `file.content` (evitando descompresión ZLib y escrituras
///   NTFS en archivos idénticos).
/// - Escribe primero en un archivo temporal `$filePath.ota_tmp` y verifica su tamaño
///   antes de reemplazar el archivo original, resguardando una copia `.ota_bak` de
///   cada archivo modificado durante la sesión.
/// - Si algún archivo falla al extraerse (`filesSkipped > 0`) y [rollbackOnPartialFailure]
///   es `true` (por defecto `true`), revierte todos los archivos `.ota_bak` y elimina
///   los archivos nuevos creados en la sesión, garantizando que `vendor/` jamás quede
///   a medias ni con archivos faltantes.
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
  bool rollbackOnPartialFailure = true,
}) {
  int filesExtracted = 0;
  int filesUnchanged = 0;
  int filesSkipped = 0;
  int filesRolledBack = 0;
  bool wroteBinaries = false;
  Uint8List? deferredVersionTxtBytes;
  Uint8List? newManifestBytes;

  // Registro transaccional para rollback seguro si algún archivo está bloqueado
  final Map<String, String> sessionBackups = <String, String>{};
  final List<String> newlyCreatedFiles = <String>[];
  final String sessionTag = DateTime.now().millisecondsSinceEpoch.toString();

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

        // 5. El archivo es nuevo o cambió -> descomprimir a archivo temporal .ota_tmp
        //    y reemplazar de forma atómica preservando backup .ota_bak de la sesión
        final data = file.content;
        final isBinary =
            lowerName.endsWith('.exe') || lowerName.endsWith('.dll');
        final bool existedBefore = outFile.existsSync();
        final String tmpPath = '$filePath.ota_tmp_$sessionTag';
        final File tmpFile = File(tmpPath);

        bool written = false;
        Object? lastWriteErr;

        // Paso 5a: Escribir bytes completos en el archivo temporal .ota_tmp
        for (int attempt = 1; attempt <= 3; attempt++) {
          try {
            tmpFile.parent.createSync(recursive: true);
            tmpFile.writeAsBytesSync(data, flush: true);
            if (tmpFile.existsSync() && tmpFile.lengthSync() == data.length) {
              written = true;
              break;
            }
          } catch (e) {
            lastWriteErr = e;
            if (attempt < 3) {
              sleep(Duration(milliseconds: 200 * attempt));
            }
          }
        }

        if (!written) {
          try {
            if (tmpFile.existsSync()) tmpFile.deleteSync();
          } catch (_) {}
          log.err(
              '  No se pudo escribir archivo temporal para $normName ($lastWriteErr)');
          filesSkipped++;
          file.clear();
          continue;
        }

        // Paso 5b: Resguardar el archivo original en .ota_bak (sin eliminarlo todavía)
        // y promover el temporal .ota_tmp a la ruta definitiva.
        bool promoted = false;
        final String backupPath = '$filePath.ota_bak_$sessionTag';

        for (int attempt = 1; attempt <= 3; attempt++) {
          try {
            if (outFile.existsSync()) {
              if (!sessionBackups.containsKey(filePath)) {
                final bakFile = File(backupPath);
                if (bakFile.existsSync()) bakFile.deleteSync();
                outFile.renameSync(backupPath);
                sessionBackups[filePath] = backupPath;
              } else {
                outFile.deleteSync();
              }
            }
            tmpFile.renameSync(filePath);
            promoted = true;
            break;
          } catch (e) {
            lastWriteErr = e;
            // Si habíamos renombrado el original a backup pero falló mover el tmp,
            // restaurar inmediatamente el original si aún no existe outFile
            try {
              if (!outFile.existsSync() && File(backupPath).existsSync()) {
                File(backupPath).renameSync(filePath);
                sessionBackups.remove(filePath);
              }
            } catch (_) {}
            if (attempt < 3) {
              sleep(Duration(milliseconds: 250 * attempt));
            }
          }
        }

        if (promoted) {
          if (!existedBefore) {
            newlyCreatedFiles.add(filePath);
          }
          filesExtracted++;
          if (isBinary) {
            wroteBinaries = true;
          }
          if (filesExtracted % 25 == 0) {
            log.log('  → $filesExtracted archivos actualizados/nuevos...');
          }
        } else {
          try {
            if (tmpFile.existsSync()) tmpFile.deleteSync();
          } catch (_) {}
          log.err('  BLOQUEADO SIN SOLUCIÓN: $normName ($lastWriteErr)');
          filesSkipped++;
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

    // 6. Commit o Rollback transaccional de los backups .ota_bak de esta sesión
    if (filesSkipped == 0 || !rollbackOnPartialFailure) {
      for (final bakPath in sessionBackups.values) {
        try {
          final f = File(bakPath);
          if (f.existsSync()) f.deleteSync();
        } catch (_) {}
      }
    } else {
      log.err(
          'Iniciando rollback transaccional debido a $filesSkipped archivo(s) bloqueado(s)...');
      // Revertir archivos modificados desde su .ota_bak intacto
      for (final entry in sessionBackups.entries) {
        final origPath = entry.key;
        final bakPath = entry.value;
        try {
          final bakFile = File(bakPath);
          if (bakFile.existsSync()) {
            final origFile = File(origPath);
            if (origFile.existsSync()) {
              origFile.deleteSync();
            }
            bakFile.renameSync(origPath);
            filesRolledBack++;
          }
        } catch (e) {
          log.err('  Error restaurando backup de $origPath: $e');
        }
      }
      // Eliminar archivos nuevos creados en esta sesión fallida
      for (final createdPath in newlyCreatedFiles) {
        try {
          final f = File(createdPath);
          if (f.existsSync()) f.deleteSync();
        } catch (_) {}
      }
      log.log(
          'Rollback transaccional completado: $filesRolledBack archivo(s) restaurado(s) a su versión previa intacta.');
    }
  } finally {
    log.setBufferedMode(false);
  }

  log.log(
    'Extracción diferencial completada: '
    '$filesExtracted actualizados/nuevos, '
    '$filesUnchanged sin cambios (omitidos por CRC-32), '
    '$filesSkipped fallidos'
    '${filesRolledBack > 0 ? ', $filesRolledBack revertidos por rollback' : ''}.',
    forceFlush: true,
  );

  return OtaExtractionStats(
    extractionOk: filesSkipped == 0,
    filesExtracted: filesExtracted,
    filesUnchanged: filesUnchanged,
    filesSkipped: filesSkipped,
    filesRolledBack: filesRolledBack,
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
/// actualiza por OTA desde `v1.4.4` o `v1.8.5` tenga definidas las variables críticas de
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

/// Genera un respaldo automático de la base de datos MySQL (`mysqldump`) en
/// `C:\ProgramData\Dev4U\Caja4U\backups\pre_ota_v<version>_<timestamp>.sql`
/// antes de ejecutar `php artisan migrate --force`, rotando los respaldos más
/// antiguos para conservar los últimos 10 archivos.
String? createPreMigrationDatabaseBackup({
  required String targetDir,
  required String version,
  required OtaLogger log,
  String? customBackupDir,
}) {
  try {
    // 1. Leer credenciales DB_* del archivo .env del backend
    String dbName = 'sistema_pos';
    String dbUser = 'root';
    String dbPass = '';
    String dbHost = '127.0.0.1';
    String dbPort = '3306';

    final envFile = File(p.join(targetDir, '.env'));
    if (envFile.existsSync()) {
      for (final rawLine in envFile.readAsLinesSync()) {
        final line = rawLine.trim();
        if (line.isEmpty || line.startsWith('#')) continue;
        final eqIdx = line.indexOf('=');
        if (eqIdx <= 0) continue;
        final k = line.substring(0, eqIdx).trim();
        var v = line.substring(eqIdx + 1).trim();
        if ((v.startsWith('"') && v.endsWith('"')) ||
            (v.startsWith("'") && v.endsWith("'"))) {
          v = v.substring(1, v.length - 1);
        }
        if (k == 'DB_DATABASE' && v.isNotEmpty) dbName = v;
        if (k == 'DB_USERNAME' && v.isNotEmpty) dbUser = v;
        if (k == 'DB_PASSWORD') dbPass = v;
        if (k == 'DB_HOST' && v.isNotEmpty) dbHost = v;
        if (k == 'DB_PORT' && v.isNotEmpty) dbPort = v;
      }
    }

    // 2. Localizar mysqldump.exe en Laragon o PATH
    String? mysqldumpExe;
    final laragonMysqlBase = Directory(r'C:\laragon\bin\mysql');
    if (laragonMysqlBase.existsSync()) {
      final mysqlDirs = laragonMysqlBase
          .listSync()
          .whereType<Directory>()
          .toList()
        ..sort((a, b) => b.path.compareTo(a.path));
      for (final dir in mysqlDirs) {
        final candidate = File(p.join(dir.path, 'bin', 'mysqldump.exe'));
        if (candidate.existsSync()) {
          mysqldumpExe = candidate.path;
          break;
        }
      }
    }

    if (mysqldumpExe == null) {
      try {
        final whereRes =
            Process.runSync('where.exe', ['mysqldump'], runInShell: false);
        if (whereRes.exitCode == 0) {
          final found =
              whereRes.stdout.toString().trim().split('\n').first.trim();
          if (found.isNotEmpty && File(found).existsSync()) {
            mysqldumpExe = found;
          }
        }
      } catch (_) {}
    }

    if (mysqldumpExe == null) {
      log.log(
          'Advertencia: mysqldump.exe no encontrado — se omite backup previo a migración.');
      return null;
    }

    // 3. Resolver directorio persistente de backups
    Directory backupDir;
    if (customBackupDir != null && customBackupDir.isNotEmpty) {
      backupDir = Directory(customBackupDir);
    } else {
      final progData =
          Platform.environment['ProgramData'] ?? r'C:\ProgramData';
      backupDir = Directory(p.join(progData, 'Dev4U', 'Caja4U', 'backups'));
    }
    try {
      backupDir.createSync(recursive: true);
    } catch (_) {
      backupDir = Directory(p.join(targetDir, 'storage', 'app', 'backups'));
      backupDir.createSync(recursive: true);
    }

    // Resguardar también copia de .env
    if (envFile.existsSync()) {
      try {
        envFile.copySync(p.join(backupDir.path, '.env.backup'));
      } catch (_) {}
    }

    final now = DateTime.now();
    final ts =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    final safeVer = version.replaceAll(RegExp(r'[^0-9A-Za-z\._-]'), '_');
    final dumpPath =
        p.join(backupDir.path, 'pre_ota_v${safeVer}_$ts.sql');

    final args = <String>[
      '-h',
      dbHost,
      '-P',
      dbPort,
      '-u',
      dbUser,
      if (dbPass.isNotEmpty) '-p$dbPass',
      '--single-transaction',
      '--routines',
      '--triggers',
      '--result-file=$dumpPath',
      dbName,
    ];

    log.log('Generando respaldo automático de BD ($dbName) en: $dumpPath');
    final res = Process.runSync(mysqldumpExe, args, runInShell: false);
    final dumpFile = File(dumpPath);

    if (res.exitCode == 0 &&
        dumpFile.existsSync() &&
        dumpFile.lengthSync() > 0) {
      final mb = (dumpFile.lengthSync() / 1024 / 1024).toStringAsFixed(2);
      log.log('  ✓ Respaldo de BD completado exitosamente ($mb MB).');

      // Rotación: conservar los 10 respaldos pre_ota_*.sql más recientes
      try {
        final dumps = backupDir
            .listSync()
            .whereType<File>()
            .where((f) =>
                p.basename(f.path).startsWith('pre_ota_') &&
                f.path.endsWith('.sql'))
            .toList()
          ..sort((a, b) =>
              b.lastModifiedSync().compareTo(a.lastModifiedSync()));
        if (dumps.length > 10) {
          for (final oldDump in dumps.sublist(10)) {
            try {
              oldDump.deleteSync();
            } catch (_) {}
          }
        }
      } catch (_) {}

      return dumpPath;
    } else {
      log.log(
          '  Advertencia: mysqldump retornó código ${res.exitCode}: ${res.stderr.toString().trim()}');
      return null;
    }
  } catch (e) {
    log.log('  Advertencia generando respaldo automático de BD: $e');
    return null;
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

/// Runner inyectable de procesos del sistema para permitir pruebas deterministas
/// del ciclo de suspensión y restauración de servicios en segundo plano.
typedef OtaProcessRunner = ProcessResult Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
});

ProcessResult _defaultOtaProcessRunner(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
}) {
  return Process.runSync(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
  );
}

/// Tareas programadas de Windows administradas durante una OTA de Backend.
const List<String> kBackendScheduledTasks = <String>[
  'SistemaPOS_Schedule',
  'SistemaPOS_Queue',
  'SistemaPOS_Reverb',
];

/// Orden de arranque de las tareas programadas al finalizar la OTA de Backend.
const List<String> kBackendScheduledTasksStartOrder = <String>[
  'SistemaPOS_Reverb',
  'SistemaPOS_Queue',
  'SistemaPOS_Schedule',
];

/// Ejecuta [action] durante una actualización OTA de **Backend** garantizando:
/// 1. Antes de extraer o migrar:
///    - Señal elegante `queue:restart` y `reverb:restart` si existe `artisan`.
///    - `schtasks /change /tn <tarea> /disable` en las 3 tareas para impedir que
///      `SistemaPOS_Schedule` (cada 1 min) se dispare en medio de la extracción o migración.
///    - `schtasks /end /tn <tarea>` y `taskkill /F /IM php-win.exe /T` para liberar locks.
/// 2. En un bloque `try / finally` incondicional (incluso ante ZIP corrupto, rollback o excepción):
///    - `schtasks /change /tn <tarea> /enable` en las 3 tareas (ninguna tarea queda deshabilitada).
///    - Si la acción tuvo éxito y existe `instalar_tareas_bg.bat`, refresca las tareas validando su
///      `exitCode` real; si la acción falló, no existe el script o retornó error (`!= 0`), re-asegura
///      `/enable` y ejecuta `schtasks /run /tn <tarea>` directamente.
Future<T> runWithBackendServicesSuspended<T>({
  required String targetDir,
  required String phpExe,
  required Map<String, String> phpEnv,
  required OtaLogger log,
  required Future<T> Function() action,
  bool Function(T result)? isActionSuccessful,
  OtaProcessRunner processRunner = _defaultOtaProcessRunner,
  Duration postStopDelay = const Duration(seconds: 2),
}) async {
  final Map<String, String>? envOrNull = phpEnv.isNotEmpty ? phpEnv : null;
  final String artisanPath = p.join(targetDir, 'artisan');

  log.log(
      'Deshabilitando y deteniendo temporalmente tareas y workers en segundo plano antes de extraer...');

  if (File(artisanPath).existsSync()) {
    for (final stopCmd in const ['queue:restart', 'reverb:restart']) {
      try {
        processRunner(
          phpExe,
          [artisanPath, stopCmd],
          workingDirectory: targetDir,
          environment: envOrNull,
        );
      } catch (_) {}
    }
  }

  for (final taskName in kBackendScheduledTasks) {
    try {
      final disRes = processRunner(
        'schtasks',
        ['/change', '/tn', taskName, '/disable'],
      );
      if (disRes.exitCode == 0) {
        log.log('  schtasks /disable $taskName: OK');
      }
    } catch (_) {}
  }

  for (final taskName in kBackendScheduledTasks) {
    try {
      processRunner('schtasks', ['/end', '/tn', taskName]);
    } catch (_) {}
  }

  try {
    processRunner('taskkill', ['/F', '/IM', 'php-win.exe', '/T']);
  } catch (_) {}

  if (postStopDelay > Duration.zero) {
    await Future<void>.delayed(postStopDelay);
  }

  bool actionSucceeded = false;
  try {
    final T result = await action();
    actionSucceeded =
        isActionSuccessful != null ? isActionSuccessful(result) : true;
    return result;
  } finally {
    log.log(
        'Restaurando y reactivando tareas en segundo plano (bloque finally garantizado)...');

    // 1. Garantizar SIEMPRE que ninguna tarea quede en estado Disabled
    for (final taskName in kBackendScheduledTasks) {
      try {
        final enRes = processRunner(
          'schtasks',
          ['/change', '/tn', taskName, '/enable'],
        );
        if (enRes.exitCode == 0) {
          log.log('  schtasks /enable $taskName: OK');
        } else {
          log.log(
              '  Advertencia: schtasks /enable $taskName retornó exitCode=${enRes.exitCode}');
        }
      } catch (e) {
        log.log('  Advertencia reactivando $taskName: $e');
      }
    }

    // 2. Si la OTA tuvo éxito, señalizar recarga de workers y refrescar instalar_tareas_bg.bat
    if (actionSucceeded && File(artisanPath).existsSync()) {
      for (final bgCmd in const ['queue:restart', 'reverb:restart']) {
        try {
          final qResult = processRunner(
            phpExe,
            [artisanPath, bgCmd],
            workingDirectory: targetDir,
            environment: envOrNull,
          );
          if (qResult.exitCode == 0) {
            log.log('  $bgCmd: OK');
          }
        } catch (e) {
          log.log('  Advertencia ejecutando $bgCmd (no bloqueante): $e');
        }
      }
    }

    bool tasksStartedByScript = false;
    final bgTasksScript = File(p.join(targetDir, 'instalar_tareas_bg.bat'));
    if (actionSucceeded && bgTasksScript.existsSync()) {
      log.log(
          'Refrescando configuración de tareas en segundo plano (instalar_tareas_bg.bat)...');
      try {
        final bgScriptResult = processRunner(
          'cmd.exe',
          ['/c', bgTasksScript.path],
          workingDirectory: targetDir,
          environment: envOrNull,
        );
        if (bgScriptResult.exitCode == 0) {
          tasksStartedByScript = true;
          log.log(
              '  instalar_tareas_bg.bat ejecutado correctamente (Reverb/Queue/Schedule activos).');
        } else {
          log.log(
              '  Advertencia: instalar_tareas_bg.bat retornó exitCode=${bgScriptResult.exitCode}. Re-asegurando /enable y ejecutando schtasks /run directo...');
          for (final taskName in kBackendScheduledTasks) {
            try {
              processRunner(
                'schtasks',
                ['/change', '/tn', taskName, '/enable'],
              );
            } catch (_) {}
          }
        }
      } catch (e) {
        log.log('  Advertencia ejecutando instalar_tareas_bg.bat: $e');
      }
    }

    // 3. Relanzar directamente las tareas si no fueron arrancadas por instalar_tareas_bg.bat
    if (!tasksStartedByScript) {
      for (final taskName in kBackendScheduledTasksStartOrder) {
        try {
          final runRes =
              processRunner('schtasks', ['/run', '/tn', taskName]);
          if (runRes.exitCode == 0) {
            log.log('  schtasks /run $taskName: OK');
          } else {
            log.log(
                '  Advertencia: schtasks /run $taskName retornó exitCode=${runRes.exitCode}');
          }
        } catch (_) {}
      }
    }
  }
}
