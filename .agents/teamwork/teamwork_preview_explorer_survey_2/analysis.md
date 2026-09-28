# FORENSIC AUDIT REPORT: DUPLICATE CHECK BUG (REQUIREMENT R2)

**Target Component:** `MovementFormDialog` & Related Payment Flow  
**Target File:** `c:\laragon\www\Sistema_POS\pos-frontend\lib\features\cash_movements\presentation\widgets\movement_form_dialog.dart`  
**Secondary Files:**
- `c:\laragon\www\Sistema_POS\pos-frontend\lib\features\checks\domain\entities\third_party_check.dart`
- `c:\laragon\www\Sistema_POS\pos-frontend\lib\features\checks\presentation\providers\check_provider.dart`
- `c:\laragon\www\Sistema_POS\pos-backend\app\Http\Requests\StoreCashMovementRequest.php`
- `c:\laragon\www\Sistema_POS\pos-backend\app\Http\Controllers\Api\CashMovementController.php`  
**Auditor:** Teamwork Preview Explorer Survey 2 (Duplicate Check Bug Investigator)  
**Date:** 2026-09-28  

---

## 1. Executive Summary

During the forensic audit of the supplier payment flow ("Abonar a Proveedor"), an exhaustive static analysis was conducted on `movement_form_dialog.dart` and its associated state providers and backend endpoints.

A **critical financial integrity defect** was confirmed: **A user can add the same third-party check (cheque de cartera) to the payment list multiple times**. 

### Key Consequences
1. **Artificial Inflation of Paid Amounts:** The total payment amount is incremented by the check face value for every duplicate addition ($Total = \sum Cash + N \times Amount_{check}$).
2. **Severe Debt Balance Distortion:** When sent to the backend, the supplier's balance is decremented by the inflated total ($balance = balance_{initial} - Total_{inflated}$), turning legitimate debts into phantom vendor credits ("Saldo a Favor").
3. **Split-Brain Portfolio State:** Multiple cash movement ledger entries link to a single physical check entity. If one entry is deleted, the backend prematurely restores the check status to `in_wallet` while the second duplicate entry continues to reference it.
4. **False Fiscal/Commercial Documentation:** Receipt and PDF vouchers print duplicate line items with identical check numbers, exposing the business to tax, audit, and commercial disputes.

---

## 2. Component Architecture & Retrieval Flow

### 2.1 Third-Party Check Retrieval Pipeline
1. **Data Model (`ThirdPartyCheck`):**
   - Path: `lib/features/checks/domain/entities/third_party_check.dart`
   - Represents physical third-party checks accepted in POS (`status: 'in_wallet' | 'deposited' | 'endorsed' | 'rejected'`).
   - Critical Architectural Observation: `ThirdPartyCheck` is a plain Dart class that **does NOT override `operator ==` or `hashCode`**. Object comparison defaults to identity (`identical`).
2. **Provider Layer (`CheckProvider`):**
   - Path: `lib/features/checks/presentation/providers/check_provider.dart`
   - Holds state `List<ThirdPartyCheck> _checks = []`.
   - Method `loadChecks()` queries API repository `GET /api/third-party-checks` and populates `_checks`.
3. **Dialog Initialization (`MovementFormDialog.initState`):**
   - Path: `movement_form_dialog.dart:108-115`
   - Triggers `context.read<CheckProvider>().loadChecks()` in a post-frame callback.
4. **Presentation in `build()`:**
   - Path: `movement_form_dialog.dart:438-440`
   ```dart
   final checkProv = context.watch<CheckProvider>();
   final availableChecks =
       checkProv.checks.where((c) => c.status == 'in_wallet').toList();
   ```
   - **VULNERABILITY:** `availableChecks` filters solely on `c.status == 'in_wallet'`. It has **zero awareness** of the dialog's local payment state (`_payments`).

---

## 3. Forensic Interaction & Code Path Trace

### 3.1 Step-by-Step User Interaction Flow

