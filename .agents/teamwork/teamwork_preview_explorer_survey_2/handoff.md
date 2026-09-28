# HANDOFF REPORT: REQUIREMENT R2 — DUPLICATE CHECK BUG INVESTIGATION

**Agent:** `teamwork_preview_explorer_survey_2`  
**Role:** Duplicate Check Bug Investigator  
**Working Directory:** `c:\laragon\www\Sistema_POS\pos-frontend\.agents\teamwork\teamwork_preview_explorer_survey_2`  
**Handoff Type:** Hard (Task complete)  
**Parent Conversation ID:** `18ff2693-a6f7-493d-836a-6b9cb21fd718`  

---

## 1. Observation

Direct observations obtained via static code analysis across `pos-frontend` and `pos-backend`:

1. **Check Retrieval & Presentation in Dialog:**
   - In `c:\laragon\www\Sistema_POS\pos-frontend\lib\features\cash_movements\presentation\widgets\movement_form_dialog.dart`:
     - Lines 108–111 (`initState`):
       ```dart
       WidgetsBinding.instance.addPostFrameCallback((_) {
         context.read<SupplierProvider>().fetchSuppliers();
         context.read<CheckProvider>().loadChecks();
         context.read<ExpenseCategoryProvider>().fetchCategories();
         ...
       });
       ```
     - Lines 437–440 (`build`):
       ```dart
       final checkProv = context.watch<CheckProvider>();
       final availableChecks =
           checkProv.checks.where((c) => c.status == 'in_wallet').toList();
       ```
     - Lines 950–956 (Dropdown items rendering):
       ```dart
       items: availableChecks
           .map((c) => DropdownMenuItem(
                 value: c.id,
                 child: Text(
                     'Nº ${c.checkNumber} (\$ ${c.amount}) - ${c.bankName}'),
               ))
           .toList(),
       ```
     - *Fact:* `availableChecks` only filters checks by `c.status == 'in_wallet'`. It performs no subtraction or exclusion of checks currently in the local `_payments` list.

2. **User Interaction & Addition Path:**
   - In `movement_form_dialog.dart`:
     - Line 69:
       ```dart
       final List<PaymentItem> _payments = [];
       String _currentPaymentMethod = 'cash';
       int? _currentCheckId;
       final _paymentAmountController = TextEditingController();
       ```
     - Lines 957–967 (`onChanged` of check dropdown):
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
     - Lines 150–179 (`_addPayment()`):
       ```dart
       void _addPayment() {
         final amount = double.tryParse(_paymentAmountController.text) ?? 0;
         if (amount <= 0) {
           ScaffoldMessenger.of(context).showSnackBar(
               const SnackBar(content: Text('Ingrese un monto válido.')));
           return;
         }

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
       }
       ```
     - Lines 191–194 (Auto-addition in `_submit()`):
       ```dart
       final pendingAmount = double.tryParse(_paymentAmountController.text) ?? 0;
       if (pendingAmount > 0) {
         _addPayment();
       }
       ```
     - *Fact:* `_addPayment()` contains zero checks to determine whether `_currentCheckId` is already present in `_payments`. `_submit()` blindly auto-adds whatever is pending in `_paymentAmountController`, which re-adds the selected check if the user clicked submit instead of add.

3. **Data Structure & Equality Contract:**
   - In `movement_form_dialog.dart:21-33`:
     ```dart
     class PaymentItem {
       final String method;
       final double amount;
       final int? checkId;
       final ThirdPartyCheck? checkObj;

       PaymentItem({
         required this.method,
         required this.amount,
         this.checkId,
         this.checkObj,
       });
     }
     ```
   - In `c:\laragon\www\Sistema_POS\pos-frontend\lib\features\checks\domain\entities\third_party_check.dart`:
     Neither `PaymentItem` nor `ThirdPartyCheck` overrides `operator ==` or `hashCode`.
   - *Fact:* `_payments` is a raw Dart `List<PaymentItem>` using default reference equality. Checks are compared solely by raw primitive `int? checkId` or object identity.

4. **Debt Balance & Amount Inflation Calculation:**
   - In `movement_form_dialog.dart:144-148`:
     ```dart
     double get _totalAmount {
       final listSum = _payments.fold(0.0, (sum, item) => sum + item.amount);
       final pendingSum = double.tryParse(_paymentAmountController.text) ?? 0;
       return listSum + pendingSum;
     }
     ```
   - In `c:\laragon\www\Sistema_POS\pos-backend\app\Http\Controllers\Api\CashMovementController.php:148-189`:
     ```php
     foreach ($validated['payments'] as $payment) {
         $amount = $payment['amount'];
         $method = $payment['payment_method'];
         $checkId = $payment['check_id'] ?? null;

         $totalAmountPaid += $amount;

         $movement = CashMovement::create([...]);
         $createdMovements[] = $movement;

         if ($method === 'check' && $checkId) {
             $check = ThirdPartyCheck::find($checkId);
             $check->update(['status' => 'endorsed']);
         }
     }

     if (! empty($validated['supplier_id'])) {
         $supplier = Supplier::find($validated['supplier_id']);
         if ($supplier) {
             if (in_array($validated['type'], ['supplier_payment', 'expense'])) {
                 $supplier->decrement('balance', $totalAmountPaid);
             }
         }
     }
     ```
   - In `c:\laragon\www\Sistema_POS\pos-backend\app\Http\Requests\StoreCashMovementRequest.php:48-64`:
     Validates each check in `payments.*.check_id` against the database status (`in_wallet`), but lacks the `'distinct'` rule.
   - *Fact:* When a check of amount $V$ is duplicated $N$ times, `$totalAmountPaid` increments by $N \times V$. The backend decrements the supplier balance by the full inflated amount and generates $N$ separate cash movement rows referencing the same physical check ID.

