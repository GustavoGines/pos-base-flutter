class EcommerceIntegration {
  final int? id;
  final String platform; // 'mercadolibre', 'tiendanube', 'woocommerce', 'ecommerce_platform'
  final String name;
  final String? storeId;
  final String? baseUrl;
  final String? clientId;
  final String? clientSecret;
  final String? accessToken;
  final String? refreshToken;
  final String? tokenExpiresAt;
  final String? webhookSecret;
  final bool isActive;
  final bool syncStockEnabled;
  final bool syncPriceEnabled;
  final bool autoPauseOnZeroStock;
  final int rateLimitPerMinute;
  final int batchSize;
  final int timeoutSeconds;
  final Map<String, dynamic>? settings;
  final String? lastHealthCheckAt;
  final String lastHealthStatus; // 'unknown', 'connected', 'error'
  final int consecutiveFailures;
  final String? circuitBreakerTrippedAt;
  final bool hasClientSecret;
  final bool hasAccessToken;
  final bool hasRefreshToken;
  final bool hasWebhookSecret;

  const EcommerceIntegration({
    this.id,
    required this.platform,
    required this.name,
    this.storeId,
    this.baseUrl,
    this.clientId,
    this.clientSecret,
    this.accessToken,
    this.refreshToken,
    this.tokenExpiresAt,
    this.webhookSecret,
    this.isActive = true,
    this.syncStockEnabled = true,
    this.syncPriceEnabled = false,
    this.autoPauseOnZeroStock = true,
    this.rateLimitPerMinute = 60,
    this.batchSize = 50,
    this.timeoutSeconds = 30,
    this.settings,
    this.lastHealthCheckAt,
    this.lastHealthStatus = 'unknown',
    this.consecutiveFailures = 0,
    this.circuitBreakerTrippedAt,
    this.hasClientSecret = false,
    this.hasAccessToken = false,
    this.hasRefreshToken = false,
    this.hasWebhookSecret = false,
  });

  bool get isHealthy => lastHealthStatus == 'healthy' || lastHealthStatus == 'connected';

  EcommerceIntegration copyWith({
    int? id,
    String? platform,
    String? name,
    String? storeId,
    String? baseUrl,
    String? clientId,
    String? clientSecret,
    String? accessToken,
    String? refreshToken,
    String? tokenExpiresAt,
    String? webhookSecret,
    bool? isActive,
    bool? syncStockEnabled,
    bool? syncPriceEnabled,
    bool? autoPauseOnZeroStock,
    int? rateLimitPerMinute,
    int? batchSize,
    int? timeoutSeconds,
    Map<String, dynamic>? settings,
    String? lastHealthCheckAt,
    String? lastHealthStatus,
    int? consecutiveFailures,
    String? circuitBreakerTrippedAt,
    bool? hasClientSecret,
    bool? hasAccessToken,
    bool? hasRefreshToken,
    bool? hasWebhookSecret,
  }) {
    return EcommerceIntegration(
      id: id ?? this.id,
      platform: platform ?? this.platform,
      name: name ?? this.name,
      storeId: storeId ?? this.storeId,
      baseUrl: baseUrl ?? this.baseUrl,
      clientId: clientId ?? this.clientId,
      clientSecret: clientSecret ?? this.clientSecret,
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      tokenExpiresAt: tokenExpiresAt ?? this.tokenExpiresAt,
      webhookSecret: webhookSecret ?? this.webhookSecret,
      isActive: isActive ?? this.isActive,
      syncStockEnabled: syncStockEnabled ?? this.syncStockEnabled,
      syncPriceEnabled: syncPriceEnabled ?? this.syncPriceEnabled,
      autoPauseOnZeroStock: autoPauseOnZeroStock ?? this.autoPauseOnZeroStock,
      rateLimitPerMinute: rateLimitPerMinute ?? this.rateLimitPerMinute,
      batchSize: batchSize ?? this.batchSize,
      timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
      settings: settings ?? this.settings,
      lastHealthCheckAt: lastHealthCheckAt ?? this.lastHealthCheckAt,
      lastHealthStatus: lastHealthStatus ?? this.lastHealthStatus,
      consecutiveFailures: consecutiveFailures ?? this.consecutiveFailures,
      circuitBreakerTrippedAt: circuitBreakerTrippedAt ?? this.circuitBreakerTrippedAt,
      hasClientSecret: hasClientSecret ?? this.hasClientSecret,
      hasAccessToken: hasAccessToken ?? this.hasAccessToken,
      hasRefreshToken: hasRefreshToken ?? this.hasRefreshToken,
      hasWebhookSecret: hasWebhookSecret ?? this.hasWebhookSecret,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EcommerceIntegration &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          platform == other.platform &&
          name == other.name &&
          storeId == other.storeId &&
          baseUrl == other.baseUrl &&
          clientId == other.clientId &&
          isActive == other.isActive &&
          syncStockEnabled == other.syncStockEnabled &&
          autoPauseOnZeroStock == other.autoPauseOnZeroStock &&
          lastHealthStatus == other.lastHealthStatus;

  @override
  int get hashCode =>
      id.hashCode ^
      platform.hashCode ^
      name.hashCode ^
      storeId.hashCode ^
      baseUrl.hashCode ^
      clientId.hashCode ^
      isActive.hashCode ^
      syncStockEnabled.hashCode ^
      autoPauseOnZeroStock.hashCode ^
      lastHealthStatus.hashCode;
}
