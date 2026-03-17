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
      _sales = await dataSource.fetchSales(period: _currentPeriod, shiftId: shiftId, userId: _selectedUserId);
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

  // Totales y estadísticas rápidas
  double get totalVentas =>
      _sales.where((s) => !s.isVoided).fold(0.0, (sum, s) => sum + s.total);
      
  double get totalCash =>
      _sales.where((s) => !s.isVoided && s.paymentMethod == 'cash').fold(0.0, (sum, s) => sum + s.total);
      
  double get totalCards =>
      _sales.where((s) => !s.isVoided && s.paymentMethod == 'card').fold(0.0, (sum, s) => sum + s.total);
      
  double get totalTransfers =>
      _sales.where((s) => !s.isVoided && s.paymentMethod == 'transfer').fold(0.0, (sum, s) => sum + s.total);

  int get countActive => _sales.where((s) => !s.isVoided).length;
  int get countVoided => _sales.where((s) => s.isVoided).length;
}
