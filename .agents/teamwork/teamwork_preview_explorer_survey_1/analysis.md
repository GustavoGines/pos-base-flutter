# Technical Analysis: Supplier Debt Payment & Check Handling Flow (Requirement R1)

**Investigator**: `teamwork_preview_explorer_survey_1` (Architecture & Core Flow Explorer)  
**Date**: 2026-09-28T02:15:00Z  
**Target Repositories**:
- Frontend: `c:\laragon\www\Sistema_POS\pos-frontend`
- Backend: `c:\laragon\www\Sistema_POS\pos-backend`

---

## 1. Executive Summary

This investigation exhaustively audits the core files, state management, UI lifecycles, and backend endpoints governing supplier debt payments ("Abonar a Proveedor") with mixed payment methods (Cash, Checks, Transfers) in the POS ecosystem.

The core UI element is `MovementFormDialog` (`lib/features/cash_movements/presentation/widgets/movement_form_dialog.dart`), which collaborates with `SupplierProvider`, `CheckProvider`, `CashMovementProvider`, `CashRegisterProvider`, and printing services. On the backend, Laravel processes submissions via `CashMovementController@store` validated by `StoreCashMovementRequest`.

### Key Findings
1. **Critical Vulnerability - Duplicate Checks**: `MovementFormDialog` computes `availableChecks` strictly filtering `c.status == 'in_wallet'`. It never filters out checks already added to the local `_payments` list. Furthermore, `_addPayment()` contains no uniqueness check, allowing an operator to append the exact same check multiple times. On the backend, `StoreCashMovementRequest` lacks the `distinct` validation rule on `payments.*.check_id`, causing the transaction in `CashMovementController@store` to execute redundant check endorsements, create multiple movement rows pointing to the same check, and artificially over-decrement supplier debts.
2. **Critical Vulnerability - Check Face-Value Discrepancy**: The "Pagar Total" / "Pagar Restante" button writes the remaining numerical debt directly to `_paymentAmountController.text`. If the user does this while the check payment method is active, `_addPayment()` saves the check with the debt amount rather than the check's actual face value (`checkObj.amount`). Neither frontend nor backend enforces `payment.amount == check.amount`.
3. **Usability / Overpayment Trap**: When opening the dialog with an `initialAmount` from `SuppliersScreen` or `SupplierInvoiceFormDialog`, an initial payment in **Cash** (`PaymentItem(method: 'cash', amount: initialAmount)`) is automatically added to `_payments`. When an operator attempts to pay with a check instead, the cash item remains unless manually deleted, resulting in accidental double payment (Cash + Check).
4. **Desynchronized Providers**: Upon successful payment, `SupplierProvider.fetchSuppliers()` is refreshed, but `CheckProvider.loadChecks()` is omitted. The endorsed check remains in the frontend in-memory wallet as `in_wallet` until an external refresh occurs.

---

## 2. Inventory of Files, Classes, and Line Numbers

### Frontend (`c:\laragon\www\Sistema_POS\pos-frontend`)

