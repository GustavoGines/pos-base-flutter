import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../features/settings/domain/entities/business_settings.dart';

enum LicenseSecurityStatus { ok, clockTampered, offlineExpired }

class LicenseHeartbeatService extends ChangeNotifier {
  static final LicenseHeartbeatService _instance =
      LicenseHeartbeatService._internal();
  factory LicenseHeartbeatService() => _instance;
  LicenseHeartbeatService._internal();

  final _storage = const FlutterSecureStorage();

  Timer? _heartbeatTimer;
  Timer? _pulseTimer;
  bool _initialized =
      false; // Guard para que los timers arranquen solo 1 vez por sesión

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

      // Timer 1: Reloj Policía (cada 15 min)
      _pulseTimer?.cancel();
      _pulseTimer = Timer.periodic(
        const Duration(minutes: 15),
        (_) => _updatePulse(),
      );

      // Timer 2: Ping Silencioso al servidor (cada 30 min)
      _heartbeatTimer?.cancel();
      _heartbeatTimer = Timer.periodic(
        const Duration(minutes: 30),
        (_) => _triggerSync(),
      );
    }
    // ──────────────────────────────────────────────────────────────────────
    notifyListeners();
  }

  Future<void> _triggerSync() async {
    if (_securityStatus == LicenseSecurityStatus.clockTampered) return;
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
        final lastTime = DateTime.parse(lastTimeStr);
        // Si el reloj actual es anterior al último registrado, hay manipulación
        if (now.isBefore(lastTime.subtract(const Duration(minutes: 2)))) {
          _securityStatus = LicenseSecurityStatus.clockTampered;
          notifyListeners();
        }
      }
    } catch (e) {
      // 🚨 FALLBACK CRÍTICO: Si DPAPI falla al desencriptar (archivo corrupto en Windows),
      // limpiamos el almacenamiento para evitar bloqueos del sistema.
      debugPrint(
        'Error de seguridad (Storage): $e. Limpiando datos corruptos...',
      );
      try {
        await _storage.deleteAll();
      } catch (_) {}
    }

    await _updatePulse();
  }

  /// Guarda el tiempo actual de forma segura para el próximo Drift Check
  Future<void> _updatePulse() async {
    if (_securityStatus == LicenseSecurityStatus.clockTampered) return;
    try {
      await _storage.write(
        key: 'drm_last_system_time',
        value: DateTime.now().toIso8601String(),
      );
    } catch (_) {
      // Si falla la escritura (ej. error nativo), ignoramos para no romper el flujo
    }
  }

  /// Verifica la regla de las 72hs para planes SaaS
  Future<void> _checkOfflineGrace(BusinessSettings settings) async {
    // Si es Lifetime, no hay bloqueo por offline
    if (settings.licensePlanMode == 'lifetime') return;

    final lastCheckStr = settings.lastLicenseCheck;
    if (lastCheckStr == null || lastCheckStr.isEmpty) return;

    try {
      final lastCheck = DateTime.parse(lastCheckStr);
      final diff = DateTime.now().difference(lastCheck);

      if (diff.inHours > 72) {
        _securityStatus = LicenseSecurityStatus.offlineExpired;
        notifyListeners();
      }
    } catch (_) {
      // Error de parseo, ignoramos por ahora
    }
  }

  /// Actualiza los datos de seguridad tras un ping exitoso al servidor
  Future<void> updateLastSync(BusinessSettings settings) async {
    _securityStatus = LicenseSecurityStatus.ok;

    if (settings.serverTime != null) {
      // Usar el tiempo del servidor para resetear la base de tiempo local
      await _storage.write(
        key: 'drm_last_system_time',
        value: settings.serverTime,
      );
    }

    await _checkOfflineGrace(settings);
    notifyListeners();
  }

  void stop() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _pulseTimer?.cancel();
    _pulseTimer = null;
    // Reset del flag para que el próximo login inicie un ciclo limpio
    _initialized = false;
    _securityStatus = LicenseSecurityStatus.ok;
  }
}
