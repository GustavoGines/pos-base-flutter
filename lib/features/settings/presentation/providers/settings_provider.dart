import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/settings/domain/entities/ecommerce_integration.dart';
import 'package:frontend_desktop/features/settings/domain/usecases/get_settings_usecase.dart';
import 'package:frontend_desktop/features/settings/domain/usecases/update_settings_usecase.dart';
import 'package:frontend_desktop/core/services/license_heartbeat_service.dart';
import 'package:frontend_desktop/core/config/app_config.dart';
import 'package:frontend_desktop/features/settings/data/repositories/settings_repository_impl.dart';

class SettingsProvider with ChangeNotifier {
  final GetSettingsUseCase getSettingsUseCase;
  final UpdateSettingsUseCase updateSettingsUseCase;

  BusinessSettings? _settings;
  BusinessSettings? get settings => _settings;
  
  String? _currentApiUrl;
  String get currentApiUrl => _currentApiUrl ?? AppConfig.kApiBaseUrl;

  bool get isLicenseActive {
    final key = _settings?.licenseStatus ?? '';
    final bool licenseValid = key.isNotEmpty && currentPlan != 'blocked';
    
    // El "Muro de Fuego" ahora considera el Heartbeat (Offline > 72h o Time Rollback)
    final heartbeat = LicenseHeartbeatService();
    return licenseValid && !heartbeat.isBlocked;
  }
  
  LicenseSecurityStatus get securityStatus => LicenseHeartbeatService().securityStatus;
  String get currentPlan => _settings?.licensePlanType ?? 'basic';

  List<String> get allowedAddons => _settings?.licenseFeatures ?? [];

  // ─── [feature-flags] Permisos Modulares ─────────────────────────────────────
  /// True cuando la licencia remota indica business_type = 'hardware_store'.
  /// Alias legado: preferir hasFeature('quotes') para nuevas condicionales.
  bool get isHardwareStore => _settings?.isHardwareStore ?? false;

  /// Lista de features modulares activos según el Servidor de Licencias.
  FeatureFlags get features => _settings?.features ?? const FeatureFlags();

  /// @deprecated Preferir el uso de `features.<nombre>` para mayor seguridad de tipos.
  bool hasFeature(String featureName) {
    return _settings?.hasFeature(featureName) ?? false;
  }

  // ─── [mayorista-iibb] Percepciones IIBB ───────────────────────────────────
  bool get isIibbPerceptionAgent => _settings?.isIibbPerceptionAgent ?? false;
  double get defaultIibbPerceptionRate => _settings?.defaultIibbPerceptionRate ?? 0.0;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  Map<String, dynamic>? _integrations;
  Map<String, dynamic>? get integrations => _integrations;

  bool _isLoadingIntegrations = false;
  bool get isLoadingIntegrations => _isLoadingIntegrations;

  bool _isUploadingCertificates = false;
  bool get isUploadingCertificates => _isUploadingCertificates;

  List<EcommerceIntegration> _ecommerceIntegrations = [];
  List<EcommerceIntegration> get ecommerceIntegrations => _ecommerceIntegrations;

  bool _isLoadingEcommerce = false;
  bool get isLoadingEcommerce => _isLoadingEcommerce;

  EcommerceIntegration? getIntegrationByPlatform(String platform) {
    try {
      return _ecommerceIntegrations.firstWhere((i) => i.platform == platform);
    } catch (_) {
      return null;
    }
  }

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

