import 'package:flutter/material.dart';
import '../../domain/entities/sale_record.dart';
import '../../data/datasources/sales_history_remote_datasource.dart';

class SalesHistoryProvider with ChangeNotifier {
  final SalesHistoryRemoteDataSource dataSource;

  List<SaleRecord> _sales = [];
  List<SaleRecord> get sales => _sales;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  String _currentPeriod = 'shift';
  String get currentPeriod => _currentPeriod;

  int? _selectedUserId;
  int? get selectedUserId => _selectedUserId;

  /// Filtro opcional por código de método de pago (ej: 'efectivo', 'debito').
  /// null = sin filtro (mostrar todos).
  String? _methodFilter;
  String? get methodFilter => _methodFilter;

  void setMethodFilter(String? code) {
    _methodFilter = code;
    notifyListeners();
  }

  void setSelectedUserId(int? id) {
    _selectedUserId = id;
    loadSales();
  }

  SalesHistoryProvider({required this.dataSource});

  Future<void> loadSales({String? period, int? shiftId}) async {
    if (period != null) {
      _currentPeriod = period;
    }
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _sales = await dataSource.fetchSales(
          period: _currentPeriod, shiftId: shiftId, userId: _selectedUserId);
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> voidSale(int saleId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final updated = await dataSource.voidSale(saleId);
      final idx = _sales.indexWhere((s) => s.id == saleId);
      if (idx != -1) {
        _sales[idx] = updated;
      }
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ─── Totales globales (ventas activas) ──────────────────────────────────────

  List<SaleRecord> get _activeSales => _sales.where((s) => !s.isVoided).toList();

  double get totalVentas =>
      _activeSales.fold(0.0, (sum, s) => sum + s.total);

  double get totalSurcharges =>
      _activeSales.fold(0.0, (sum, s) => sum + s.surchargeTotal);

  // ─── Totales por método de pago ─────────────────────────────────────────────
  // Construidos dinámicamente desde los registros de sale_payments.

  /// Mapa de código de método → monto total cobrado en ese método.
  /// Ej: {'efectivo': 1200.00, 'debito': 3500.00, 'transferencia': 800.00}
  Map<String, double> get totalByMethod {
    final Map<String, double> result = {};
    for (final sale in _activeSales) {
      for (final payment in sale.payments) {
        result[payment.methodCode] =
            (result[payment.methodCode] ?? 0.0) + payment.totalAmount;
      }
    }
    return result;
  }

  /// Mapa de código → nombre legible del método (para mostrar en UI).
  Map<String, String> get methodNames {
    final Map<String, String> result = {};
    for (final sale in _sales) {
      for (final payment in sale.payments) {
        result.putIfAbsent(payment.methodCode, () => payment.methodName);
      }
    }
    return result;
  }

  /// Lista de códigos únicos de métodos que aparecen en las ventas activas.
  List<String> get activeMethodCodes => totalByMethod.keys.toList()
    ..sort();

  // ─── Retrocompat. helper getters (evitan romper pantallas que usaban los viejos) ──

  double get totalCash => totalByMethod.entries
      .where((e) => e.key.contains('efectivo') || e.key == 'cash')
      .fold(0.0, (sum, e) => sum + e.value);

  double get totalCards => totalByMethod.entries
      .where((e) =>
          e.key.contains('debito') ||
          e.key.contains('credito') ||
          e.key == 'card')
      .fold(0.0, (sum, e) => sum + e.value);

  double get totalTransfers => totalByMethod.entries
      .where((e) => e.key.contains('transferencia') || e.key == 'transfer')
      .fold(0.0, (sum, e) => sum + e.value);

  double get totalCuentaCorriente =>
      totalByMethod['cuenta_corriente'] ?? 0.0;

  int get countActive => _activeSales.length;
  int get countVoided => _sales.where((s) => s.isVoided).length;
}
