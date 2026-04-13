class UpdateInfo {
  final String version;
  final String downloadUrl;
  final String changelog;
  final bool isCritical;

  UpdateInfo({
    required this.version,
    required this.downloadUrl,
    required this.changelog,
    required this.isCritical,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    return UpdateInfo(
      version: json['version'] ?? '',
      downloadUrl: json['download_url'] ?? '',
      changelog: json['changelog'] ?? '',
      isCritical: json['is_critical'] ?? false,
    );
  }
}