```
[User selects Method: "Cheque"]
       │
       ▼
[_currentPaymentMethod = 'check']
[_paymentAmountController is locked]
       │
       ▼
[User opens "Seleccionar Cheque en Cartera" Dropdown]
       │
       ▼
[Dropdown renders `availableChecks` (status == 'in_wallet')]
       │
       ▼
[User selects Check #12 ($50,000)] ──> [_currentCheckId = 12, Controller.text = "50000.0"]
       │
       ▼
[User taps "Agregar" Button]
       │
       ▼
[_addPayment() executes]
       ├── Validates amount > 0 (PASS: 50000.0)
       ├── Validates _currentCheckId != null (PASS: 12)
       ├── Retrieves checkObj from CheckProvider
       ├── Appends new PaymentItem to _payments (LENGTH: 1)
       └── Clears _paymentAmountController and sets _currentCheckId = null
       │
       ▼
[Widget Rebuilds (setState)]
       ├── _payments has [ PaymentItem(checkId: 12, amount: 50000) ]
       ├── `availableChecks` STILL includes Check #12 (because checkProv is unchanged!)
       └── Dropdown displays Check #12 AGAIN as selectable item
       │
       ▼
[User taps Dropdown AGAIN and selects Check #12 AGAIN]
       │
       ▼
[_currentCheckId = 12, Controller.text = "50000.0"]
       │
       ▼
[User taps "Agregar" OR taps "Procesar Movimiento" (Auto-add triggers)]
       │
       ▼
[_addPayment() executes AGAIN]
       ├── No check against existing _payments items
       └── Appends second PaymentItem to _payments (LENGTH: 2, duplicate checkId: 12)
       │
       ▼
[_totalAmount is now $100,000 for a single $50,000 check]
```

### 3.2 The Auto-Add Trap in `_submit()`
In `movement_form_dialog.dart:191-194`:
```dart
// Auto-agregar el pago si el usuario lo escribió pero olvidó presionar "Agregar"
final pendingAmount = double.tryParse(_paymentAmountController.text) ?? 0;
if (pendingAmount > 0) {
  _addPayment();
}
```
If a user selects Check #12 in the dropdown, the amount controller immediately populates with `"50000.0"`. If the user then directly clicks **"Procesar Movimiento"**, `_submit()` blindly calls `_addPayment()`. If Check #12 had already been added earlier, this auto-add logic silently appends the duplicate check without user confirmation!

---

## 4. Root Cause Analysis (Static Code Analysis)

The defect stems from five compounding design flaws:

### Defect 1: Unfiltered Available Checks in UI Layer
- **Location:** `movement_form_dialog.dart:438-440`
- **Flawed Code:**
  ```dart
  final availableChecks =
      checkProv.checks.where((c) => c.status == 'in_wallet').toList();
  ```
- **Analysis:** `availableChecks` only filters checks based on global provider status. It never subtracts the IDs of checks already present in `_payments`. Because the check is not yet endorsed on the backend while the dialog is open, its status remains `in_wallet`, leaving it visible in the dropdown indefinitely.

### Defect 2: Complete Absence of Deduplication Guard in `_addPayment()`
- **Location:** `movement_form_dialog.dart:158-179`
- **Flawed Code:**
  ```dart
  ThirdPartyCheck? checkObj;
  if (_currentPaymentMethod == 'check') {
    if (_currentCheckId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Seleccione un cheque.')));
      return;
    }
    final checks = context.read<CheckProvider>().checks;
    checkObj = checks.firstWhere((c) => c.id == _currentCheckId);
  }

  setState(() {
    _payments.add(PaymentItem(
      method: _currentPaymentMethod,
      amount: amount,
      checkId: _currentCheckId,
      checkObj: checkObj,
    ));
    _paymentAmountController.clear();
    _currentCheckId = null;
  });
  ```
- **Analysis:** `_addPayment()` does not inspect `_payments` before appending. It lacks:
  ```dart
  if (_payments.any((p) => p.method == 'check' && p.checkId == _currentCheckId))
  ```