| File Path | Class / Interface | Key Methods / Members | Line Reference | Purpose |
|---|---|---|---|---|
| `lib/features/cash_movements/presentation/widgets/movement_form_dialog.dart` | `PaymentItem` | Constructor | L21–33 | Model for itemized payments in the dialog |
| `lib/features/cash_movements/presentation/widgets/movement_form_dialog.dart` | `MovementFormDialog` | `createState()` | L35–53 | Entry widget accepting initial routing parameters |
| `lib/features/cash_movements/presentation/widgets/movement_form_dialog.dart` | `_MovementFormDialogState` | `initState()` | L90–115 | Normalizes type/category, auto-adds initial cash, triggers provider loads |
| `lib/features/cash_movements/presentation/widgets/movement_form_dialog.dart` | `_MovementFormDialogState` | `_totalAmount` (getter) | L144–148 | Computes live sum of `_payments` plus pending input text |
| `lib/features/cash_movements/presentation/widgets/movement_form_dialog.dart` | `_MovementFormDialogState` | `_addPayment()` | L150–179 | Adds a payment item to `_payments` (lacks check deduplication) |
| `lib/features/cash_movements/presentation/widgets/movement_form_dialog.dart` | `_MovementFormDialogState` | `_submit()` | L187–221 | Validates form, auto-appends pending amount, triggers admin PIN if needed |
| `lib/features/cash_movements/presentation/widgets/movement_form_dialog.dart` | `_MovementFormDialogState` | `_executeSubmit()` | L223–432 | Assembles payload, calls API, triggers receipts/drawers, refreshes suppliers |
| `lib/features/cash_movements/presentation/widgets/movement_form_dialog.dart` | `_MovementFormDialogState` | `build()` | L435–1080 | Renders UI, suppliers dropdown, balance box, checks dropdown (L927–969) |
| `lib/features/cash_movements/providers/cash_movement_provider.dart` | `CashMovementProvider` | `createMovement()` | L154–198 | Dispatches POST to `/cash-movements` |
| `lib/features/cash_movements/models/cash_movement_model.dart` | `CashMovementModel` | `fromJson()` | L1–67 | Represents a persisted cash movement |
| `lib/features/checks/presentation/providers/check_provider.dart` | `CheckProvider` | `loadChecks()`, `checks` | L1–53 | Loads checks from repository into memory |
| `lib/features/checks/domain/entities/third_party_check.dart` | `ThirdPartyCheck` | Constructor, `fromJson()` | L1–47 | Data entity representing third-party check carton |
| `lib/features/checks/data/datasources/check_remote_datasource.dart` | `CheckRemoteDataSourceImpl` | `fetchThirdPartyChecks()` | L16–33 | Interacts with GET `/third-party-checks` |
| `lib/features/suppliers/providers/supplier_provider.dart` | `SupplierProvider` | `fetchSuppliers()` | L34–64 | Fetches supplier entities including `balance` |
| `lib/features/suppliers/models/supplier_model.dart` | `Supplier` | Constructor, `fromJson()` | L1–56 | Model representing supplier entity and balance |
| `lib/features/suppliers/presentation/screens/suppliers_screen.dart` | `_SuppliersScreenState` | `_openPaymentForm()` | L38–58 | Opens dialog passing supplier ID, type, and total balance |
| `lib/features/suppliers/presentation/screens/supplier_current_account_screen.dart` | `_SupplierCurrentAccountScreenState` | ElevatedButton onPressed | L220–241 | Opens dialog for current account debt payment |
| `lib/features/suppliers/presentation/widgets/supplier_invoice_form_dialog.dart` | `_SupplierInvoiceFormDialogState` | `_save()` callback | L256–270 | Opens dialog directly after registering new purchase invoice |
| `lib/features/cash_movements/services/cash_movement_pdf_service.dart` | `CashMovementPdfService` | `printSupplierPayment()` | L138–208 | Renders PDF receipt for supplier payment |
| `lib/core/utils/receipt_printer_service.dart` | `ReceiptPrinterService` | `printSupplierPaymentTicket()` | L1120–1260 | Renders thermal ESC/POS receipt for supplier payment |

### Backend (`c:\laragon\www\Sistema_POS\pos-backend`)

| File Path | Class / Module | Key Methods / Handlers | Line Reference | Purpose |
|---|---|---|---|---|
| `routes/api.php` | Routing | `cash-movements` resource | L120–123 | Exposes POST and DELETE `/cash-movements` |
| `routes/api.php` | Routing | `third-party-checks` | L130–131 | Exposes GET and PATCH `/third-party-checks` |
| `app/Http/Requests/StoreCashMovementRequest.php` | `StoreCashMovementRequest` | `rules()` | L24–66 | Validates incoming movement payload |
| `app/Http/Controllers/Api/CashMovementController.php` | `CashMovementController` | `store()` | L103–214 | DB transaction: creates movements, endorses checks, updates supplier debt |
| `app/Http/Controllers/Api/CashMovementController.php` | `CashMovementController` | `destroy()` | L216–260 | Reverses movement, reverts check to `in_wallet`, increments supplier debt |
| `app/Models/CashMovement.php` | `CashMovement` | Model definition | L1–68 | Eloquent model for movement records |
| `app/Models/ThirdPartyCheck.php` | `ThirdPartyCheck` | Model definition | L1–52 | Eloquent model for third party checks |
| `app/Models/Supplier.php` | `Supplier` | Model definition | L1–41 | Eloquent model for suppliers |
| `app/Services/CashShiftService.php` | `CashShiftService` | `closeShift()` | L140–248 | Computes expected cash balance (only cash payments affect drawer) |

