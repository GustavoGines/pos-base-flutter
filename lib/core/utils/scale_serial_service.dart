import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';

/// Información descriptiva de un puerto serie detectado en el sistema operativo
class SerialPortInfo {
  final String portName;
  final String? description;
  final String? manufacturer;

  const SerialPortInfo({
    required this.portName,
    this.description,
    this.manufacturer,
  });

  /// Nombre amigable para mostrar en listas desplegables (ej: "COM3 — USB-SERIAL CH340")
  String get displayName {
    if (description != null && description!.trim().isNotEmpty) {
      return '$portName — ${description!.trim()}';
    }
    return portName;
  }

  @override
  String toString() => displayName;
}

/// Resultado de una operación de lectura desde la balanza
class ScaleReadResult {
  final bool success;
  final double? weightKg;
  final String rawData;
  final String? errorMessage;

  const ScaleReadResult({
    required this.success,
    this.weightKg,
    this.rawData = '',
    this.errorMessage,
  });

  factory ScaleReadResult.success(double weightKg, {String rawData = ''}) {
    return ScaleReadResult(
      success: true,
      weightKg: weightKg,
      rawData: rawData,
    );
  }

  factory ScaleReadResult.failure(String errorMessage, {String rawData = ''}) {
    return ScaleReadResult(
      success: false,
      rawData: rawData,
      errorMessage: errorMessage,
    );
  }
}

/// Servicio universal para detección y lectura de balanzas electrónicas comerciales
/// (Systel, Kretz, Moretti, Toledo, Torrey, CAS, etc.) vía puerto serie / USB.
class ScaleSerialService {
  ScaleSerialService._();
  static final ScaleSerialService instance = ScaleSerialService._();

  Future<ScaleReadResult>? _activeReadFuture;

  /// Obtiene la lista de puertos serie disponibles en el sistema con su información amigable
  List<SerialPortInfo> getAvailablePorts() {
    try {
      final portNames = SerialPort.availablePorts;
      final List<SerialPortInfo> results = [];

      for (final name in portNames) {
        String? desc;
        String? mfg;
        try {
          final port = SerialPort(name);
          desc = port.description;
          mfg = port.manufacturer;
          port.dispose();
        } catch (e) {
          debugPrint('Error al inspeccionar metadata del puerto $name: $e');
        }
        results.add(SerialPortInfo(
          portName: name,
          description: desc,
          manufacturer: mfg,
        ));
      }

      return results;
    } catch (e) {
      debugPrint('Error al listar puertos serie del sistema: $e');
      return [];
    }
  }

  /// Extrae un peso numérico de una única línea/trama individual ya normalizada.
  static double? _extractWeightFromSingleFrame(String frame) {
    if (frame.trim().isEmpty) return null;
    final normalized = frame.replaceAll(',', '.');

    // Patrón primario: signo opcional y número con 2 o 3 decimales (ej: 1.250 o 01.25)
    final RegExp regex = RegExp(r'(?:[+\-]|\b)\s*(\d{1,4}\.\d{2,3})\b');
    final matches = regex.allMatches(normalized);
    if (matches.isNotEmpty) {
      final valStr = matches.last.group(1);
      if (valStr != null) {
        final parsed = double.tryParse(valStr);
        if (parsed != null) return parsed;
      }
    }

    // Fallback para balanzas que envían 1 decimal o formatos compactos
    final RegExp fallbackRegex = RegExp(r'(\d+\.\d+)');
    final fallbackMatches = fallbackRegex.allMatches(normalized);
    if (fallbackMatches.isNotEmpty) {
      return double.tryParse(fallbackMatches.last.group(0)!);
    }

    return null;
  }

  /// Indica si una trama individual está marcada explícitamente como inestable ("US")
  static bool _isUnstableFrame(String frame) {
    final upper = frame.toUpperCase();
    return upper.contains('US,') || upper.startsWith('US ');
  }