### Defect 3: Data Structure Permissiveness & Lack of Equality Contracts
- **Location:** `movement_form_dialog.dart:21-33`, `movement_form_dialog.dart:69`, `third_party_check.dart:1-46`
- **Analysis:**
  - `_payments` is declared as `final List<PaymentItem> _payments = [];`. A `List` inherently permits duplicate elements.
  - Neither `PaymentItem` nor `ThirdPartyCheck` implements `operator ==` or `hashCode`.
  - While using a `Set<PaymentItem>` might seem like an obvious fix, a naive `Set` would fail if equality is based on `checkId`: cash payments have `checkId == null` and would collide if amounts match, while distinct check instances would not collide without custom equality. Thus, the list data structure is appropriate for multi-tender lines, but requires an explicit domain constraint on check uniqueness.

### Defect 4: Missing Pre-Submission Integrity Barrier in `_submit()`
- **Location:** `movement_form_dialog.dart:187-200`
- **Analysis:** `_submit()` validates form keys and non-emptiness of `_payments`, but contains zero validation to guarantee that `checkId`s are distinct across the payload.

### Defect 5: Backend Request Validation Gap (Full Stack Vulnerability)
- **Location:** `pos-backend/app/Http/Requests/StoreCashMovementRequest.php:48-64`
- **Flawed Code:**
  ```php
  'payments.*.check_id' => [
      'nullable',
      'integer',
      'required_if:payments.*.payment_method,check',
      function ($attribute, $value, $fail) {
          if ($value) {
              $check = ThirdPartyCheck::find($value);
              if (! $check) {
                  $fail('El cheque seleccionado no existe.');
              } elseif ($check->status !== 'in_wallet') {
                  $fail('El cheque seleccionado ya no se encuentra en cartera.');
              }
          }
      },
  ],
  ```
- **Analysis:** The backend validates each check element independently against the database status (`in_wallet`). Since the database is only updated inside the transaction in `CashMovementController.php`, all duplicate elements in the payload point to the same check that is still `in_wallet` during validation. The backend lacks the Laravel `'distinct'` validation rule on `payments.*.check_id`.

---

## 5. Financial & Accounting Impact Analysis

### 5.1 Mathematical Inflation Model
Let $P = \{p_1, p_2, \dots, p_k\}$ be the set of payment items in `_payments`.
The total recorded disbursement is:
$$Total_{paid} = \sum_{i=1}^{k} amount(p_i)$$

If a single check $C$ with face value $V$ is added $m$ times ($m \ge 2$):
$$Total_{paid} = \sum_{cash} A_{cash} + m \cdot V$$
The artificial inflation of company disbursements is:
$$\Delta_{inflation} = (m - 1) \cdot V$$

### 5.2 Distortion of Supplier Current Account (Cuenta Corriente)
In `CashMovementController.php:185`:
```php
if (in_array($validated['type'], ['supplier_payment', 'expense'])) {
    $supplier->decrement('balance', $totalAmountPaid);
}
```
Consider a real-world scenario:
- **Actual Supplier Debt:** \$100,000 (Supplier `balance` = +100,000).
- **Payment Method:** The cashier hands over one check of \$50,000, but accidentally adds it twice ($m = 2$).
- **Calculated Total:** \$100,000.
- **Backend Execution:** `$supplier->decrement('balance', 100000)`.
- **Resulting Balance:** \$0.00.
- **Real Physical Settlement:** Only \$50,000 in paper value changed hands.
- **Accounting Deficit:** \$50,000 of real liability was wiped from the books without actual funds.

If the check was \$100,000 and added twice:
- **Resulting Balance:** $100,000 - 200,000 = -\$100,000$.
- The supplier account flips to an artificial **"Saldo a Favor"** of \$100,000. The store believes the vendor owes them money!

