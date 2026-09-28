# Forensic Audit & Analysis: Mixed Payments & State Bugs (Requirement R3)

**Auditor:** Teamwork Preview Explorer Survey 3 (Mixed Payments & State Bug Investigator)  
**Date:** 2026-09-27  
**Workspace Targets:**  
- Frontend: `c:\laragon\www\Sistema_POS\pos-frontend`
- Backend: `c:\laragon\www\Sistema_POS\pos-backend`

---

## 1. Executive Summary

Requirement R3 requires an exhaustive investigation of the "Abonar a Proveedor" (Pay Supplier) flow when combining mixed payment methods (specifically Cash + Third-Party Checks, Transfers, etc.) in `movement_form_dialog.dart`, related providers/controllers, and the backend API (`pos-backend`).

Our static forensic code audit identified **critical architectural flaws, arithmetic vulnerabilities, state synchronization bugs, and backend validation omissions**:
1. **Check Value Tampering / Face Value Disconnect:** The UI allows arbitrary overwriting of a check's face value via the "Pagar Restante" button, and the backend API accepts any arbitrary amount for a check without verifying that `payment['amount'] == check->amount`. An endorsed $50,000 check can be submitted as $5,000, losing $45,000 of check value from the company.
2. **Missing Overpayment & Change (Vuelto) Handling:** Neither frontend nor backend prevents paying more than the supplier debt. When a check exceeds debt, the backend simply drives the supplier balance into negative (credit), without offering or recording cash change (vuelto) returned by the supplier.
3. **Silent Input Discard on Submit:** In `_submit()`, if a user enters a comma-decimal amount (e.g. `150,50` standard in Argentina) or negative value, `pendingAmount > 0` evaluates to false. If prior payments exist in the list, the pending amount is silently dropped without throwing any validation error.
4. **State Desynchronization on Supplier Change:** Selecting a different supplier does NOT reset `_payments` or clear controllers, allowing payments calculated for Supplier A to be applied to Supplier B.
5. **HTTP 422 Crash on Type Switching:** Switching from `supplier_payment` to `expense` retains `_selectedSupplierId` in state, which triggers Laravel's `'supplier_id' => 'prohibited_if:type,expense'` validation failure.
6. **Stale Check Cache in Frontend:** Upon successful payment, `checkProvider.loadChecks()` is never invoked, leaving client memory with outdated `in_wallet` checks.
7. **Missing Supplier Foreign Key on Endorsed Checks:** The backend updates `third_party_checks.status = 'endorsed'` but fails to populate `supplier_id`, severing auditability.
8. **Splitting Without Batch/Parent ID:** Backend persists each payment item as a separate independent `CashMovement` row with no linking transaction/batch ID, preventing holistic audit, reprinting, or coordinated cancellation.

---

## 2. Architecture & Data Flow Tracing

### 2.1 Frontend Dialog Lifecycle (`movement_form_dialog.dart`)
- **Initialization (`initState`, lines 91–115):**
  - Reads `initialType` (default `'expense'`) or `'supplier_payment'`, `initialSupplierId`, `initialCategory`.
  - If `initialAmount > 0`, it adds an initial `PaymentItem(method: 'cash', amount: initialAmount)` to `_payments` (lines 100–102).
  - Listens to `_paymentAmountController` to trigger `setState()` on text changes (line 104).
  - Dispatches `SupplierProvider.fetchSuppliers()`, `CheckProvider.loadChecks()`, and `ExpenseCategoryProvider.fetchCategories()` via `addPostFrameCallback`.
- **Payment Method Management (lines 872–972):**
  - Dropdown allows selecting `'cash'`, `'transfer'`, or `'check'`.
  - When `'check'` is chosen:
    - `_paymentAmountController` is disabled (`enabled: _currentPaymentMethod != 'check'`).
    - A second dropdown lists `availableChecks` (`status == 'in_wallet'`).
    - Selecting a check assigns `_currentCheckId = val` and sets `_paymentAmountController.text = check.amount.toString()`.
  - Clicking "Agregar" (`_addPayment()`, lines 150–179):
    - Parses `double.tryParse(_paymentAmountController.text) ?? 0`.
    - Validates `amount > 0` and, if method is check, validates `_currentCheckId != null`.
    - Pushes `PaymentItem` to `_payments`.
    - Resets `_paymentAmountController.clear()` and `_currentCheckId = null`.
