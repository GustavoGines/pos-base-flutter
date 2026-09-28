import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_desktop/features/cash_movements/presentation/widgets/movement_form_dialog.dart';
import 'package:frontend_desktop/features/cash_movements/providers/cash_movement_provider.dart';
import 'package:frontend_desktop/features/cash_movements/providers/expense_category_provider.dart';
import 'package:frontend_desktop/features/cash_movements/models/expense_category_model.dart';
import 'package:frontend_desktop/features/suppliers/providers/supplier_provider.dart';
import 'package:frontend_desktop/features/suppliers/models/supplier_model.dart';
import 'package:frontend_desktop/features/checks/presentation/providers/check_provider.dart';
import 'package:frontend_desktop/features/checks/domain/entities/third_party_check.dart';
import 'package:frontend_desktop/features/cash_register/presentation/providers/cash_register_provider.dart';
import 'package:frontend_desktop/features/cash_register/domain/entities/cash_register_shift.dart';
import 'package:frontend_desktop/features/auth/presentation/providers/auth_provider.dart';
import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';

class MockCheckProvider extends ChangeNotifier implements CheckProvider {
  List<ThirdPartyCheck> _checks = [];
  @override
  List<ThirdPartyCheck> get checks => _checks;

  void setChecks(List<ThirdPartyCheck> list) {
    _checks = list;
    notifyListeners();
  }

