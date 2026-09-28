# Project: Software Forensic Audit Squad — "Abonar a Proveedor con Cheques"

## Architecture
- **Frontend Architecture (`pos-frontend`)**:
  - Presentation Layer: `MovementFormDialog` in `lib/features/cash_movements/presentation/widgets/movement_form_dialog.dart` (1,082 lines).
  - State Management: Uses `Provider` (`ChangeNotifierProvider`). Listens to `SupplierProvider`, `CheckProvider`, `CashRegisterProvider`, `ExpenseCategoryProvider`, `CashMovementProvider`.
  - Data Flow: User interacts with dialog -> Local `_payments` (`List<PaymentItem>`) tracks payment lines -> Submits JSON payload with `payments` array to `CashMovementProvider.createMovement()`.
  - Entry Points:
    1. `SuppliersScreen` (`lib/features/suppliers/presentation/screens/suppliers_screen.dart:47`)
    2. `SupplierCurrentAccountScreen` (`lib/features/suppliers/presentation/screens/supplier_current_account_screen.dart:230`)
    3. `SupplierInvoiceFormDialog` (`lib/features/suppliers/presentation/widgets/supplier_invoice_form_dialog.dart:259`)
- **Backend Architecture (`pos-backend`)**:
  - Controller: `CashMovementController.php` (`app/Http/Controllers/Api/CashMovementController.php:148-190`).
  - Validation: `StoreCashMovementRequest.php` (`app/Http/Requests/StoreCashMovementRequest.php:44-65`).
  - Models & Relations: `CashMovement`, `ThirdPartyCheck`, `Supplier`.
  - Processing: Unrolls `payments` array, creates a `CashMovement` per item, updates `ThirdPartyCheck` to `status = 'endorsed'`, and decrements `Supplier` balance by total paid amount.

## Feature Inventory
| # | Feature / Bug Area | Description | Milestone | Source |
|---|--------------------|-------------|-----------|--------|
| 1 | R1: Core Flow Mapping | Static code analysis of `movement_form_dialog.dart`, providers, controllers, and backend endpoints | M1 | Survey |
| 2 | R2: Duplicate Check Selection | Root cause: `availableChecks` does not exclude selected check IDs, `_addPayment` lacks deduplication guard, backend lacks `distinct` validation | M1, M2, M3 | Survey |
| 3 | R2: Check List Subtraction & Controlled Picker | Solution: Subtract `selectedCheckIds` from `availableChecks`, bind dropdown value defensively, guard `_addPayment` | M2, M3 | Survey |
| 4 | R3: Check Value Decoupling / Tampering | "Pagar Restante" overwrites check face value in controller; backend lacks face-value check | M1, M2, M3 | Survey |
| 5 | R3: Overpayment & Vuelto Handling | Checks exceeding supplier debt decrease balance below zero without registering cash drawer change | M2, M3 | Survey |
| 6 | R3: Silent Input Discard | Negative amounts or comma decimals (`100,50`) silently dropped on submit if another payment exists | M2, M3 | Survey |
| 7 | R3: Supplier Change Desynchronization | Changing supplier retains previously added payments, risking payment misallocation | M2, M3 | Survey |
| 8 | R3: Movement Type HTTP 422 Bug | Changing type to `expense` retains `_selectedSupplierId`, violating backend's `prohibited_if:type,expense` | M2, M3 | Survey |
| 9 | R3: Provider Cache Invalidation | `CheckProvider.loadChecks()` not refreshed after payment creation, leaving endorsed check in memory | M2, M3 | Survey |
| 10 | R3: Traceability Gap on Endorsed Checks | Backend sets check status to `endorsed` but leaves `supplier_id` unassigned | M2 | Survey |
| 11 | R4: Comprehensive Remediation Report | Exhaustive forensic report specifying exact lines of code, diffs, architectural analysis, and mitigation | M2 | User Request |
| 12 | R5: Reproduction & Verification Tests | Professional Flutter unit/widget tests covering duplicate check bug and mixed payment logic | M3 | User Request |
| 13 | Audit & Verification Gate | Independent review, challenge stress-testing, and forensic integrity audit before delivery | M4 | Methodology |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M1 | Survey & Technical Investigation | Exhaustive static analysis across frontend & backend for R1, R2, R3 | none | DONE |
| M2 | Forensic Remediation Report (R4) | Author comprehensive `REMEDIATION_REPORT.md` with exact lines, root causes, diffs, and security hardening | M1 | DONE |
| M3 | Reproduction & Verification Tests (R5) | Implement Flutter automated tests reproducing bugs and verifying proposed fixes | M1 | DONE |
| M4 | Review, Challenge & Integrity Audit | 2 Reviewers + 2 Challengers + 1 Forensic Auditor gate verification | M2, M3 | DONE |
| M5 | Final Victory Claim & Reporting | Synthesize deliverables and report to Sentinel | M4 | IN_PROGRESS |

## Interface Contracts
### `movement_form_dialog.dart` ↔ `CashMovementProvider` / Backend API
- **Endpoint**: `POST /api/cash-movements`
- **Payload Schema**:
  ```json
  {
    "type": "supplier_payment",
    "category": "Pago a Proveedor",
    "cash_shift_id": 1,
    "expense_category_id": null,
    "description": "Pago factura 0001",
    "receipt_number": "REC-001",
    "supplier_id": 5,
    "payments": [
      {
        "amount": 50000.0,
        "payment_method": "check",
        "check_id": 12
      },
      {
        "amount": 15000.0,
        "payment_method": "cash",
        "check_id": null
      }
    ]
  }
  ```
- **Constraints**:
  - `payments.*.check_id`: Must be distinct, must exist in `third_party_checks` with `status = 'in_wallet'`.
  - `payments.*.amount`: For `payment_method = 'check'`, must strictly equal `ThirdPartyCheck.amount`.
  - `supplier_id`: Required if `type = 'supplier_payment'`, strictly prohibited if `type = 'expense'`.

## Code Layout
- Frontend Dialog: `lib/features/cash_movements/presentation/widgets/movement_form_dialog.dart`
- Check Entity & Provider: `lib/features/checks/domain/entities/third_party_check.dart`, `lib/features/checks/presentation/providers/check_provider.dart`
- Cash Movement Provider: `lib/features/cash_movements/presentation/providers/cash_movement_provider.dart`
- Supplier Provider: `lib/features/suppliers/presentation/providers/supplier_provider.dart`
- Backend Controller: `pos-backend/app/Http/Controllers/Api/CashMovementController.php`
- Backend Request: `pos-backend/app/Http/Requests/StoreCashMovementRequest.php`
- Remediation Report Target: `REMEDIATION_REPORT.md` (or `.agents/teamwork/REMEDIATION_REPORT.md` / `c:\laragon\www\Sistema_POS\pos-frontend\REMEDIATION_REPORT.md`)
- Test Targets: `test/features/cash_movements/presentation/widgets/movement_form_dialog_test.dart` and `test/features/cash_movements/payment_items_logic_test.dart`
