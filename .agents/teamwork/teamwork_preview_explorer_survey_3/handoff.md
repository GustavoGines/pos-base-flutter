# Handoff Report: Mixed Payments & State Bug Investigation (R3)

**Agent:** `teamwork_preview_explorer_survey_3` (Mixed Payments & State Bug Investigator)  
**Assigned Working Directory:** `c:\laragon\www\Sistema_POS\pos-frontend\.agents\teamwork\teamwork_preview_explorer_survey_3`  
**Task Mission:** Exhaustive Forensic Analysis of Requirement R3 (Mixed Payments Bugs & Extended Audit)  
**Date:** 2026-09-27  

---

## 1. Observation

Direct code observations from static analysis across `pos-frontend` and `pos-backend`:

### Observation 1.1: Check Face Value Desynchronization via "Pagar Restante"
- **File:** `pos-frontend/lib/features/cash_movements/presentation/widgets/movement_form_dialog.dart`
- **Lines 733–739:**
  ```dart
  onPressed: () {
    setState(() {
      final listSum = _payments.fold(0.0, (sum, item) => sum + item.amount);
      final remaining = supplier.balance.abs() - listSum;
      _paymentAmountController.text = 
          (remaining % 1 == 0 ? remaining.toInt().toString() : remaining.toStringAsFixed(2));
    });
  },
  ```
- **Lines 957–967:**
  ```dart
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
  ```
