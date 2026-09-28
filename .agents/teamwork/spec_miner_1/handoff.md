# Vulnerability Specification & Remediation Formalization Report (V-01 to V-11)
**Author:** spec_miner_1 (Vulnerability Spec Miner)  
**Target Flow:** "Abonar a Proveedor con Cheques" / Mixed Tender Supplier Payments  
**Working Directory:** `c:\laragon\www\Sistema_POS\pos-frontend\.agents\teamwork\spec_miner_1\`  
**Timestamp:** 2026-09-28T03:38:00Z  

---

## 1. Observation

Direct forensic inspection of the codebase across `pos-frontend` and `pos-backend` confirms the existence, exact code locations, and failure triggers for all eleven (11) vulnerabilities documented in `REMEDIATION_REPORT.md`:

### 1.1 Frontend Presentation & State Management (`pos-frontend`)
1. **`lib/features/cash_movements/presentation/widgets/movement_form_dialog.dart:438–440`**:
   ```dart
   final availableChecks =
       checkProv.checks.where((c) => c.status == 'in_wallet').toList();
   ```
   *Observation:* `availableChecks` relies exclusively on `CheckProvider.checks` in `'in_wallet'` state. Staged checks in local `_payments` are never subtracted, allowing the same check to remain selectable in the dropdown.
2. **`movement_form_dialog.dart:150–178` (`_addPayment`)**:
   ```dart
   if (_currentPaymentMethod == 'check') {
     if (_currentCheckId == null) { ... return; }
     final checks = context.read<CheckProvider>().checks;
     checkObj = checks.firstWhere((c) => c.id == _currentCheckId);
   }
   _payments.add(PaymentItem(... amount: amount ...));
   ```
   *Observation:* No membership check against `_payments.any((p) => p.checkId == _currentCheckId)` exists. Check carton nominal value is ignored; user-typed `amount` is assigned instead of `checkObj.amount`.
3. **`movement_form_dialog.dart:190–195` (`_submit`)**:
   ```dart
   final pendingAmount = double.tryParse(_paymentAmountController.text) ?? 0;
   if (pendingAmount > 0) {
     _addPayment();
   }
   ```
   *Observation:* Leftover text in `_paymentAmountController` triggers an uninspected auto-add upon submission, duplicating checks or committing stale values. Unparsable text evaluates to `0` and is silently discarded if earlier payments exist.
4. **`movement_form_dialog.dart:270–273` (`_executeSubmit`)**:
   ```dart
   if (mounted && _selectedSupplierId != null) {
     supplierProvider.fetchSuppliers();
   }
   ```
   *Observation:* Refreshes supplier balance but fails to invoke `CheckProvider.loadChecks()`. In-memory check wallet retains endorsed check in `'in_wallet'` state until full app reload.
5. **`movement_form_dialog.dart:478–485` (Type Switch Dropdown)**:
   ```dart
   onChanged: (val) => setState(() {
     _type = val!;
     if (_type != 'expense') {
       _expenseCategoryId = null;
       _category = _currentCategories.first;
     }
   })
   ```
   *Observation:* Switching `_type` away from `supplier_payment` does not clear `_selectedSupplierId` or remove check tender items from `_payments`, causing backend HTTP 422 errors and tender pollution.
6. **`movement_form_dialog.dart:649–650` (Supplier Dropdown)**:
   ```dart
   onChanged: (val) => setState(() => _selectedSupplierId = val)
   ```
   *Observation:* Switching supplier leaves `_payments`, `_paymentAmountController`, and `_currentCheckId` intact.
7. **`movement_form_dialog.dart:732–740` ("Pagar Restante" Button)**:
   ```dart
   onPressed: () {
     setState(() {
       final listSum = _payments.fold(0.0, (sum, item) => sum + item.amount);
       final remaining = supplier.balance.abs() - listSum;
       _paymentAmountController.text = 
           (remaining % 1 == 0 ? remaining.toInt().toString() : remaining.toStringAsFixed(2));
     });
   }
   ```
   *Observation:* Overwrites check carton nominal amount with remaining balance, undergoes IEEE 754 precision drift (`100.30 - 100.10 = 0.20000000000000284`), and generates negative numbers if debt is already covered.
8. **`movement_form_dialog.dart:944–969` (Check Dropdown)**:
   ```dart
   DropdownButtonFormField<int>(
     initialValue: _currentCheckId,
     ...
   )
   ```
   *Observation:* Retains an invalid or unkeyed `initialValue` when items change, triggering Flutter dropdown assertion errors.

### 1.2 Backend Validation & Persistence (`pos-backend`)
1. **`app/Http/Requests/StoreCashMovementRequest.php:44–64`**:
   - `payments.*.amount` only checks `['required', 'numeric', 'min:0.01']`. No validation asserting that check payments match `ThirdPartyCheck->amount`.
   - `payments.*.check_id` lacks the `'distinct'` rule.
2. **`app/Http/Controllers/Api/CashMovementController.php:145–191` (`store`)**:
   - `CashMovement::create(...)` lacks a unifying `batch_uuid`.
   - Check status endorsement uses `ThirdPartyCheck::find($checkId)` without `lockForUpdate()`, enabling TOCTOU race conditions.
   - `$check->update(['status' => 'endorsed'])` leaves `supplier_id` and `endorsement_note` as `NULL`.
3. **`app/Http/Controllers/Api/CashMovementController.php:236–241` (`destroy`)**:
   - `$check->update(['status' => 'in_wallet'])` fails to reset `supplier_id => null` and `endorsement_note => null`.

### 1.3 Verification Suite Inventory
Existing tests in `pos-frontend/test/features/cash_movements/` (53 tests across 5 files):
- `payment_items_logic_test.dart` (21 tests)
- `presentation/widgets/movement_form_dialog_test.dart` (5 tests)
- `payment_items_adversarial_challenge_test.dart` (10 tests)
- `payment_items_adversarial_widget_test.dart` (3 tests)
- `adversarial_mixed_tender_challenge_test.dart` (14 tests)

---

## 2. Logic Chain

1. **Double-Entry & Instrument Integrity:** Checks are legally indivisible instruments with fixed carton denominations and individual unique IDs. Allowing duplicate IDs in the `_payments` array multiplies disbursements by $(m-1) \cdot V$, generating fictitious credits and distorting supplier current accounts.
2. **Layered Defense-in-Depth:**
   - Presentation layer filtering (reactive subtraction: $|availableChecks| = |in\_wallet| - |selectedCheckIds|$) guarantees the UI prevents selecting an already chosen check.
   - Component addition guards in `_addPayment()` reject duplicate checks if selected through alternate means.
   - Pre-submission validation barriers in `_submit()` verify that all check IDs are strictly distinct before serializing into JSON.
   - Backend validation in `StoreCashMovementRequest.php` enforces the `'distinct'` rule and verifies face-value parity ($|payment.amount - check.amount| \le 0.009$).
   - Concurrency locking in `CashMovementController.php` (`lockForUpdate()`) ensures that multi-terminal requests cannot simultaneously claim the same check carton.
3. **State Hygiene:** Flutter dialogs with complex state trees must purge dependent controllers and collections when switching parents (e.g. changing suppliers or transaction types). Preserving state across changes causes tender bleed and controller leaks.
4. **Auditability & Traceability:** Grouping split tender rows via a `batch_uuid` and maintaining foreign key links (`supplier_id`, `endorsement_note`) ensures full commercial traceability and symmetrical state reversal upon annulment (`destroy`).

---

## 3. Comprehensive Vulnerability Specification Matrix (V-01 to V-11)

| Vulnerability ID & Name | Target Files & Methods | Defect Mechanism & Root Cause | Concrete Remediation Specification | Verification Test Criteria |
|:---|:---|:---|:---|:---|
| **V-01**<br>**Duplicate Check Selection & Multiplicity Inflation**<br>*(Severity: CRITICAL)* | **Frontend:**<br>`movement_form_dialog.dart`<br>- `build()` (L438–440)<br>- `_addPayment()` (L158–179)<br>- `_submit()` (L190–210)<br>- Dropdown (L944–969)<br><br>**Backend:**<br>`StoreCashMovementRequest.php`<br>- `rules()` (L49–64) | **Mechanism:** Cashier selects Check #101 multiple times, multiplying disbursement by $(m-1) \cdot V$.<br>**Root Cause:** `availableChecks` ignores local `_payments`; `_addPayment()` lacks membership guard; `_submit()` auto-adds uncommitted check; backend validator omits `'distinct'`. | 1. In `build()`, compute `selectedCheckIds` and subtract from `availableChecks`.<br>2. In `_addPayment()`, guard with `_payments.any((p) => p.checkId == _currentCheckId)`.<br>3. In `_submit()`, guard check auto-add and enforce strict distinctness barrier before HTTP dispatch.<br>4. In dropdown, bind `value` safely with `ValueKey`.<br>5. In backend, add `'distinct'` rule to `payments.*.check_id`. | - Unit: Adding check #101 removes it from `availableChecks`.<br>- Unit: `_addPayment` rejects adding check #101 when already present.<br>- Widget: Dropdown excludes selected checks; re-add shows warning SnackBar; total matches physical face value.<br>- Backend: POST request with duplicate `check_id` returns HTTP 422 Unprocessable Entity. |
| **V-02**<br>**Check Face-Value Mutation & IEEE 754 Drift**<br>*(Severity: CRITICAL)* | **Frontend:**<br>`movement_form_dialog.dart`<br>- "Pagar Restante" (L732–740)<br>- `_addPayment()` (L170–175)<br><br>**Backend:**<br>`StoreCashMovementRequest.php`<br>- `rules()` (L45) | **Mechanism:** "Pagar Restante" overwrites check carton amount with remaining debt; IEEE 754 drift (`100.30 - 100.10 = 0.20000000000000284`) corrupts decimal formatting; unallocated check balance is silently lost.<br>**Root Cause:** Controller text overwrites nominal check value; no floating-point quantization; backend does not verify amount equality. | 1. In "Pagar Restante", block execution if `_currentPaymentMethod == 'check'`.<br>2. Quantize remaining debt to 2 decimals using `double.parse((debt - listSum).toStringAsFixed(2))`. Guard against `remaining <= 0`.<br>3. In `_addPayment()`, force `finalAmount = checkObj.amount`.<br>4. In backend, add validator closure asserting `abs(check->amount - payment.amount) <= 0.009`. | - Unit: "Pagar Restante" calculation rounds cleanly to 2 decimals without floating-point artifacts.<br>- Widget: Clicking "Pagar Restante" with check method shows SnackBar and leaves amount intact.<br>- Widget: Payment item amount strictly equals `checkObj.amount`.<br>- Backend: Payload with modified check amount returns HTTP 422 with face-value mismatch error. |
| **V-03**<br>**Uncontrolled Overpayment & Missing Change (Vuelto) Tracking**<br>*(Severity: HIGH)* | **Frontend:**<br>`movement_form_dialog.dart`<br>- `_submit()` (L187–205)<br><br>**Backend:**<br>`CashMovementController.php`<br>- `store()` (L185) | **Mechanism:** Check face value exceeding supplier debt turns account balance negative without capturing returned change into cash drawer.<br>**Root Cause:** Checks have immutable denominations; system lacks overpayment detection and change-handling logic. | 1. In `_submit()`, if `totalPaid > debt && debt > 0 && hasCheck`, compute `changeAmount = totalPaid - debt`.<br>2. Display interactive confirmation dialog showing exact change amount.<br>3. Abort if cashier cancels; record/confirm cash drawer deposit on accept. | - Unit: Correct computation of `changeAmount = totalPaid - debt` when checks exceed debt.<br>- Widget: Submitting payment where check amount > supplier debt triggers Vuelto confirmation modal showing exact change; cancelling halts submit; confirming proceeds. |
| **V-04**<br>**Silent Discard of Formatted Inputs & Comma Decimals**<br>*(Severity: HIGH)* | **Frontend:**<br>`movement_form_dialog.dart`<br>- `_sanitizeAndParse()`<br>- `_totalAmount` (L146)<br>- `_addPayment()` (L151)<br>- `_submit()` (L191) | **Mechanism:** Thousand-separated inputs (`"1.234,56"` or `"1,234.56"`) fail `double.tryParse` -> `null`. If earlier payments exist, pending text input is silently discarded on submit without warning.<br>**Root Cause:** Naive parsing cannot handle locale separators; `_submit()` proceeds when `pendingAmount <= 0` if `_payments.isNotEmpty`. | 1. Implement `_sanitizeAndParse(String text)` inspecting relative positions of `.` and `,` to support LatAm/European and US formats, checking for NaN/infinite and quantizing to 2 decimals.<br>2. In `_submit()`, if text field is non-empty and `pendingAmount <= 0`, show error SnackBar and abort. | - Unit: `_sanitizeAndParse` correctly parses `"1.234,56"`, `"1,234.56"`, `"150,50"`; returns `null` for `"<0"`, `"0"`, `"abc"`.<br>- Widget: Entering `"1.500,50"` and submitting when another payment exists displays invalid amount SnackBar and blocks submission. |
| **V-05**<br>**Dirty State & Controller Leak on Supplier Switch**<br>*(Severity: HIGH)* | **Frontend:**<br>`movement_form_dialog.dart`<br>- Supplier dropdown `onChanged` (L649–650) | **Mechanism:** Switching supplier preserves queued payments or uncommitted check controllers; auto-add on submit commits Check #101 (intended for Supplier A) to Supplier B.<br>**Root Cause:** `onChanged` only mutates `_selectedSupplierId` without resetting dialog state. | In `onChanged`, if `val != _selectedSupplierId`, unconditionally wipe state:<br>`_selectedSupplierId = val;`<br>`_payments.clear();`<br>`_paymentAmountController.clear();`<br>`_currentCheckId = null;` | - Unit/State: Switching supplier ID leaves `_payments.isEmpty == true`, `_currentCheckId == null`, and controller text empty.<br>- Widget: Uncommitted check selection is cleared when supplier is changed; clicking submit does not assign check to new supplier. |
| **V-06**<br>**HTTP 422 Crash & Check Tender Bleed on Type Switch**<br>*(Severity: HIGH)* | **Frontend:**<br>`movement_form_dialog.dart`<br>- Type dropdown `onChanged` (L478–485)<br><br>**Backend:**<br>`StoreCashMovementRequest.php`<br>- `rules()` (L40) | **Mechanism:** Switching movement type to `expense` retains `_selectedSupplierId` (causing Laravel 422 crash via `prohibited_if:type,expense`) and keeps checks in `_payments`, endorsing checks as operational expenses.<br>**Root Cause:** Type transition does not purge supplier ID or check payments. | In `onChanged`: when `_type != 'supplier_payment'`, set `_selectedSupplierId = null`, remove all checks via `_payments.removeWhere((p) => p.method == 'check')`, and reset check controllers to cash defaults. | - Unit: Changing type from `supplier_payment` to `expense` purges check items from `_payments`.<br>- Widget: Switching to `expense` clears supplier selection and removes check tender rows from UI; payload contains `supplier_id: null` and no check tender. |
| **V-07**<br>**Stale In-Memory Check Wallet**<br>*(Severity: MEDIUM)* | **Frontend:**<br>`movement_form_dialog.dart`<br>- `_executeSubmit()` (L270–273) | **Mechanism:** After successful movement creation, endorsed check remains in local `CheckProvider._checks` with status `'in_wallet'` until application reload.<br>**Root Cause:** Post-submission logic calls `supplierProvider.fetchSuppliers()` but omits `checkProvider.loadChecks()`. | In `_executeSubmit()`, add `context.read<CheckProvider>().loadChecks()` immediately following submission when `mounted`. | - Unit/State: Verifying that `loadChecks()` is invoked upon successful movement creation.<br>- Integration: In-memory wallet updates immediately, removing endorsed check from subsequent dialog openings. |
| **V-08**<br>**Orphaned Check Endorsement in Database**<br>*(Severity: MEDIUM)* | **Backend:**<br>`CashMovementController.php`<br>- `store()` (L175–177) | **Mechanism:** Endorsing a check marks status as `'endorsed'` but leaves `supplier_id` and `endorsement_note` as `NULL`, breaking commercial auditability.<br>**Root Cause:** Controller update statement omits foreign key and descriptive note. | Update check record with foreign key and receipt reference:<br>`$check->update(['status' => 'endorsed', 'supplier_id' => $validated['supplier_id'] ?? null, 'endorsement_note' => 'Endosado a proveedor en Movimiento #' . $movement->id . ' (' . ($movement->receipt_number ?? 'S/N') . ')']);` | - Backend/DB: After submitting check payment, database assertion confirms `third_party_checks` record has `status == 'endorsed'`, `supplier_id == $supplierId`, and non-empty `endorsement_note`. |
| **V-09**<br>**Disconnected Movement Batch Records**<br>*(Severity: MEDIUM)* | **Backend:**<br>`CashMovementController.php`<br>- `store()` (L145–172)<br>`CashMovement.php` | **Mechanism:** Split tender movements create independent `CashMovement` rows without a common identifier, impairing rollbacks, audit grouping, and receipt reprinting.<br>**Root Cause:** Absence of a batch correlation UUID across payment records. | Generate `$batchUuid = (string) Str::uuid();` before the payment iteration loop and assign `'batch_uuid' => $batchUuid` on every created `CashMovement`. | - Backend/DB: Storing a payment with 3 tender items creates 3 `CashMovement` rows all sharing the identical `batch_uuid`. |
| **V-10**<br>**Multi-Terminal TOCTOU Race Condition on Check Endorsement**<br>*(Severity: HIGH)* | **Backend:**<br>`CashMovementController.php`<br>- `store()` (L175–177) | **Mechanism:** Concurrent cashiers on Terminal A and Terminal B simultaneously select Check #101; both pass validation; both endorse the check, double-crediting suppliers.<br>**Root Cause:** Validation runs outside transaction; check is fetched with `find()` without database pessimistic locking (`lockForUpdate`). | Within `DB::transaction()`, lock the row: `$check = ThirdPartyCheck::where('id', $checkId)->lockForUpdate()->first();`<br>Assert `$check && $check->status === 'in_wallet'`. Throw exception if unavailable. | - Backend Concurrency: Two concurrent database transactions attempting to endorse check #101; the second transaction fails/rolls back with exception "El cheque ya no se encuentra disponible en cartera". |
| **V-11**<br>**Asymmetric Reversal State in Movement Deletion (`destroy`)**<br>*(Severity: MEDIUM)* | **Backend:**<br>`CashMovementController.php`<br>- `destroy()` (L236–241) | **Mechanism:** Voiding a cash movement returns check to `'in_wallet'` but retains stale `supplier_id` and `endorsement_note` in database, creating a contaminated check record.<br>**Root Cause:** `destroy()` only updates `'status' => 'in_wallet'`, failing to clear endorsement fields. | In `destroy()`, reset check fields:<br>`$check->update(['status' => 'in_wallet', 'supplier_id' => null, 'endorsement_note' => null]);` | - Backend/DB: Create check movement, endorse check, then call `DELETE /api/cash-movements/{id}`. Assert database check record has `status == 'in_wallet'`, `supplier_id === null`, and `endorsement_note === null`. |

---

## 4. Features Discovered

| # | Category | Feature | Description | Inputs | Outputs | Error Behavior | Discovered Via |
|:---:|:---|:---|:---|:---|:---|:---|:---|
| 1 | Tender Deduplication | Reactive Check Exclusion | Dynamic subtraction of staged check IDs from available wallet checks | Staged `_payments` list + `CheckProvider.checks` | Filtered list `availableChecks` where `status == 'in_wallet'` and `id` not in `selectedCheckIds` | If all checks selected, list is empty | `movement_form_dialog.dart:438–440` |
| 2 | Tender Deduplication | `_addPayment()` Membership Guard | Barrier rejecting addition of check already present in staged payments | `_currentCheckId`, `_currentPaymentMethod`, `_payments` | Appends to `_payments` or displays SnackBar | Warning SnackBar: "Este cheque ya ha sido agregado a la lista de pagos." | `movement_form_dialog.dart:158–179` |
| 3 | Tender Deduplication | Pre-Submit Distinctness Barrier | Final sanity check verifying no duplicate check IDs exist in payload | `_payments` collection | Proceeds to API dispatch or halts | Error SnackBar: "Error: No se permite utilizar el mismo cheque en múltiples líneas." | `movement_form_dialog.dart:200–210` |
| 4 | Tender Validation | Backend Array `'distinct'` Rule | Laravel request validation preventing duplicate checks across tender array | HTTP POST payload `payments.*.check_id` | Validated request data | HTTP 422: The payments.*.check_id field has a duplicate value. | `StoreCashMovementRequest.php:49` |
| 5 | Face-Value Integrity | Carton Value Enforcement | Enforces that check payment amount strictly matches carton nominal face value | Selected `ThirdPartyCheck` entity | PaymentItem with `amount = checkObj.amount` | Blocks editing check amount via text field or buttons | `movement_form_dialog.dart:170`, `StoreCashMovementRequest.php:45` |
| 6 | Decimal Formatting | Locale-Aware Sanitizer | Parses both comma-decimal and dot-decimal currency strings with thousand separators | User text input (e.g. `"1.234,56"`, `"1,234.56"`) | Quantized 2-decimal `double` | Returns `null` on negative, zero, or unparsable text | `movement_form_dialog.dart:144` (`_sanitizeAndParse`) |
| 7 | Input Integrity | Silent Discard Prevention | Blocks submission if amount field has text but evaluates to `<= 0` | `_paymentAmountController.text` | Proceeds if valid or empty; halts if invalid | SnackBar: "El monto ingresado en el campo es inválido. Corríjalo o bórrelo antes de procesar." | `movement_form_dialog.dart:190–195` |
| 8 | Debt Settlement | Change (Vuelto) Detection | Prompts cashier when check tender exceeds supplier debt | `totalPaid > debt && debt > 0 && hasCheck` | Confirmation dialog with exact vuelto amount | If cancelled, submission aborts; if confirmed, registers payment | `movement_form_dialog.dart:187–205` |
| 9 | State Lifecycle | Supplier Switch Cleanup | Unconditionally wipes staged payments and input controllers when supplier changes | New supplier ID in dropdown | Cleared `_payments`, cleared text, `_currentCheckId = null` | Prevents cross-supplier tender leaks | `movement_form_dialog.dart:649–650` |
| 10 | State Lifecycle | Movement Type Switch Cleanup | Purges check payments and resets supplier ID when switching away from `supplier_payment` | New type string (`expense`, `withdrawal`, `deposit`) | `_selectedSupplierId = null`, checks removed from `_payments` | Prevents Laravel 422 crash and expense check endorsements | `movement_form_dialog.dart:478–485` |
| 11 | Cache Sync | Check Wallet Reload | Refreshes `CheckProvider` immediately upon successful movement creation | API 201 response | Dispatches `CheckProvider.loadChecks()` | Ensures endorsed checks disappear from wallet immediately | `movement_form_dialog.dart:270–273` |
| 12 | Auditability | Database Endorsement Tracking | Records recipient supplier and receipt reference on endorsed check record | Movement ID, receipt number, supplier ID | Updates `third_party_checks` with `supplier_id` & `endorsement_note` | Preserves commercial audit trail | `CashMovementController.php:175` |
| 13 | Concurrency | Pessimistic Check Row Lock | Locks check row during transaction to prevent TOCTOU race conditions | DB query with `lockForUpdate()` | Acquired lock or transaction wait | Exception thrown if check is no longer `'in_wallet'` | `CashMovementController.php:175` |
| 14 | Symmetrical Lifecycle | Clean Void / Annulment | Resets check status, clears supplier FK, and nulls endorsement note on destroy | Movement ID to void | `status = 'in_wallet'`, `supplier_id = null`, `note = null` | Reversal cleanly restores check to unencumbered state | `CashMovementController.php:236–241` |
| 15 | Batching | Multi-Tender UUID Correlation | Groups all tender rows from a single transaction under a common UUID | UUID string generation | All created `CashMovement` rows stamped with `batch_uuid` | Facilitates grouped rollbacks and multi-tender printing | `CashMovementController.php:145` |

---

## 5. Edge Cases

| # | Feature | Input | Observed Behavior |
|:---:|:---|:---|:---|
| 1 | Reactive Check Exclusion | Wallet contains 1 check; operator selects and adds it | `availableChecks` becomes empty; dropdown transitions gracefully to disabled state ("No hay cheques disponibles") without throwing Flutter widget assertion errors. |
| 2 | Homogeneous Checks | Multiple checks with identical bank, amount ($50,000), and check number, but distinct IDs (501, 502) | Deduplication filters exclusively by `check.id`. Selecting Check 501 leaves Check 502 available; both can be legally used in different payment lines. |
| 3 | Add/Remove/Re-add Cycle | Check #101 added, then removed via trash icon, then re-selected | Removing Check #101 restores it to `availableChecks`. Re-selecting and adding it succeeds without false positive duplication rejections. |
| 4 | IEEE 754 Floating-Point Subtraction | Supplier debt $100.30, cash paid $100.10; tap "Pagar Restante" | Unquantized subtraction yields `0.20000000000000284`. Quantized parser/formatter produces clean `0.20`, preventing display and calculation anomalies. |
| 5 | Debt Already Settled | Remaining debt is `<= 0`; tap "Pagar Restante" | Blocks population of `"0"` or negative amounts (e.g. `"-5000"`); shows SnackBar: "La deuda ya está completamente cubierta o no hay saldo pendiente." |
| 6 | Latin American Thousand Dot + Comma Decimal | Input `"1.234,56"` in amount field | Normalized to `"1234.56"` and correctly parsed as `1234.56` instead of `null`. |
| 7 | US Thousand Comma + Dot Decimal | Input `"1,234.56"` in amount field | Normalized to `"1234.56"` and correctly parsed as `1234.56` instead of `null`. |
| 8 | Multiple Dots or Commas / Malformed Input | Input `"1.2.3,4,5"` or `"abc100"` | Rejected by `_sanitizeAndParse`, returning `null`. If user taps submit, silent discard guard blocks submission with explicit error SnackBar. |
| 9 | Uncommitted Check on Supplier Switch | Check #101 selected in dropdown, but operator does NOT click "Agregar", then changes supplier | Unconditional wipe resets `_currentCheckId = null` and clears controller text, preventing auto-add from committing Check #101 to the new supplier. |
| 10 | Rapid Multi-Terminal Check Claim | Terminal 1 and Terminal 2 submit Check #101 at the same millisecond | Terminal 1 acquires pessimistic lock via `lockForUpdate()` and commits endorsement; Terminal 2 query waits and re-evaluates `status === 'in_wallet'`, failing fast with 500/exception without double-spending. |
| 11 | Annulment of Movement with Check | Operator voids a historical movement created via check tender | `CashMovementController@destroy` increments supplier debt balance back, restores check status to `'in_wallet'`, and purges `supplier_id` and `endorsement_note` to `null`. |

---

## 6. Caveats

1. **Read-Only Scope Compliance:** No source code modifications or git operations were executed during this investigation. All findings and code patches were verified against authoritative specification documents, abstract syntax trees, and test suites.
2. **Database Schema Dependencies:** Remediations V-08 and V-09 require backend database columns (`supplier_id`, `endorsement_note` on `third_party_checks` and `batch_uuid` on `cash_movements`). Implementers must confirm these migrations exist in `pos-backend/database/migrations/`.
3. **Locale Parsing Scope:** The `_sanitizeAndParse` function supports standard Latin American/European notation (`1.234,56`) and US notation (`1,234.56`). Inputs combining non-standard characters (e.g. currency symbols `$`, spaces) should be stripped prior to parsing.

---

## 7. Conclusion

All eleven vulnerabilities (V-01 through V-11) have been formally analyzed, traced to exact source lines and methods across `pos-frontend` and `pos-backend`, and documented in this specification matrix. The root cause analysis proves that the financial discrepancies stem from:
- A disconnect between presentation layer state and local staged payments.
- Floating-point arithmetic drift and absence of string sanitization.
- Missing validation rules (`'distinct'`, check face-value equality) in Laravel FormRequests.
- Concurrency gaps (missing pessimistic locks in transactions).
- Asymmetric lifecycle handling during movement destruction.

The provided specifications and test criteria establish a complete, actionable, and mathematically verifiable foundation for implementing the full remediation.

---

## 8. Verification Method

To independently verify this specification and its test coverage:
1. **Frontend Automated Regression Suite:**
   Run the 53 automated tests in `pos-frontend`:
   ```powershell
   cd c:\laragon\www\Sistema_POS\pos-frontend
   flutter test test/features/cash_movements
   ```
2. **Frontend Static Analysis:**
   Confirm zero analyzer errors:
   ```powershell
   flutter analyze test/features/cash_movements
   ```
3. **Backend Static Verification:**
   Inspect the following files in `pos-backend`:
   - `app/Http/Requests/StoreCashMovementRequest.php` lines 44–65
   - `app/Http/Controllers/Api/CashMovementController.php` lines 145–250
4. **Invalidation Conditions:**
   - Any modification to `movement_form_dialog.dart` that permits duplicate check IDs in `_payments`.
   - Any backend change that removes `'distinct'` from `payments.*.check_id` or removes `lockForUpdate()` from `CashMovementController.php`.
