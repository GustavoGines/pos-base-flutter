import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_desktop/features/updater/data/models/update_info.dart';

void main() {
  group('UpdateInfo — Selección Inteligente de Paquete Full vs Liviano (App)', () {
    const fullUrl = 'https://r2.example.com/update_backend_v2.2.0.zip';
    const appUrl = 'https://r2.example.com/update_backend_app_v2.2.0.zip';
    final fullContent = utf8.encode('full-zip-binary-content');
    final appContent = utf8.encode('lightweight-app-zip-binary-content');
    final fullSha = sha256.convert(fullContent).toString();
    final appSha = sha256.convert(appContent).toString();
    final vendorHashA = 'a' * 64;
    final vendorHashB = 'b' * 64;

    test('usa paquete liviano (app_download_url) sólo cuando component==backend y vendor_hash coincide con localVendorHash', () {
      final info = UpdateInfo.fromJson(
        {
          'version': '2.2.0',
          'download_url': fullUrl,
          'sha256': fullSha,
          'app_download_url': appUrl,
          'app_sha256': appSha,
          'vendor_hash': vendorHashA.toUpperCase(),
          'changelog': 'Fast OTA',
          'is_critical': false,
        },
        component: 'backend',
        localVendorHash: vendorHashA,
      );

      expect(info.useLightweightAppPackage, isTrue);
      expect(info.effectiveDownloadUrl, equals(appUrl));
      expect(info.effectiveSha256Checksum, equals(appSha));
    });

    test('usa paquete completo (download_url) cuando localVendorHash es null (clientes v1.8.5 / v2.1.0)', () {
      final info = UpdateInfo.fromJson(
        {
          'version': '2.2.0',
          'download_url': fullUrl,
          'sha256': fullSha,
          'app_download_url': appUrl,
          'app_sha256': appSha,
          'vendor_hash': vendorHashA,
          'changelog': 'Upgrade from v1.8.5',
          'is_critical': false,
        },
        component: 'backend',
        localVendorHash: null,
      );

      expect(info.useLightweightAppPackage, isFalse);
      expect(info.effectiveDownloadUrl, equals(fullUrl));
      expect(info.effectiveSha256Checksum, equals(fullSha));
    });

    test('usa paquete completo (download_url) cuando composer.lock cambió (vendor_hash != localVendorHash)', () {
      final info = UpdateInfo.fromJson(
        {
          'version': '2.2.0',
          'download_url': fullUrl,
          'sha256': fullSha,
          'app_download_url': appUrl,
          'app_sha256': appSha,
          'vendor_hash': vendorHashB,
          'changelog': 'New composer dependencies',
          'is_critical': false,
        },
        component: 'backend',
        localVendorHash: vendorHashA,
      );

      expect(info.useLightweightAppPackage, isFalse);
      expect(info.effectiveDownloadUrl, equals(fullUrl));
      expect(info.effectiveSha256Checksum, equals(fullSha));
    });

    test('verifyFileIntegrity valida contra app_sha256 cuando se selecciona el paquete liviano y contra sha256 cuando se selecciona el completo', () async {
      final tempDir = Directory.systemTemp.createTempSync('update_info_test_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final appFile = File('${tempDir.path}/app.zip')..writeAsBytesSync(appContent);
      final fullFile = File('${tempDir.path}/full.zip')..writeAsBytesSync(fullContent);

      final lightweightInfo = UpdateInfo.fromJson(
        {
          'version': '2.2.0',
          'download_url': fullUrl,
          'sha256': fullSha,
          'app_download_url': appUrl,
          'app_sha256': appSha,
          'vendor_hash': vendorHashA,
          'changelog': 'Fast OTA',
        },
        component: 'backend',
        localVendorHash: vendorHashA,
      );

      expect(await lightweightInfo.verifyFileIntegrity(appFile), isTrue);
      expect(await lightweightInfo.verifyFileIntegrity(fullFile), isFalse);

      final fullInfo = UpdateInfo.fromJson(
        {
          'version': '2.2.0',
          'download_url': fullUrl,
          'sha256': fullSha,
          'app_download_url': appUrl,
          'app_sha256': appSha,
          'vendor_hash': vendorHashB,
          'changelog': 'Full OTA',
        },
        component: 'backend',
        localVendorHash: vendorHashA,
      );

      expect(await fullInfo.verifyFileIntegrity(fullFile), isTrue);
      expect(await fullInfo.verifyFileIntegrity(appFile), isFalse);
    });

    test('parsea can_auto_update, ota_block_reason, is_free_for_lifetime y degrada is_critical si can_auto_update==false', () {
      final blocked = UpdateInfo.fromJson(
        {
          'version': '2.3.0',
          'download_url': null,
          'changelog': 'Novedades v2.3.0',
          'is_critical': true,
          'is_free_for_lifetime': false,
          'can_auto_update': false,
          'ota_block_reason': 'lifetime_upgrade_required',
        },
        component: 'frontend',
      );

      expect(blocked.canAutoUpdate, isFalse);
      expect(blocked.otaBlockReason, 'lifetime_upgrade_required');
      expect(blocked.isFreeForLifetime, isFalse);
      expect(blocked.isCritical, isFalse);
      expect(blocked.effectiveDownloadUrl, isEmpty);

      final hotfix = UpdateInfo.fromJson(
        {
          'version': '2.2.1',
          'download_url': fullUrl,
          'changelog': 'Fix ARCA',
          'is_critical': true,
          'is_free_for_lifetime': true,
          'can_auto_update': true,
          'ota_block_reason': null,
        },
        component: 'frontend',
      );

      expect(hotfix.canAutoUpdate, isTrue);
      expect(hotfix.isFreeForLifetime, isTrue);
      expect(hotfix.isCritical, isTrue);
      expect(hotfix.effectiveDownloadUrl, fullUrl);
    });
  });
}
