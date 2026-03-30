import 'package:flutter/material.dart';
import '../../domain/entities/cash_register_shift.dart';
import '../../domain/usecases/get_all_shifts_usecase.dart';
import '../../domain/usecases/get_current_shift_usecase.dart';
import '../../domain/usecases/open_shift_usecase.dart';
import '../../domain/usecases/close_shift_usecase.dart';
import '../../domain/usecases/get_registers_usecase.dart';
import '../../domain/entities/cash_register.dart';
import 'package:frontend_desktop/core/utils/receipt_printer_service.dart';

class CashRegisterProvider with ChangeNotifier {
  final GetCurrentShiftUseCase getCurrentShiftUseCase;
  final OpenShiftUseCase openShiftUseCase;
  final CloseShiftUseCase closeShiftUseCase;
  final ReceiptPrinterService? printerService;  // Inyección opcional

  CashRegisterShift? _currentShift;
  CashRegisterShift? get currentShift => _currentShift;

  List<CashRegisterShift> _shiftsHistory = [];
  List<CashRegisterShift> get shiftsHistory => _shiftsHistory;

  final GetAllShiftsUseCase? getAllShiftsUseCase;
  final GetRegistersUseCase? getRegistersUseCase;

  List<CashRegister>? _availableRegisters;
  List<CashRegister>? get availableRegisters => _availableRegisters;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  CashRegisterProvider({
    required this.getCurrentShiftUseCase,
    this.getAllShiftsUseCase,
    required this.openShiftUseCase,
    required this.closeShiftUseCase,
    this.getRegistersUseCase,
    this.printerService,  // Opcional
  });

  Future<void> loadRegisters() async {
    if (getRegistersUseCase == null) return;
    _clearError();
    _setLoading(true);
    try {
      _availableRegisters = await getRegistersUseCase!();
      notifyListeners();
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _setLoading(false);
    }
  }

  Future<void> checkCurrentShift({int? registerId}) async {
    _clearError();
    _setLoading(true);
    try {
      _currentShift = await getCurrentShiftUseCase(registerId: registerId);
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _setLoading(false);
    }
  }

  Future<void> loadAllShifts() async {
    if (getAllShiftsUseCase == null) return;
    _clearError();
    _setLoading(true);
    try {
      _shiftsHistory = await getAllShiftsUseCase!();
      notifyListeners();
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> openShift(double openingBalance, int userId, [int? registerId]) async {
    _clearError();
    _setLoading(true);
    try {
      _currentShift = await openShiftUseCase(openingBalance, userId, registerId);
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<CashRegisterShift?> closeShift(double countedCash, {int? closerUserId}) async {
    _clearError();
    _setLoading(true);
    try {
      if (_currentShift == null) return null;
      final closedShift = await closeShiftUseCase(
        _currentShift!.id,
        countedCash,
        closerUserId: closerUserId,
      );
      _currentShift = null;
      return closedShift;
    } catch (e) {
      _errorMessage = e.toString();
      return null;
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
