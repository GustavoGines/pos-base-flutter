import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/config/app_config.dart';
import '../models/update_info.dart';

class UpdateCheckResult {
  final UpdateInfo? frontendUpdate;
  final UpdateInfo? backendUpdate;
  final String channel;
  final bool serverChecked;

  UpdateCheckResult({
    this.frontendUpdate,
    this.backendUpdate,
    this.channel = 'stable',
    this.serverChecked = true,
  });

  bool get hasAny => frontendUpdate != null || backendUpdate != null;
  bool get isBeta => channel.toLowerCase() == 'beta';
  bool get isFullSystemUpdate =>
      frontendUpdate != null && backendUpdate != null;
}

class UpdateService {
  UpdateService._internal();
  static final UpdateService _instance = UpdateService._internal();
  factory UpdateService() => _instance;
  static UpdateService get instance => _instance;

  /// Notificador global reactivo para mostrar la alerta en la barra de navegación.
  static final ValueNotifier<UpdateCheckResult?> updateNotifier =
      ValueNotifier(null);

  /// Canal activo (`stable` o `beta`) sincronizado en tiempo real.
  static final ValueNotifier<String> channelNotifier = ValueNotifier('stable');

  /// Indica si hay una consulta de actualización en curso.
  static final ValueNotifier<bool> isCheckingNotifier = ValueNotifier(false);

  /// Indica que el cambio de canal (`stable` <-> `beta`) está esperando respuesta del servidor.
  static final ValueNotifier<bool> isSwitchingChannelNotifier =
      ValueNotifier(false);

  int _checkGeneration = 0;
  int _activeChecksCount = 0;
  Timer? _pollingTimer;

  http.Client? _testHttpClient;
  Future<String> Function()? _testFrontendVersionProvider;
  bool _forceAllowInDebugForTest = false;

  bool get isPeriodicCheckActive => _pollingTimer?.isActive == true;

  @visibleForTesting
  void configureForTesting({
    http.Client? httpClient,
    Future<String> Function()? frontendVersionProvider,
    bool forceAllowInDebug = false,
  }) {
    _testHttpClient = httpClient;
    _testFrontendVersionProvider = frontendVersionProvider;
    _forceAllowInDebugForTest = forceAllowInDebug;
  }

  @visibleForTesting
  void resetForTesting() {
    stopPeriodicCheck();
    _checkGeneration++;
    _activeChecksCount = 0;
    _testHttpClient = null;
    _testFrontendVersionProvider = null;
    _forceAllowInDebugForTest = false;
    updateNotifier.value = null;
    channelNotifier.value = 'stable';
    isCheckingNotifier.value = false;
    isSwitchingChannelNotifier.value = false;
  }

  static String _normalizeChannel(String? raw) {
    return raw?.trim().toLowerCase() == 'beta' ? 'beta' : 'stable';
  }

  Future<http.Response> _httpGet(
    Uri uri, {
    Map<String, String>? headers,
    required Duration timeout,
  }) {
    final client = _testHttpClient;
    if (client != null) {
      return client.get(uri, headers: headers).timeout(timeout);
    }
    return http.get(uri, headers: headers).timeout(timeout);
  }

  Future<String> _resolveFrontendVersion() async {
    if (_testFrontendVersionProvider != null) {
      return await _testFrontendVersionProvider!();
    }
    final packageInfo = await PackageInfo.fromPlatform();
    return packageInfo.version;
  }

  /// Cambia el canal de actualizaciones (`stable` <-> `beta`), invalida en 0ms
  /// el badge del canal anterior y dispara una verificación inmediata protegida
  /// contra condiciones de carrera mediante [_checkGeneration].
  Future<UpdateCheckResult> setChannel(
    String newChannel, {
    bool allowInDebug = true,
  }) async {
    final normalized = _normalizeChannel(newChannel);
    final int switchGen = ++_checkGeneration;
    channelNotifier.value = normalized;
    updateNotifier.value = null;
    isSwitchingChannelNotifier.value = true;
    isCheckingNotifier.value = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('update_channel', normalized);
    } catch (_) {}