- **Submission Flow (`_submit()` & `_executeSubmit()`, lines 187–273):**
  - If `_paymentAmountController.text` has an unadded amount (`pendingAmount > 0`), it automatically calls `_addPayment()`.
  - Requires `_payments.isNotEmpty`.
  - Constructs JSON payload with array of payments:
    ```json
    {
      "type": "supplier_payment",
      "category": "Pago a Proveedor",
      "cash_shift_id": 1,
      "expense_category_id": null,
      "description": "...",
      "receipt_number": "...",
      "supplier_id": 5,
      "payments": [
        {"amount": 5000.0, "payment_method": "cash", "check_id": null},
        {"amount": 12500.0, "payment_method": "check", "check_id": 14}
      ]
    }
    ```
  - Sends POST request to `$baseUrl/cash-movements` via `CashMovementProvider.createMovement`.

### 2.2 Backend Execution (`CashMovementController.php` & `StoreCashMovementRequest.php`)
- **Validation (`StoreCashMovementRequest.php`, lines 26–65):**
  - Verifies `type` in `['expense', 'withdrawal', 'deposit', 'supplier_payment']`.
  - `supplier_id`: `required_if:type,supplier_payment` and `prohibited_if:type,expense`.
  - `payments`: required array, `min:1`.
  - `payments.*.amount`: required numeric, `min:0.01`.
  - `payments.*.payment_method`: in `['cash', 'transfer', 'check']`.
  - `payments.*.check_id`: required if method is check; custom closure checks `status === 'in_wallet'`.
- **Transaction & Persistence (`CashMovementController::store`, lines 145–191):**
  - Iterates over each item in `$validated['payments']`.
  - Creates a dedicated `CashMovement` database row for each item.
  - If `method === 'check'`, updates `$check->update(['status' => 'endorsed'])`.
  - Aggregates `$totalAmountPaid += $amount`.
  - Decrements supplier balance: `$supplier->decrement('balance', $totalAmountPaid)`.
  - Returns 201 with array of created movement IDs.

---

## 3. In-Depth Arithmetic & Formula Audit

### 3.1 Live Total vs. Committed Payments Formula
In `movement_form_dialog.dart`, lines 144–148:
```dart
double get _totalAmount {
  final listSum = _payments.fold(0.0, (sum, item) => sum + item.amount);
  final pendingSum = double.tryParse(_paymentAmountController.text) ?? 0;
  return listSum + pendingSum;
}
```
**Identified Flaws:**
1. **Uncommitted State Pollution:** `_totalAmount` aggregates committed items (`_payments`) with raw, unvalidated text currently typed in `_paymentAmountController`. If a user enters `"-500"`, `_totalAmount` immediately drops by $500, misrepresenting the total transaction sum.
2. **Parsing Discrepancy:** If the user enters a decimal with comma (e.g. `2500,50`), `double.tryParse` returns `null` (`0.0`). The on-screen total fails to include it, despite the text field displaying `$ 2500,50`.
3. **Floating Point Rounding (IEEE-754):** Both Dart and PHP perform floating point addition (`double`). Adding sums like `$100.10 + $200.20` generates `$300.30000000000007`. In financial accounting, currency arithmetic must be rounded to 2 decimal places or calculated in integer cents.

