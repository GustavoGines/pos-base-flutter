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

  List<dynamic> get criticalAlerts =>
      _alerts.where((a) => a['alert_level'] == 'critical').toList();

  List<dynamic> get warningAlerts =>
      _alerts.where((a) => a['alert_level'] == 'warning').toList();

  int get totalAlertsCount => _alerts.length;

  Future<void> fetchAlerts({int threshold = 7}) async {
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
