import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_desktop/features/cash_movements/presentation/widgets/movement_form_dialog.dart';
import 'package:frontend_desktop/features/checks/domain/entities/third_party_check.dart';
import 'package:frontend_desktop/features/suppliers/models/supplier_model.dart';

void main() {
  group('R2 & R5: Duplicate Check Bug Reproduction', () {
    late List<ThirdPartyCheck> walletChecks;

    setUp(() {
      walletChecks = [
        ThirdPartyCheck(
          id: 101,
          bankName: 'Banco Santander',
          checkNumber: 'CHK-00101',
          amount: 50000.0,
          issueDate: DateTime(2026, 9, 1),
          paymentDate: DateTime(2026, 9, 30),
          issuerName: 'Cliente Mayorista SRL',
          issuerCuit: '30-11223344-9',
          status: 'in_wallet',
        ),
        ThirdPartyCheck(
          id: 102,
          bankName: 'Banco Galicia',
          checkNumber: 'CHK-00102',
          amount: 25000.0,
          issueDate: DateTime(2026, 9, 5),
          paymentDate: DateTime(2026, 10, 5),
          issuerName: 'Comercial del Sur SA',
          issuerCuit: '30-99887766-1',
          status: 'in_wallet',
        ),
      ];
    });

    test('Reproduction: Absence of filtering allows selecting the same check twice in availableChecks', () {
      // In movement_form_dialog.dart lines 438-440:
      // final availableChecks = checkProv.checks.where((c) => c.status == 'in_wallet').toList();
      //
      // Emulate adding Check #101 to _payments:
      final payments = <PaymentItem>[
        PaymentItem(
          method: 'check',
          amount: 50000.0,
          checkId: 101,
          checkObj: walletChecks.firstWhere((c) => c.id == 101),
        ),
      ];

      // Unpatched availableChecks computation (does NOT check _payments):
      final unpatchedAvailableChecks = walletChecks.where((c) => c.status == 'in_wallet').toList();

      // Bug confirmed: Check #101 is in payments but STILL present in availableChecks
      expect(payments.length, 1);
      expect(payments.first.checkId, 101);
      expect(unpatchedAvailableChecks.any((c) => c.id == 101), isTrue);
      expect(unpatchedAvailableChecks.length, 2);
    });

    test('Reproduction: Adding duplicate check items inflates _totalAmount beyond legitimate value', () {
      // In movement_form_dialog.dart lines 144-148 & 150-179:
      // _addPayment() appends without checkId uniqueness verification.
      final payments = <PaymentItem>[];

      // Operator adds Check #101 ($50,000)
      payments.add(PaymentItem(
        method: 'check',
        amount: 50000.0,
        checkId: 101,
        checkObj: walletChecks.firstWhere((c) => c.id == 101),
      ));

      // Operator adds Check #101 ($50,000) AGAIN due to lack of guard
      payments.add(PaymentItem(
        method: 'check',
        amount: 50000.0,
        checkId: 101,
        checkObj: walletChecks.firstWhere((c) => c.id == 101),
      ));

      // Calculation of _totalAmount:
      final listSum = payments.fold(0.0, (sum, item) => sum + item.amount);
      const pendingSum = 0.0;
      final totalAmount = listSum + pendingSum;

      // Bug confirmed: total is $100,000 instead of physical $50,000
      expect(payments.length, 2);
      expect(totalAmount, 100000.0);
      expect(totalAmount, isNot(equals(50000.0)));
    });

    test('Reproduction: Submitting duplicate check items generates duplicate check_id in payload', () {
      final payments = <PaymentItem>[
        PaymentItem(method: 'check', amount: 50000.0, checkId: 101),
        PaymentItem(method: 'check', amount: 50000.0, checkId: 101), // Duplicate
      ];

      // Emulate lines 257-263 in movement_form_dialog.dart:
      final paymentsPayload = payments
          .map((p) => {
                'amount': p.amount,
                'payment_method': p.method,
                'check_id': p.checkId,
              })
          .toList();

      final checkIdsInPayload = paymentsPayload
          .where((p) => p['payment_method'] == 'check' && p['check_id'] != null)
          .map((p) => p['check_id'] as int)
          .toList();

      // Bug confirmed: Payload contains duplicate check_id 101
      expect(checkIdsInPayload, [101, 101]);
      expect(checkIdsInPayload.length, isNot(equals(checkIdsInPayload.toSet().length)));
    });

    test('Reproduction: Double deduction model decrements supplier balance twice for single check', () {
      double supplierBalance = 80000.0; // Current debt to supplier
      const checkFaceValue = 50000.0;

      // Backend simulates CashMovementController.php:
      // foreach ($validated['payments'] as $payment) { $totalAmountPaid += $payment['amount']; }
      // $supplier->decrement('balance', $totalAmountPaid);
      final duplicatePayments = [
        {'amount': checkFaceValue, 'payment_method': 'check', 'check_id': 101},
        {'amount': checkFaceValue, 'payment_method': 'check', 'check_id': 101},
      ];

      final totalPaid = duplicatePayments.fold(0.0, (sum, p) => sum + (p['amount'] as double));
      supplierBalance -= totalPaid;

      // Bug confirmed: Supplier balance becomes -20,000 (erroneous credit/saldo a favor)
      // When it should legitimately be 80,000 - 50,000 = +30,000
      expect(totalPaid, 100000.0);
      expect(supplierBalance, -20000.0);
    });
  });

  group('R2 & R5: Proposed Defensive Fixes Verification', () {
    late List<ThirdPartyCheck> walletChecks;

    setUp(() {
      walletChecks = [
        ThirdPartyCheck(
          id: 101,
          bankName: 'Banco Santander',
          checkNumber: 'CHK-00101',
          amount: 50000.0,
          issueDate: DateTime(2026, 9, 1),
          paymentDate: DateTime(2026, 9, 30),
          issuerName: 'Cliente Mayorista SRL',
          issuerCuit: '30-11223344-9',
          status: 'in_wallet',
        ),
        ThirdPartyCheck(
          id: 102,
          bankName: 'Banco Galicia',
          checkNumber: 'CHK-00102',
          amount: 25000.0,
          issueDate: DateTime(2026, 9, 5),
          paymentDate: DateTime(2026, 10, 5),
          issuerName: 'Comercial del Sur SA',
          issuerCuit: '30-99887766-1',
          status: 'in_wallet',
        ),
      ];
    });

    test('Fix Verification: Subtracting selected checks from available checks prevents duplicate selection', () {
      final payments = <PaymentItem>[
        PaymentItem(
          method: 'check',
          amount: 50000.0,
          checkId: 101,
          checkObj: walletChecks.firstWhere((c) => c.id == 101),
        ),
      ];

      // Proposed defensive reactive filtering:
      final selectedCheckIds = payments
          .where((p) => p.method == 'check' && p.checkId != null)
          .map((p) => p.checkId!)
          .toSet();

      final availableChecks = walletChecks
          .where((c) => c.status == 'in_wallet' && !selectedCheckIds.contains(c.id))
          .toList();

      // Check #101 is excluded; only Check #102 is available
      expect(availableChecks.length, 1);
      expect(availableChecks.first.id, 102);
      expect(availableChecks.any((c) => c.id == 101), isFalse);
    });

    test('Fix Verification: Selecting all wallet checks leaves availableChecks empty', () {
      final payments = <PaymentItem>[
        PaymentItem(method: 'check', amount: 50000.0, checkId: 101),
        PaymentItem(method: 'check', amount: 25000.0, checkId: 102),
      ];

      final selectedCheckIds = payments
          .where((p) => p.method == 'check' && p.checkId != null)
          .map((p) => p.checkId!)
          .toSet();

      final availableChecks = walletChecks
          .where((c) => c.status == 'in_wallet' && !selectedCheckIds.contains(c.id))
          .toList();

      expect(availableChecks.isEmpty, isTrue);
    });

    test('Fix Verification: Dynamic recovery restores check to availableChecks when payment item is removed', () {
      final payments = <PaymentItem>[
        PaymentItem(method: 'check', amount: 50000.0, checkId: 101),
        PaymentItem(method: 'check', amount: 25000.0, checkId: 102),
      ];

      // Remove Check #101 (index 0)
      payments.removeAt(0);

      final selectedCheckIds = payments
          .where((p) => p.method == 'check' && p.checkId != null)
          .map((p) => p.checkId!)
          .toSet();

      final availableChecks = walletChecks
          .where((c) => c.status == 'in_wallet' && !selectedCheckIds.contains(c.id))
          .toList();

      expect(availableChecks.length, 1);
      expect(availableChecks.first.id, 101);
    });

    test('Fix Verification: Defensive guard if (_payments.any((p) => p.checkId == checkId)) rejects duplicate check addition', () {
      final payments = <PaymentItem>[
        PaymentItem(method: 'check', amount: 50000.0, checkId: 101),
      ];

      bool addPaymentDefensive({
        required String method,
        required double amount,
        required int? checkId,
      }) {
        if (amount <= 0) return false;
        if (method == 'check') {
          if (checkId == null) return false;
          // DEFENSIVE GUARD
          if (payments.any((p) => p.method == 'check' && p.checkId == checkId)) {
            return false; // Rejected
          }
        }
        payments.add(PaymentItem(method: method, amount: amount, checkId: checkId));
        return true;
      }

      // Attempt to add duplicate Check #101
      final addedDuplicate = addPaymentDefensive(method: 'check', amount: 50000.0, checkId: 101);
      expect(addedDuplicate, isFalse);
      expect(payments.length, 1);

      // Attempt to add legitimate Check #102
      final addedLegitimate = addPaymentDefensive(method: 'check', amount: 25000.0, checkId: 102);
      expect(addedLegitimate, isTrue);
      expect(payments.length, 2);
    });

    test('Fix Verification: Pre-submission barrier detects and blocks duplicate check IDs in payload', () {
      final payments = <PaymentItem>[
        PaymentItem(method: 'check', amount: 50000.0, checkId: 101),
        PaymentItem(method: 'check', amount: 50000.0, checkId: 101),
      ];

      bool validateSubmissionIntegrity(List<PaymentItem> items) {
        if (items.isEmpty) return false;
        final checkIds = items
            .where((p) => p.method == 'check' && p.checkId != null)
            .map((p) => p.checkId!)
            .toList();
        if (checkIds.length != checkIds.toSet().length) {
          return false; // Submission blocked
        }
        return true;
      }

      expect(validateSubmissionIntegrity(payments), isFalse);

      // Now with unique checks
      final validPayments = <PaymentItem>[
        PaymentItem(method: 'check', amount: 50000.0, checkId: 101),
        PaymentItem(method: 'check', amount: 25000.0, checkId: 102),
        PaymentItem(method: 'cash', amount: 5000.0),
      ];
      expect(validateSubmissionIntegrity(validPayments), isTrue);
    });
  });

  group('R3 & R5: Check Face-Value Decoupling Reproduction & Fix Verification', () {
    late ThirdPartyCheck check101;

    setUp(() {
      check101 = ThirdPartyCheck(
        id: 101,
        bankName: 'Banco Macro',
        checkNumber: 'CHK-999',
        amount: 35000.0, // Face value is $35,000
        issueDate: DateTime(2026, 9, 1),
        paymentDate: DateTime(2026, 9, 30),
        issuerName: 'Cliente Test',
        issuerCuit: '20-12345678-9',
        status: 'in_wallet',
      );
    });

    test('Reproduction: "Pagar Restante" logic overwrites check nominal values', () {
      const supplierDebt = 10000.0; // Debt is only $10,000
      final payments = <PaymentItem>[];

      // User selects check: controller sets to check.amount (35000.0)
      String controllerText = check101.amount.toString();
      final currentCheckId = check101.id;
      final currentMethod = 'check';

      // User clicks "Pagar Restante" button:
      // Lines 734-738 in movement_form_dialog.dart:
      final listSum = payments.fold(0.0, (sum, item) => sum + item.amount);
      final remaining = supplierDebt - listSum;
      controllerText = (remaining % 1 == 0 ? remaining.toInt().toString() : remaining.toStringAsFixed(2));

      // Bug occurs: controller text is now "10000", decoupling from check face value 35000
      expect(controllerText, '10000');

      // Operator clicks "Agregar": _addPayment() reads double.tryParse(_paymentAmountController.text)
      final parsedAmount = double.tryParse(controllerText) ?? 0;
      payments.add(PaymentItem(
        method: currentMethod,
        amount: parsedAmount, // $10,000 instead of $35,000!
        checkId: currentCheckId,
        checkObj: check101,
      ));

      expect(payments.first.amount, 10000.0);
      expect(payments.first.amount, isNot(equals(check101.amount)));
      expect(check101.amount - payments.first.amount, 25000.0); // $25,000 unaccounted loss
    });

    test('Fix Verification: Locking check amount to checkObj.amount prevents face value tampering', () {
      const manipulatedControllerText = '10000'; // Altered by Pagar Restante or user

      // Proposed defensive logic in _addPayment():
      PaymentItem createGuardedPayment({
        required String method,
        required double parsedControllerAmount,
        required int? checkId,
        required ThirdPartyCheck? checkObj,
      }) {
        final finalAmount = (method == 'check' && checkObj != null)
            ? checkObj.amount // IMMUTABLE: strictly locked to face value
            : parsedControllerAmount;

        return PaymentItem(
          method: method,
          amount: finalAmount,
          checkId: checkId,
          checkObj: checkObj,
        );
      }

      final item = createGuardedPayment(
        method: 'check',
        parsedControllerAmount: double.parse(manipulatedControllerText),
        checkId: check101.id,
        checkObj: check101,
      );

      // Fix confirmed: check nominal value is strictly maintained at 35,000.0
      expect(item.amount, 35000.0);
      expect(item.amount, equals(check101.amount));
    });

    test('Fix Verification: Guarding "Pagar Restante" action when method is check', () {
      bool canExecutePagarRestante(String currentMethod) {
        if (currentMethod == 'check') {
          return false; // Prohibited for checks
        }
        return true;
      }

      expect(canExecutePagarRestante('check'), isFalse);
      expect(canExecutePagarRestante('cash'), isTrue);
      expect(canExecutePagarRestante('transfer'), isTrue);
    });
  });

  group('R3 & R5: Comma-Decimal Parsing Failure Reproduction & Fix Verification', () {
    test('Reproduction: double.tryParse("150,50") returns null without comma normalization', () {
      const inputWithComma = '150,50';
      final unnormalizedParsed = double.tryParse(inputWithComma);

      // Bug confirmed: Dart's standard double.tryParse fails on Argentine comma notation
      expect(unnormalizedParsed, isNull);
      expect(unnormalizedParsed ?? 0, 0.0);
    });

    test('Reproduction: Silent input discard in _submit() drops unnormalized pending amount when prior payments exist', () {
      final payments = <PaymentItem>[
        PaymentItem(method: 'cash', amount: 500.0), // Pre-existing payment
      ];

      const pendingInput = '150,50'; // User entered amount with comma

      // In movement_form_dialog.dart lines 191-195:
      final pendingAmount = double.tryParse(pendingInput) ?? 0;
      if (pendingAmount > 0) {
        // Will NOT be called because pendingAmount is 0!
        payments.add(PaymentItem(method: 'cash', amount: pendingAmount));
      }

      // Bug confirmed: payments.length is still 1, pending 150,50 was silently discarded
      expect(payments.length, 1);
      expect(payments.first.amount, 500.0);
    });

    test('Fix Verification: Normalized parsing correctly parses Argentine format numbers', () {
      double? parseNormalizedAmount(String text) {
        final clean = text.trim().replaceAll(',', '.');
        return double.tryParse(clean);
      }

      expect(parseNormalizedAmount('150,50'), 150.50);
      expect(parseNormalizedAmount('10500,75'), 10500.75);
      expect(parseNormalizedAmount('0,99'), 0.99);
      expect(parseNormalizedAmount('  250,5  '), 250.5);
      expect(parseNormalizedAmount('150.50'), 150.50); // Period remains valid
      expect(parseNormalizedAmount('1000'), 1000.0);
      expect(parseNormalizedAmount('abc'), isNull);
      expect(parseNormalizedAmount(''), isNull);
    });
  });

  group('R3 & R5: State Desynchronization on Supplier Change Reproduction & Fix Verification', () {
    late Supplier supplierA;
    late Supplier supplierB;

    setUp(() {
      supplierA = Supplier(
        id: 1,
        name: 'Proveedor Mayorista A',
        cuit: '30-11111111-1',
        balance: 80000.0,
        isActive: true,
      );
      supplierB = Supplier(
        id: 2,
        name: 'Proveedor Menor B',
        cuit: '30-22222222-2',
        balance: 5000.0,
        isActive: true,
      );
    });

    test('Reproduction: Payments are preserved across supplier changes in unpatched dialog', () {
      int? selectedSupplierId = supplierA.id;
      final payments = <PaymentItem>[];

      // Add payment intended for Supplier A ($80,000)
      payments.add(PaymentItem(method: 'cash', amount: 80000.0));

      // User changes dropdown to Supplier B:
      // Line 649 in movement_form_dialog.dart:
      // onChanged: (val) => setState(() => _selectedSupplierId = val),
      selectedSupplierId = supplierB.id;

      // Bug confirmed: payments still has the $80,000 intended for Supplier A
      expect(selectedSupplierId, supplierB.id);
      expect(payments.length, 1);
      expect(payments.first.amount, 80000.0);

      // If submitted, Supplier B ($5,000 debt) receives $80,000 payment:
      final resultingBalanceB = supplierB.balance - payments.first.amount;
      expect(resultingBalanceB, -75000.0); // Severe ledger distortion
    });

    test('Fix Verification: Resetting payments on supplier switch isolates supplier ledger entries', () {
      int? selectedSupplierId = supplierA.id;
      final payments = <PaymentItem>[
        PaymentItem(method: 'cash', amount: 80000.0),
      ];

      // Proposed defensive supplier switch handler:
      void onSupplierChanged(int? newSupplierId) {
        if (selectedSupplierId != newSupplierId && payments.isNotEmpty) {
          payments.clear(); // Reset payments to prevent cross-supplier pollution
        }
        selectedSupplierId = newSupplierId;
      }

      onSupplierChanged(supplierB.id);

      // Fix confirmed: payments list is wiped clean when switching supplier
      expect(selectedSupplierId, supplierB.id);
      expect(payments.isEmpty, isTrue);
    });
  });

  group('R3 & R5: Movement Type Switch Desynchronization (HTTP 422 Bug)', () {
    test('Reproduction: Switching type to "expense" retains supplier_id triggering backend 422', () {
      String currentType = 'supplier_payment';
      int? selectedSupplierId = 5;

      // Unpatched type change handler lines 478-485 in movement_form_dialog.dart:
      // onChanged: (val) => setState(() {
      //   _type = val!;
      //   if (_type != 'expense') { _expenseCategoryId = null; ... }
      // })
      // Notice: _selectedSupplierId is NOT reset to null!
      currentType = 'expense';

      // Submission payload construction line 256:
      final payload = {
        'type': currentType,
        'supplier_id': selectedSupplierId, // Still 5!
      };

      // Backend rule: 'supplier_id' => 'prohibited_if:type,expense'
      final isViolatingBackendRule = payload['type'] == 'expense' && payload['supplier_id'] != null;
      expect(isViolatingBackendRule, isTrue);
    });

    test('Fix Verification: Resetting supplier_id to null when type != supplier_payment satisfies backend rule', () {
      String currentType = 'supplier_payment';
      int? selectedSupplierId = 5;

      // Proposed defensive handler:
      void onTypeChanged(String newType) {
        currentType = newType;
        if (currentType != 'supplier_payment') {
          selectedSupplierId = null; // Clean state
        }
      }

      onTypeChanged('expense');

      final payload = {
        'type': currentType,
        'supplier_id': selectedSupplierId,
      };

      expect(payload['type'], 'expense');
      expect(payload['supplier_id'], isNull);
    });
  });

  group('R3 & R5: Mixed Payments Multi-tender Arithmetic & Overpayment Handling', () {
    test('Multi-tender sum arithmetic handles Cash + Check + Transfer with precision', () {
      final payments = <PaymentItem>[
        PaymentItem(method: 'cash', amount: 15250.50),
        PaymentItem(method: 'check', amount: 35000.00, checkId: 101),
        PaymentItem(method: 'transfer', amount: 49749.50),
      ];

      final totalPaid = payments.fold(0.0, (sum, p) => sum + p.amount);

      expect(totalPaid, 100000.0);
      expect(payments.length, 3);
    });

    test('Overpayment detection calculates proper change (vuelto) when check exceeds debt', () {
      const supplierDebt = 30000.0;
      const checkAmount = 35000.0; // Physical check exceeds debt by $5,000

      final isOverpayment = checkAmount > supplierDebt;
      final changeAmount = isOverpayment ? checkAmount - supplierDebt : 0.0;

      expect(isOverpayment, isTrue);
      expect(changeAmount, 5000.0);
    });
  });
}
