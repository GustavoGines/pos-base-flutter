# Project: Remediation of "Abonar a Proveedor con Cheques" (V-01 to V-11)

## Architecture
- **Frontend (Flutter)**: Presentation layer (`MovementFormDialog`), state management (`CheckProvider`, `SupplierProvider`, `CashMovementProvider`), and output peripherals.
- **Backend (Laravel API)**: Request validation (`StoreCashMovementRequest`), business logic and persistence (`CashMovementController`), models (`CashMovement`, `ThirdPartyCheck`, `Supplier`).
- **Data Flow**: User inputs payments -> Frontend sanitizes, validates, enforces distinct checks and face values -> Dispatches payload to `/api/cash-movements` -> Backend validates (`distinct`, nominal amount match) -> DB transaction with pessimistic locking (`lockForUpdate`), endorsed check metadata (`supplier_id`, `endorsement_note`), batch UUID grouping -> Response -> Frontend refreshes suppliers & checks.

## Feature Inventory
| # | Feature | Description | Milestone | Source | Status |
|---|---------|-------------|-----------|--------|--------|
| 1 | V-01 Duplicate Check Prevention | UI reactive filtering, `_addPayment` guard, pre-submit barrier, backend 'distinct' rule | M1 & M2 | REMEDIATION_REPORT.md §3 | VERIFIED |
| 2 | V-02 Check Face-Value Mutation & Float Drift | Lock "Pagar Restante" on checks, enforce carton face value, quantize remaining debt, backend validation | M1 & M2 | REMEDIATION_REPORT.md §4.1 | VERIFIED |
| 3 | V-03 Overpayment & Vuelto Handling | Detect overpayment when check > debt, prompt confirmation dialog, record cash drawer sync | M2 | REMEDIATION_REPORT.md §4.2 | VERIFIED |
| 4 | V-04 Sanitized Input & Decimal Parsing | Support Argentine/Euro dot-comma and US formats, reject invalid text on submit | M2 | REMEDIATION_REPORT.md §4.3 | VERIFIED |
| 5 | V-05 Reset on Supplier Switch | Unconditionally clear `_payments`, amount controller, and current check when supplier changes | M2 | REMEDIATION_REPORT.md §4.4 | VERIFIED |
| 6 | V-06 Movement Type Switch Protection | Purge checks, reset tender method to cash, clear `_selectedSupplierId` on non-supplier types | M2 | REMEDIATION_REPORT.md §4.5 | VERIFIED |
| 7 | V-07 Stale Check Cache Invalidation | Call `CheckProvider.loadChecks()` in dialog post-submission | M2 | REMEDIATION_REPORT.md §4.6 | VERIFIED |
| 8 | V-08 Orphaned Check Endorsement Fix | Populate `supplier_id` and `endorsement_note` in check update | M1 | REMEDIATION_REPORT.md §4.7 | VERIFIED |
| 9 | V-09 Batch UUID Movement Grouping | Assign common `batch_uuid` to all split-tender cash movements | M1 | REMEDIATION_REPORT.md §4.8 | VERIFIED |
| 10 | V-10 Multi-Terminal Pessimistic Lock | Apply `lockForUpdate()` on check in DB transaction, recheck `in_wallet` | M1 | REMEDIATION_REPORT.md §4.9.1 | VERIFIED |
| 11 | V-11 Asymmetric Reversal on Destroy | Reset `supplier_id => null`, `endorsement_note => null` when voiding check payment | M1 | REMEDIATION_REPORT.md §4.9.2 | VERIFIED |
| 12 | Automated Verification & Testing | Unit, widget, and integration tests for frontend and backend | M3 | REMEDIATION_REPORT.md §7 | VERIFIED |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| 1 | Backend Hardening (M1) | StoreCashMovementRequest.php & CashMovementController.php (V-01, V-02, V-08, V-09, V-10, V-11) | none | DONE |
| 2 | Frontend Hardening (M2) | movement_form_dialog.dart (V-01, V-02, V-03, V-04, V-05, V-06, V-07) | none | DONE |
| 3 | Automated Testing & Verification (M3) | Flutter 71 test suite execution & Backend 217 tests | M1, M2 | DONE |
| 4 | Audit & Challenger Verification (M4) | Adversarial challenge and forensic integrity audit verification | M3 | DONE |

## Interface Contracts
### Frontend -> Backend Payload (`POST /api/cash-movements`)
```json
{
  "type": "supplier_payment",
  "supplier_id": 12,
  "payments": [
    {
      "payment_method": "check",
      "amount": 50000.00,
      "check_id": 101
    },
    {
      "payment_method": "cash",
      "amount": 10000.00
    }
  ]
}
```
- `payments.*.check_id`: Must be unique across the array (`distinct`).
- `payments.*.amount`: For check method, must strictly match `ThirdPartyCheck.amount`.
- Backend returns 201 Created on success, 422 Unprocessable Entity on validation failure, 500/exception on race condition/unavailable check.

## Code Layout
- Frontend: `c:\laragon\www\Sistema_POS\pos-frontend\lib\features\cash_movements\presentation\widgets\movement_form_dialog.dart`
- Backend Request: `c:\laragon\www\Sistema_POS\pos-backend\app\Http\Requests\StoreCashMovementRequest.php`
- Backend Controller: `c:\laragon\www\Sistema_POS\pos-backend\app\Http\Controllers\Api\CashMovementController.php`
- Frontend Tests: `c:\laragon\www\Sistema_POS\pos-frontend\test\features\cash_movements\`
- Backend Tests: `c:\laragon\www\Sistema_POS\pos-backend\tests\`
