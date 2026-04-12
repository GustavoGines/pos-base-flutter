import 'package:frontend_desktop/core/utils/currency_formatter.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter_pos_printer_platform_image_3/flutter_pos_printer_platform_image_3.dart';
import '../../../features/cash_register/domain/entities/cash_register_shift.dart';
import '../../../features/pos/domain/entities/cart_item.dart';
import '../../../features/settings/domain/entities/business_settings.dart';

/// Tipo de conexión con la impresora térmica
enum PrinterConnectionType {
  tcp, // Red (IP + Puerto) — la mayoría de impresoras WiFi y LAN
  usb, // Puerto COM/USB vía libserialport (Windows/Linux)
}

/// Configuración de la impresora
class PrinterConfig {
  final PrinterConnectionType connectionType;
  final String? tcpHost; // IP de la impresora (solo TCP)
  final int? tcpPort; // Puerto TCP (normalmente 9100)
  final String? comPort; // Puerto COM (solo USB, ej: "COM3")
  final int baudRate; // Velocidad del puerto serie (default: 115200)
  final PaperSize paperSize; // Tamaño del papel.

  const PrinterConfig({
    required this.connectionType,
    this.tcpHost,
    this.tcpPort = 9100,
    this.comPort,
    this.baudRate = 115200,
    this.paperSize = PaperSize.mm80,
  });

  /// Configuración de red por defecto (para impresoras IP)
  factory PrinterConfig.defaultTcp() => const PrinterConfig(
    connectionType: PrinterConnectionType.tcp,
    tcpHost: '192.168.1.100',
    tcpPort: 9100,
    paperSize: PaperSize.mm80,
  );

  /// Configuración USB/COM por defecto (Windows)
  factory PrinterConfig.defaultUsb() => const PrinterConfig(
    connectionType: PrinterConnectionType.usb,
    comPort: 'COM3',
    baudRate: 115200,
    paperSize: PaperSize.mm58,
  );
}

/// Servicio de impresión térmica ESC/POS para Flutter Desktop Windows
///
/// Soporta dos modos de conexión:
/// - [PrinterConnectionType.tcp]: Impresoras de red (WiFi / LAN) vía socket TCP.
/// - [PrinterConnectionType.usb]: Impresoras USB/COM via driver nativo de Windows.
///
/// Uso básico:
/// ```dart
/// final printer = ReceiptPrinterService(config: PrinterConfig.defaultTcp());
/// await printer.printSaleTicket(cartItems, total, settings);
/// ```
class ReceiptPrinterService {
  PrinterConfig config;

  // Singleton pattern
  static final ReceiptPrinterService _instance =
      ReceiptPrinterService._internal(config: PrinterConfig.defaultUsb());
  static ReceiptPrinterService get instance => _instance;

  // Cache para el perfil de capacidad (evita recargas constantes de assets que crashean en Windows)
  CapabilityProfile? _cachedProfile;

  ReceiptPrinterService._internal({required this.config});

  /// Inicializa los recursos pesados (como el perfil de capacidades) al arranque.
  /// Esto previene el error "Unable to load asset: AssetManifest.json" en medio de una venta.
  Future<void> initialize() async {
    try {
      _cachedProfile = await CapabilityProfile.load();
    } catch (e) {
      debugPrint('ReceiptPrinterService: Error al pre-cargar perfil, usando default: $e');
      _cachedProfile = null; // Forzará el uso de fallback
    }
  }

  /// Obtiene el perfil cargado o uno por defecto si falló la carga de assets.
  Future<CapabilityProfile> _getProfile() async {
    if (_cachedProfile != null) return _cachedProfile!;
    try {
      return await CapabilityProfile.load();
    } catch (_) {
      // Fallback definitivo para evitar crash
      return CapabilityProfile.load(); // Si esto también falla, esc_pos levantará su propia excepción manejable
    }
  }

