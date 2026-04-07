import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/entities/business_settings.dart';
import '../../domain/usecases/get_settings_usecase.dart';
import '../../domain/usecases/update_settings_usecase.dart';
import '../../../../core/services/license_heartbeat_service.dart';
import '../../../../core/config/app_config.dart';
import '../../data/repositories/settings_repository_impl.dart';
import '../../../../core/utils/receipt_printer_service.dart';

class SettingsProvider with ChangeNotifier {
  final GetSettingsUseCase getSettingsUseCase;
  final UpdateSettingsUseCase updateSettingsUseCase;

  BusinessSettings? _settings;
  BusinessSettings? get settings => _settings;

  bool get isLicenseActive {
    final key = _settings?.licenseStatus ?? '';
    final bool licenseValid = key.isNotEmpty && currentPlan != 'blocked';
    
    // El "Muro de Fuego" ahora considera el Heartbeat (Offline > 72h o Time Rollback)
    final heartbeat = LicenseHeartbeatService();
    return licenseValid && !heartbeat.isBlocked;
  }
  
  LicenseSecurityStatus get securityStatus => LicenseHeartbeatService().securityStatus;
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
  }) {
    _loadLocalSettings();
    // Escuchar el Heartbeat para reconstruir el UI (como el LicenseGuard) cuando hay bloqueos
    LicenseHeartbeatService().addListener(_onHeartbeatChanged);
  }

  void _onHeartbeatChanged() {
    notifyListeners();
  }

  @override
  void dispose() {
    LicenseHeartbeatService().removeListener(_onHeartbeatChanged);
    super.dispose();
  }

  int _assignedRegisterId = 0;
  int get assignedRegisterId => _assignedRegisterId;

  Future<void> _loadLocalSettings() async {
    final prefs = await SharedPreferences.getInstance();
    // 0 = sin asignar (usa comportamiento libre/dropdown por defecto)
    _assignedRegisterId = prefs.getInt('assigned_cash_register_id') ?? 0;
    notifyListeners();
  }

  Future<void> setAssignedRegisterId(int id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('assigned_cash_register_id', id);
    _assignedRegisterId = id;
    notifyListeners();
  }

  Future<void> loadSettings() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _settings = await getSettingsUseCase();
      
      // Iniciar el sistema de seguridad DRM
      await LicenseHeartbeatService().initialize(
        _settings,
        onSyncRequested: () => syncLicenseWithServer(AppConfig.kApiBaseUrl),
      );

      // Reconfigurar la impresora con los ajustes guardados en la DB
      if (_settings != null) {
        await ReceiptPrinterService.instance.reconfigureFromSettings(_settings!);
      }
      
      _checkAndSyncSilentlyOnStartup();
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Refresco silencioso para validaciones de fondo en la navegación.
  /// No altera 'isLoading' ni 'errorMessage' para evitar asustar al usuario
  /// con carteles rojos si hay un micro-corte de red.
  Future<void> refreshSettingsSilently() async {
    try {
      final newSettings = await getSettingsUseCase();
      _settings = newSettings;
      
      // Actualizar el Heartbeat con la nueva data (server_time, etc)
      await LicenseHeartbeatService().initialize(
        _settings,
        onSyncRequested: () => syncLicenseWithServer(AppConfig.kApiBaseUrl),
      );
      
      notifyListeners();
    } catch (e) {
      // Silencio absoluto: si falla, seguimos con los permisos que ya teníamos
      // cargados localmente (permitiendo el modo offline de 72h).
      debugPrint('=== Settings Silencioso: Ignorando error de red ($e) ===');
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

  void updateBaseUrl(String newUrl) {
    if (updateSettingsUseCase.repository is SettingsRepositoryImpl) {
      (updateSettingsUseCase.repository as SettingsRepositoryImpl).updateBaseUrl(newUrl);
    }
  }

  Future<String> activateLicense(String baseUrl, String licenseKey) async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/settings/license'),
        headers: {'Accept': 'application/json', 'Content-Type': 'application/json'},
        body: json.encode({'license_key': licenseKey}),
      );

      final dynamic data;
      try {
        data = json.decode(response.body);
      } catch (_) {
        throw const FormatException('La respuesta del servidor no es un JSON válido.');
      }

      if (response.statusCode == 200) {
        final plan = data['plan'] as String? ?? 'basic';
        // Refresh local settings so Feature Gating reacts immediately
        await loadSettings();
        
        // Notificar al sistema de seguridad que sincronizamos con el server
        if (_settings != null) {
          await LicenseHeartbeatService().updateLastSync(_settings!);
        }
        
        return plan;
      } else if (response.statusCode == 404) {
        throw Exception('Error de conexión: No se encontró el servidor. Verifica la URL configurada.');
      } else if (response.statusCode == 500) {
        throw Exception('Error interno del servidor. Contacte a soporte técnico.');
      } else {
        // En caso de error, recargamos por si el backend mandó la app a 'blocked'
        await loadSettings();
        throw Exception(data['error'] ?? 'Error al validar la licencia.');
      }
    } on FormatException catch (e) {
      throw Exception(e.message);
    } catch (e) {
      final errStr = e.toString();
      if (errStr.contains('SocketException') ||
          errStr.contains('TimeoutException') ||
          errStr.contains('ClientException')) {
        throw Exception('Error de conexión: No se encontró el servidor. Verifica la URL configurada.');
      }
      rethrow;
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
      ).timeout(const Duration(minutes: 4)); // 4 min: tolera cold-start de Render (2-3 min)

      final dynamic data;
      try {
        data = json.decode(response.body);
      } catch (_) {
        throw const FormatException('La respuesta del servidor no es un JSON válido.');
      }

      if (response.statusCode == 200) {
        await loadSettings();
        // Notificar al sistema de seguridad que sincronizamos con el server
        if (_settings != null) {
          await LicenseHeartbeatService().updateLastSync(_settings!);
        }
      } else if (response.statusCode == 404) {
        throw Exception('Error de conexión: No se encontró el servidor. Verifica la URL configurada.');
      } else if (response.statusCode == 500) {
        throw Exception('Error interno del servidor. Contacte a soporte técnico.');
      } else {
        // Si el sync detectó revocación, el backend guardó el plan como 'blocked'.
        // Recargamos settings para forzar al "LicenseGuard" a mostrar la pantalla de bloqueo.
        await loadSettings();
        throw Exception(data['error'] ?? 'Error al sincronizar permisos.');
      }
    } on FormatException catch (e) {
      throw Exception(e.message);
    } on TimeoutException {
      throw Exception('El servidor central se está encendiendo. Por favor, espera 1 minuto y vuelve a intentarlo.');
    } catch (e) {
      final errStr = e.toString();
      if (errStr.contains('SocketException') ||
          errStr.contains('TimeoutException') ||
          errStr.contains('ClientException')) {
        throw Exception('Error de conexión: No se encontró el servidor. Verifica la URL configurada.');
      }
      rethrow;
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
      http.post(
        Uri.parse('${AppConfig.kApiBaseUrl}/settings/license/sync'),
        headers: {'Accept': 'application/json', 'Content-Type': 'application/json'},
      ).timeout(const Duration(minutes: 4)).then((response) { // 4 min: tolera cold-start de Render
        if (response.statusCode == 200) {
          getSettingsUseCase().then((newSettings) {
            _settings = newSettings;
            // Bug #3 fix: actualizar el Secure Storage con el server_time recibido
            // para que el Drift Check del próximo ciclo use el reloj del servidor.
            LicenseHeartbeatService().updateLastSync(newSettings);
            notifyListeners();
          });
        }
      }).catchError((_) {
        // Fracaso silencioso intencional
      });
    }
  }
}