### 3.2 Remaining Debt Calculation & Floating Point Modulo
In `movement_form_dialog.dart`, lines 734–738:
```dart
final listSum = _payments.fold(0.0, (sum, item) => sum + item.amount);
final remaining = supplier.balance.abs() - listSum;
_paymentAmountController.text = 
    (remaining % 1 == 0 ? remaining.toInt().toString() : remaining.toStringAsFixed(2));
```
**Identified Flaws:**
1. **Modulo on Float (`remaining % 1 == 0`):** Due to IEEE-754 precision issues, `remaining` can be `150.00000000000003` or `149.99999999999997`. `remaining % 1` is not `0.0`, resulting in unexpected formatted text.
2. **Absolute Value Assumption (`supplier.balance.abs()`):** If a supplier has a credit balance (e.g. `balance = -5000.00`), `abs()` yields `+5000.00`. The dialog offers "Pagar Total" / "Pagar Restante" for $5,000, encouraging the user to pay even more money to a supplier who already owes us money!

### 3.3 Check Face Value Tampering via "Pagar Restante" (Critical Security/Integrity Bug)
**Code Location:** `movement_form_dialog.dart`, lines 733–739 and 957–967.
**Mechanism:**
1. User selects a check with face value $15,000.
2. `_currentCheckId` is set to the check ID, and `_paymentAmountController.text` is populated with `"15000"`.
3. User then clicks the "Pagar Restante" button because debt is only $6,000.
4. The button's `onPressed` overwrites `_paymentAmountController.text` with `"6000"`.
5. `_currentCheckId` remains set to the $15,000 check!
6. When "Agregar" is tapped, `PaymentItem(method: 'check', amount: 6000, checkId: ...)` is added to `_payments`.
7. In the backend, `StoreCashMovementRequest` does **not** validate that `amount == check->amount`.
8. Backend records the check as `endorsed` (taken out of wallet), but only credits $6,000 to the supplier!
9. **Impact:** $9,000 of check face value disappears from the company's books without trace.

---

## 4. Edge Cases & Vulnerability Analysis

| Edge Case | Observed Behavior | Code Locations | Impact / Severity |
| :--- | :--- | :--- | :--- |
| **Check Amount > Debt** | Allowed without restriction; no warning or confirmation; no change (vuelto) option. | Frontend: line 187 (`_submit`)<br>Backend: `CashMovementController.php:185` | **High:** Supplier balance turns negative. Cash change returned by supplier cannot be registered in cash drawer. |
| **Negative Cash Amount** | Reduces `_totalAmount` on screen. In `_submit()`, `pendingAmount > 0` is false, so it is silently discarded if other payments exist. | Frontend: lines 146, 191 | **Medium:** Silent omission of user-entered value; misleading UI total. |
| **Comma Decimal Input (`100,50`)** | `double.tryParse` returns `null` -> `0`. Silently ignored on submit if other payments exist. | Frontend: lines 151, 191 | **High:** In Argentina, comma is standard. Cashier believes amount was submitted, but it is dropped. |
| **Total Paid > Total Debt** | Full amount decremented from supplier balance without warning. | Frontend: `movement_form_dialog.dart:257`<br>Backend: `CashMovementController.php:185` | **Medium:** Uncontrolled creation of negative balances (unapproved supplier credit). |
| **Check Status Lifecycle** | Check marked `'endorsed'`, but `supplier_id` on `third_party_checks` table is left `NULL`. | Backend: `CashMovementController.php:176` | **High:** Loss of relational traceability; check wallet cannot show which supplier received the check. |
| **Frontend Check Cache Invalidation** | `checkProvider.loadChecks()` is NOT called after movement creation. | Frontend: `movement_form_dialog.dart:270` | **High:** Stale client state. Reopening modal or navigating to wallet shows endorsed check still in wallet. |
| **Deleting Movement** | Deleting check movement reverts check to `in_wallet`, but partial delete of a mixed payment leaves remaining payments orphaned. | Backend: `CashMovementController.php:236-241` | **Medium:** Inconsistent multi-part payment cancellation. |

---

## 5. State Synchronization Flaws Across User Interactions

