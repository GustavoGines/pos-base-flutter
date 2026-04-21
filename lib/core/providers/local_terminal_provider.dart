import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalTerminalProvider extends ChangeNotifier {
  static const String _printerFormatKey = 'local_printer_format';
  static const String _printerConnectionKey = 'local_printer_connection';
  static const String _printerNameOrIpKey = 'local_printer_name_or_ip';
  static const String _scaleComPortKey = 'local_scale_com_port';

  // Opciones válidas: 'thermal_80', 'thermal_58', 'a4'
  String _printerFormat = 'thermal_80';
  
  // Opciones válidas: 'usb', 'network', 'none'
  String _printerConnection = 'none';
  
  String _printerNameOrIp = '';
  String _scaleComPort = '';

  bool _isInitialized = false;

  String get printerFormat => _printerFormat;
  String get printerConnection => _printerConnection;
  String get printerNameOrIp => _printerNameOrIp;
  String get scaleComPort => _scaleComPort;
  bool get isInitialized => _isInitialized;

  LocalTerminalProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _printerFormat = prefs.getString(_printerFormatKey) ?? 'thermal_80';
    if (_printerFormat == 'a4_split' || _printerFormat == 'a4_standard' || _printerFormat == 'a4_normal') {
      _printerFormat = 'a4';
      prefs.setString(_printerFormatKey, 'a4'); // Update the stored preference
    }
    _printerConnection = prefs.getString(_printerConnectionKey) ?? 'none';
    _printerNameOrIp = prefs.getString(_printerNameOrIpKey) ?? '';
    _scaleComPort = prefs.getString(_scaleComPortKey) ?? '';
    _isInitialized = true;
    notifyListeners();
  }

  Future<void> setPrinterFormat(String format) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_printerFormatKey, format);
    _printerFormat = format;
    notifyListeners();
  }

  Future<void> setPrinterConnection(String connection) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_printerConnectionKey, connection);
    _printerConnection = connection;
    notifyListeners();
  }

  Future<void> setPrinterNameOrIp(String nameOrIp) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_printerNameOrIpKey, nameOrIp);
    _printerNameOrIp = nameOrIp;
    notifyListeners();
  }

  Future<void> setScaleComPort(String port) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_scaleComPortKey, port);
    _scaleComPort = port;
    notifyListeners();
  }
}