  Future<void> loadSettings({bool isSilent = false}) async {
    if (!isSilent) {
      _isLoading = true;
      notifyListeners();
    }
    
    try {
      final prefs = await SharedPreferences.getInstance();
      _currentApiUrl = prefs.getString('pos_api');

      _settings = await getSettingsUseCase();
      
      // DEBUG: Inspección de permisos PRO
      if (_settings != null) {
        debugPrint('=== DEBUG LICENCIA ===');
        debugPrint('Plan: ${_settings!.licensePlanType}');
        debugPrint('Features Dictionary Loaded: ${_settings!.features}');
        debugPrint('Advanced Reports: ${_settings!.features.advancedReports}');
        debugPrint('=======================');
      }
      
      // Iniciar el sistema de seguridad DRM
      await LicenseHeartbeatService().initialize(
        _settings,
        onSyncRequested: () => syncLicenseWithServer(AppConfig.kApiBaseUrl, isSilent: true),
      );

      // Hardware config migrado a LocalTerminalProvider (SharedPreferences por caja).
      // Ya no se reconfigura la impresora desde los ajustes globales de la nube.
      
      _checkAndSyncSilentlyOnStartup();
    } catch (e, stack) {
      if (!isSilent) {
        debugPrint('=== ERROR CRITICO CARGANDO SETTINGS ===');
        debugPrint('Error: $e');
        debugPrint('Stack: $stack');
      }
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      rethrow;
    } finally {
      if (!isSilent) {
        _isLoading = false;
        notifyListeners();
      } else {
        // Solo notificar si cambió el config subyacente sin bloquear UI
        notifyListeners();
      }
    }
  }

  /// Refresco silencioso para validaciones de fondo en la navegación.
  DateTime? _lastSilentRefresh;

