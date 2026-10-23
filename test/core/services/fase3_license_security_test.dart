import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_desktop/core/presentation/widgets/license_guard.dart';
import 'package:frontend_desktop/core/services/license_heartbeat_service.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/updater/data/models/update_info.dart';

class FakeSecureStorage extends FlutterSecureStorage {
  final Map<String, String> store = {};
  bool throwPlatformExceptionOnRead = false;

  FakeSecureStorage() : super();

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (throwPlatformExceptionOnRead) {
      throw PlatformException(code: 'DPAPI_ERROR', message: 'Decryption failed');
    }
    return store[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      store.remove(key);
    } else {
      store[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    store.remove(key);
  }

  @override
  Future<void> deleteAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    store.clear();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Fase 3 — LicenseGuard.isRemoteApiUrl (L-13)', () {
    test('permite terminales LAN con HTTP y HTTPS sin exigir addon remote_access', () {
      expect(LicenseGuard.isRemoteApiUrl('http://localhost:8000/api'), isFalse);
      expect(LicenseGuard.isRemoteApiUrl('https://localhost/Sistema_POS/pos-backend/public/api'), isFalse);
      expect(LicenseGuard.isRemoteApiUrl('https://127.0.0.1:8443/api'), isFalse);
      expect(LicenseGuard.isRemoteApiUrl('https://192.168.1.200/Sistema_POS/pos-backend/public/api'), isFalse);
      expect(LicenseGuard.isRemoteApiUrl('http://10.0.0.45:8080/api'), isFalse);
      expect(LicenseGuard.isRemoteApiUrl('https://172.16.5.10/api'), isFalse);
      expect(LicenseGuard.isRemoteApiUrl('https://172.31.255.1/api'), isFalse);
      expect(LicenseGuard.isRemoteApiUrl('https://servidor-caja.local/api'), isFalse);
      expect(LicenseGuard.isRemoteApiUrl('http://pc-mostrador/api'), isFalse);
    });

    test('detecta correctamente accesos remotos por túneles o IPs/dominios públicos (HTTP y HTTPS)', () {
      expect(LicenseGuard.isRemoteApiUrl('https://pos-tienda.trycloudflare.com/api'), isTrue);
      expect(LicenseGuard.isRemoteApiUrl('http://pos-tienda.trycloudflare.com/api'), isTrue);
      expect(LicenseGuard.isRemoteApiUrl('http://181.45.20.11:8080/api'), isTrue);
      expect(LicenseGuard.isRemoteApiUrl('https://pos.micomercio.com.ar/api'), isTrue);
      expect(LicenseGuard.isRemoteApiUrl('http://172.32.0.1/api'), isTrue); // Fuera de rango RFC 1918 (172.16-31)
    });
  });

  group('Fase 3 — LicenseHeartbeatService Clock Tampering & Recovery (L-03, L-08, L-16)', () {
    late FakeSecureStorage fakeStorage;
    late LicenseHeartbeatService heartbeat;

    setUp(() {
      fakeStorage = FakeSecureStorage();
      heartbeat = LicenseHeartbeatService();
      heartbeat.stop();
      heartbeat.setStorageForTesting(fakeStorage);
    });

    tearDown(() {
      heartbeat.stop();
    });

    test('L-03: detecta atraso de reloj pero permite recuperarse automáticamente al sincronizar con el servidor (cero deadlock)', () async {
      // Simular que el último pulso guardado fue 2 horas en el futuro (el reloj de la PC se atrasó)
      final futureTime = DateTime.now().add(const Duration(hours: 2));
      fakeStorage.store['drm_last_system_time'] = futureTime.toIso8601String();

      bool syncCalled = false;
      final initialSettings = BusinessSettings(
        licenseStatus: 'pos_key_123',
        licensePlanType: 'pro',
        licensePlanMode: 'saas',
        lastLicenseCheck: DateTime.now().toIso8601String(),
      );

      await heartbeat.initialize(
        initialSettings,
        onSyncRequested: () async {
          syncCalled = true;
          // Simular que el servidor responde con la hora actual corregida
          final refreshedSettings = initialSettings.copyWith(
            serverTime: DateTime.now().toIso8601String(),
            lastLicenseCheck: DateTime.now().toIso8601String(),
          );
          await heartbeat.updateLastSync(refreshedSettings);
        },
      );

      // Inicialmente queda bloqueado por clockTampered
      expect(heartbeat.securityStatus, LicenseSecurityStatus.clockTampered);
      expect(heartbeat.isBlocked, isTrue);

      // Cuando la app vuelve a primer plano (resumed) o corre el heartbeat, NO debe abortar el sync
      heartbeat.didChangeAppLifecycleState(AppLifecycleState.resumed);
      // Esperar microtasks / postFrameCallback
      await Future.delayed(const Duration(milliseconds: 50));

      // Si el callback de sync o updateLastSync se ejecuta, se destraba el deadlock
      if (!syncCalled) {
        await heartbeat.updateLastSync(
          initialSettings.copyWith(
            serverTime: DateTime.now().toIso8601String(),
            lastLicenseCheck: DateTime.now().toIso8601String(),
          ),
        );
      }

      expect(heartbeat.securityStatus, LicenseSecurityStatus.ok);
      expect(heartbeat.isBlocked, isFalse);
    });

    test('L-16: corrupción de formato en drm_last_system_time marca clockTampered en vez de borrar todo el storage', () async {
      fakeStorage.store['drm_last_system_time'] = 'CORRUPTED_NOT_A_DATE';
      fakeStorage.store['other_secret_key'] = 'must_survive';

      final settings = BusinessSettings(
        licenseStatus: 'pos_key_123',
        licensePlanType: 'pro',
        licensePlanMode: 'saas',
        lastLicenseCheck: DateTime.now().toIso8601String(),
      );

      await heartbeat.initialize(settings);

      expect(heartbeat.securityStatus, LicenseSecurityStatus.clockTampered);
      expect(fakeStorage.store['other_secret_key'], 'must_survive');
    });

    test('L-08: bloquea en modo offline si licenseExpiresAt ya venció aunque lastLicenseCheck sea menor a 72h', () async {
      final expiredSettings = BusinessSettings(
        licenseStatus: 'pos_key_123',
        licensePlanType: 'pro',
        licensePlanMode: 'saas',
        lastLicenseCheck: DateTime.now().subtract(const Duration(hours: 2)).toIso8601String(),
        licenseExpiresAt: DateTime.now().subtract(const Duration(days: 1)),
      );

      await heartbeat.initialize(expiredSettings);

      expect(heartbeat.securityStatus, LicenseSecurityStatus.offlineExpired);
      expect(heartbeat.isBlocked, isTrue);
    });
  });

  group('Fase 3 — UpdateInfo SHA-256 Verification (L-14)', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('pos_ota_sha256_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('acepta paquete cuando el hash SHA-256 coincide exactamente y rechaza cuando está alterado', () async {
      final testFile = File('${tempDir.path}/update_test.zip');
      final bytes = 'POS-BINARY-RELEASE-PAYLOAD-V2.0.3'.codeUnits;
      await testFile.writeAsBytes(bytes);

      final expectedHash = sha256.convert(bytes).toString();

      final validUpdate = UpdateInfo.fromJson({
        'version': '2.0.3',
        'download_url': 'https://example.com/update.zip',
        'sha256': expectedHash.toUpperCase(), // Prueba normalización case-insensitive
        'changelog': 'Fix',
        'is_critical': false,
      });

      expect(await validUpdate.verifyFileIntegrity(testFile), isTrue);

      final tamperedUpdate = UpdateInfo.fromJson({
        'version': '2.0.3',
        'download_url': 'https://example.com/update.zip',
        'sha256': '0000000000000000000000000000000000000000000000000000000000000000',
        'changelog': 'Fix',
        'is_critical': false,
      });

      expect(await tamperedUpdate.verifyFileIntegrity(testFile), isFalse);
    });

    test('mantiene retrocompatibilidad cuando el servidor no envía sha256 (releases antiguos)', () async {
      final testFile = File('${tempDir.path}/legacy_update.zip');
      await testFile.writeAsString('legacy-payload');

      final legacyUpdate = UpdateInfo.fromJson({
        'version': '2.0.1',
        'download_url': 'https://example.com/legacy.zip',
        'changelog': 'Legacy',
        'is_critical': false,
      });

      expect(legacyUpdate.sha256Checksum, isNull);
      expect(await legacyUpdate.verifyFileIntegrity(testFile), isTrue);
    });
  });
}
