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

  bool get isLicenseActive => _settings?.licenseStatus == 'active';
  String get currentPlan => _settings?.licensePlanType ?? 'basic';

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
}
