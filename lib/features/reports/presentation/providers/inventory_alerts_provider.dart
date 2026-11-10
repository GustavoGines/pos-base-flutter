import 'package:flutter/material.dart';
import '../../data/datasources/inventory_alerts_datasource.dart';

class InventoryAlertsProvider extends ChangeNotifier {
  final InventoryAlertsDataSource dataSource;
  InventoryAlertsProvider({required this.dataSource});

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _error;
  String? get error => _error;

  List<dynamic> _alerts = [];
  List<dynamic> get alerts => _alerts;

  List<dynamic> get reactiveAlerts =>
      _alerts.where((a) => a['alert_type'] == 'out_of_stock' || a['alert_type'] == 'low_stock').toList();

  List<dynamic> get predictiveCriticalAlerts =>
      _alerts.where((a) => a['alert_type'] == 'predictive' && a['alert_level'] == 'critical').toList();

  List<dynamic> get expirationAlerts =>
      _alerts.where((a) => a['alert_type'] == 'expiration').toList();

  int get totalAlertsCount => _alerts.length;

  /// Retorna el tipo de alerta visual para un producto específico en el POS.
  String? getAlertStatusForProduct(int productId) {
    if (reactiveAlerts.any((a) => (a['product_id'] as num?)?.toInt() == productId)) return 'out_of_stock';
    if (expirationAlerts.any((a) => (a['product_id'] as num?)?.toInt() == productId && a['alert_level'] == 'critical')) {
      return 'out_of_stock';
    }
    if (predictiveCriticalAlerts.any((a) => (a['product_id'] as num?)?.toInt() == productId)) return 'predictive_critical';
    return null;
  }

  Future<bool> snoozeExpirationAlert(
    int productId, {
    required String action,
    int? days,
    String? expirationDate,
  }) async {
    try {
      await dataSource.snoozeExpirationAlert(
        productId,
        action: action,
        days: days,
        expirationDate: expirationDate,
      );
      await fetchAlerts();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<void>? _inFlightFetch;
  int? _inFlightThreshold;

  Future<void> fetchAlerts({int threshold = 3}) {
    if (_inFlightFetch != null && _inFlightThreshold == threshold) {
      return _inFlightFetch!;
    }
    _inFlightThreshold = threshold;
    final future = _performFetchAlerts(threshold: threshold);
    _inFlightFetch = future;
    return future.whenComplete(() {
      if (identical(_inFlightFetch, future)) {
        _inFlightFetch = null;
        _inFlightThreshold = null;
      }
    });
  }

  Future<void> _performFetchAlerts({required int threshold}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await dataSource.getInventoryAlerts(threshold: threshold);
      final stockAlerts = (result['alerts'] as List?) ?? [];
      final expAlerts = (result['expiration_alerts'] as List?) ?? [];
      _alerts = [
        ...stockAlerts,
        ...expAlerts.where(
          (e) => !stockAlerts.any(
            (s) => s['alert_type'] == 'expiration' && s['product_id'] == e['product_id'],
          ),
        ),
      ];
    } catch (e) {
      _error = e.toString();
      _alerts = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