  /// Parser robusto de tramas recibidas desde balanzas comerciales.
  /// Extrae el peso numérico en kilogramos limpiando encabezados, unidades y
  /// descartando colas truncadas al final del buffer serial.
  ///
  /// Ejemplos soportados:
  /// - "ST,GS,+0001.250kg\r\n" -> 1.250
  /// - "US,GS,+0000.500kg\r\n" -> 0.500
  /// - "01.258\r\n01.2"        -> 1.258 (ignora la cola incompleta "01.2")
  /// - "001,450"               -> 1.450
  /// - "P 002.300\r"           -> 2.300
  /// - "=00.750\r"             -> 0.750
  /// - "+  1.250 kg"           -> 1.250
  static double? parseWeightString(String rawData, {bool requireCompleteFrame = false}) {
    if (rawData.trim().isEmpty) return null;

    // Verificar si el stream tiene delimitadores de fin de trama (\r, \n o ETX \x03)
    final bool hasDelimiters = rawData.contains('\r') ||
        rawData.contains('\n') ||
        rawData.contains('\x03');

    if (hasDelimiters) {
      // Separar por delimitadores conservando solo las tramas que finalizaron en un delimitador
      final parts = rawData.split(RegExp(r'[\r\n\x03]+'));
      final bool endsWithDelimiter =
          rawData.endsWith('\r') || rawData.endsWith('\n') || rawData.endsWith('\x03');

      // Si no termina en delimitador, el último elemento de `parts` es una cola en tránsito (posiblemente truncada)
      final int completeCount = endsWithDelimiter ? parts.length : parts.length - 1;

      double? lastValidWeight;
      double? lastStableWeight;

      for (int i = 0; i < completeCount; i++) {
        final frame = parts[i].trim();
        if (frame.isEmpty) continue;
        final w = _extractWeightFromSingleFrame(frame);
        if (w != null) {
          lastValidWeight = w;
          if (!_isUnstableFrame(frame)) {
            lastStableWeight = w;
          }
        }
      }

      if (lastStableWeight != null) return lastStableWeight;
      if (!requireCompleteFrame && lastValidWeight != null) return lastValidWeight;

      // Si se requería trama completa y estable pero aún no llegó, retornar null para seguir escuchando
      if (requireCompleteFrame) return null;
    }

    if (requireCompleteFrame) {
      return null;
    }

    // Fallback cuando la balanza envía una única trama sin delimitadores CR/LF
    return _extractWeightFromSingleFrame(rawData);
  }

  /// Lee el peso desde el puerto serie indicado de forma segura contra doble clic.
  Future<ScaleReadResult> readWeight(
    String comPort, {
    Duration timeout = const Duration(milliseconds: 2000),
  }) {
    if (_activeReadFuture != null) {
      return _activeReadFuture!;
    }
    final future = _performReadWeight(comPort, timeout: timeout);
    _activeReadFuture = future;
    return future.whenComplete(() {
      _activeReadFuture = null;
    });
  }