---

## 3. End-to-End Lifecycle Analysis

### 3.1 Invocation and Entry Points

The `MovementFormDialog` is reached through 5 primary entry points:

1. **Suppliers List Screen (`suppliers_screen.dart:38–58`)**:
   - Operator clicks "Abonar" or "Cobrar" on a supplier row.
   - Guard check: verifies `cashProv.currentShift != null && cashProv.currentShift!.isOpen`. If closed, displays an orange SnackBar and terminates.
   - Launches `MovementFormDialog` with:
     - `initialSupplierId: supplierId`
     - `initialType: balance > 0 ? 'supplier_payment' : 'deposit'`
     - `initialCategory: balance > 0 ? 'Pago a Proveedor' : 'Cobro de Saldo a Favor'`
     - `initialAmount: balance.abs()`
2. **Supplier Current Account Screen (`supplier_current_account_screen.dart:220–241`)**:
   - Operator clicks "Abonar Saldo" in header action.
   - **Flaw**: Does **not** check if cash shift is open prior to opening the dialog.
   - Passes `initialSupplierId: widget.supplierId`, `initialType: 'supplier_payment'`. Omits `initialAmount`.
3. **Supplier Invoice Form Dialog (`supplier_invoice_form_dialog.dart:256–270`)**:
   - Fired immediately after submitting a new invoice where cash payment is pending (`amountToPay > 0`).
   - Guard check: verifies active shift is open.
   - Passes `initialSupplierId`, `initialType: 'supplier_payment'`, `initialAmount: amountToPay`, `initialCategory: 'Pago a Proveedor'`, and informational `helperText`.
4. **Cash Movements Screen (`cash_movements_screen.dart:63`)**:
   - Fired from FloatingActionButton (`const MovementFormDialog()`). Defaults to `expense`.
5. **POS Cash Register Screen (`pos_screen.dart:1691`)**:
   - Fired from drawer menu (`const MovementFormDialog()`).

### 3.2 State Initialization (`_MovementFormDialogState.initState`)

When initialized:
- `_type` is assigned `widget.initialType ?? 'expense'`.
- `_category` is assigned `widget.initialCategory ?? 'Mercadería'`.
- `_selectedSupplierId` is set to `widget.initialSupplierId`.
- **Pre-populated Cash Item**:
  ```dart
  if (widget.initialAmount != null && widget.initialAmount! > 0) {
    _payments.add(PaymentItem(method: 'cash', amount: widget.initialAmount!));
  }
  ```
  *Consequence*: If the operator opened the dialog intending to pay using checks, a cash payment item for the full debt is already seated in `_payments`.
- Post-frame callbacks execute asynchronously:
  - `SupplierProvider.fetchSuppliers()` (GET `/api/suppliers`)
  - `CheckProvider.loadChecks()` (GET `/api/third-party-checks`)
  - `ExpenseCategoryProvider.fetchCategories()` (GET `/api/expense-categories`)
  - `_loadPrintPreference()` reads local SharedPreferences (`auto_print_cash_movement`).

### 3.3 Supplier Selection & Debt State

When `_type == 'supplier_payment'`:
- Displays a `DropdownButtonFormField<int>` populated with `supplierProv.suppliers`.
- Upon selecting `_selectedSupplierId`, a card is rendered (L656–753) detailing:
  - Debt label (`Deuda Actual` if `balance > 0`, `Saldo a Favor` if `balance < 0`, `Cuenta al día` if `0`).
  - Contact person.
  - Formatted balance: `NumberFormat.currency(symbol: '$').format(supplier.balance.abs())`.
  - Action button: "Pagar Total" or "Pagar Restante" if `balance.abs() > sum(_payments)`.
  - Button logic:
    ```dart
    final listSum = _payments.fold(0.0, (sum, item) => sum + item.amount);
    final remaining = supplier.balance.abs() - listSum;
    _paymentAmountController.text = (remaining % 1 == 0 ? remaining.toInt().toString() : remaining.toStringAsFixed(2));
    ```