  Future<void> refreshSettingsSilently() async {
    final now = DateTime.now();
    // Rate limit: Evitar sobrecargar el servidor local en cada navegación (máx 1 vez cada 2 minutos)
    if (_lastSilentRefresh != null && now.difference(_lastSilentRefresh!).inMinutes < 2) {
      return;
    }
    _lastSilentRefresh = now;

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
      final updated = await updateSettingsUseCase(data);
      if (updated.effectiveLogoUrl == null && _settings?.effectiveLogoUrl != null) {
        _settings = updated.copyWith(
          logoUrl: _settings!.logoUrl,
          logoPath: updated.logoPath ?? _settings!.logoPath,
        );
      } else {
        _settings = updated;
      }
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> uploadLogo(String filePath, {List<int>? bytes, String? filename}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await updateSettingsUseCase.repository.uploadLogo(filePath, bytes: bytes, filename: filename);
      await loadSettings(isSilent: true);
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
    _currentApiUrl = newUrl;
    if (updateSettingsUseCase.repository is SettingsRepositoryImpl) {
      (updateSettingsUseCase.repository as SettingsRepositoryImpl).updateBaseUrl(newUrl);
    }
  }

  Future<Map<String, dynamic>?> loadIntegrations({bool isSilent = false}) async {
    if (!isSilent) {
      _isLoadingIntegrations = true;
      notifyListeners();
    }
    try {
      final repo = updateSettingsUseCase.repository;
      final data = await repo.fetchIntegrations();
      _integrations = data;
      return data;
    } catch (e) {
      debugPrint('[SettingsProvider] Error al cargar integraciones: $e');
      if (!isSilent) {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      }
      return null;
    } finally {
      if (!isSilent) {
        _isLoadingIntegrations = false;
        notifyListeners();
      }
    }
  }

  Future<bool> saveIntegrations(Map<String, dynamic> data) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final repo = updateSettingsUseCase.repository;
      final success = await repo.updateIntegrations(data);
      if (success) {
        await loadIntegrations(isSilent: true);
        await loadSettings(isSilent: true);
      }
      return success;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> testMercadoPagoConnection({String? mpAccessToken}) async {
    final repo = updateSettingsUseCase.repository;
    return await repo.testMercadoPagoConnection(mpAccessToken: mpAccessToken);
  }

  Future<Map<String, dynamic>> uploadAfipCertificates({
    required String cuit,
    required List<int> certBytes,
    required String certFilename,
    required List<int> keyBytes,
    required String keyFilename,
    String? keyPassphrase,
  }) async {
    _isUploadingCertificates = true;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final repo = updateSettingsUseCase.repository;
      final result = await repo.uploadAfipCertificates(
        cuit: cuit,
        certBytes: certBytes,
        certFilename: certFilename,
        keyBytes: keyBytes,
        keyFilename: keyFilename,
        keyPassphrase: keyPassphrase,
      );
      await loadIntegrations(isSilent: true);
      return result;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      rethrow;
    } finally {
      _isUploadingCertificates = false;
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<List<EcommerceIntegration>> loadEcommerceIntegrations({bool isSilent = false}) async {
    if (!isSilent) {
      _isLoadingEcommerce = true;
      notifyListeners();
    }
    try {
      final repo = updateSettingsUseCase.repository;
      final list = await repo.getEcommerceIntegrations();
      _ecommerceIntegrations = List<EcommerceIntegration>.from(list);
      return list;
    } catch (e) {
      debugPrint('[SettingsProvider] Error al cargar integraciones e-commerce: $e');
      if (!isSilent) {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      }
      return _ecommerceIntegrations;
    } finally {
      if (!isSilent) {
        _isLoadingEcommerce = false;
        notifyListeners();
      }
    }
  }

  Future<EcommerceIntegration?> saveEcommerceIntegration(Map<String, dynamic> data, {int? id}) async {
    _isLoadingEcommerce = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final repo = updateSettingsUseCase.repository;
      final EcommerceIntegration saved;
      int? effectiveId = id;
      if (effectiveId == null) {
        final existing = _ecommerceIntegrations.cast<EcommerceIntegration?>().firstWhere(
          (i) => i != null && i.platform == data['platform'],
          orElse: () => null,
        );
        if (existing != null) {
          effectiveId = existing.id;
        }
      }

      if (effectiveId != null) {
        saved = await repo.updateEcommerceIntegration(effectiveId, data);
        final index = _ecommerceIntegrations.indexWhere((i) => i.id == effectiveId);
        if (index != -1) {
          _ecommerceIntegrations[index] = saved;
        } else {
          _ecommerceIntegrations.add(saved);
        }
      } else {
        try {
          saved = await repo.createEcommerceIntegration(data);
          final index = _ecommerceIntegrations.indexWhere((i) => i.platform == saved.platform);
          if (index != -1) {
            _ecommerceIntegrations[index] = saved;
          } else {
            _ecommerceIntegrations.add(saved);
          }
        } catch (e) {
          if (e.toString().contains('unique') || e.toString().contains('422')) {
            final freshList = await repo.getEcommerceIntegrations();
            _ecommerceIntegrations = List<EcommerceIntegration>.from(freshList);
            final match = freshList.cast<EcommerceIntegration?>().firstWhere(
              (i) => i != null && i.platform == data['platform'],
              orElse: () => null,
            );
            if (match != null && match.id != null) {
              final updated = await repo.updateEcommerceIntegration(match.id!, data);
              final idx = _ecommerceIntegrations.indexWhere((i) => i.id == match.id);
              if (idx != -1) {
                _ecommerceIntegrations[idx] = updated;
              } else {
                _ecommerceIntegrations.add(updated);
              }
              notifyListeners();
              return updated;
            }
          }
          rethrow;
        }
      }
      notifyListeners();
      return saved;
    } catch (e) {
      debugPrint('[SettingsProvider] Error al guardar integración e-commerce: $e');
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      rethrow;
    } finally {
      _isLoadingEcommerce = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> testEcommerceConnection(int id) async {
    try {
      final repo = updateSettingsUseCase.repository;
      final result = await repo.testEcommerceConnection(id);
      final isSuccess = result['success'] == true;
      final newStatus = isSuccess ? 'connected' : 'error';
      final index = _ecommerceIntegrations.indexWhere((i) => i.id == id);
      if (index != -1) {
        _ecommerceIntegrations[index] = _ecommerceIntegrations[index].copyWith(
          lastHealthStatus: newStatus,
          lastHealthCheckAt: DateTime.now().toIso8601String(),
        );
        notifyListeners();
      }
      return result;
    } catch (e) {
      debugPrint('[SettingsProvider] Error al probar conexión e-commerce: $e');
      return {
        'success': false,
        'message': e.toString().replaceAll('Exception: ', ''),
      };
    }
  }

  Future<EcommerceIntegration?> toggleEcommerceActive(int id) async {
    try {
      final repo = updateSettingsUseCase.repository;
      final updated = await repo.toggleEcommerceActive(id);
      final index = _ecommerceIntegrations.indexWhere((i) => i.id == id);
      if (index != -1) {
        _ecommerceIntegrations[index] = updated;
      } else {
        _ecommerceIntegrations.add(updated);
      }
      notifyListeners();
      return updated;
    } catch (e) {
      debugPrint('[SettingsProvider] Error al cambiar activo de e-commerce: $e');
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      rethrow;
    }
  }

  Future<bool> deleteEcommerceIntegration(int id) async {
    try {
      final repo = updateSettingsUseCase.repository;
      final success = await repo.deleteEcommerceIntegration(id);
      if (success) {
        _ecommerceIntegrations.removeWhere((i) => i.id == id);
        notifyListeners();
      }
      return success;
    } catch (e) {
      debugPrint('[SettingsProvider] Error al eliminar integración e-commerce: $e');
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      return false;
    }
  }

  Future<Map<String, dynamic>> importEcommerceCatalog(int id) async {
    try {
      final repo = updateSettingsUseCase.repository;
      final result = await repo.importEcommerceCatalog(id);
      return result;
    } catch (e) {
      debugPrint('[SettingsProvider] Error al importar catálogo e-commerce: $e');
      return {
        'success': false,
        'message': e.toString().replaceAll('Exception: ', ''),
      };
    }
  }

  Future<Map<String, dynamic>> exportEcommerceCatalog(int id) async {
    try {
      final repo = updateSettingsUseCase.repository;
      final result = await repo.exportEcommerceCatalog(id);
      return result;
    } catch (e) {
      debugPrint('[SettingsProvider] Error al exportar catálogo e-commerce: $e');
      return {
        'success': false,
        'message': e.toString().replaceAll('Exception: ', ''),
      };
    }
  }

  Future<String> activateLicense(String baseUrl, String licenseKey) async {
    _isLoading = true;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      final activeUrl = prefs.getString('pos_api') ?? baseUrl;
      
      final response = await http.post(
        Uri.parse('$activeUrl/settings/license'),
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
        await loadSettings(isSilent: true);
        
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
        await loadSettings(isSilent: true);
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
  Future<void> syncLicenseWithServer(String baseUrl, {bool isSilent = false}) async {
    if (!isSilent) {
      _isLoading = true;
      notifyListeners();
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final activeUrl = prefs.getString('pos_api') ?? baseUrl;

      final response = await http.post(
        Uri.parse('$activeUrl/settings/license/sync'),
        headers: {'Accept': 'application/json', 'Content-Type': 'application/json'},
      ).timeout(const Duration(minutes: 4)); // 4 min: tolera cold-start de Render (2-3 min)

      final dynamic data;
      try {
        data = json.decode(response.body);
      } catch (_) {
        throw const FormatException('La respuesta del servidor no es un JSON válido.');
      }

      if (response.statusCode == 200) {
        await loadSettings(isSilent: true);
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
        await loadSettings(isSilent: true);
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
      if (!isSilent) rethrow; // Consumimos el error si es un chequeo silencioso (heartbeat)
    } finally {
      if (!isSilent) {
        _isLoading = false;
        notifyListeners();
      }
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
      // ⚠️ CRÍTICO: usar la URL activa (SharedPrefs) y NO AppConfig.kApiBaseUrl hardcodeado.
      // Si la app apunta a un backend alternativo (ej: _test), sincronizar contra ese backend
      // para que los permisos se actualicen donde realmente está leyendo la app.
      SharedPreferences.getInstance().then((prefs) {
        final activeUrl = prefs.getString('pos_api') ?? AppConfig.kApiBaseUrl;
        http.post(
          Uri.parse('$activeUrl/settings/license/sync'),
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
      });
    }
  }
}