  /// Implementación interna híbrida e inteligente:
  /// 1. Abre el puerto a 9600 8N1 con líneas DTR/RTS activas (aisladas para puertos virtuales).
  /// 2. Escucha durante 250ms por si la balanza transmite en Modo Continuo.
  /// 3. Si no recibe datos, envía automáticamente el pulso de interrogación (ENQ / 'P\r')
  ///    para activar balanzas en modo "A Pedido" (Systel/Kretz/Moretti).
  /// 4. Espera una trama completa terminada en CR/LF/ETX o una ventana de silencio de 100ms
  ///    para jamás truncar el último dígito decimal.
  Future<ScaleReadResult> _performReadWeight(
    String comPort, {
    required Duration timeout,
  }) async {
    final trimmedPort = comPort.trim();
    if (trimmedPort.isEmpty) {
      return ScaleReadResult.failure('No se ha configurado el puerto COM de la balanza.');
    }

    SerialPort? port;
    StreamSubscription? subscription;
    Timer? quietWindowTimer;

    try {
      port = SerialPort(trimmedPort);

      // Intentar abrir en modo lectura/escritura (para poder enviar comando de polling)
      bool opened = port.openReadWrite();
      if (!opened) {
        // Fallback a modo solo lectura si el driver o cable no admite escritura
        opened = port.openRead();
      }

      if (!opened) {
        final err = SerialPort.lastError;
        final errMsg = err != null ? ' (${err.message})' : '';
        return ScaleReadResult.failure(
          'No se pudo abrir el puerto $trimmedPort$errMsg. Verifique que otra aplicación no lo esté usando.',
        );
      }

      // 1. Configuración base obligatoria (9600 baudios, 8N1)
      final config = port.config;
      config.baudRate = 9600;
      config.bits = 8;
      config.stopBits = 1;
      config.parity = SerialPortParity.none;
      port.config = config;

      // 2. Activar DTR/RTS en bloque aislado (algunos puertos virtuales rechazan pines físicos)
      try {
        config.dtr = SerialPortDtr.on;
        config.rts = SerialPortRts.on;
        port.config = config;
      } catch (e) {
        debugPrint('Puerto $trimmedPort no admite control manual de DTR/RTS: $e');
      }

      String accumulatedData = '';
      final reader = SerialPortReader(port, timeout: 100);
      final completer = Completer<ScaleReadResult>();

      subscription = reader.stream.listen((data) {
        final chunk = String.fromCharCodes(data);
        accumulatedData += chunk;

        // A. Si ya llegó al menos una línea completa cerrada por \r, \n o \x03 y estable >= 1 gramo (0.001 Kg):
        final completeFrameWeight =
            parseWeightString(accumulatedData, requireCompleteFrame: true);
        if (completeFrameWeight != null && completeFrameWeight >= 0.001) {
          quietWindowTimer?.cancel();
          if (!completer.isCompleted) {
            completer.complete(ScaleReadResult.success(
              completeFrameWeight,
              rawData: accumulatedData,
            ));
          }
          return;
        }

        // B. Si la balanza no envía CR/LF al final de la trama, esperar 100ms de silencio
        // después del último byte recibido para garantizar que llegaron todos los decimales.
        quietWindowTimer?.cancel();
        quietWindowTimer = Timer(const Duration(milliseconds: 100), () {
          if (completer.isCompleted) return;
          final settledWeight =
              parseWeightString(accumulatedData, requireCompleteFrame: false);
          if (settledWeight != null && settledWeight >= 0.001) {
            completer.complete(ScaleReadResult.success(
              settledWeight,
              rawData: accumulatedData,
            ));
          }
        });
      }, onError: (err) {
        quietWindowTimer?.cancel();
        if (!completer.isCompleted) {
          completer.complete(ScaleReadResult.failure(
            'Error durante la lectura del puerto $trimmedPort: $err',
            rawData: accumulatedData,
          ));
        }
      });

      // Esperar los primeros 250ms por si la balanza ya está en modo continuo
      await Future.delayed(const Duration(milliseconds: 250));

      if (!completer.isCompleted && accumulatedData.isEmpty) {
        // La balanza no envía datos continuos: enviar pulso de interrogación (Polling)
        try {
          // 1. ENQ (0x05) estándar para Systel Cuora, Kretz Report/Novel, Toledo
          port.write(Uint8List.fromList([0x05]), timeout: 200);
          // 2. 'P\r' (0x50, 0x0D) estándar para Systel Croma/Bumerang, Moretti
          port.write(Uint8List.fromList([0x50, 0x0D]), timeout: 200);
        } catch (e) {
          debugPrint('Advertencia: No se pudo enviar comando de polling a $trimmedPort: $e');
        }
      }

      // Esperar hasta que se complete o se cumpla el timeout total
      final remainingTimeout = timeout - const Duration(milliseconds: 250);
      final timeoutDuration = remainingTimeout.isNegative
          ? const Duration(milliseconds: 1500)
          : remainingTimeout;

      final result = await completer.future.timeout(
        timeoutDuration,
        onTimeout: () {
          quietWindowTimer?.cancel();
          // Evaluar si se recibió algo al expirar el tiempo (incluyendo tramas US inestables)
          final finalParsed =
              parseWeightString(accumulatedData, requireCompleteFrame: false);
          if (finalParsed != null) {
            if (finalParsed < 0.001) {
              return ScaleReadResult.failure(
                'La balanza está en cero (0.000 Kg). Coloque el producto sobre el plato.',
                rawData: accumulatedData,
              );
            }
            return ScaleReadResult.success(finalParsed, rawData: accumulatedData);
          }

          if (accumulatedData.isNotEmpty) {
            return ScaleReadResult.failure(
              'No se detectó un peso numérico válido. Trama recibida: "$accumulatedData"',
              rawData: accumulatedData,
            );
          }

          return ScaleReadResult.failure(
            'No se recibió respuesta de la balanza en $trimmedPort. Verifique el cable y que esté encendida.',
            rawData: accumulatedData,
          );
        },
      );

      return result;
    } catch (e) {
      return ScaleReadResult.failure('Error al comunicar con la balanza: $e');
    } finally {
      quietWindowTimer?.cancel();
      await subscription?.cancel();
      try {
        port?.close();
        port?.dispose();
      } catch (_) {}
    }
  }
}