  /// Permite reconfigurar el hardware en caliente (desde SettingsScreen)
  Future<void> reconfigureFromSettings(BusinessSettings settings) async {
    debugPrint('=== PrinterService: reconfigureFromSettings() ===');
    debugPrint('  printerType: ${settings.printerType}');
    debugPrint('  comPort: ${settings.printerComPort}');
    debugPrint('  tcpHost: ${settings.printerIpAddress}');

    PrinterConnectionType type;
    switch (settings.printerType.toLowerCase()) {
      case 'network':
        type = PrinterConnectionType.tcp;
        break;
      case 'usb':
        type = PrinterConnectionType.usb;
        break;
      default:
        type = PrinterConnectionType.usb;
    }

    final paperSize = (settings.printerPaperWidth == '80') ? PaperSize.mm80 : PaperSize.mm58;

    config = PrinterConfig(
      connectionType: type,
      tcpHost: settings.printerIpAddress,
      tcpPort: int.tryParse(settings.printerIpPort ?? '9100') ?? 9100,
      comPort: settings.printerComPort,
      paperSize: paperSize,
    );
    debugPrint('  -> Config aplicada: type=$type, comPort=${config.comPort}, paper=${config.paperSize}');
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // API PÚBLICA
  // ─────────────────────────────────────────────────────────────────────────────

  /// Imprime el ticket de una venta.
  ///
  /// Incluye: nombre del negocio, items, total, mensaje de pie de página
  /// y ejecuta el "Drawer Kick" (apertura de gaveta portamonedas).
  Future<void> printSaleTicket({
    required List<CartItem> items,
    required double total,
    required BusinessSettings settings,
    String paymentMethod = 'EFECTIVO',
    List<Map<String, dynamic>> paymentDetails = const [], // [{name, amount}]
    String? receiptNumber,
    String? userName,
    String? cashierName,
    double surchargeAmount = 0.0,
    double tenderedAmount = 0.0,
    double changeAmount = 0.0,
  }) async {
    // Guardia: si la impresora está desactivada, no hacer nada
    if (settings.printerType.toLowerCase() == 'none') {
      debugPrint('=== PrinterService: printerType=none, saltando impresión ===');
      return;
    }
    // Guardia: si el comPort está vacío en modo USB, no hacer nada
    if (config.connectionType == PrinterConnectionType.usb &&
        (config.comPort == null || config.comPort!.trim().isEmpty)) {
      debugPrint('=== PrinterService: comPort vacío — configure el puerto en Ajustes > Hardware ===');
      return;
    }

    debugPrint('=== PrinterService: Iniciando impresión ===');
    debugPrint('  comPort: ${config.comPort}  paperSize: ${config.paperSize}  type: ${config.connectionType}');
    debugPrint('  receiptNumber: $receiptNumber  items: ${items.length}');

    final profile = await _getProfile();
    final generator = Generator(config.paperSize, profile);
    List<int> bytes = [];


    // ── Encabezado ──────────────────────────────────────────────
    bytes += generator.reset();
    bytes += generator.text(
      _cleanText(settings.companyName?.toUpperCase() ?? 'MI NEGOCIO'),
      styles: const PosStyles(
        bold: true,
        align: PosAlign.center,
        height: PosTextSize.size2,
        width: PosTextSize.size2,
      ),
    );
    bytes += generator.feed(1);

    if (settings.address != null && settings.address!.isNotEmpty) {
      bytes += generator.text(
        _cleanText(settings.address!),
        styles: const PosStyles(align: PosAlign.center),
      );
    }
    if (settings.taxId != null && settings.taxId!.isNotEmpty) {
      bytes += generator.text(
        'CUIT: ${settings.taxId}',
        styles: const PosStyles(align: PosAlign.center, bold: true),
      );
    }
    if (settings.phone != null && settings.phone!.isNotEmpty) {
      bytes += generator.text(
        'Tel: ${settings.phone}',
        styles: const PosStyles(align: PosAlign.center),
      );
    }
    bytes += generator.hr(ch: '=');

    bytes += generator.text(
      _cleanText('COMPROBANTE DE VENTA'),
      styles: const PosStyles(align: PosAlign.center, bold: true),
    );
    bytes += generator.hr(ch: '-');

    // ── Fecha y número de comprobante ────────────────────────────
    final now = DateTime.now();
    // Fecha ocupa la línea completa
    bytes += generator.text(
      'FECHA: ${_formatDate(now)}',
      styles: const PosStyles(bold: true, align: PosAlign.left),
    );
    // Número de ticket en su propia línea — funciona con cualquier cantidad de dígitos
    if (receiptNumber != null) {
      bytes += generator.text(
        'TICKET N°: ${receiptNumber.padLeft(6, '0')}',
        styles: const PosStyles(bold: true, align: PosAlign.right),
      );
    }
    if (userName != null) {
      final String cashierLine = (cashierName == null || userName == cashierName)
          ? 'CAJERO: ${_cleanText(userName).toUpperCase()}'
          : 'GENERO: ${_cleanText(userName).toUpperCase()} | COBRO: ${_cleanText(cashierName).toUpperCase()}';
      
      bytes += generator.text(
        cashierLine,
        styles: const PosStyles(align: PosAlign.left),
      );
    }
    // ── Items ─────────────────────────────────────────────────────
    // Formato profesional estilo POS moderno:
    // Línea 1: [CANT x $PRECIO_UNIT]    [$SUBTOTAL]   (columnas izq/der)
    // Línea 2: NOMBRE DEL PRODUCTO      (nombre completo abajo, bold)
    bytes += generator.hr(ch: '-');

    int totalItemsQty = 0;

    for (final item in items) {
      final isWeight = item.product.isSoldByWeight;
      final cantStr = isWeight
          ? '${item.quantity.toQty()} kg'
          : '${item.quantity.toInt()} un';

      if (!isWeight) totalItemsQty += item.quantity.toInt();

      final double price = item.product.sellingPrice;
      final double subtotal = item.subtotal;

      final productName = _cleanText(item.product.name.toUpperCase());
      final unitPriceStr = '$cantStr x \$${_formatPrice(price)}';
      final subtotalStr = '\$${_formatPrice(subtotal)}';

      // Línea 1: [3 un x $1500    LEFT] [$4500 RIGHT]
      bytes += generator.row([
        PosColumn(
          text: unitPriceStr,
          width: 8,
          styles: const PosStyles(align: PosAlign.left),
        ),
        PosColumn(
          text: subtotalStr,
          width: 4,
          styles: const PosStyles(align: PosAlign.right, bold: true),
        ),
      ]);
      // Línea 2: NOMBRE DEL PRODUCTO en negrita
      bytes += generator.text(
        productName,
        styles: const PosStyles(bold: true),
      );
    }
    bytes += generator.hr(ch: '=');



    // ── Resumen de Pago (Anti-Redundancia) ──────────────────────────
    final hasSurcharge = surchargeAmount > 0.01;
    final grandTotal = total + surchargeAmount;
    final hasChange = changeAmount > 0.01;
    final hasTendered = tenderedAmount > 0.01;

    final bool isComplexPayment = paymentDetails.length > 1 || hasSurcharge;

    if (isComplexPayment) {
      // Caso 3: Venta Compleja (Múltiples métodos o Recargos)
      bytes += _labelValue(generator, 'SUBTOTAL:', '\$${_formatPrice(total)}');

      if (paymentDetails.isNotEmpty) {
        bytes += generator.hr(ch: '-');
        for (final pd in paymentDetails) {
          final methodName = _cleanText((pd['name'] as String? ?? 'PAGO').toUpperCase());
          final methodAmt = (pd['amount'] as num?)?.toDouble() ?? 0.0;
          bytes += _labelValue(generator, methodName, '\$${_formatPrice(methodAmt)}');
        }
      } else {
        bytes += generator.hr(ch: '-');
        bytes += _labelValue(generator, _cleanText(paymentMethod.toUpperCase()), '\$${_formatPrice(total)}');
      }

      if (hasSurcharge) {
        bytes += _labelValue(generator, 'RECARGO BANCARIO:', '\$${_formatPrice(surchargeAmount)}');
      }

      bytes += generator.hr(ch: '-');
      bytes += _labelValue(generator, 'TOTAL COBRADO:', '\$${_formatPrice(grandTotal)}');

      if (hasTendered) {
        bytes += _labelValue(generator, 'EFECTIVO RECIBIDO:', '\$${_formatPrice(tenderedAmount)}');
      }
      if (hasChange) {
        bytes += _labelValue(generator, 'SU VUELTO:', '\$${_formatPrice(changeAmount)}');
      }
    } else {
      // Casos 1 y 2: Venta Simple (Un solo pago, sin recargos)
      bytes += _labelValue(generator, 'TOTAL GENERAL:', '\$${_formatPrice(grandTotal)}');
      bytes += generator.hr(ch: '-');

      final singlePaymentName = paymentDetails.isNotEmpty
          ? _cleanText((paymentDetails.first['name'] as String? ?? 'PAGO').toUpperCase())
          : _cleanText(paymentMethod.toUpperCase());

      bytes += _labelValue(generator, 'PAGO EN:', singlePaymentName);

      // Si pagó con efectivo, mostramos cuánto dio sólo si hay vuelto o si abona de más/menos.
      // Si el pago es exacto, no ensuciamos el ticket.
      final bool isExactCash = hasTendered && (tenderedAmount - grandTotal).abs() < 0.01;

      if (hasTendered && !isExactCash) {
        bytes += _labelValue(generator, 'EFECTIVO RECIBIDO:', '\$${_formatPrice(tenderedAmount)}');
      }
      if (hasChange) {
        bytes += _labelValue(generator, 'SU VUELTO:', '\$${_formatPrice(changeAmount)}');
      }
    }

    bytes += generator.feed(1);

    bytes += generator.row([
      PosColumn(
        text: 'UNIDADES VENDIDAS:',
        width: 9,
        styles: const PosStyles(bold: true),
      ),
      PosColumn(
        text: '$totalItemsQty',
        width: 3,
        styles: const PosStyles(align: PosAlign.right, bold: true),
      ),
    ]);
    bytes += generator.hr(ch: '-');


    // ── Código de barras del comprobante (sin número duplicado) ──
    if (receiptNumber != null && receiptNumber.isNotEmpty) {
      try {
        final cleanStringForBarcode = receiptNumber.replaceAll(RegExp(r'[^A-Z0-9\-\.\ \$\/\+\%]'), '');
        if (cleanStringForBarcode.isNotEmpty) {
          bytes += generator.barcode(
            Barcode.code39(cleanStringForBarcode.split('')),
            width: 2,
            height: 60,
            textPos: BarcodeText.none, // Suprime el *47* del hardware
          );
          // Texto legible limpio, sin asteriscos
          bytes += generator.text(
            cleanStringForBarcode,
            styles: const PosStyles(align: PosAlign.center),
          );
        }
      } catch (e) {
        debugPrint("Error imprimiendo Code39 barcode: $e");
      }
      bytes += generator.feed(1);
    }

    // ── Pie de ticket (SOLO el mensaje configurado por el usuario) ──
    // No se agregan mensajes hardcodeados adicionales para evitar duplicados.
    if (settings.receiptFooterMessage != null &&
        settings.receiptFooterMessage!.isNotEmpty) {
      bytes += generator.text(
        _cleanText(settings.receiptFooterMessage!),
        styles: const PosStyles(align: PosAlign.center, bold: true),
      );
      bytes += generator.feed(1);
    }
    bytes += generator.text(
      '*** NO VALIDO COMO FACTURA ***',
      styles: const PosStyles(align: PosAlign.center, bold: true),
    );

    bytes += generator.feed(3);
    bytes += generator.cut();

    // ── Drawer Kick (apertura de gaveta) ─────────────────────────
    bytes += _drawerKickBytes(generator);

    await _send(Uint8List.fromList(bytes));
  }

  /// Imprime el comprobante de Cierre Z (Auditoría del turno).
  Future<void> printZCloseTicket({
    required CashRegisterShift shift,
    required BusinessSettings settings,
  }) async {
    final profile = await _getProfile();
    final generator = Generator(config.paperSize, profile);
    List<int> bytes = [];

    bytes += generator.reset();
    bytes += generator.text(
      _cleanText(settings.companyName?.toUpperCase() ?? 'MI NEGOCIO'),
      styles: const PosStyles(
        bold: true,
        align: PosAlign.center,
        height: PosTextSize.size2,
        width: PosTextSize.size2,
      ),
    );
    bytes += generator.text(
      _cleanText('=== CIERRE Z ==='),
      styles: const PosStyles(align: PosAlign.center, bold: true),
    );
    bytes += generator.hr();

    final closedAt = shift.closedAt ?? DateTime.now();
    bytes += generator.row([
      PosColumn(text: 'Apertura:', width: 6),
      PosColumn(
        text: _formatDate(shift.openedAt),
        width: 6,
        styles: const PosStyles(align: PosAlign.right),
      ),
    ]);
    bytes += generator.row([
      PosColumn(text: 'Cierre:', width: 6),
      PosColumn(
        text: _formatDate(closedAt),
        width: 6,
        styles: const PosStyles(align: PosAlign.right),
      ),
    ]);
    bytes += generator.hr();

    bytes += generator.text(
      _cleanText('RESUMEN DEL TURNO'),
      styles: const PosStyles(bold: true),
    );
    bytes += generator.hr(ch: '-');
    const currency = '\$';
    bytes += _labelValue(
      generator,
      'Saldo inicial:',
      '$currency${shift.openingBalance.toCurrency()}',
    );
    bytes += _labelValue(
      generator,
      'Ventas del turno:',
      '$currency${(shift.totalSales ?? 0.0).toCurrency()}',
    );
    bytes += _labelValue(
      generator,
      'Total Recargos:',
      '$currency${(shift.totalSurcharge ?? 0.0).toCurrency()}',
    );
    bytes += _labelValue(
      generator,
      'Efectivo esperado:',
      '$currency${((shift.openingBalance) + (shift.cashSales ?? 0.0)).toCurrency()}',
    );
    bytes += generator.hr(ch: '=');
    bytes += _labelValue(
      generator,
      'Efectivo contado:',
      '$currency${(shift.closingBalance ?? 0.0).toCurrency()}',
    );

    final diff = shift.difference ?? 0.0;
    final diffStr = diff >= 0
        ? '+$currency${diff.toCurrency()} (SOBRANTE)'
        : '-$currency${diff.abs().toCurrency()} (FALTANTE)';
    bytes += generator.row([
      PosColumn(
        text: 'Diferencia:',
        width: 6,
        styles: const PosStyles(bold: true),
      ),
      PosColumn(
        text: diffStr,
        width: 6,
        styles: PosStyles(
          bold: true,
          align: PosAlign.right,
          fontType: diff < 0 ? PosFontType.fontB : PosFontType.fontA,
        ),
      ),
    ]);
    bytes += generator.hr();
    bytes += generator.text(
      'Firma cajero: ___________________',
      styles: const PosStyles(align: PosAlign.center),
    );
    bytes += generator.feed(4);
    bytes += generator.cut();

    await _send(Uint8List.fromList(bytes));
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────────────────────────

  /// Elimina acentos y caracteres especiales que no soportan las impresoras térmicas chinas (CP437).
  String _cleanText(String text) {
    if (text.isEmpty) return text;
    const Map<String, String> accents = {
      'À':'A', 'Á':'A', 'Â':'A', 'Ã':'A', 'Ä':'A', 'Å':'A',
      'à':'a', 'á':'a', 'â':'a', 'ã':'a', 'ä':'a', 'å':'a',
      'Ò':'O', 'Ó':'O', 'Ô':'O', 'Õ':'O', 'Ö':'O', 'Ø':'O',
      'ò':'o', 'ó':'o', 'ô':'o', 'õ':'o', 'ö':'o', 'ø':'o',
      'È':'E', 'É':'E', 'Ê':'E', 'Ë':'E',
      'è':'e', 'é':'e', 'ê':'e', 'ë':'e',
      'Ç':'C', 'ç':'c',
      'Ì':'I', 'Í':'I', 'Î':'I', 'Ï':'I',
      'ì':'i', 'í':'i', 'î':'i', 'ï':'i',
      'Ù':'U', 'Ú':'U', 'Û':'U', 'Ü':'U',
      'ù':'u', 'ú':'u', 'û':'u', 'ü':'u',
      'Ñ':'N', 'ñ':'n',
    };
    return text.split('').map((char) => accents[char] ?? char).join();
  }

  List<int> _labelValue(Generator gen, String label, String value) {
    // Para 58mm, si width es 7, usa 18 chars; si width es 5, usa 13 chars.
    final bool is58mm = config.paperSize == PaperSize.mm58;
    return gen.row([
      PosColumn(text: label, width: is58mm ? 8 : 7),
      PosColumn(
        text: value,
        width: is58mm ? 4 : 5,
        styles: const PosStyles(align: PosAlign.right, bold: true),
      ),
    ]);
  }

  /// Genera el comando de apertura de gaveta (Drawer Kick) mediante el pin 2 o pin 5 del conector RJ-11
  List<int> _drawerKickBytes(Generator gen) {
    // ESC/POS comando: ESC p m t1 t2
    // p=0 (pin2), on=100ms, off=200ms
    return [0x1B, 0x70, 0x00, 0x64, 0xC8];
  }

  /// Formatea un precio eliminando decimales si son .00
  String _formatPrice(double value) {
    if (value == value.truncate()) {
      return value.toInt().toString();
    }
    return value.toCurrency();
  }

  String _formatDate(DateTime dt) {
    final localDt = dt.toLocal();
    return '${localDt.day.toString().padLeft(2, '0')}/${localDt.month.toString().padLeft(2, '0')}/${localDt.year} ${localDt.hour.toString().padLeft(2, '0')}:${localDt.minute.toString().padLeft(2, '0')}';
  }

  /// Envía los bytes a la impresora según el tipo de conexión configurado.
  Future<void> _send(Uint8List data) async {
    switch (config.connectionType) {
      case PrinterConnectionType.tcp:
        await _sendViaTcp(data);
        break;
      case PrinterConnectionType.usb:
        await _sendViaSerialPort(data);
        break;
    }
  }

  /// Envía los bytes por socket TCP (impresoras de red / WiFi)
  Future<void> _sendViaTcp(Uint8List data) async {
    if (config.tcpHost == null) {
      throw Exception('ReceiptPrinterService: tcpHost no configurado.');
    }
    Socket? socket;
    try {
      socket = await Socket.connect(
        config.tcpHost!,
        config.tcpPort ?? 9100,
        timeout: const Duration(seconds: 3),
      );
      socket.add(data);
      await socket.flush();
    } finally {
      socket?.destroy();
    }
  }

  /// Envía los bytes usando el driver nativo de Windows (Spooler)
  Future<void> _sendViaSerialPort(Uint8List data) async {
    if (config.comPort == null || config.comPort!.isEmpty) {
      throw Exception('ReceiptPrinterService: Nombre de impresora no configurado.');
    }
    
    final pm = PrinterManager.instance;
    try {
      await pm.connect(
        type: PrinterType.usb,
        model: UsbPrinterInput(name: config.comPort!),
      );
      await pm.send(type: PrinterType.usb, bytes: data.toList());
      // Damos un breve margen para asegurar que los bytes salgan antes de desconectar
      await Future.delayed(const Duration(milliseconds: 50));
    } finally {
      await pm.disconnect(type: PrinterType.usb);
    }
  }
}