### 3.4 Payment Item Management

Payments are stored in `_payments = <PaymentItem>[]`.
Each payment item represents:
```dart
class PaymentItem {
  final String method; // 'cash' | 'transfer' | 'check'
  final double amount;
  final int? checkId;
  final ThirdPartyCheck? checkObj;
}
```

#### The Check Selection Mechanism (L927–969):
1. In `build()`, checks are filtered from provider:
   ```dart
   final availableChecks = checkProv.checks.where((c) => c.status == 'in_wallet').toList();
   ```
2. When method dropdown is `'check'`, a dropdown displays `availableChecks`.
3. Selecting a check sets:
   ```dart
   _currentCheckId = val;
   final check = availableChecks.firstWhere((c) => c.id == val);
   _paymentAmountController.text = check.amount.toString();
   ```
4. Clicking "Agregar" invokes `_addPayment()`:
   ```dart
   void _addPayment() {
     final amount = double.tryParse(_paymentAmountController.text) ?? 0;
     if (amount <= 0) return;
     ThirdPartyCheck? checkObj;
     if (_currentPaymentMethod == 'check') {
       if (_currentCheckId == null) return;
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

### 3.5 Submission Payload Construction & Dispatch

1. **Submission Guard (`_submit()`, L187–221)**:
   - Evaluates `_formKey.currentState!.validate()`.
   - Auto-adds pending amount: if operator typed an amount or selected a check but did not click "Agregar", `_addPayment()` is invoked automatically.
   - Verifies `_payments.isNotEmpty`.
   - If `_type == 'withdrawal'`, prompts for Admin PIN via `AdminPinDialog`.
2. **Payload Formation (`_executeSubmit()`, L248–264)**:
   ```json
   {
     "type": "supplier_payment",
     "category": "Pago a Proveedor",
     "cash_shift_id": 42,
     "expense_category_id": null,
     "description": "Pago factura 001",
     "receipt_number": "REC-9912",
     "supplier_id": 7,
     "payments": [
       {
         "amount": 15000.0,
         "payment_method": "check",
         "check_id": 105
       },
       {
         "amount": 5000.0,
         "payment_method": "cash",
         "check_id": null
       }
     ]
   }
   ```
3. **Dispatch**: Dispatched via `CashMovementProvider.createMovement(data, adminPin: adminPin)`.

### 3.6 Backend Processing (`CashMovementController.php@store`)

1. **Verification of Active Shift**:
   - `shift = CashShiftService->getCurrentShift()`.
   - Fails with HTTP 403 if no shift exists or `shift->status !== 'open'`.
2. **Validation (`StoreCashMovementRequest.php`)**:
   - Validates `payments` is an array with `min:1`.
   - Validates each `payments.*.payment_method` is in `cash,transfer,check`.
   - Validates each `payments.*.amount` is numeric `min:0.01`.
   - For `check`, validates `payments.*.check_id` exists and has `status === 'in_wallet'`.
   - **Omission**: Does **not** validate uniqueness of `payments.*.check_id`.
   - **Omission**: Does **not** validate that `payments.*.amount == check->amount`.
3. **Database Transaction (`DB::transaction`)**:
   - Iterates over `$validated['payments']`:
     - Creates a record in `cash_movements` for every single payment line.
     - If `payment_method == 'check'`, runs:
       `ThirdPartyCheck::find($checkId)->update(['status' => 'endorsed']);`
     - Accumulates `$totalAmountPaid += $amount`.
   - Updates Supplier Debt:
     `$supplier->decrement('balance', $totalAmountPaid);`
4. **Response**: HTTP 201 with `{ "message": "...", "movements": [...] }`.

### 3.7 Post-Submission Actions & Printing

- `SupplierProvider.fetchSuppliers()` is executed to reflect the new balance.
- **Printing Routine (L274–413)**:
  - If thermal printer is configured: invokes `ReceiptPrinterService.instance.printSupplierPaymentTicket(...)`.
  - If A4/PDF is configured: invokes `CashMovementPdfService.printSupplierPayment(...)`.
  - If payment included cash (`hasCash`), executes `openCashDrawer(localTerminal)`.
  - Printing errors are wrapped in non-blocking try-catch blocks and notify via SnackBar without aborting.
- Dialog closes via `Navigator.of(context).pop()`.

---

## 4. Deep Dive into Architectural Bugs & Flaws

```
+---------------------------------------------------------------------------------------------------+
|                                 IDENTIFIED SYSTEMIC FLAWS                                          |
+----+-------------------------------------------+----------------+---------------------------------+
| #  | Vulnerability Description                 | Severity       | Location                        |
+----+-------------------------------------------+----------------+---------------------------------+
| F1 | Duplicate Check Selection (UI & Backend)  | CRITICAL       | Dialog L438, L150; Backend L49  |
| F2 | Check Amount Tampering / Override         | HIGH           | Dialog L736, L151; Backend L45  |
| F3 | Pre-populated Cash Item Trap              | MEDIUM-HIGH    | Dialog L100–102                 |
| F4 | Incomplete Auto-Add on Submit             | MEDIUM         | Dialog L190–195                 |
| F5 | Stale Check Provider Cache                | MEDIUM         | Dialog L270–273                 |
| F6 | Loss of Check Identity in Receipts/PDF    | MEDIUM         | Dialog L295–301; Printer Serv.  |
| F7 | Orphaned Check Endorsements in DB         | MEDIUM         | CashMovementController L174–177 |
| F8 | Unchecked Shift in Current Account Screen | LOW-MEDIUM     | supplier_current_account_screen |
+----+-------------------------------------------+----------------+---------------------------------+
```

### Detailed Breakdown of Flaws

#### F1. Duplicate Check Selection (Critical)
- **Frontend Observation**: In `movement_form_dialog.dart:438–440`:
  ```dart
  final availableChecks = checkProv.checks.where((c) => c.status == 'in_wallet').toList();
  ```
  `availableChecks` ignores checks already staged in `_payments`. In `_addPayment()` (L150–178), there is no guard condition checking `if (_payments.any((p) => p.checkId == _currentCheckId))`. Consequently, the operator can add Check #12 ($5,000) three times, producing three `PaymentItem`s totaling $15,000.
- **Backend Observation**: In `StoreCashMovementRequest.php:49–64`, each check in `payments.*.check_id` is validated individually against `in_wallet`. Because validation occurs prior to the database transaction, duplicate check IDs in the array all validate successfully as `in_wallet`. In `CashMovementController.php:148–178`, the loop creates 3 distinct `cash_movements` records, each referencing the same check. Supplier balance is decremented by $15,000 instead of $5,000.
- **Annulling Hazard (`destroy()` L236–241)**: If one of the duplicated movements is annulled, the backend sets the check back to `in_wallet`, leaving the remaining movements pointing to a check that is marked as "in wallet".

#### F2. Check Amount Tampering / Override (High)
- **Frontend Observation**: When a check is chosen, the amount field is disabled (`enabled: _currentPaymentMethod != 'check'`), and `_paymentAmountController.text = check.amount.toString()`. However, the "Pagar Total / Restante" button (L732–740) directly overwrites `_paymentAmountController.text` with the remaining debt balance without checking if the current payment method is `'check'`.
- When "Agregar" is clicked, `_addPayment()` reads `amount = double.tryParse(_paymentAmountController.text)`, creating a `PaymentItem` with `method: 'check'`, `checkId: 105`, but an amount decoupled from the check's face value.
- **Backend Observation**: `StoreCashMovementRequest.php` validates `payments.*.amount => 'numeric|min:0.01'`. It never cross-checks that `payment.amount == ThirdPartyCheck::find($checkId)->amount`. The check is endorsed, but the movement amount differs from the check carton.

#### F3. Pre-populated Cash Item Trap (Medium-High)
- **Frontend Observation**: In `suppliers_screen.dart:54` and `supplier_invoice_form_dialog.dart:265`, `initialAmount` is passed into `MovementFormDialog`.
- In `movement_form_dialog.dart:100–102`:
  ```dart
  if (widget.initialAmount != null && widget.initialAmount! > 0) {
    _payments.add(PaymentItem(method: 'cash', amount: widget.initialAmount!));
  }
  ```
- If an operator intended to pay with a check or bank transfer, they find an existing cash payment in the list. Unless they manually tap the trash icon on the Cash row, the check payment is added alongside it, doubling the payment and deducting cash from the cash register shift.

#### F4. Incomplete Auto-Add on Submit (Medium)
- **Frontend Observation**: In `movement_form_dialog.dart:190–195`:
  ```dart
  final pendingAmount = double.tryParse(_paymentAmountController.text) ?? 0;
  if (pendingAmount > 0) {
    _addPayment();
  }
  ```
- If the operator selects `'check'` as the payment method, but does not select a check from the dropdown, and `_paymentAmountController.text` has leftover text (e.g. from pressing "Pagar Total"), `_submit()` calls `_addPayment()`.
- `_addPayment()` checks `if (_currentCheckId == null)` and returns early without adding the payment. However, `_submit()` does not inspect the outcome of `_addPayment()` and proceeds with `_executeSubmit()`, submitting the transaction without the intended payment.

#### F5. Stale Check Provider Cache (Medium)
- **Frontend Observation**: After `createMovement()` succeeds (L270–273), the dialog calls `supplierProvider.fetchSuppliers()`. It does **not** call `context.read<CheckProvider>().loadChecks()`.
- If the operator navigates to the Check Wallet (`CheckWalletScreen`), the endorsed check will continue to be listed as `in_wallet` until a manual swipe-to-refresh or screen remount occurs.

#### F6. Loss of Check Identity in Receipts and PDFs (Medium)
- **Frontend Observation**: In `movement_form_dialog.dart:295–301`:
  ```dart
  final paymentMaps = _payments.map((p) => <String, dynamic>{
    'payment_method': p.method,
    'amount': p.amount,
  }).toList();
  ```
  `p.checkObj?.checkNumber` and `p.checkObj?.bankName` are stripped.
- In `ReceiptPrinterService.dart:1236–1240` and `CashMovementPdfService.dart:370–385`, the receipts print only `CHEQUE: $5,000.00`, leaving out which check (number, issuing bank) was delivered to the supplier.

#### F7. Orphaned Check Endorsements in DB (Medium)
- **Backend Observation**: The `third_party_checks` database table includes `supplier_id` (foreign key) and `endorsement_note` (added in migration `2026_04_23_202842_add_endorsement_note_to_third_party_checks_table.php`).
- In `CashMovementController.php:175–177`:
  ```php
  $check = ThirdPartyCheck::find($checkId);
  $check->update(['status' => 'endorsed']);
  ```
  It does not assign `$check->supplier_id = $validated['supplier_id']`, nor does it record an endorsement note. The check becomes endorsed in the database without any record on the check entity of who it was endorsed to.

#### F8. Unchecked Shift in Current Account Screen (Low-Medium)
- **Frontend Observation**: `suppliers_screen.dart:40` verifies `cashProv.currentShift != null && cashProv.currentShift!.isOpen` before launching `MovementFormDialog`.
- In `supplier_current_account_screen.dart:229–237`, the button launches `MovementFormDialog` unconditionally. If the shift is closed, the user completes data entry only to receive a backend 403 error upon clicking "Procesar Movimiento".

---

## 5. Complete Sequence Flow Diagram

```
[Operator]         [MovementFormDialog]          [Providers]              [Backend API]
    |                       |                         |                         |
    |-- Click "Abonar" ---->|                         |                         |
    |                       |-- initState() --------->|                         |
    |                       |   auto-add Cash if init |                         |
    |                       |-- postFrame ------------> fetchSuppliers() ------>| GET /suppliers
    |                       |                          loadChecks() ----------->| GET /third-party-checks
    |                       |<------------------------- Return data ------------|
    |                       |                                                   |
    |-- Select Method Check |                                                   |
    |-- Choose Check #5 --->| Filter: status=='in_wallet'                       |
    |                       | Set amount = check.amount                         |
    |-- Click "Agregar" --->| Lacks deduplication check!                        |
    |                       | Append to _payments                               |
    |                       |                                                   |
    |-- Choose Check #5 --->| [BUG] Check #5 is STILL in dropdown!              |
    |-- Click "Agregar" --->| [BUG] Duplicate Check #5 appended to _payments!   |
    |                       |                                                   |
    |-- Click "Procesar" -->| _submit() -> _executeSubmit()                     |
    |                       | Format payload {payments: [check#5, check#5]}     |
    |                       |-------------------------------------------------->| POST /cash-movements
    |                       |                                                   | - Validate (missing distinct!)
    |                       |                                                   | - Begin DB Transaction
    |                       |                                                   | - Insert CashMovement 1 ($check#5)
    |                       |                                                   | - Insert CashMovement 2 ($check#5)
    |                       |                                                   | - Endorse Check #5
    |                       |                                                   | - Decrement Supplier Balance (2x!)
    |                       |                                                   | - Commit DB Transaction
    |                       |<------------------ 201 Created -------------------|
    |                       |                                                   |
    |                       |-- fetchSuppliers() ------------------------------>| GET /suppliers
    |                       |   [BUG] Omits loadChecks()!                       |
    |                       |-- Print Ticket / PDF                              |
    |                       |-- Navigator.pop()                                 |
    |<-- Closes dialog -----|                                                   |
```

---

## 6. Concrete Remediation Guidelines

1. **Frontend Check Deduplication**:
   - Filter `availableChecks`:
     ```dart
     final availableChecks = checkProv.checks
         .where((c) => c.status == 'in_wallet' && !_payments.any((p) => p.checkId == c.id))
         .toList();
     ```
   - In `_addPayment()`, guard against duplicates:
     ```dart
     if (_currentPaymentMethod == 'check') {
       if (_currentCheckId == null) { ... return; }
       if (_payments.any((p) => p.checkId == _currentCheckId)) {
         ScaffoldMessenger.of(context).showSnackBar(
           const SnackBar(content: Text('Este cheque ya ha sido agregado.')));
         return;
       }
     }
     ```
2. **Prevent Check Amount Alteration**:
   - In the "Pagar Total / Restante" button callback:
     ```dart
     if (_currentPaymentMethod == 'check') {
       ScaffoldMessenger.of(context).showSnackBar(
         const SnackBar(content: Text('El monto de un cheque está determinado por su valor nominal.')));
       return;
     }
     ```
   - In `_addPayment()`, ensure:
     ```dart
     final paymentAmount = _currentPaymentMethod == 'check' ? checkObj!.amount : amount;
     ```
3. **Backend Validation Hardening**:
   - In `StoreCashMovementRequest.php`:
     ```php
     'payments.*.check_id' => [
         'nullable',
         'integer',
         'distinct',
         'required_if:payments.*.payment_method,check',
         function ($attribute, $value, $fail) use ($request) {
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
   - Also validate that for every payment where `payment_method === 'check'`, `payment.amount == check.amount`.
4. **Backend Endorsement Traceability**:
   - In `CashMovementController.php@store`:
     ```php
     if ($method === 'check' && $checkId) {
         $check = ThirdPartyCheck::find($checkId);
         $check->update([
             'status' => 'endorsed',
             'supplier_id' => $validated['supplier_id'] ?? null,
             'endorsement_note' => 'Endosado en Movimiento de Caja a Proveedor #' . ($validated['supplier_id'] ?? 'N/A'),
         ]);
     }
     ```
5. **Provider Synchronization**:
   - In `movement_form_dialog.dart:_executeSubmit`:
     ```dart
     if (mounted) {
       if (_selectedSupplierId != null) {
         supplierProvider.fetchSuppliers();
       }
       context.read<CheckProvider>().loadChecks();
     }
     ```