### 5.1 Changing Supplier Does Not Reset Payments
- **Location:** `movement_form_dialog.dart`, lines 649–650:
  ```dart
  onChanged: (val) => setState(() => _selectedSupplierId = val),
  ```
- **Bug:** If a cashier selects Supplier A (Debt $40,000), adds checks and cash totaling $40,000, and then realizes they selected the wrong supplier and switches the dropdown to Supplier B (Debt $2,000):
  - `_payments` is NOT cleared.
  - `_paymentAmountController` is NOT cleared.
  - Submitting pays $40,000 to Supplier B, driving Supplier B's account to -$38,000!

### 5.2 Changing Movement Type Triggers HTTP 422
- **Location:** `movement_form_dialog.dart`, lines 478–485:
  ```dart
  onChanged: (val) => setState(() {
    _type = val!;
    if (_type != 'expense') {
      _expenseCategoryId = null;
      _category = _currentCategories.first;
    }
  }),
  ```
- **Bug:** `_selectedSupplierId` is NOT reset to `null` when switching to `expense`.
- In `_executeSubmit()`, `data['supplier_id'] = _selectedSupplierId` is sent.
- Backend `StoreCashMovementRequest.php` line 40 enforces:
  `'supplier_id' => [..., 'prohibited_if:type,expense']`.
- The request immediately crashes with HTTP 422: `"The supplier_id field is prohibited when type is expense."`

### 5.3 Single Shared Controller for Manual Entry and Checks
- `_paymentAmountController` is reused across Cash, Transfer, and Check.
- Switching methods leaves pending values in the controller or allows buttons ("Pagar Restante") to contaminate check amounts.

### 5.4 Inverted Flow in Supplier Current Account Screen
- **Location:** `supplier_current_account_screen.dart`, lines 220–240:
  When `_currentBalance < 0` (business has a "Saldo a Favor"), the button displays "Cobrar Saldo" but instantiates:
  ```dart
  MovementFormDialog(
    initialSupplierId: widget.supplierId,
    initialType: 'supplier_payment', // BUG: supplier_payment is an OUTFLOW (egreso)
  )
  ```
  Collecting credit from a supplier is an INFLOW (`deposit` / "Cobro de Saldo a Favor"), but the screen routes it as an expense/payment out of the drawer!

---

## 6. Backend Payload & Contract Audit

### 6.1 Schema Comparison Table

| Field | Frontend Payload (`movement_form_dialog.dart`) | Backend Request (`StoreCashMovementRequest.php`) | Discrepancy / Risk |
| :--- | :--- | :--- | :--- |
| `type` | String (`'supplier_payment'`, etc.) | `in:expense,withdrawal,deposit,supplier_payment` | Validated. |
| `supplier_id` | `int?` | `required_if:type,supplier_payment`, `prohibited_if:type,expense` | Frontend sends non-null on type switch to expense -> 422 error. |
| `payments` | Array of objects | `required, array, min:1` | Validated. |
| `payments.*.amount` | `double` | `required, numeric, min:0.01` | **Missing backend check:** No validation that check amount matches check face value! |
| `payments.*.payment_method` | `string` (`'cash'`, `'transfer'`, `'check'`) | `in:cash,transfer,check` | Validated. |
| `payments.*.check_id` | `int?` | `required_if:...,check`, status `in_wallet` | Validated status, but **does not verify check ownership or matching face value**. |
| `check_details` | Not sent | Not expected | Matched. |

### 6.2 Structural Persistence Defect: Lack of Transaction Batching
- Backend `CashMovementController.php` creates individual unlinked records for each payment item in the array:
  ```php
  foreach ($validated['payments'] as $payment) {
      $movement = CashMovement::create([...]);
  }
  ```
- If a supplier payment of $10,000 consists of $3,000 Cash and $7,000 Check:
  - Movement 101: Cash, $3,000
  - Movement 102: Check, $7,000
