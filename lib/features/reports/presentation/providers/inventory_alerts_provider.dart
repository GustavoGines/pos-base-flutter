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

  int get totalAlertsCount => _alerts.length;

  /// Retorna el tipo de alerta visual para un producto específico en el POS.
  String? getAlertStatusForProduct(int productId) {
    if (reactiveAlerts.any((a) => (a['product_id'] as num?)?.toInt() == productId)) return 'out_of_stock';
    if (predictiveCriticalAlerts.any((a) => (a['product_id'] as num?)?.toInt() == productId)) return 'predictive_critical';
    return null;
  }

  Future<void> fetchAlerts({int threshold = 3}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await dataSource.getInventoryAlerts(threshold: threshold);
      _alerts = result['alerts'] ?? [];
    } catch (e) {
      _error = e.toString();
      _alerts = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