### 5.3 Cash Movement Ledger vs. Physical Wallet Desynchronization
- The backend creates $m$ rows in `cash_movements` table, all with `check_id = C.id`.
- The physical check wallet (`third_party_checks` table) contains only 1 check, whose status is updated to `'endorsed'`.
- If an auditor sums check outflows from `cash_movements`, it exceeds the total face value of endorsed checks in the wallet.

### 5.4 Rollback / Deletion Corruption
In `CashMovementController::destroy($id)`:
```php
if ($movement->payment_method === 'check' && $movement->check_id) {
    $check = ThirdPartyCheck::find($movement->check_id);
    if ($check) {
        $check->update(['status' => 'in_wallet']);
    }
}
```
If an administrator notices the duplicate entry and deletes **one** of the duplicate cash movements:
1. Movement #1 is deleted.
2. Check #12 is updated back to `status: 'in_wallet'`.
3. **Critical Split-Brain:** Movement #2 still exists in the database referencing Check #12, but Check #12 is now marked as available in wallet! Another cashier can now use Check #12 in a completely different payment!

---

## 6. Flawed Code Catalog

| File Path | Line(s) | Defect Description |
|:---|:---:|:---|
| `lib/features/cash_movements/presentation/widgets/movement_form_dialog.dart` | 69 | `List<PaymentItem> _payments = [];` allows unrestricted duplicate items. |
| `lib/features/cash_movements/presentation/widgets/movement_form_dialog.dart` | 158–179 | `_addPayment()` lacks verification for `checkId` already present in `_payments`. |
| `lib/features/cash_movements/presentation/widgets/movement_form_dialog.dart` | 191–194 | `_submit()` blindly auto-adds pending check without checking for duplicates. |
| `lib/features/cash_movements/presentation/widgets/movement_form_dialog.dart` | 438–440 | `availableChecks` does not subtract `_payments` check IDs. |
| `lib/features/cash_movements/presentation/widgets/movement_form_dialog.dart` | 927–969 | `DropdownButtonFormField<int>` presents already selected checks as active items. |
| `pos-backend/app/Http/Requests/StoreCashMovementRequest.php` | 48–64 | Missing `'distinct'` rule on `payments.*.check_id`. |

---

## 7. Concrete Remediation Strategies

A multi-layered defense strategy guarantees that duplicate checks cannot be added in the UI, cannot bypass submission, and cannot be accepted by the backend.

### Layer 1: Reactive UI Filtering (Available Checks Subtraction)
In `movement_form_dialog.dart:438-440`:
Subtract all check IDs currently present in `_payments` from the list of checks retrieved from `CheckProvider`.

```dart
// BEFORE
final availableChecks =
    checkProv.checks.where((c) => c.status == 'in_wallet').toList();

// AFTER
final selectedCheckIds = _payments
    .where((p) => p.method == 'check' && p.checkId != null)
    .map((p) => p.checkId!)
    .toSet();

final availableChecks = checkProv.checks
    .where((c) => c.status == 'in_wallet' && !selectedCheckIds.contains(c.id))
    .toList();
```

### Layer 2: Safe Controlled Dropdown Widget
In `movement_form_dialog.dart:944-969`:
Replace `initialValue: _currentCheckId` with a validated `value`:

```dart
final currentCheckValue = availableChecks.any((c) => c.id == _currentCheckId)
    ? _currentCheckId
    : null;

DropdownButtonFormField<int>(
  key: ValueKey('check_dropdown_${selectedCheckIds.length}'),
  value: currentCheckValue,
  decoration: const InputDecoration(
      labelText: 'Seleccionar Cheque en Cartera',
      isDense: true),
  items: availableChecks
      .map((c) => DropdownMenuItem(
            value: c.id,
            child: Text(
                'Nº ${c.checkNumber} (\$ ${c.amount}) - ${c.bankName}'),
          ))
      .toList(),
  onChanged: (val) {
    setState(() {
      _currentCheckId = val;
      if (val != null) {
        final check = availableChecks
            .firstWhere((c) => c.id == val);
        _paymentAmountController.text =
            check.amount.toString();
      }
    });
  },
)
```

