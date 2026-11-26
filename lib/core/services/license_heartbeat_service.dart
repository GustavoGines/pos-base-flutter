import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../features/settings/domain/entities/business_settings.dart';

enum LicenseSecurityStatus {
  ok,
  clockTampered,
  offlineExpired,
  subscriptionExpired,
  trialExpired,
  suspended,
}

class LicenseHeartbeatService extends ChangeNotifier with WidgetsBindingObserver {
  static final LicenseHeartbeatService _instance =
      LicenseHeartbeatService._internal();
  factory LicenseHeartbeatService() => _instance;
  LicenseHeartbeatService._internal() {
    WidgetsBinding.instance.addObserver(this);
  }

  FlutterSecureStorage _storage = const FlutterSecureStorage();

  @visibleForTesting
  void setStorageForTesting(FlutterSecureStorage storage) {
    _storage = storage;
  }

  Timer? _heartbeatTimer;
  Timer? _pulseTimer;
  bool _initialized =
      false; // Guard para que los timers arranquen solo 1 vez por sesión
  BusinessSettings? _lastSettings;
  DateTime? _lastPulseStorageWrite;

  // Función para inyectar la dependencia de sincronización desde SettingsProvider
  Future<void> Function()? _onSyncRequested;

  LicenseSecurityStatus _securityStatus = LicenseSecurityStatus.ok;
  LicenseSecurityStatus get securityStatus => _securityStatus;

  bool get isBlocked => _securityStatus != LicenseSecurityStatus.ok;

  /// Inicialización: Carga datos locales y verifica Drift inicial
  Future<void> initialize(
    BusinessSettings? settings, {
    Future<void> Function()? onSyncRequested,
  }) async {
    if (settings == null) return;
    _lastSettings = settings;

    if (onSyncRequested != null) {
      _onSyncRequested = onSyncRequested;
    }

    // Siempre ejecutamos los checks de seguridad (drift + grace period)
    // porque el usuario puede volver de un período largo de inactividad.
    await _checkClockDrift();
    await _checkOfflineGrace(settings);

    // ─── GUARD DE INICIALIZACIÓN ───────────────────────────────────────────
    // Los Timer.periodic SOLO se crean la primera vez que el usuario inicia
    // sesión. Las llamadas subsiguientes desde el LicenseRefreshObserver (que
    // triggers loadSettings en cada pantalla) solo actualizan el callback de
    // sync sin matar ni recrear los timers.
    if (!_initialized) {
      _initialized = true;

      // Timer 1: Pulso local cada 1 min (re-evalúa corte exacto en memoria y persiste storage cada 15 min)
      _pulseTimer?.cancel();
      _pulseTimer = Timer.periodic(
        const Duration(minutes: 1),
        (_) => _onPulseTick(),
      );

      // Timer 2: Ping Silencioso al servidor (cada 3 min)
      _heartbeatTimer?.cancel();
      _heartbeatTimer = Timer.periodic(
        const Duration(minutes: 3),
        (_) => _triggerSync(),
      );
    }
    // ──────────────────────────────────────────────────────────────────────
    notifyListeners();
  }

  Future<void> _onPulseTick() async {
    final now = DateTime.now();
    if (_lastPulseStorageWrite == null ||
        now.difference(_lastPulseStorageWrite!).inMinutes >= 15) {
      await _updatePulse();
    }
    if (_lastSettings != null) {
      await _checkOfflineGrace(_lastSettings!);
    }
  }

  /// L-03: Permitir que _triggerSync se ejecute incluso si el estado actual es clockTampered,
  /// de modo que cuando la PC recupere la hora oficial o contacte al servidor,
  /// updateLastSync() restablezca la marca temporal con server_time y destrabe el POS (cero deadlock).
  Future<void> _triggerSync() async {
    try {
      if (_onSyncRequested != null) {
        await _onSyncRequested!();
      }
    } catch (_) {
      // Falla silenciosa si no hay internet
    }
  }

  /// Verifica si el reloj fue atrasado manualmente (Time Rollback)
  Future<void> _checkClockDrift() async {
    try {
      final now = DateTime.now();
      final lastTimeStr = await _storage.read(key: 'drm_last_system_time');

      if (lastTimeStr != null) {
        final lastTime = DateTime.tryParse(lastTimeStr);
        if (lastTime == null) {
          // L-16: Si el valor en storage fue manipulado con formato inválido, marcar anomalía sin purgar todo el storage
          _securityStatus = LicenseSecurityStatus.clockTampered;
          notifyListeners();
          return;
        }
        // Si el reloj actual es anterior al último registrado, hay manipulación
        if (now.isBefore(lastTime.subtract(const Duration(minutes: 2)))) {
          _securityStatus = LicenseSecurityStatus.clockTampered;
          notifyListeners();
          return;
        }
      }
    } on PlatformException catch (e) {
      // L-16: Solo ante excepción nativa de desencriptación DPAPI en Windows,
      // borrar únicamente la llave corrupta e intentar resincronizar con el servidor.
      debugPrint(
        'Error nativo DPAPI en Storage: $e. Limpiando llave corrupta y forzando sync...',
      );
      try {
        await _storage.delete(key: 'drm_last_system_time');
      } catch (_) {}
      await _triggerSync();
      return;
    } catch (e) {
      debugPrint('Error verificando reloj DRM: $e');
      return;
    }

    await _updatePulse();
  }

