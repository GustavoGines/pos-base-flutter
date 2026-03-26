import 'dart:io';
import 'dart:typed_data';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
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
    paperSize: PaperSize.mm80,
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

  ReceiptPrinterService._internal({required this.config});

  /// Permite reconfigurar el hardware en caliente (desde SettingsScreen)
  Future<void> reconfigureFromSettings(BusinessSettings settings) async {
    PrinterConnectionType type;
    switch (settings.printerType.toLowerCase()) {
      case 'network':
        type = PrinterConnectionType.tcp;
        break;
      case 'usb':
        type = PrinterConnectionType.usb;
        break;
      default:
        // Si es 'none' u otro, dejamos configurado algo pero no imprimirá (manejado arriba en UI o interceptado aquí)
        type = PrinterConnectionType.usb;
    }

    config = PrinterConfig(
      connectionType: type,
      tcpHost: settings.printerIpAddress,
      tcpPort: int.tryParse(settings.printerIpPort ?? '9100') ?? 9100,
      comPort: settings.printerComPort,
    );
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
    String? receiptNumber,
    String? userName,
  }) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(config.paperSize, profile);
    List<int> bytes = [];

    // ── Encabezado ──────────────────────────────────────────────
    bytes += generator.reset();
    bytes += generator.text(
      settings.companyName?.toUpperCase() ?? 'MI NEGOCIO',
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
        settings.address!,
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
      'COMPROBANTE DE VENTA',
      styles: const PosStyles(align: PosAlign.center, bold: true),
    );
    bytes += generator.hr(ch: '-');

    // ── Fecha y número de comprobante ────────────────────────────
    final now = DateTime.now();
    bytes += generator.row([
      PosColumn(
        text: 'FECHA: ${_formatDate(now)}',
        width: 7,
        styles: const PosStyles(bold: true),
      ),
      PosColumn(
        text: receiptNumber != null
            ? 'TICKET #${receiptNumber.padLeft(6, '0')}'
            : '',
        width: 5,
        styles: const PosStyles(align: PosAlign.right, bold: true),
      ),
    ]);
    if (userName != null) {
      bytes += generator.text(
        'CAJERO: ${userName.toUpperCase()}',
        styles: const PosStyles(align: PosAlign.left),
      );
    }
    bytes += generator.hr(ch: '=');

    // ── Items ────────────────────────────────────────────────────
    bytes += generator.row([
      PosColumn(text: 'CANT', width: 2, styles: const PosStyles(bold: true)),
      PosColumn(
        text: 'DESCRIPCIÓN',
        width: 6,
        styles: const PosStyles(bold: true),
      ),
      PosColumn(
        text: 'TOTAL',
        width: 4,
        styles: const PosStyles(align: PosAlign.right, bold: true),
      ),
    ]);
    bytes += generator.hr(ch: '-');

    int totalItemsQty = 0;

    for (final item in items) {
      final isWeight = item.product.isSoldByWeight;
      final cantStr = isWeight
          ? item.quantity.toStringAsFixed(3)
          : item.quantity.toInt().toString();

      if (!isWeight) totalItemsQty += item.quantity.toInt();

      final price = item.product.sellingPrice;
      final subtotal = item.subtotal;

      // Primera línea: Nombre del producto
      bytes += generator.text(
        item.product.name.toUpperCase(),
        styles: const PosStyles(bold: true),
      );
      // Segunda línea: Cantidad | Precio unitario | Subtotal
      bytes += generator.row([
        PosColumn(text: cantStr, width: 2),
        PosColumn(text: 'x \$${price.toStringAsFixed(2)}', width: 6),
        PosColumn(
          text: '\$${subtotal.toStringAsFixed(2)}',
          width: 4,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
      bytes += generator.feed(1); // Espacio pequeño entre items
    }
    bytes += generator.hr(ch: '=');

    // ── Total ────────────────────────────────────────────────────
    bytes += generator.row([
      PosColumn(
        text: 'TOTAL A PAGAR:',
        width: 7,
        styles: const PosStyles(bold: true, height: PosTextSize.size2),
      ),
      PosColumn(
        text: '\$${total.toStringAsFixed(2)}',
        width: 5,
        styles: const PosStyles(
          bold: true,
          align: PosAlign.right,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ),
      ),
    ]);
    bytes += generator.feed(1);
    bytes += generator.row([
      PosColumn(
        text: 'MÉTODO DE PAGO:',
        width: 7,
        styles: const PosStyles(bold: true),
      ),
      PosColumn(
        text: paymentMethod.toUpperCase(),
        width: 5,
        styles: const PosStyles(align: PosAlign.right, bold: true),
      ),
    ]);
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

    // ── Código de barras (Nro Comprobante) y Pie ──────────────────
    if (receiptNumber != null && receiptNumber.isNotEmpty) {
      try {
        // Imprime un código de barras limpio si hay número de comprobante
        bytes += generator.barcode(
          Barcode.code128(receiptNumber.padLeft(8, '0').codeUnits),
          width: 2,
          height: 60,
        );
      } catch (e) {
        // Ignorar si el string no permite ser code128 (aunque números padLeft siempre deberían funcionar)
      }
      bytes += generator.feed(1);
    }

    if (settings.receiptFooterMessage != null &&
        settings.receiptFooterMessage!.isNotEmpty) {
      bytes += generator.text(
        settings.receiptFooterMessage!,
        styles: const PosStyles(align: PosAlign.center, bold: true),
      );
    }
    bytes += generator.feed(1);
    bytes += generator.text(
      '*** GRACIAS POR SU COMPRA ***',
      styles: const PosStyles(align: PosAlign.center, bold: true),
    );
    bytes += generator.text(
      'Conserve este ticket para devoluciones',
      styles: const PosStyles(align: PosAlign.center),
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
    final profile = await CapabilityProfile.load();
    final generator = Generator(config.paperSize, profile);
    List<int> bytes = [];

    bytes += generator.reset();
    bytes += generator.text(
      settings.companyName?.toUpperCase() ?? 'MI NEGOCIO',
      styles: const PosStyles(
        bold: true,
        align: PosAlign.center,
        height: PosTextSize.size2,
        width: PosTextSize.size2,
      ),
    );
    bytes += generator.text(
      '=== CIERRE Z ===',
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
      'RESUMEN DEL TURNO',
      styles: const PosStyles(bold: true),
    );
    bytes += generator.hr(ch: '-');
    const currency = '\$';
    bytes += _labelValue(
      generator,
      'Saldo inicial:',
      '$currency${shift.openingBalance.toStringAsFixed(2)}',
    );
    bytes += _labelValue(
      generator,
      'Ventas del turno:',
      '$currency${(shift.totalSales ?? 0.0).toStringAsFixed(2)}',
    );
    bytes += _labelValue(
      generator,
      'Efectivo esperado:',
      '$currency${((shift.openingBalance) + (shift.totalSales ?? 0.0)).toStringAsFixed(2)}',
    );
    bytes += generator.hr(ch: '=');
    bytes += _labelValue(
      generator,
      'Efectivo contado:',
      '$currency${(shift.closingBalance ?? 0.0).toStringAsFixed(2)}',
    );

    final diff = shift.difference ?? 0.0;
    final diffStr = diff >= 0
        ? '+$currency${diff.toStringAsFixed(2)} (SOBRANTE)'
        : '-$currency${diff.abs().toStringAsFixed(2)} (FALTANTE)';
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

  List<int> _labelValue(Generator gen, String label, String value) {
    return gen.row([
      PosColumn(text: label, width: 7),
      PosColumn(
        text: value,
        width: 5,
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

  /// Envía los bytes por puerto COM/USB (impresoras USB via Serial Port)
  Future<void> _sendViaSerialPort(Uint8List data) async {
    if (config.comPort == null) {
      throw Exception('ReceiptPrinterService: comPort no configurado.');
    }
    final port = SerialPort(config.comPort!);
    try {
      if (!port.openWrite()) {
        throw Exception('No se pudo abrir el puerto ${config.comPort}');
      }
      port.write(data);
    } finally {
      port.close();
      port.dispose();
    }
  }
}