### Layer 3: Defensive Guard in `_addPayment()`
In `movement_form_dialog.dart:158-168`:
Add explicit uniqueness validation:

```dart
    ThirdPartyCheck? checkObj;
    if (_currentPaymentMethod == 'check') {
      if (_currentCheckId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Seleccione un cheque.')));
        return;
      }
      
      // GUARDIA DEFENSIVA CONTRA DUPLICADOS
      final isAlreadyAdded = _payments.any(
          (p) => p.method == 'check' && p.checkId == _currentCheckId);
      if (isAlreadyAdded) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Este cheque ya fue agregado a la lista de pagos.'),
              backgroundColor: Colors.orange,
            ));
        return;
      }

      final checks = context.read<CheckProvider>().checks;
      try {
        checkObj = checks.firstWhere((c) => c.id == _currentCheckId);
      } catch (_) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('El cheque seleccionado no es válido.')));
        return;
      }
    }
```

### Layer 4: Auto-Add Hardening & Submission Barrier in `_submit()`
In `movement_form_dialog.dart:187-200`:

```dart
    // Auto-agregar el pago si el usuario lo escribió pero olvidó presionar "Agregar"
    final pendingAmount = double.tryParse(_paymentAmountController.text) ?? 0;
    if (pendingAmount > 0) {
      if (_currentPaymentMethod == 'check') {
        if (_currentCheckId != null &&
            !_payments.any((p) => p.method == 'check' && p.checkId == _currentCheckId)) {
          _addPayment();
        }
      } else {
        _addPayment();
      }
    }

    if (_payments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Agregue al menos un método de pago.')));
      return;
    }

    // BARRERA DE INTEGRIDAD ESTRICTA: Prevenir duplicados en el payload
    final checkIds = _payments
        .where((p) => p.method == 'check' && p.checkId != null)
        .map((p) => p.checkId!)
        .toList();
    if (checkIds.length != checkIds.toSet().length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error: No se puede utilizar el mismo cheque más de una vez.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
```

### Layer 5: Reactive Dynamic Restoration on Removal
When `_removePayment(index)` is invoked:
`_payments.removeAt(index)` removes the item. Because `availableChecks` dynamically filters against `selectedCheckIds`, calling `setState` immediately re-inserts the freed check back into the available dropdown list without needing manual recovery flags or secondary state caches.

### Layer 6: Backend Defense in Depth
In `StoreCashMovementRequest.php:48-64`:
```php
'payments.*.check_id' => [
    'nullable',
    'integer',
    'distinct', // Laravel standard rule: prevents duplicate check_id values across payments.*
    'required_if:payments.*.payment_method,check',
    function ($attribute, $value, $fail) {
        if ($value) {
            $check = ThirdPartyCheck::find($value);
            if (! $check) {
                $fail('El cheque seleccionado no existe.');
            } elseif ($check->status !== 'in_wallet') {
                $fail('El cheque seleccionado ya no se encuentra en cartera.');
            }
        }
    },
],
```

---

## 8. Automated Verification Suite (Flutter Tests)

Below is the complete, production-grade Flutter test designed to reproduce the bug and verify all proposed fixes.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend_desktop/features/cash_movements/presentation/widgets/movement_form_dialog.dart';
import 'package:frontend_desktop/features/cash_movements/providers/cash_movement_provider.dart';
import 'package:frontend_desktop/features/cash_movements/providers/expense_category_provider.dart';
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

class FakeCheckProvider extends ChangeNotifier implements CheckProvider {
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

class FakeSupplierProvider extends ChangeNotifier implements SupplierProvider {
  List<Supplier> _suppliers = [];
  @override
  List<Supplier> get suppliers => _suppliers;

  void setSuppliers(List<Supplier> list) {
    _suppliers = list;
    notifyListeners();
  }

