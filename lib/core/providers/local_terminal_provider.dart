import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend_desktop/core/utils/receipt_printer_service.dart';

class LocalTerminalProvider extends ChangeNotifier {
  static const String _printerFormatKey = 'local_printer_format';
  static const String _printerConnectionKey = 'local_printer_connection';
  static const String _printerNameOrIpKey = 'local_printer_name_or_ip';
  static const String _scaleComPortKey = 'local_scale_com_port';
  static const String _pdfPaperSizeKey = 'local_pdf_paper_size';
  static const String _lockedPriceTierKey = 'local_locked_price_tier';
  static const String _lockedPriceTierLabelKey = 'local_locked_price_tier_label';

  // Opciones válidas: 'thermal_80', 'thermal_58', 'a4'
  String _printerFormat = 'thermal_80';
  
  // Opciones válidas: 'usb', 'network', 'none'
  String _printerConnection = 'none';
  
  String _printerNameOrIp = '';
  String _scaleComPort = '';
  String _pdfPaperSize = 'a4'; // Opciones válidas: 'a4', 'letter'
  
  String _lockedPriceTier = 'none';
  String? _lockedPriceTierLabel;

  bool _isInitialized = false;

  String get printerFormat => _printerFormat;
  String get printerConnection => _printerConnection;
  String get printerNameOrIp => _printerNameOrIp;
  String get scaleComPort => _scaleComPort;
  String get pdfPaperSize => _pdfPaperSize;
  String get lockedPriceTier => _lockedPriceTier;
  String? get lockedPriceTierLabel => _lockedPriceTierLabel;
  bool get isInitialized => _isInitialized;

  LocalTerminalProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _printerFormat = prefs.getString(_printerFormatKey) ?? 'thermal_80';
    if (_printerFormat == 'a4_split' || _printerFormat == 'a4_standard' || _printerFormat == 'a4_normal') {
      _printerFormat = 'a4';
      prefs.setString(_printerFormatKey, 'a4');
    }
    _printerConnection = prefs.getString(_printerConnectionKey) ?? 'none';
    _printerNameOrIp = prefs.getString(_printerNameOrIpKey) ?? '';
    _scaleComPort = prefs.getString(_scaleComPortKey) ?? '';
    _pdfPaperSize = prefs.getString(_pdfPaperSizeKey) ?? 'a4';
    _lockedPriceTier = prefs.getString(_lockedPriceTierKey) ?? 'none';
    _lockedPriceTierLabel = prefs.getString(_lockedPriceTierLabelKey);
    _isInitialized = true;

    // ── CRÍTICO: sincronizar el singleton de impresión con la config guardada.
    // Sin esto, ReceiptPrinterService arranca siempre con defaultUsb() (COM3
    // hardcodeado) ignorando lo que el usuario configuró en Ajustes > Hardware.
    _syncPrinterService();

    notifyListeners();
  }

  /// Propaga la configuración actual al singleton ReceiptPrinterService.
  /// Se llama al cargar los ajustes (arranque) y al cambiar cualquier
  /// parámetro de impresora para mantener ambos en sincronía.
  void _syncPrinterService() {
    ReceiptPrinterService.instance.reconfigure(this);
  }

  Future<void> setPrinterFormat(String format) async {
    // ── IMPORTANTE: actualizar la memoria ANTES del await para que
    // _syncPrinterService() lea el valor nuevo y no el viejo.
    _printerFormat = format;
    _syncPrinterService();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_printerFormatKey, format);
  }

  Future<void> setPrinterConnection(String connection) async {
    _printerConnection = connection;
    _syncPrinterService();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_printerConnectionKey, connection);
  }

  Future<void> setPrinterNameOrIp(String nameOrIp) async {
    _printerNameOrIp = nameOrIp;
    _syncPrinterService();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_printerNameOrIpKey, nameOrIp);
  }

  Future<void> setScaleComPort(String port) async {
    _scaleComPort = port;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_scaleComPortKey, port);
  }

  Future<void> setPdfPaperSize(String size) async {
    _pdfPaperSize = size;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pdfPaperSizeKey, size);
  }

  Future<void> setLockedPriceTier(String tier, {String? label}) async {
    _lockedPriceTier = tier;
    _lockedPriceTierLabel = label;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lockedPriceTierKey, tier);
    if (label != null) {
      await prefs.setString(_lockedPriceTierLabelKey, label);
    } else {
      await prefs.remove(_lockedPriceTierLabelKey);
    }
  }
}
