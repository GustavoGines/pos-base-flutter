import 'package:flutter/material.dart';
import '../../domain/entities/cash_register_shift.dart';
import '../../domain/usecases/get_all_shifts_usecase.dart';
import '../../domain/usecases/get_current_shift_usecase.dart';
import '../../domain/usecases/open_shift_usecase.dart';
import '../../domain/usecases/close_shift_usecase.dart';
import '../../domain/usecases/get_registers_usecase.dart';
import '../../domain/entities/cash_register.dart';
import 'package:frontend_desktop/core/utils/receipt_printer_service.dart';
import 'package:frontend_desktop/core/network/api_client.dart' show SessionExpiredException;

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

  /// Verifica el turno activo de forma EXPLÍCITA (con loading visible).
  /// Usar al hacer login o al montar la pantalla de Apertura de Caja por primera vez.
  Future<void> checkCurrentShift({int? registerId}) async {
    _clearError();
    _setLoading(true);
    try {
      final result = await getCurrentShiftUseCase(registerId: registerId);
      _currentShift = result; // Solo actualiza si la llamada tuvo éxito
    } catch (e) {
      // No limpiamos _currentShift: un error de red no debe borrar el estado conocido.
      // Tampoco seteamos _errorMessage para no contaminar la UI en chequeos de fondo.
      debugPrint('=== CashRegisterProvider: checkCurrentShift error: $e ===');
    } finally {
      _setLoading(false);
    }
  }

  /// Verifica el turno activo de forma SILENCIOSA (sin loading ni flicker de UI).
  /// Usar en el polling periódico para no interrumpir la pantalla en curso.
  Future<void> checkCurrentShiftSilently({int? registerId}) async {
    try {
      final result = await getCurrentShiftUseCase(registerId: registerId);
      if (_currentShift?.id != result?.id) {
        // Solo notificar si el estado cambió realmente
        _currentShift = result;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('=== CashRegisterProvider: silent check error (ignored): $e ===');
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
    } on SessionExpiredException catch (e) {
      // Sesión única: otro dispositivo inició sesión con este usuario.
      _errorMessage = 'SESSION_EXPIRED: ${e.message}';
      return false;
    } catch (e) {
      final errorMsg = e.toString();

      // ── AUTO-RECUPERACIÓN (nivel Provider) ─────────────────────────────────
      // Si el backend rechaza porque ya existe un turno activo, significa que
      // checkCurrentShift() no lo detectó a tiempo (race condition de timing).
      // Solución: buscamos el turno activo directamente y devolvemos true
      // (el Consumer en /home verá currentShift != null y mostrará PosScreen).
      // Esta lógica vive en el Provider para evitar el problema del BuildContext
      // stale que ocurre cuando el Consumer se reconstruye durante el await.
      if (errorMsg.contains('Ya existe un turno abierto')) {
        debugPrint('=== CashRegisterProvider: turno ya existe → buscando turno activo ===');
        try {
          final existing = await getCurrentShiftUseCase(registerId: registerId);
          if (existing != null) {
            _currentShift = existing;
            debugPrint('=== CashRegisterProvider: turno activo recuperado (ID:${existing.id}) → redirigiendo ===');
            return true; // Tratamos como éxito: main.dart navegará a /pos
          }
        } catch (_) {
          // Si tampoco podemos obtener el turno, caemos al error normal
        }
      }

      _errorMessage = errorMsg;
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