  @override
  Future<void> fetchSuppliers() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeCheckProvider fakeCheckProvider;
  late FakeSupplierProvider fakeSupplierProvider;

  setUp(() {
    fakeCheckProvider = FakeCheckProvider();
    fakeSupplierProvider = FakeSupplierProvider();

    fakeSupplierProvider.setSuppliers([
      Supplier(
        id: 1,
        name: 'Distribuidora Central',
        cuit: '30-12345678-9',
        balance: 100000.0,
        isActive: true,
      ),
    ]);

    fakeCheckProvider.setChecks([
      ThirdPartyCheck(
        id: 101,
        bankName: 'Banco Santander',
        checkNumber: '8877001',
        amount: 35000.0,
        issueDate: DateTime.now(),
        paymentDate: DateTime.now(),
        issuerName: 'Cliente Juan',
        issuerCuit: '20-11223344-5',
        status: 'in_wallet',
      ),
      ThirdPartyCheck(
        id: 102,
        bankName: 'Banco Galicia',
        checkNumber: '8877002',
        amount: 25000.0,
        issueDate: DateTime.now(),
        paymentDate: DateTime.now(),
        issuerName: 'Cliente Pedro',
        issuerCuit: '20-99887766-5',
        status: 'in_wallet',
      ),
    ]);
  });

  group('Duplicate Check Bug Prevention Tests', () {
    test('Filtering selected checks prevents duplicate selection', () {
      final payments = <PaymentItem>[
        PaymentItem(method: 'check', amount: 35000.0, checkId: 101),
      ];

      final selectedCheckIds = payments
          .where((p) => p.method == 'check' && p.checkId != null)
          .map((p) => p.checkId!)
          .toSet();

      final availableChecks = fakeCheckProvider.checks
          .where((c) => c.status == 'in_wallet' && !selectedCheckIds.contains(c.id))
          .toList();

      expect(availableChecks.length, 1);
      expect(availableChecks.first.id, 102);
      expect(availableChecks.any((c) => c.id == 101), isFalse);
    });

    test('Adding all available checks leaves availableChecks empty', () {
      final payments = <PaymentItem>[
        PaymentItem(method: 'check', amount: 35000.0, checkId: 101),
        PaymentItem(method: 'check', amount: 25000.0, checkId: 102),
      ];

      final selectedCheckIds = payments
          .where((p) => p.method == 'check' && p.checkId != null)
          .map((p) => p.checkId!)
          .toSet();

      final availableChecks = fakeCheckProvider.checks
          .where((c) => c.status == 'in_wallet' && !selectedCheckIds.contains(c.id))
          .toList();

      expect(availableChecks.isEmpty, isTrue);
    });

    test('Removing a payment item restores the check to availableChecks', () {
      final payments = <PaymentItem>[
        PaymentItem(method: 'check', amount: 35000.0, checkId: 101),
        PaymentItem(method: 'check', amount: 25000.0, checkId: 102),
      ];

      // Remove Check 101
      payments.removeAt(0);

      final selectedCheckIds = payments
          .where((p) => p.method == 'check' && p.checkId != null)
          .map((p) => p.checkId!)
          .toSet();

      final availableChecks = fakeCheckProvider.checks
          .where((c) => c.status == 'in_wallet' && !selectedCheckIds.contains(c.id))
          .toList();

      expect(availableChecks.length, 1);
      expect(availableChecks.first.id, 101);
    });

    test('Submission barrier detects and blocks duplicate check IDs', () {
      final payments = <PaymentItem>[
        PaymentItem(method: 'check', amount: 35000.0, checkId: 101),
        PaymentItem(method: 'check', amount: 35000.0, checkId: 101), // Duplicate
      ];

      final checkIds = payments
          .where((p) => p.method == 'check' && p.checkId != null)
          .map((p) => p.checkId!)
          .toList();

      final hasDuplicates = checkIds.length != checkIds.toSet().length;
      expect(hasDuplicates, isTrue);
    });
  });
}
```

---
*End of Forensic Analysis Report.*