- **Problems:**
  1. No `batch_id` or `parent_id` connects Movement 101 and 102.
  2. Reprinting a ticket from `cash_movements_screen.dart` (lines 126–128) only prints that individual row ($3,000 Cash), losing the combined breakdown of the actual transaction.
  3. Canceling Movement 101 leaves Movement 102 active, corrupting payment history reconciliation.

---

## 7. Extended Audit Findings (Summary List)

1. **Check Amount Desynchronization:** "Pagar Restante" overwrites check amount; backend allows any amount for a check.
2. **Missing Check Endorsement Foreign Key:** Backend does not update `third_party_checks.supplier_id`.
3. **Frontend Cache Staleness:** `CheckProvider.loadChecks()` is not called after payment execution.
4. **Prohibited Supplier on Expense Type Switch:** Switching type to expense triggers HTTP 422 crash.
5. **Silent Discard of Pending Inputs:** Non-numeric, negative, or comma inputs are dropped without notification if another payment exists.
6. **No Comma Decimal Support:** Argentina POS users cannot use `,` as decimal separator in `_paymentAmountController`.
7. **Dirty State on Supplier Switch:** Changing supplier retains previously entered payments.
8. **Lack of Overpayment Warning / Change (Vuelto) Flow:** Overpaying with a check turns balance negative without registering returned cash in drawer.
9. **Inverted "Cobrar Saldo" Flow:** `SupplierCurrentAccountScreen` opens `supplier_payment` (egreso) instead of `deposit` (ingreso).
10. **Lack of Batch Linking in `cash_movements` Table:** Multi-method payments are split into disconnected rows.

---

## 8. Concrete Remediation Proposals

### Proposal 1: Frontend Sanitization and Validation in `movement_form_dialog.dart`
- **Helper function for locale-aware numeric parsing:**
  ```dart
  double? _parseAmount(String text) {
    final clean = text.trim().replaceAll(',', '.');
    return double.tryParse(clean);
  }
  ```
- **Enforce check amount immutability:**
  When `_currentPaymentMethod == 'check'`, ignore "Pagar Restante" or set amount strictly to `selectedCheck.amount`.
- **Reset payments on supplier or type switch:**
  ```dart
  onChanged: (val) => setState(() {
    if (_selectedSupplierId != val && _payments.isNotEmpty) {
      // Clear payments or confirm dialog
      _payments.clear();
      _paymentAmountController.clear();
    }
    _selectedSupplierId = val;
  })
  ```
  ```dart
  onChanged: (val) => setState(() {
    _type = val!;
    if (_type != 'supplier_payment') {
      _selectedSupplierId = null;
    }
    ...
  })
  ```
- **Sync `CheckProvider` on submit completion:**
  ```dart
  if (mounted) {
    context.read<CheckProvider>().loadChecks();
  }
  ```

### Proposal 2: Backend Check Amount Validation in `StoreCashMovementRequest.php`
- Add strict face-value validation in the check validator rule:
  ```php
  'payments.*.amount' => [
      'required',
      'numeric',
      'min:0.01',
      function ($attribute, $value, $fail) {
          $index = explode('.', $attribute)[1];
          $payment = request()->input("payments.{$index}");
          if (($payment['payment_method'] ?? null) === 'check' && !empty($payment['check_id'])) {
              $check = ThirdPartyCheck::find($payment['check_id']);
              if ($check && abs((float)$check->amount - (float)$value) > 0.009) {
                  $fail("El monto indicado (\${$value}) no coincide con el valor nominal del cheque (\${$check->amount}).");
              }
          }
      },
  ],
  ```

### Proposal 3: Store Supplier ID on Check Endorsement in `CashMovementController.php`
- In `CashMovementController.php`, line 176:
  ```php
  if ($method === 'check' && $checkId) {
      $check = ThirdPartyCheck::find($checkId);
      if ($check) {
          $check->update([
              'status' => 'endorsed',
              'supplier_id' => $validated['supplier_id'] ?? null,
              'endorsement_note' => 'Endosado a proveedor en Movimiento de Caja #' . $movement->id,
          ]);
      }
  }
  ```
