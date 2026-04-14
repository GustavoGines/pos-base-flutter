class UpdateInfo {
  final String version;
  final String downloadUrl;
  final String changelog;
  final bool isCritical;
  final String component;

  UpdateInfo({
    required this.version,
    required this.downloadUrl,
    required this.changelog,
    required this.isCritical,
    required this.component,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json, {String component = 'frontend'}) {
    return UpdateInfo(
      version: json['version'] ?? '',
      downloadUrl: json['download_url'] ?? '',
      changelog: json['changelog'] ?? '',
      isCritical: json['is_critical'] ?? false,
      component: component,
    );
  }
}