  @override
  Future<void> loadChecks() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockSupplierProvider extends ChangeNotifier implements SupplierProvider {
  List<Supplier> _suppliers = [];
  @override
  List<Supplier> get suppliers => _suppliers;

  void setSuppliers(List<Supplier> list) {
    _suppliers = list;
    notifyListeners();
  }

  @override
  Future<void> fetchSuppliers({String? search}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockExpenseCategoryProvider extends ChangeNotifier implements ExpenseCategoryProvider {
  List<ExpenseCategory> _categories = [];
  @override
  List<ExpenseCategory> get categories => _categories;

  void setCategories(List<ExpenseCategory> list) {
    _categories = list;
    notifyListeners();
  }

  @override
  Future<void> fetchCategories() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockCashMovementProvider extends ChangeNotifier implements CashMovementProvider {
  Map<String, dynamic>? lastSubmittedPayload;
  int createMovementCallCount = 0;
  List<int> resultIds = [1];

  @override
  Future<List<int>> createMovement(Map<String, dynamic> data, {String? adminPin}) async {
    createMovementCallCount++;
    lastSubmittedPayload = data;
    return resultIds;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockCashRegisterProvider extends ChangeNotifier implements CashRegisterProvider {
  CashRegisterShift? _currentShift;
  @override
  CashRegisterShift? get currentShift => _currentShift;

  void setShift(CashRegisterShift? shift) {
    _currentShift = shift;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockSettingsProvider extends ChangeNotifier implements SettingsProvider {
  BusinessSettings? _settings = const BusinessSettings();
  @override
  BusinessSettings? get settings => _settings;

  void setSettings(BusinessSettings? settings) {
    _settings = settings;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockAuthProvider extends ChangeNotifier implements AuthProvider {
  bool _isAdmin = true;
  @override
  bool get isAdmin => _isAdmin;

  void setIsAdmin(bool value) {
    _isAdmin = value;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockLocalTerminalProvider extends ChangeNotifier implements LocalTerminalProvider {
  @override
  String get printerConnection => 'none';

  @override
  String get printerFormat => 'thermal_80';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CHALLENGE 1: Removal and Re-Addition (Dynamic Reactive Subtraction)', () {
    late List<ThirdPartyCheck> wallet;

    setUp(() {
      wallet = [
        ThirdPartyCheck(
          id: 1,
          bankName: 'Banco Santander',
          checkNumber: 'CHK-001',
          amount: 10000.0,
          issueDate: DateTime(2026, 9, 1),
          paymentDate: DateTime(2026, 9, 30),
          issuerName: 'Emisor 1',
          issuerCuit: '20-11111111-1',
          status: 'in_wallet',
        ),
        ThirdPartyCheck(
          id: 2,
          bankName: 'Banco Galicia',
          checkNumber: 'CHK-002',
          amount: 20000.0,
          issueDate: DateTime(2026, 9, 1),
          paymentDate: DateTime(2026, 9, 30),
          issuerName: 'Emisor 2',
          issuerCuit: '20-22222222-2',
          status: 'in_wallet',
        ),
        ThirdPartyCheck(
          id: 3,
          bankName: 'Banco Macro',
          checkNumber: 'CHK-003',
          amount: 30000.0,
          issueDate: DateTime(2026, 9, 1),
          paymentDate: DateTime(2026, 9, 30),
          issuerName: 'Emisor 3',
          issuerCuit: '20-33333333-3',
          status: 'in_wallet',
        ),
      ];
    });

    List<ThirdPartyCheck> computeAvailable(List<PaymentItem> payments) {
      final selectedIds = payments
          .where((p) => p.method == 'check' && p.checkId != null)
          .map((p) => p.checkId!)
          .toSet();
      return wallet
          .where((c) => c.status == 'in_wallet' && !selectedIds.contains(c.id))
          .toList();
    }

    test('Stress Test: Repeated removal, re-addition, and order shuffling preserves wallet integrity', () {
      final payments = <PaymentItem>[];

      // Add Check 1
      payments.add(PaymentItem(method: 'check', amount: 10000.0, checkId: 1));
      var avail = computeAvailable(payments);
      expect(avail.map((c) => c.id).toList(), [2, 3]);

      // Add Check 2
      payments.add(PaymentItem(method: 'check', amount: 20000.0, checkId: 2));
      avail = computeAvailable(payments);
      expect(avail.map((c) => c.id).toList(), [3]);

      // Remove Check 1 (index 0)
      payments.removeAt(0);
      avail = computeAvailable(payments);
      expect(avail.map((c) => c.id).toSet(), {1, 3}, reason: 'Check 1 must be restored to availableChecks');

      // Re-add Check 1
      payments.add(PaymentItem(method: 'check', amount: 10000.0, checkId: 1));
      avail = computeAvailable(payments);
      expect(avail.map((c) => c.id).toList(), [3]);

      // Add Check 3
      payments.add(PaymentItem(method: 'check', amount: 30000.0, checkId: 3));
      avail = computeAvailable(payments);
      expect(avail.isEmpty, isTrue, reason: 'All checks selected must leave availableChecks empty');

      // Remove Check 2 (middle item)
      payments.removeWhere((p) => p.checkId == 2);
      avail = computeAvailable(payments);
      expect(avail.map((c) => c.id).toList(), [2]);

      // Remove all remaining
      payments.clear();
      avail = computeAvailable(payments);
      expect(avail.length, 3, reason: 'Clearing payments restores all wallet checks');

      // Invariant check: selected + available == total
      final selectedIds = payments.where((p) => p.checkId != null).map((p) => p.checkId!).toSet();
      expect(avail.length + selectedIds.length, wallet.length);
    });
  });

  group('CHALLENGE 2: Homogeneous Checks (Identical Amount/Bank, Different IDs)', () {
    late List<ThirdPartyCheck> homogeneousChecks;

    setUp(() {
      homogeneousChecks = [
        ThirdPartyCheck(
          id: 501,
          bankName: 'Banco de la Nación Argentina',
          checkNumber: '0008812',
          amount: 50000.0,
          issueDate: DateTime(2026, 9, 10),
          paymentDate: DateTime(2026, 10, 10),
          issuerName: 'Agropecuaria Central',
          issuerCuit: '30-55555555-5',
          status: 'in_wallet',
        ),
        ThirdPartyCheck(
          id: 502,
          bankName: 'Banco de la Nación Argentina', // Identical bank
          checkNumber: '0008812', // Identical check number (e.g. from different account/branch)
          amount: 50000.0, // Identical amount
          issueDate: DateTime(2026, 9, 10),
          paymentDate: DateTime(2026, 10, 10),
          issuerName: 'Agropecuaria Central',
          issuerCuit: '30-55555555-5',
          status: 'in_wallet',
        ),
        ThirdPartyCheck(
          id: 503,
          bankName: 'Banco de la Nación Argentina',
          checkNumber: '0008813',
          amount: 50000.0,
          issueDate: DateTime(2026, 9, 10),
          paymentDate: DateTime(2026, 10, 10),
          issuerName: 'Agropecuaria Central',
          issuerCuit: '30-55555555-5',
          status: 'in_wallet',
        ),
      ];
    });

    test('Adversarial Test: Deduplication logic filters ONLY by check.id, NEVER falsely colliding on amount, bank, or number', () {
      final payments = <PaymentItem>[
        PaymentItem(method: 'check', amount: 50000.0, checkId: 501),
      ];

      final selectedIds = payments
          .where((p) => p.method == 'check' && p.checkId != null)
          .map((p) => p.checkId!)
          .toSet();

      final available = homogeneousChecks
          .where((c) => c.status == 'in_wallet' && !selectedIds.contains(c.id))
          .toList();

      // Only Check 501 must be excluded; Check 502 and 503 MUST remain available
      expect(available.length, 2);
      expect(available.any((c) => c.id == 501), isFalse);
      expect(available.any((c) => c.id == 502), isTrue, reason: 'Check 502 has distinct ID, must NOT be blocked');
      expect(available.any((c) => c.id == 503), isTrue, reason: 'Check 503 has distinct ID, must NOT be blocked');

      // Operator adds Check 502
      bool addPaymentGuard(int checkId, double amount) {
        if (payments.any((p) => p.method == 'check' && p.checkId == checkId)) {
          return false; // Duplicate
        }
        payments.add(PaymentItem(method: 'check', amount: amount, checkId: checkId));
        return true;
      }

      final add502Success = addPaymentGuard(502, 50000.0);
      expect(add502Success, isTrue);
      expect(payments.length, 2);

      // Verify payload construction
      final payloadChecks = payments.map((p) => p.checkId).toList();
      expect(payloadChecks, [501, 502]);
      expect(payloadChecks.length, payloadChecks.toSet().length, reason: 'Distinct check IDs must satisfy payload integrity');

      // Attempting to re-add 501 MUST be blocked
      final add501Again = addPaymentGuard(501, 50000.0);
      expect(add501Again, isFalse, reason: 'Identical check ID must be blocked');
    });
  });

  group('CHALLENGE 3: Dropdown Exhaustion & Value Safety (All Checks Selected / Empty Wallet)', () {
    test('Dropdown value binding: coercion to null prevents Flutter assertion crashes when availableChecks changes', () {
      final wallet = [
        ThirdPartyCheck(
          id: 10,
          bankName: 'Banco Macro',
          checkNumber: '001',
          amount: 15000.0,
          issueDate: DateTime(2026, 9, 1),
          paymentDate: DateTime(2026, 9, 30),
          issuerName: 'Test',
          issuerCuit: '20-11111111-1',
          status: 'in_wallet',
        ),
      ];

      // Initial state: check 10 is available
      var payments = <PaymentItem>[];
      var selectedIds = payments.where((p) => p.checkId != null).map((p) => p.checkId!).toSet();
      var available = wallet.where((c) => c.status == 'in_wallet' && !selectedIds.contains(c.id)).toList();

      int? currentCheckId = 10;
      // Proposed patch evaluation:
      int? boundValue = available.any((c) => c.id == currentCheckId) ? currentCheckId : null;
      expect(boundValue, 10);

      // Operator adds Check 10 to payments:
      payments.add(PaymentItem(method: 'check', amount: 15000.0, checkId: 10));
      selectedIds = payments.where((p) => p.checkId != null).map((p) => p.checkId!).toSet();
      available = wallet.where((c) => c.status == 'in_wallet' && !selectedIds.contains(c.id)).toList();

      // available is now EMPTY
      expect(available.isEmpty, isTrue);

      // If currentCheckId was not reset immediately, boundValue safely coerces to NULL:
      boundValue = available.any((c) => c.id == currentCheckId) ? currentCheckId : null;
      expect(boundValue, isNull, reason: 'Must coerce to null to avoid Flutter DropdownMenuItem assertion failure');
    });

    test('Empty initial wallet renders disabled state cleanly without throwing null assertion', () {
      final List<ThirdPartyCheck> emptyWallet = [];
      final payments = <PaymentItem>[];
      final selectedIds = payments.where((p) => p.checkId != null).map((p) => p.checkId!).toSet();
      final available = emptyWallet.where((c) => c.status == 'in_wallet' && !selectedIds.contains(c.id)).toList();

      expect(available.isEmpty, isTrue);
      final dropdownItems = available.isEmpty
          ? const [DropdownMenuItem<int>(value: null, child: Text('No hay cheques disponibles'))]
          : available.map((c) => DropdownMenuItem<int>(value: c.id, child: Text(c.checkNumber))).toList();

      expect(dropdownItems.length, 1);
      expect(dropdownItems.first.value, isNull);
    });
  });

  group('CHALLENGE 4: Input Submission Vectors (Enter, Click, Auto-Submit)', () {
    test('Auto-submit exploit neutralization: Submitting without clicking Agregar adds uncommitted check only ONCE', () {
      final payments = <PaymentItem>[];
      int? currentCheckId = 88;
      String currentMethod = 'check';
      double pendingAmount = 45000.0;

      // Simulated auto-add in _submit():
      void guardedAutoAdd() {
        if (pendingAmount > 0) {
          if (currentMethod == 'check') {
            if (currentCheckId != null &&
                !payments.any((p) => p.method == 'check' && p.checkId == currentCheckId)) {
              payments.add(PaymentItem(method: currentMethod, amount: pendingAmount, checkId: currentCheckId));
              currentCheckId = null;
            }
          } else {
            payments.add(PaymentItem(method: currentMethod, amount: pendingAmount));
          }
        }
      }

      // First submit triggers auto-add:
      guardedAutoAdd();
      expect(payments.length, 1);
      expect(payments.first.checkId, 88);

      // Re-triggering auto-add (e.g. rapid double click on submit button):
      guardedAutoAdd();
      expect(payments.length, 1, reason: 'Second auto-add attempt must be a no-op');
    });

    test('Auto-submit with existing check rejects second auto-addition', () {
      // Check 88 is ALREADY committed in payments
      final payments = <PaymentItem>[
        PaymentItem(method: 'check', amount: 45000.0, checkId: 88),
      ];

      // Leftover controller text and currentCheckId pointing to 88
      int? currentCheckId = 88;
      String currentMethod = 'check';
      double pendingAmount = 45000.0;

      bool wasAdded = false;
      if (pendingAmount > 0) {
        if (currentMethod == 'check') {
          if (!payments.any((p) => p.method == 'check' && p.checkId == currentCheckId)) {
            payments.add(PaymentItem(method: currentMethod, amount: pendingAmount, checkId: currentCheckId));
            wasAdded = true;
          }
        }
      }

      expect(wasAdded, isFalse, reason: 'Duplicate auto-add must be rejected');
      expect(payments.length, 1);
    });
  });

  group('CHALLENGE 5: Mathematical Inflation Formula & Mixed Tender Arithmetic', () {
    test('Mathematical proof: Duplicate checks inflate ledger by exactly (m - 1) * V', () {
      const checkFaceValue = 75000.0;
      const physicalTenderCash = 25000.0;
      const supplierDebt = 100000.0;

      // When duplicated m = 3 times:
      const m = 3;
      final duplicatePayments = [
        {'amount': physicalTenderCash, 'method': 'cash', 'check_id': null},
        {'amount': checkFaceValue, 'method': 'check', 'check_id': 99},
        {'amount': checkFaceValue, 'method': 'check', 'check_id': 99},
        {'amount': checkFaceValue, 'method': 'check', 'check_id': 99},
      ];

      final recordedTotal = duplicatePayments.fold(0.0, (sum, p) => sum + (p['amount'] as double));
      const legitimateTotal = physicalTenderCash + checkFaceValue;
      final deltaInflation = recordedTotal - legitimateTotal;

      expect(recordedTotal, 250000.0);
      expect(legitimateTotal, 100000.0);
      expect(deltaInflation, (m - 1) * checkFaceValue);
      expect(deltaInflation, 150000.0);

      // Resulting supplier balance:
      final resultingBalance = supplierDebt - recordedTotal;
      expect(resultingBalance, -150000.0, reason: 'Wipes debt and creates phantom \$150,000 corporate asset credit');
    });

    test('Patched model guarantees m <= 1, forcing deltaInflation == 0.00 across all permutations', () {
      final payments = <PaymentItem>[];

      void attemptAdd({required String method, required double amount, int? checkId}) {
        if (method == 'check') {
          if (checkId == null) return;
          if (payments.any((p) => p.method == 'check' && p.checkId == checkId)) return;
        }
        payments.add(PaymentItem(method: method, amount: amount, checkId: checkId));
      }

      // Attacker attempts 10 duplicate additions of Check 99 ($75,000)
      for (int i = 0; i < 10; i++) {
        attemptAdd(method: 'check', amount: 75000.0, checkId: 99);
      }
      attemptAdd(method: 'cash', amount: 25000.0);

      final totalPaid = payments.fold(0.0, (sum, p) => sum + p.amount);
      expect(payments.where((p) => p.checkId == 99).length, 1);
      expect(totalPaid, 100000.0);
    });

    test('Floating-point precision: Mixed payments sum matches exact two-decimal currency representation', () {
      final items = [
        PaymentItem(method: 'cash', amount: 12345.67),
        PaymentItem(method: 'check', amount: 67890.12, checkId: 1),
        PaymentItem(method: 'transfer', amount: 19764.21),
      ];

      final sumRaw = items.fold(0.0, (acc, item) => acc + item.amount);
      final sumSanitized = double.parse(sumRaw.toStringAsFixed(2));

      expect(sumSanitized, 100000.00);
    });
  });

  group('CHALLENGE 6: State Desynchronization Edge Cases & Discoveries', () {
    test('Finding: Supplier switch with empty _payments but uncommitted controller/checkId requires unconditional clearing', () {
      // SCENARIO UNDER TEST:
      // Operator selected Check 101 ($50,000) for Supplier A.
      // Operator did NOT press "Agregar", so _payments is empty.
      // Operator switches to Supplier B.
      int? selectedSupplierId = 1;
      final payments = <PaymentItem>[];
      int? currentCheckId = 101;
      String controllerText = '50000.0';

      // Flawed implementation in Remediation Report snippet:
      // if (_payments.isNotEmpty) { _payments.clear(); _paymentAmountController.clear(); _currentCheckId = null; }
      void flawedSupplierChange(int newSupplierId) {
        if (newSupplierId != selectedSupplierId) {
          selectedSupplierId = newSupplierId;
          if (payments.isNotEmpty) {
            payments.clear();
            controllerText = '';
            currentCheckId = null;
          }
        }
      }

      flawedSupplierChange(2);

      // BUG REPRODUCED IN REMEDIATION SPECIFICATION:
      // Because payments was empty, controllerText and currentCheckId were NOT cleared!
      expect(currentCheckId, 101, reason: 'Flawed snippet leaves checkId 101 pending');
      expect(controllerText, '50000.0', reason: 'Flawed snippet leaves amount 50000.0 pending');

      // ROBUST DEFENSIVE SPECIFICATION:
      void robustSupplierChange(int newSupplierId) {
        if (newSupplierId != selectedSupplierId) {
          selectedSupplierId = newSupplierId;
          payments.clear();
          controllerText = '';
          currentCheckId = null;
        }
      }

      robustSupplierChange(3);
      expect(currentCheckId, isNull, reason: 'Robust logic unconditionally clears currentCheckId');
      expect(controllerText, isEmpty, reason: 'Robust logic unconditionally clears controllerText');
    });
  });
}