    if (switchGen != _checkGeneration) {
      return UpdateCheckResult(channel: normalized, serverChecked: false);
    }

    return checkUpdate(
      throwErrors: false,
      allowInDebug: allowInDebug,
      isChannelSwitch: true,
      channelOverride: normalized,
    );
  }

  /// Inicia el polling silencioso en segundo plano (singleton, idempotente).
  /// Si la terminal está offline, falla en silencio sin mostrar errores ni limpiar
  /// el estado actual.
  void startPeriodicCheck({
    Duration interval = const Duration(minutes: 45),
    bool allowInDebug = false,
  }) {
    if (_pollingTimer?.isActive == true) return;
    _pollingTimer = Timer.periodic(interval, (_) {
      if (kDebugMode && !allowInDebug && !_forceAllowInDebugForTest) return;
      if (isCheckingNotifier.value) return;
      unawaited(checkUpdate(throwErrors: false, allowInDebug: allowInDebug));
    });
  }

  void stopPeriodicCheck() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  /// Consulta al servidor si hay versiones nuevas disponibles.
  /// Chequea backend y frontend de forma separada y descarta respuestas viejas
  /// si el usuario cambia rápido de canal (`_checkGeneration`), permitiendo que
  /// llamadas concurrentes sobre el MISMO canal (ej. Fase 2 Auto-Resume en
  /// `main.dart` + `LoginScreen`) completen ambas sin cancelarse mutuamente.
  Future<UpdateCheckResult> checkUpdate({
    bool throwErrors = false,
    bool allowInDebug = false,
    bool isChannelSwitch = false,
    String? channelOverride,
  }) async {
    final int myGen = _checkGeneration;
    final prefs = await SharedPreferences.getInstance();
    if (myGen != _checkGeneration) {
      return updateNotifier.value ??
          UpdateCheckResult(
            channel: channelNotifier.value,
            serverChecked: false,
          );
    }
    final updateChannel = _normalizeChannel(
      channelOverride ?? prefs.getString('update_channel') ?? 'stable',
    );
    if (myGen == _checkGeneration) {
      channelNotifier.value = updateChannel;
    }

    if (kDebugMode && !allowInDebug && !_forceAllowInDebugForTest) {
      final result = UpdateCheckResult(channel: updateChannel);
      if (myGen == _checkGeneration) {
        updateNotifier.value = result;
        if (_activeChecksCount == 0) {
          isCheckingNotifier.value = false;
        }
        if (isChannelSwitch) {
          isSwitchingChannelNotifier.value = false;
        }
      }
      return result;
    }

    _activeChecksCount++;
    if (myGen == _checkGeneration) {
      isCheckingNotifier.value = true;
      if (isChannelSwitch) {
        isSwitchingChannelNotifier.value = true;
      }
    }

    UpdateInfo? frontendUpdate;
    UpdateInfo? backendUpdate;
    bool anyServerCheckSucceeded = false;
    final serverTimeout =
        throwErrors ? const Duration(minutes: 4) : const Duration(seconds: 45);

    try {
      final currentFrontendVersion = await _resolveFrontendVersion();
      if (myGen != _checkGeneration) {
        return updateNotifier.value ??
            UpdateCheckResult(channel: updateChannel, serverChecked: false);
      }

      // 0. Obtener versión REAL del backend local (Single Source of Truth).
      // IMPORTANTE: si /version-check falla (timeout, URL incorrecta, etc.)
      // usamos '0.0.0' como fallback —nunca el valor cacheado en SharedPrefs—
      // para evitar que un entorno cambiado bloquee silenciosamente la detección.
      String currentBackendVersion = '0.0.0';
      String? localBackendVendorHash;
      try {
        final currentApiUrl = prefs.getString('pos_api') ?? AppConfig.kApiBaseUrl;
        final localBackendUri = Uri.parse(
          '$currentApiUrl/version-check?t=${DateTime.now().millisecondsSinceEpoch}',
        );
        final localResponse = await _httpGet(
          localBackendUri,
          timeout: const Duration(seconds: 5),
        );
        if (localResponse.statusCode == 200) {
          final localData = json.decode(localResponse.body);
          currentBackendVersion = localData['version'] ?? '0.0.0';
          localBackendVendorHash = localData['vendor_hash']?.toString();
        } else {
          // Si el servidor responde pero hay error (500, 404), usamos 0.0.0 para permitir que el OTA lo repare.
          currentBackendVersion = '0.0.0';
        }
      } on TimeoutException {
        // Laragon o la red no ha arrancado todavía
        if (throwErrors) {
          throw Exception(
              'El servidor local está apagado o iniciando (Timeout).');
        }
      } catch (e) {
        // Conexión rechazada (SocketException), etc.
        if (throwErrors) {
          throw Exception('El servidor local está apagado o inaccesible.');
        }
      }

      if (myGen != _checkGeneration) {
        return updateNotifier.value ??
            UpdateCheckResult(channel: updateChannel, serverChecked: false);
      }

      // 1. Chequeo de Backend
      final backendUri =
          Uri.parse('${AppConfig.kLicenseServerUrl}/api/check-update').replace(
        queryParameters: {
          'component': 'backend',
          'current_version': currentBackendVersion,
          'channel': updateChannel,
        },
      );

      final backendResponse = await _httpGet(
        backendUri,
        headers: const {'Accept': 'application/json'},
        timeout: serverTimeout,
      );

      if (myGen != _checkGeneration) {
        return updateNotifier.value ??
            UpdateCheckResult(channel: updateChannel, serverChecked: false);
      }

      if (backendResponse.statusCode == 200) {
        anyServerCheckSucceeded = true;
        final data = json.decode(backendResponse.body);
        if (data['success'] == true &&
            data['update_available'] == true &&
            data['data'] != null) {
          backendUpdate = UpdateInfo.fromJson(
            Map<String, dynamic>.from(data['data'] as Map),
            component: 'backend',
            localVendorHash: localBackendVendorHash,
          );
        }
      }

      // 2. Chequeo de Frontend
      final frontendUri =
          Uri.parse('${AppConfig.kLicenseServerUrl}/api/check-update').replace(
        queryParameters: {
          'component': 'frontend',
          'current_version': currentFrontendVersion,
          'channel': updateChannel,
        },
      );

      final frontendResponse = await _httpGet(
        frontendUri,
        headers: const {'Accept': 'application/json'},
        timeout: serverTimeout,
      );

      if (myGen != _checkGeneration) {
        return updateNotifier.value ??
            UpdateCheckResult(channel: updateChannel, serverChecked: false);
      }

      if (frontendResponse.statusCode == 200) {
        anyServerCheckSucceeded = true;
        final data = json.decode(frontendResponse.body);
        if (data['success'] == true &&
            data['update_available'] == true &&
            data['data'] != null) {
          frontendUpdate = UpdateInfo.fromJson(
            Map<String, dynamic>.from(data['data'] as Map),
            component: 'frontend',
          );
        }
      }
    } on TimeoutException {
      if (throwErrors) {
        throw Exception(
            'Timeout esperando al servidor (posible arranque en Render).');
      }
    } catch (e) {
      if (throwErrors) rethrow;
    } finally {
      if (_activeChecksCount > 0) {
        _activeChecksCount--;
      }
      if (myGen == _checkGeneration) {
        if (_activeChecksCount == 0) {
          isCheckingNotifier.value = false;
        }
        if (isChannelSwitch) {
          isSwitchingChannelNotifier.value = false;
        }
      }
    }

    if (myGen != _checkGeneration) {
      return updateNotifier.value ??
          UpdateCheckResult(channel: updateChannel, serverChecked: false);
    }

    final result = UpdateCheckResult(
      frontendUpdate: frontendUpdate,
      backendUpdate: backendUpdate,
      channel: updateChannel,
      serverChecked: anyServerCheckSucceeded,
    );

    if (anyServerCheckSucceeded) {
      updateNotifier.value = result;
    } else if (isChannelSwitch) {
      updateNotifier.value = null;
    }
    return result;
  }
}

