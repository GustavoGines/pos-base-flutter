import 'package:flutter/material.dart';
import '../../domain/entities/cash_register_shift.dart';
import '../../domain/usecases/get_current_shift_usecase.dart';
import '../../domain/usecases/open_shift_usecase.dart';
import '../../domain/usecases/close_shift_usecase.dart';

class CashRegisterProvider with ChangeNotifier {
  final GetCurrentShiftUseCase getCurrentShiftUseCase;
  final OpenShiftUseCase openShiftUseCase;
  final CloseShiftUseCase closeShiftUseCase;

  CashRegisterShift? _currentShift;
  CashRegisterShift? get currentShift => _currentShift;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  CashRegisterProvider({
    required this.getCurrentShiftUseCase,
    required this.openShiftUseCase,
    required this.closeShiftUseCase,
  });

  Future<void> checkCurrentShift() async {
    _clearError();
    _setLoading(true);
    try {
      _currentShift = await getCurrentShiftUseCase();
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> openShift(double initialBalance) async {
    _clearError();
    _setLoading(true);
    try {
      _currentShift = await openShiftUseCase(initialBalance);
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> closeShift(double closingBalance) async {
    _clearError();
    _setLoading(true);
    try {
      _currentShift = await closeShiftUseCase(closingBalance);
      // Optional: set to null since it's closed, depending on how UI needs it
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      return false;
    } finally {
      _setLoading(false);
    }
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
  
  void _clearError() {
    _errorMessage = null;
  }
}
