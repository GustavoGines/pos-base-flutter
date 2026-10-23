import 'dart:io';
import 'package:crypto/crypto.dart';

class UpdateInfo {
  final String version;
  final String downloadUrl;
  final String? sha256Checksum;
  final String changelog;
  final bool isCritical;
  final String component;

  UpdateInfo({
    required this.version,
    required this.downloadUrl,
    this.sha256Checksum,
    required this.changelog,
    required this.isCritical,
    required this.component,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json, {String component = 'frontend'}) {
    final rawSha = json['sha256']?.toString().trim();
    return UpdateInfo(
      version: json['version'] ?? '',
      downloadUrl: json['download_url'] ?? '',
      sha256Checksum: (rawSha != null && rawSha.isNotEmpty) ? rawSha.toLowerCase() : null,
      changelog: json['changelog'] ?? '',
      isCritical: json['is_critical'] ?? false,
      component: component,
    );
  }

  /// L-14: Verifica el checksum SHA-256 de un archivo descargado si el release provee `sha256`.
  /// Si `sha256Checksum` es null (releases de legado), retorna true por retrocompatibilidad.
  Future<bool> verifyFileIntegrity(File file) async {
    final expected = sha256Checksum?.trim().toLowerCase();
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