- **Observation:** If a user selects a check for $10,000, `_currentCheckId` is set to the check ID and `_paymentAmountController.text` becomes `"10000"`. If the user then taps the "Pagar Restante" button (e.g. remaining debt is $3,000), `_paymentAmountController.text` is overwritten with `"3000"`, but `_currentCheckId` remains set. Tapping "Agregar" pushes `PaymentItem(method: 'check', amount: 3000, checkId: _currentCheckId)`.
- **Backend File:** `pos-backend/app/Http/Requests/StoreCashMovementRequest.php`
- **Lines 44–65:**
  ```php
  'payments' => ['required', 'array', 'min:1'],
  'payments.*.amount' => ['required', 'numeric', 'min:0.01'],
  'payments.*.payment_method' => ['required', 'string', 'in:cash,transfer,check'],
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
- **Observation:** The backend never checks that `$payment['amount'] == $check->amount`. It accepts any arbitrary amount for a check, updates `$check->update(['status' => 'endorsed'])` (`CashMovementController.php:176`), and decrements supplier balance by the arbitrary amount, causing the remaining face value ($7,000) to vanish.

---

### Observation 1.2: Check Amount Exceeding Supplier Debt (Overpayment & Missing Change)
- **Frontend File:** `pos-frontend/lib/features/cash_movements/presentation/widgets/movement_form_dialog.dart`
- **Lines 187–200:**
  ```dart
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final pendingAmount = double.tryParse(_paymentAmountController.text) ?? 0;
    if (pendingAmount > 0) {
      _addPayment();
    }

    if (_payments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Agregue al menos un método de pago.')));
      return;
    }
  ```
- **Backend File:** `pos-backend/app/Http/Controllers/Api/CashMovementController.php`
- **Lines 180–190:**
  ```php
  if (! empty($validated['supplier_id'])) {
      $supplier = Supplier::find($validated['supplier_id']);
      if ($supplier) {
          if (in_array($validated['type'], ['supplier_payment', 'expense'])) {
              $supplier->decrement('balance', $totalAmountPaid);
          } elseif ($validated['type'] === 'deposit') {
              $supplier->increment('balance', $totalAmountPaid);
          }
      }
  }
  ```
- **Observation:** If a check for $10,000 is applied to a debt of $4,000, neither frontend nor backend blocks or warns the user. The supplier balance is decremented to -$6,000. There is no workflow or field to register change ("vuelto") received in cash, which would need to enter the cash drawer as a deposit in `CashShiftService.php`.

---

### Observation 1.3: Silent Discard of Pending Negative or Comma-Decimal Amounts on Submit
- **Frontend File:** `pos-frontend/lib/features/cash_movements/presentation/widgets/movement_form_dialog.dart`
- **Lines 144–148 & 191–194:**
  ```dart
  double get _totalAmount {
    final listSum = _payments.fold(0.0, (sum, item) => sum + item.amount);
    final pendingSum = double.tryParse(_paymentAmountController.text) ?? 0;
    return listSum + pendingSum;
  }
  ```
  ```dart
  final pendingAmount = double.tryParse(_paymentAmountController.text) ?? 0;
  if (pendingAmount > 0) {
    _addPayment();
  }
  ```
- **Observation:** If a user types `150,50` (using a comma, typical in Argentina) or a negative value `-500`:
  1. `double.tryParse("150,50")` returns `null`, so `pendingAmount` is `0.0`.
  2. `pendingAmount > 0` evaluates to `false`.
  3. `_addPayment()` is skipped.
  4. If `_payments` already contains another payment (e.g. a check), `_submit()` proceeds and submits ONLY the existing payments, silently discarding the $150.50 cash payment without alerting the user.

---

### Observation 1.4: Changing Supplier Does Not Reset Payments (Payment Misallocation)
- **Frontend File:** `pos-frontend/lib/features/cash_movements/presentation/widgets/movement_form_dialog.dart`
- **Lines 649–650:**
  ```dart
  onChanged: (val) =>
      setState(() => _selectedSupplierId = val),
  ```
- **Observation:** When the user changes `_selectedSupplierId` from the dropdown, `_payments` is never cleared and `_paymentAmountController` is never reset. Payments computed and added for Supplier A are automatically submitted and credited against Supplier B.

---

### Observation 1.5: Switching Movement Type Triggers HTTP 422
- **Frontend File:** `pos-frontend/lib/features/cash_movements/presentation/widgets/movement_form_dialog.dart`
- **Lines 478–485:**
  ```dart
  onChanged: (val) => setState(() {
    _type = val!;
    if (_type != 'expense') {
      _expenseCategoryId = null;
      _category = _currentCategories.first;
    }
  }),
  ```
- **Backend File:** `pos-backend/app/Http/Requests/StoreCashMovementRequest.php`
- **Lines 35–41:**
  ```php
  'supplier_id' => [
      'nullable',
      'integer',
      'exists:suppliers,id',
      'required_if:type,supplier_payment',
      'prohibited_if:type,expense',
  ],
  ```
- **Observation:** If the dialog is opened as `supplier_payment` or a supplier was selected, and the user switches `_type` to `expense`, `_selectedSupplierId` is preserved in state. Upon submit, `data['supplier_id']` is sent to the backend, causing Laravel validation to reject the request with HTTP 422: `"The supplier_id field is prohibited when type is expense."`

---

### Observation 1.6: Omission of `CheckProvider.loadChecks()` After Payment
- **Frontend File:** `pos-frontend/lib/features/cash_movements/presentation/widgets/movement_form_dialog.dart`
- **Lines 267–273:**
  ```dart
  final createdIds =
      await provider.createMovement(data, adminPin: adminPin);

  if (mounted && _selectedSupplierId != null) {
    supplierProvider.fetchSuppliers();
  }
  ```
- **Observation:** `supplierProvider.fetchSuppliers()` is called, but `checkProvider.loadChecks()` is omitted. In client memory, `CheckProvider._checks` retains the endorsed check as `status == 'in_wallet'`.

---

### Observation 1.7: Endorsed Checks Missing `supplier_id` Foreign Key
- **Backend File:** `pos-backend/app/Http/Controllers/Api/CashMovementController.php`
- **Lines 173–177:**
  ```php
  // Si se usó un cheque, endosarlo
  if ($method === 'check' && $checkId) {
      $check = ThirdPartyCheck::find($checkId);
      $check->update(['status' => 'endorsed']);
  }
  ```
- **Backend File:** `pos-backend/app/Models/ThirdPartyCheck.php`
- **Lines 20 & 47–50:**
  ```php
  'supplier_id',
  ...
  public function supplier(): BelongsTo
  {
      return $this->belongsTo(Supplier::class);
  }
  ```
- **Observation:** Despite `ThirdPartyCheck` having a `supplier_id` column and relation specifically for endorsements ("Fase 2 – Endoso"), `CashMovementController` does not store `$validated['supplier_id']` on `$check`, severing database auditability.

---

### Observation 1.8: Mixed Payments Split into Disconnected Rows Without Batch ID
- **Backend File:** `pos-backend/app/Http/Controllers/Api/CashMovementController.php`
- **Lines 148–171:**
  A separate `CashMovement` row is created in a loop for every payment in `payments`.
- **Observation:** There is no `transaction_batch_id` or parent identifier. When reprinting a ticket in `cash_movements_screen.dart` (lines 126–128):
  `final List<Map<String, dynamic>> payments = [{'payment_method': movement.paymentMethod, 'amount': movement.amount}];`
  Only that individual payment slice is reprinted; the full mixed payment breakdown is lost.

---

### Observation 1.9: Inverted "Cobrar Saldo" Flow in Current Account
- **Frontend File:** `pos-frontend/lib/features/suppliers/presentation/screens/supplier_current_account_screen.dart`
- **Lines 230–237:**
  ```dart
  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => MovementFormDialog(
      initialSupplierId: widget.supplierId,
      initialType: 'supplier_payment',
    ),
  );
  ```
- **Observation:** When `_currentBalance < 0` (we have credit / Saldo a Favor), the screen displays "Cobrar Saldo" but passes `initialType: 'supplier_payment'`. `supplier_payment` is an egress (outflow from cash drawer). Collecting credit from a supplier is an inflow (`deposit`).

---

## 2. Logic Chain

1. **Step 1 (Check Value Decoupling):**  
   From Observation 1.1, `movement_form_dialog.dart` shares a single text controller (`_paymentAmountController`) between cash inputs and check face values. The "Pagar Restante" button calculates remaining debt and writes directly to `_paymentAmountController.text` without clearing `_currentCheckId`. Because `StoreCashMovementRequest.php` validates check status (`in_wallet`) but never validates check face value equality (`$check->amount == $amount`), a cashier or client can submit a partial or arbitrary amount for any check. This causes severe financial discrepancy where a check is marked `endorsed` but only partially credits the debt.

2. **Step 2 (Overpayment & Unrecorded Change):**  
   From Observation 1.2, neither frontend nor backend checks if total payment exceeds debt. When a check exceeds debt, the backend decrements supplier balance past zero into negative. In retail and commercial practice, paying a supplier with a third-party check that exceeds the debt often involves receiving cash back ("vuelto"). Because the system lacks a change mechanism, the received cash is not registered in the cash drawer (`CashShiftService.php:218`), causing an untracked cash surplus in the physical drawer.

3. **Step 3 (Silent Dropping of Pending Amounts):**  
   From Observation 1.3, Argentine users entering `,` for decimals causes `double.tryParse` to fail silently (`null`). In `_submit()`, `pendingAmount > 0` evaluates to false. When multiple payments are used (e.g. check was already added), the form submits successfully without the pending cash amount, leading to underpayment without user feedback.

4. **Step 4 (State Desync Across Transitions):**  
   From Observations 1.4 and 1.5, `_MovementFormDialogState` fails to isolate or reset dependent state fields when parent selectors (`_selectedSupplierId` or `_type`) change. Changing supplier preserves the payment list, risking payment misallocation to the wrong vendor. Changing type preserves `_selectedSupplierId`, causing an unhandled HTTP 422 exception.

5. **Step 5 (Cache Staleness & Auditability Loss):**  
   From Observations 1.6, 1.7, and 1.8, the lifecycle of endorsed checks is incomplete across both tiers. The frontend fails to refresh `CheckProvider`, leaving endorsed checks as available in wallet. The backend fails to link the check to the supplier in `third_party_checks.supplier_id`, and splits mixed payments into disconnected rows, preventing proper reprinting and atomic cancellations.

---

## 3. Caveats

- **Scope:** Static code analysis of frontend and backend code was performed in read-only mode without executing migrations or live database transactions.
- **Assumptions:** We assume standard Latin American / Argentine business practices regarding third-party checks (valores de terceros), where checks are non-divisible financial instruments (a $10,000 check must either be endorsed in full or not endorsed at all).
- **Alternative Interpretations:** If partial check endorsement was intended, it would require a backend mechanism to create a "residual check" or issue a credit note for the difference. The current schema has no support for residual checks, proving that the omission of face-value validation is a bug.

---

## 4. Conclusion

Requirement R3 analysis confirms multiple critical flaws in mixed payments and payment state synchronization:
1. **Critical Defect:** Check amount tampering allows endorsing full checks while crediting arbitrary amounts to debt.
2. **Workflow Defect:** Overpayment with checks lacks change/credit accounting.
3. **Data Entry Defect:** Comma-decimal cash inputs are silently dropped upon submission.
4. **State Management Defects:** Dirty payment state survives supplier changes; `_selectedSupplierId` leaks into expense types causing HTTP 422.
5. **Architectural Gap:** Endorsed checks lose vendor foreign key reference; mixed payment items are fragmented into orphan movement records.

---

## 5. Verification Method

### 5.1 Verification Commands
- **Frontend test execution (when tests are added):**
  ```powershell
  cd c:\laragon\www\Sistema_POS\pos-frontend
  flutter test test/features/cash_movements/movement_form_dialog_test.dart
  ```
- **Backend test execution:**
  ```powershell
  cd c:\laragon\www\Sistema_POS\pos-backend
  php artisan test --filter=CashMovementTest
  ```

### 5.2 Independent Verification Files & Lines to Inspect
1. Inspect `movement_form_dialog.dart:733–739` and `957–967` to verify that "Pagar Restante" can overwrite a check's amount.
2. Inspect `StoreCashMovementRequest.php:44–65` to verify the absence of check face-value validation.
3. Inspect `movement_form_dialog.dart:191–194` to verify silent skipping of pending amount on submit.
4. Inspect `movement_form_dialog.dart:649–650` to verify lack of payment reset on supplier dropdown change.
5. Inspect `movement_form_dialog.dart:478–485` vs `StoreCashMovementRequest.php:40` to verify the HTTP 422 bug on type switch.
6. Inspect `CashMovementController.php:173–177` to verify that `$check->supplier_id` is never set.

### 5.3 Invalidation Conditions
- This assessment would be invalidated if:
  - Third-party checks are intentionally allowed to be partially endorsed with no tracking of the difference (contradicted by accounting standards and lack of residual check columns).
  - The backend had a middleware or database trigger automatically synchronizing check amounts (verified: no such triggers exist).
