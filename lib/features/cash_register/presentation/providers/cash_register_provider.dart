import 'package:flutter/material.dart';
import '../../domain/entities/cash_register_shift.dart';
import '../../domain/usecases/get_all_shifts_usecase.dart';
import '../../domain/usecases/get_current_shift_usecase.dart';
import '../../domain/usecases/open_shift_usecase.dart';
import '../../domain/usecases/close_shift_usecase.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
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

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  CashRegisterProvider({
    required this.getCurrentShiftUseCase,
    this.getAllShiftsUseCase,
    required this.openShiftUseCase,
    required this.closeShiftUseCase,
    this.printerService,  // Opcional
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

  Future<bool> openShift(double initialBalance, int userId) async {
    _clearError();
    _setLoading(true);
    try {
      _currentShift = await openShiftUseCase(initialBalance, userId);
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> closeShift(double countedCash, [BusinessSettings? settings]) async {
    _clearError();
    _setLoading(true);
    try {
      final closedShift = await closeShiftUseCase(countedCash);
      
      // Disparar impresión del Ticket de Cierre Z (silenciosa)
      if (printerService != null && settings != null) {
        printerService!.printZCloseTicket(
          shift: closedShift,
          settings: settings,
        ).catchError((e) => debugPrint('=== Printer Z Error: $e ==='));
      }

      _currentShift = null; // Limpiamos el turno activo
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
