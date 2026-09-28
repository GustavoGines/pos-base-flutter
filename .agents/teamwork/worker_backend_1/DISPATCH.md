## 2026-09-28T03:42:35Z
You are worker_backend_1 (Role: Backend Implementer & Test Engineer).
Working directory: c:\laragon\www\Sistema_POS\pos-frontend\.agents\teamwork\worker_backend_1\

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

EXCLUSIVE WRITE OWNERSHIP:
- c:\laragon\www\Sistema_POS\pos-backend\app\Http\Requests\StoreCashMovementRequest.php
- c:\laragon\www\Sistema_POS\pos-backend\app\Http\Controllers\Api\CashMovementController.php
- c:\laragon\www\Sistema_POS\pos-backend\tests\Feature\CashMovementSupplierPaymentTest.php

DO NOT touch any git commands or create git commits.

Tasks:
1. Read the user request: c:\laragon\www\Sistema_POS\pos-frontend\.agents\teamwork\ORIGINAL_REQUEST.md
2. Read the remediation specification: c:\laragon\www\Sistema_POS\pos-frontend\REMEDIATION_REPORT.md (§6.2, §6.3, §4.7-4.9, §5)
3. Read the backend exploration findings: c:\laragon\www\Sistema_POS\pos-frontend\.agents\teamwork\explorer_2\handoff.md
4. Modify c:\laragon\www\Sistema_POS\pos-backend\app\Http\Requests\StoreCashMovementRequest.php:
   - In 'payments.*.amount', add validation closure to enforce that if payment_method is 'check', the amount matches ThirdPartyCheck::find($checkId)->amount within 0.009 tolerance (V-02).
   - In 'payments.*.check_id', add the 'distinct' rule to prevent duplicate check IDs in the payments array (V-01).
5. Modify c:\laragon\www\Sistema_POS\pos-backend\app\Http\Controllers\Api\CashMovementController.php:
   - In store(): generate $batchUuid = (string) \Illuminate\Support\Str::uuid(); (V-09).
   - In store(): when method is 'check' and checkId is present:
     Use pessimistic locking: ThirdPartyCheck::where('id', $checkId)->lockForUpdate()->first().
     Assert check exists and status === 'in_wallet', throwing Exception if unavailable (V-10).
     Update check with 'status' => 'endorsed', 'supplier_id' => $validated['supplier_id'] ?? null, and 'endorsement_note' with movement reference (V-08).
   - In destroy(): when reverting check payment, update check with 'status' => 'in_wallet', 'supplier_id' => null, and 'endorsement_note' => null (V-11).
6. Create c:\laragon\www\Sistema_POS\pos-backend\tests\Feature\CashMovementSupplierPaymentTest.php with full automated tests as specified in explorer_2/handoff.md §5.2.
7. Run the test suite:
   - In pos-backend: php artisan test tests/Feature/CashMovementSupplierPaymentTest.php
   - Run full php artisan test to ensure 0 regressions.
8. Document exact diffs, test execution outputs, and verification in c:\laragon\www\Sistema_POS\pos-frontend\.agents\teamwork\worker_backend_1\handoff.md.
9. Send completion message back to parent.