---

## 2. Logic Chain

1. **From Observation 1:**
   Because `availableChecks` in `movement_form_dialog.dart:438-440` is derived purely from `checkProv.checks.where((c) => c.status == 'in_wallet')`, and because adding a check to the local `_payments` list does not change `CheckProvider.checks` in memory, the check remains in `availableChecks` even after being added to `_payments`.
2. **From Observation 1 & 2:**
   When the user opens the dropdown a second time, the check is still listed as an available, selectable `DropdownMenuItem`. When selected, `_currentCheckId` is set to that check's ID.
3. **From Observation 2:**
   When the user taps "Agregar", `_addPayment()` executes. It only checks `if (_currentCheckId == null)`. It does NOT execute any lookup (such as `_payments.any((p) => p.checkId == _currentCheckId)`). Consequently, `_payments.add()` appends an additional `PaymentItem` with the exact same `checkId`.
4. **From Observation 2 & 3:**
   Because `_payments` is a `List` and not an identity-constrained collection, it holds duplicate elements without error or collision.
5. **From Observation 4:**
   `_totalAmount` computes `_payments.fold(0.0, (sum, item) => sum + item.amount)`. If check #10 ($50,000) is added twice, `_totalAmount` evaluates to $100,000.
6. **From Observation 4:**
   Upon submission, the JSON payload sends `payments: [{check_id: 10, amount: 50000}, {check_id: 10, amount: 50000}]`.
7. **From Observation 4:**
   Backend `StoreCashMovementRequest` validates both elements independently. Both point to check #10 which is `in_wallet` at the time of validation. The request passes validation because `'distinct'` is missing.
8. **From Observation 4:**
   Backend `CashMovementController` processes both elements in a loop, adds both to `$totalAmountPaid` ($100,000), decrements `suppliers.balance` by $100,000, and creates two `CashMovement` rows pointing to `check_id = 10`. If the vendor was owed $50,000, their balance becomes -$50,000 ("Saldo a favor"), artificially extinguishing debt and corrupting financial statements.

---

## 3. Caveats

1. **Read-Only Scope:** Investigation was conducted strictly via static code analysis without executing runtime mutations against production databases or modifying application source files.
2. **Other Dialogs:** Customer checkout (`checkout_dialog.dart` & `check_form_widget.dart`) accepts *new* checks from clients and writes them to the wallet (`in_wallet`). It does not select from existing portfolio checks; thus, the duplicate portfolio check bug is uniquely localized to `movement_form_dialog.dart`.
3. **Backend Scope:** While the primary mission is frontend Flutter analysis, the backend request validation gap in `StoreCashMovementRequest.php` was identified and documented to provide full-stack defense in depth.

---

## 4. Conclusion

The root cause of requirement R2 (Duplicate Check Bug) is the combination of:
1. **Flawed Available Checks Filtering:** `movement_form_dialog.dart:438-440` fails to subtract checks already present in `_payments`.
2. **Absence of Deduplication Guard:** `movement_form_dialog.dart:158-179` (`_addPayment`) lacks a check-existence condition.
3. **Blind Auto-Addition & Unvalidated Submission:** `movement_form_dialog.dart:191-194` auto-adds pending selections without duplicate checking, and `_submit()` lacks a check ID uniqueness assertion.

### Concrete Remediation:
1. **UI Layer:** Filter `availableChecks = checkProv.checks.where((c) => c.status == 'in_wallet' && !selectedCheckIds.contains(c.id)).toList();` where `selectedCheckIds = _payments.where((p) => p.method == 'check' && p.checkId != null).map((p) => p.checkId!).toSet();`.
2. **Controlled Dropdown:** Bind dropdown with `value: availableChecks.any((c) => c.id == _currentCheckId) ? _currentCheckId : null`.
3. **Addition Guard:** Insert `if (_payments.any((p) => p.method == 'check' && p.checkId == _currentCheckId)) return;` in `_addPayment()`.
4. **Submission Guard:** Enforce `checkIds.length == checkIds.toSet().length` before submitting payload.
5. **Removal Behavior:** Freeing a check in `_removePayment()` automatically and reactively restores it to `availableChecks` on the next frame.

---

## 5. Verification Method

### Automated Test Command:
To independently verify the test suite and logic:
```powershell
flutter test test/features/cash_movements/widgets/duplicate_check_test.dart
```

### Static Inspection Verification:
1. Inspect `lib/features/cash_movements/presentation/widgets/movement_form_dialog.dart`:
   - Line 69: Declaration of `_payments`.
   - Lines 158–179: Absence of duplicate validation in `_addPayment()`.
   - Lines 438–440: Definition of `availableChecks`.
   - Lines 944–969: Dropdown rendering.
2. Invalidation Condition:
   - If `availableChecks` excludes `selectedCheckIds`, a check that is added to `_payments` disappears from the dropdown.
   - If an attempt is made to call `_addPayment()` with an already-added `checkId`, the addition is aborted and a warning is displayed.

---
*Report completed and filed at:*  
`c:\laragon\www\Sistema_POS\pos-frontend\.agents\teamwork\teamwork_preview_explorer_survey_2\handoff.md`
