import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

void main(List<String> args) async {
  if (args.length < 2) {
    print('Uso: updater.exe <ruta_zip> <ruta_instalacion>');
    exit(1);
  }

  final zipPath = args[0];
  final installPath = args[1];

  print('Updater Iniciado.');
  print('Ruta ZIP: $zipPath');
  print('Ruta Destino: $installPath');

  // 1. Esperar 3 segundos para que la aplicación principal se cierre
  print('Esperando 3 segundos a que la aplicación principal libere los archivos...');
  await Future.delayed(const Duration(seconds: 3));

  // 2. Extraer el ZIP
  print('Extrayendo actualizaciones en el directorio...');
  try {
    final bytes = File(zipPath).readAsBytesSync();
    // decodeBytes se usa de archive
    final archive = ZipDecoder().decodeBytes(bytes);

    for (final file in archive) {
      final filename = file.name;
      if (file.isFile) {
        final data = file.content as List<int>;
        final filePath = p.join(installPath, filename);
        final outFile = File(filePath);
        outFile.createSync(recursive: true);
        outFile.writeAsBytesSync(data);
      } else {
        final dirPath = p.join(installPath, filename);
        Directory(dirPath).createSync(recursive: true);
      }
    }
    print('Extracción completada con éxito.');
  } catch (e) {
    print('Error extrayendo el ZIP: $e');
  }

  // 3. Ejecutar migraciones de Laravel
  final backendPath = p.join(installPath, 'pos-backend');
  if (Directory(backendPath).existsSync()) {
    print('Ejecutando php artisan migrate --force en backend...');
    try {
      final result = await Process.run(
        'php',
        ['artisan', 'migrate', '--force'],
        workingDirectory: backendPath,
      );
      print('Migración stdout: ${result.stdout}');
      if (result.stderr.toString().trim().isNotEmpty) {
        print('Migración stderr: ${result.stderr}');
      }
    } catch (e) {
      print('Error al intentar ejecutar la migración: $e');
    }
  } else {
    print('Advertencia: No se encontró la carpeta del backend en $backendPath (Se saltan migraciones).');
  }

  // 4. Volver a lanzar el Sistema
  final exePath = p.join(installPath, 'Sistema_POS.exe');
  if (File(exePath).existsSync()) {
    print('Lanzando la aplicación actualizada...');
    try {
      // Lanzamos la aplicación y nos desvinculamos del proceso para que el updater pueda morir
      await Process.start(exePath, [], workingDirectory: installPath, mode: ProcessStartMode.detached);
    } catch (e) {
      print('Error al abrir $exePath: $e');
    }
  } else {
    print('Advertencia: No se encontró $exePath para reabrir automáticamente.');
  }

  print('Proceso de actualización finalizado.');
  exit(0);
}