  /// Guarda el tiempo actual de forma segura para el próximo Drift Check
  Future<void> _updatePulse() async {
    if (_securityStatus == LicenseSecurityStatus.clockTampered) return;
    try {
      final now = DateTime.now();
      await _storage.write(
        key: 'drm_last_system_time',
        value: now.toIso8601String(),
      );
      _lastPulseStorageWrite = now;
    } catch (_) {
      // Si falla la escritura (ej. error nativo), ignoramos para no romper el flujo
    }
  }

  /// Verifica la regla de las 72hs y expiración contractual diferenciando Demo vs SaaS (L-08)
  Future<void> _checkOfflineGrace(BusinessSettings settings) async {
    if (settings.licenseBlockReason == 'clock_tampered') {
      _securityStatus = LicenseSecurityStatus.clockTampered;
      notifyListeners();
      return;
    }

    // Si es Lifetime, no hay bloqueo por expiración ni por offline
    if (settings.licensePlanMode == 'lifetime' || settings.isLifetime) {
      if (_securityStatus != LicenseSecurityStatus.clockTampered) {
        _securityStatus = LicenseSecurityStatus.ok;
      }
      return;
    }

    // L-08: Si se conoce la fecha de expiración contractual y ya venció, bloquear con motivo exacto
    if (settings.licenseExpiresAt != null &&
        DateTime.now().isAfter(settings.licenseExpiresAt!)) {
      _securityStatus = settings.isTrial
          ? LicenseSecurityStatus.trialExpired
          : LicenseSecurityStatus.subscriptionExpired;
      notifyListeners();
      return;
    }

    if (settings.licensePlanType == 'blocked') {
      _securityStatus = switch (settings.licenseBlockReason) {
        'trial_expired' => LicenseSecurityStatus.trialExpired,
        'subscription_expired' => LicenseSecurityStatus.subscriptionExpired,
        'offline_grace_expired' => LicenseSecurityStatus.offlineExpired,
        'suspended' => LicenseSecurityStatus.suspended,
        'clock_tampered' => LicenseSecurityStatus.clockTampered,
        _ => settings.isTrial
            ? LicenseSecurityStatus.trialExpired
            : LicenseSecurityStatus.subscriptionExpired,
      };
      notifyListeners();
      return;
    }

    final lastCheckStr = settings.lastLicenseCheck;
    if (lastCheckStr == null || lastCheckStr.isEmpty) {
      if (_securityStatus != LicenseSecurityStatus.clockTampered) {
        _securityStatus = LicenseSecurityStatus.ok;
      }
      return;
    }

    try {
      final lastCheck = DateTime.parse(lastCheckStr);
      final diff = DateTime.now().difference(lastCheck);

      if (diff.inHours > 72) {
        _securityStatus = LicenseSecurityStatus.offlineExpired;
        notifyListeners();
        return;
      }
    } catch (_) {
      // Error de parseo, ignoramos por ahora
    }

    if (_securityStatus != LicenseSecurityStatus.clockTampered) {
      _securityStatus = LicenseSecurityStatus.ok;
    }
  }

  /// Actualiza los datos de seguridad tras un ping exitoso al servidor
  Future<void> updateLastSync(BusinessSettings settings) async {
    _lastSettings = settings;
    _securityStatus = LicenseSecurityStatus.ok;

    // LIC-07: Usar DateTime.now() local al confirmar sincronización exitosa con el servidor,
    // evitando falsos positivos de clockTampered cuando el reloj de Windows del cliente
    // tiene algunos minutos de desfase respecto al reloj UTC del servidor en Render.
    try {
      final now = DateTime.now();
      await _storage.write(
        key: 'drm_last_system_time',
        value: now.toIso8601String(),
      );
      _lastPulseStorageWrite = now;
    } catch (_) {}

    await _checkOfflineGrace(settings);
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _initialized) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        debugPrint('=== App Resumed: Forcing License Sync ===');
        _triggerSync();
      });
    }
  }

  void stop() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _pulseTimer?.cancel();
    _pulseTimer = null;
    _lastSettings = null;
    _lastPulseStorageWrite = null;
    // Reset del flag para que el próximo login inicie un ciclo limpio
    _initialized = false;
    _securityStatus = LicenseSecurityStatus.ok;
  }
}
