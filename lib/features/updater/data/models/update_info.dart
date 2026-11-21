import 'dart:io';
import 'package:crypto/crypto.dart';

class UpdateInfo {
  final String version;
  final String downloadUrl;
  final String? sha256Checksum;
  final String? appDownloadUrl;
  final String? appSha256Checksum;
  final String? vendorHash;
  final String? localVendorHash;
  final String changelog;
  final bool isCritical;
  final String component;

  UpdateInfo({
    required this.version,
    required this.downloadUrl,
    this.sha256Checksum,
    this.appDownloadUrl,
    this.appSha256Checksum,
    this.vendorHash,
    this.localVendorHash,
    required this.changelog,
    required this.isCritical,
    required this.component,
  });

  factory UpdateInfo.fromJson(
    Map<String, dynamic> json, {
    String component = 'frontend',
    String? localVendorHash,
  }) {
    final rawSha = json['sha256']?.toString().trim();
    final rawAppUrl = json['app_download_url']?.toString().trim();
    final rawAppSha = json['app_sha256']?.toString().trim();
    final rawVendorHash = json['vendor_hash']?.toString().trim();
    final cleanLocalVendorHash = localVendorHash?.trim();

    return UpdateInfo(
      version: json['version'] ?? '',
      downloadUrl: json['download_url'] ?? '',
      sha256Checksum:
          (rawSha != null && rawSha.isNotEmpty) ? rawSha.toLowerCase() : null,
      appDownloadUrl:
          (rawAppUrl != null && rawAppUrl.isNotEmpty) ? rawAppUrl : null,
      appSha256Checksum: (rawAppSha != null && rawAppSha.isNotEmpty)
          ? rawAppSha.toLowerCase()
          : null,
      vendorHash: (rawVendorHash != null && rawVendorHash.isNotEmpty)
          ? rawVendorHash.toLowerCase()
          : null,
      localVendorHash:
          (cleanLocalVendorHash != null && cleanLocalVendorHash.isNotEmpty)
              ? cleanLocalVendorHash.toLowerCase()
              : null,
      changelog: json['changelog'] ?? '',
      isCritical: json['is_critical'] ?? false,
      component: component,
    );
  }

  /// Devuelve `true` únicamente si es una actualización de Backend, el release
  /// provee un paquete liviano (`app_download_url`) y el hash de `composer.lock`
  /// del servidor local coincide exactamente con el del nuevo release.
  /// Si el backend local aún es v1.8.5–v2.1.0 (no devuelve `vendor_hash`) o si
  /// `composer.lock` cambió entre versiones, retorna `false` y descarga el ZIP completo.
  bool get useLightweightAppPackage {
    if (component != 'backend') return false;
    if (appDownloadUrl == null || appDownloadUrl!.isEmpty) return false;
    if (vendorHash == null || vendorHash!.isEmpty) return false;
    if (localVendorHash == null || localVendorHash!.isEmpty) return false;
    return vendorHash == localVendorHash;
  }

  /// URL efectiva a descargar (paquete liviano de ~850 KB o paquete completo con vendor/).
  String get effectiveDownloadUrl =>
      useLightweightAppPackage ? appDownloadUrl! : downloadUrl;

  /// Checksum SHA-256 correspondiente a la URL efectiva seleccionada.
  String? get effectiveSha256Checksum =>
      useLightweightAppPackage ? appSha256Checksum : sha256Checksum;

  /// L-14: Verifica el checksum SHA-256 de un archivo descargado según el paquete seleccionado.
  /// Si el checksum efectivo es null (releases de legado), retorna true por retrocompatibilidad.
  Future<bool> verifyFileIntegrity(File file) async {
    final expected = effectiveSha256Checksum?.trim().toLowerCase();
    if (expected == null || expected.isEmpty) {
      return true;
    }

    if (!await file.exists()) {
      return false;
    }

    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString().toLowerCase() == expected;
  }
}
