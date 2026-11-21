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
  });
}
