import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../domain/entities/business_settings.dart';
import '../../domain/usecases/get_settings_usecase.dart';
import '../../domain/usecases/update_settings_usecase.dart';

class SettingsProvider with ChangeNotifier {
  final GetSettingsUseCase getSettingsUseCase;
  final UpdateSettingsUseCase updateSettingsUseCase;

  BusinessSettings? _settings;
  BusinessSettings? get settings => _settings;

  bool get isLicenseActive {
    final key = _settings?.licenseStatus ?? '';
    return key.isNotEmpty && currentPlan != 'blocked';
  }
  String get currentPlan => _settings?.licensePlanType ?? 'basic';
  List<String> get allowedAddons => _settings?.licenseAllowedAddons ?? [];

  /// Feature Gating: Retorna true si el plan es PRO/ENTERPRISE o si tiene el addon específico
  bool hasFeature(String featureName) {
    if (currentPlan == 'pro' || currentPlan == 'enterprise') return true;
    return allowedAddons.contains(featureName);
  }

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  SettingsProvider({
    required this.getSettingsUseCase,
    required this.updateSettingsUseCase,
  });

  Future<void> loadSettings() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _settings = await getSettingsUseCase();
      _checkAndSyncSilentlyOnStartup();
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> saveSettings(Map<String, dynamic> data) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _settings = await updateSettingsUseCase(data);
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Activation: POSTs the new license key to /api/settings/license.
  /// Returns the new plan string on success, throws on error.
  Future<String> activateLicense(String baseUrl, String licenseKey) async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/settings/license'),
        headers: {'Accept': 'application/json', 'Content-Type': 'application/json'},
        body: json.encode({'license_key': licenseKey}),
      );

      final data = json.decode(response.body);
      if (response.statusCode == 200) {
        final plan = data['plan'] as String? ?? 'basic';
        // Refresh local settings so Feature Gating reacts immediately
        await loadSettings();
        return plan;
      } else {
        throw Exception(data['error'] ?? 'Error al validar la licencia.');
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Sync: POSTs to /api/settings/license/sync to force update permissions
  Future<void> syncLicenseWithServer(String baseUrl) async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/settings/license/sync'),
        headers: {'Accept': 'application/json', 'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 120));

      final data = json.decode(response.body);
      if (response.statusCode == 200) {
        await loadSettings();
      } else {
        throw Exception(data['error'] ?? 'Error al sincronizar permisos.');
      }
    } on TimeoutException {
      throw Exception('El servidor central se está encendiendo. Por favor, espera 1 minuto y vuelve a intentarlo.');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Sincronización silenciosa en background (Fallback si el local apaga PC y el cron falla)
  void _checkAndSyncSilentlyOnStartup() {
    if (!isLicenseActive) return;
    
    final lastCheckStr = _settings!.lastLicenseCheck;
    bool needsSync = false;
    
    if (lastCheckStr == null || lastCheckStr.isEmpty) {
      needsSync = true;
    } else {
      try {
        final lastCheck = DateTime.parse(lastCheckStr);
        if (DateTime.now().difference(lastCheck).inHours > 24) {
          needsSync = true;
        }
      } catch (_) {
        needsSync = true;
      }
    }

    if (needsSync) {
      const baseUrl = 'http://127.0.0.1/Sistema_POS/pos-backend/public/api';
      http.post(
        Uri.parse('$baseUrl/settings/license/sync'),
        headers: {'Accept': 'application/json', 'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 120)).then((response) {
        if (response.statusCode == 200) {
          getSettingsUseCase().then((newSettings) {
            _settings = newSettings;
            notifyListeners();
          });
        }
      }).catchError((_) {
        // Fracaso silencioso intencional
      });
    }
  }
}
