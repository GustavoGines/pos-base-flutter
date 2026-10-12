import '../../domain/entities/ecommerce_integration.dart';

class EcommerceIntegrationModel extends EcommerceIntegration {
  const EcommerceIntegrationModel({
    super.id,
    required super.platform,
    required super.name,
    super.storeId,
    super.baseUrl,
    super.clientId,
    super.clientSecret,
    super.accessToken,
    super.refreshToken,
    super.tokenExpiresAt,
    super.webhookSecret,
    super.isActive = true,
    super.syncStockEnabled = true,
    super.syncPriceEnabled = false,
    super.autoPauseOnZeroStock = true,
    super.rateLimitPerMinute = 60,
    super.batchSize = 50,
    super.timeoutSeconds = 30,
    super.settings,
    super.lastHealthCheckAt,
    super.lastHealthStatus = 'unknown',
    super.consecutiveFailures = 0,
    super.circuitBreakerTrippedAt,
    super.hasClientSecret = false,
    super.hasAccessToken = false,
    super.hasRefreshToken = false,
    super.hasWebhookSecret = false,
  });

  factory EcommerceIntegrationModel.fromJson(Map<String, dynamic> json) {
    return EcommerceIntegrationModel(
      id: json['id'] is int ? json['id'] as int : int.tryParse(json['id']?.toString() ?? ''),
      platform: json['platform']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      storeId: json['store_id']?.toString(),
      baseUrl: json['base_url']?.toString(),
      clientId: json['client_id']?.toString(),
      clientSecret: json['client_secret']?.toString(),
      accessToken: json['access_token']?.toString(),
      refreshToken: json['refresh_token']?.toString(),
      tokenExpiresAt: json['token_expires_at']?.toString(),
      webhookSecret: json['webhook_secret']?.toString(),
      isActive: json['is_active'] == true ||
          json['is_active'] == 1 ||
          json['is_active'] == '1',
      syncStockEnabled: json['sync_stock_enabled'] == true ||
          json['sync_stock_enabled'] == 1 ||
          json['sync_stock_enabled'] == '1',
      syncPriceEnabled: json['sync_price_enabled'] == true ||
          json['sync_price_enabled'] == 1 ||
          json['sync_price_enabled'] == '1',
      autoPauseOnZeroStock: json['auto_pause_on_zero_stock'] == true ||
          json['auto_pause_on_zero_stock'] == 1 ||
          json['auto_pause_on_zero_stock'] == '1',
      rateLimitPerMinute: int.tryParse(json['rate_limit_per_minute']?.toString() ?? '') ?? 60,
      batchSize: int.tryParse(json['batch_size']?.toString() ?? '') ?? 50,
      timeoutSeconds: int.tryParse(json['timeout_seconds']?.toString() ?? '') ?? 30,
      settings: json['settings'] is Map ? Map<String, dynamic>.from(json['settings']) : null,
      lastHealthCheckAt: json['last_health_check_at']?.toString(),
      lastHealthStatus: json['last_health_status']?.toString() ?? 'unknown',
      consecutiveFailures: int.tryParse(json['consecutive_failures']?.toString() ?? '') ?? 0,
      circuitBreakerTrippedAt: json['circuit_breaker_tripped_at']?.toString(),
      hasClientSecret: json['has_client_secret'] == true,
      hasAccessToken: json['has_access_token'] == true,
      hasRefreshToken: json['has_refresh_token'] == true,
      hasWebhookSecret: json['has_webhook_secret'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'platform': platform,
      'name': name,
      if (storeId != null) 'store_id': storeId,
      if (baseUrl != null) 'base_url': baseUrl,
      if (clientId != null) 'client_id': clientId,
      if (clientSecret != null) 'client_secret': clientSecret,
      if (accessToken != null) 'access_token': accessToken,
      if (refreshToken != null) 'refresh_token': refreshToken,
      if (tokenExpiresAt != null) 'token_expires_at': tokenExpiresAt,
      if (webhookSecret != null) 'webhook_secret': webhookSecret,
      'is_active': isActive,
      'sync_stock_enabled': syncStockEnabled,
      'sync_price_enabled': syncPriceEnabled,
      'auto_pause_on_zero_stock': autoPauseOnZeroStock,
      'rate_limit_per_minute': rateLimitPerMinute,
      'batch_size': batchSize,
      'timeout_seconds': timeoutSeconds,
      if (settings != null) 'settings': settings,
    };
    return map;
  }

  @override
  EcommerceIntegrationModel copyWith({
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
    return EcommerceIntegrationModel(
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
}
