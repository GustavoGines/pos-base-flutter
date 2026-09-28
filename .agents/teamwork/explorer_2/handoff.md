# Forensic Backend Audit & Handoff Report

**Target Workspace:** `c:\laragon\www\Sistema_POS\pos-backend`  
**Reporter:** `explorer_2` (Backend Codebase Explorer)  
**Date:** 2026-09-28  
**Scope:** Investigation of backend validation rules, transactional locking, check endorsement lifecycle, batch identifiers, database schemas, and regression tests.

---

## 1. Observation

### 1.1 `StoreCashMovementRequest.php` (Validation Layer)
- **File:** `pos-backend/app/Http/Requests/StoreCashMovementRequest.php:24–66`
- **Verbatim Current Implementation:**
  ```php
  24:     public function rules(): array
  25:     {
  26:         return [
  27:             'type' => ['required', 'string', 'in:expense,withdrawal,deposit,supplier_payment'],
  28:             'expense_category_id' => ['nullable', 'integer', 'exists:expense_categories,id'],
  29:             'category' => ['nullable', 'string', 'max:100'],
  30:             'description' => ['nullable', 'string', 'max:500'],
  31:             'receipt_number' => ['nullable', 'string', 'max:100'],
  32:             'receipt_file_url' => ['nullable', 'string', 'max:255'],
  33: 
  34:             // Proveedor
  35:             'supplier_id' => [
  36:                 'nullable',
  37:                 'integer',
  38:                 'exists:suppliers,id',
  39:                 'required_if:type,supplier_payment',
  40:                 'prohibited_if:type,expense',
  41:             ],
  42: 
  43:             // Array de pagos (para pagos mixtos)
  44:             'payments' => ['required', 'array', 'min:1'],
  45:             'payments.*.amount' => ['required', 'numeric', 'min:0.01'],
  46:             'payments.*.payment_method' => ['required', 'string', 'in:cash,transfer,check'],
  47: 
  48:             // Validación específica si el pago incluye cheque
  49:             'payments.*.check_id' => [
  50:                 'nullable',
  51:                 'integer',
  52:                 'required_if:payments.*.payment_method,check',
  53:                 // El cheque debe existir y estar in_wallet
  54:                 function ($attribute, $value, $fail) {
  55:                     if ($value) {
  56:                         $check = ThirdPartyCheck::find($value);
  57:                         if (! $check) {
  58:                             $fail('El cheque seleccionado no existe.');
  59:                         } elseif ($check->status !== 'in_wallet') {
  60:                             $fail('El cheque seleccionado ya no se encuentra en cartera.');
  61:                         }
  62:                     }
  63:                 },
  64:             ],
  65:         ];
  66:     }
  ```
- **Observations on Gaps:**
  1. **Line 45 (`payments.*.amount`):** Validates only `'required', 'numeric', 'min:0.01'`. It performs no check against the underlying `ThirdPartyCheck` face value when `payment_method === 'check'`. An arbitrary amount (e.g. $12,000 for a $50,000 check) will pass validation (V-02).
  2. **Lines 49–52 (`payments.*.check_id`):** Lacks the `'distinct'` rule. When multiple payment elements contain the exact same `check_id`, Laravel iterates each element separately. Since the check remains `'in_wallet'` in the database prior to controller transaction commit, each duplicate element passes validation independently (V-01).
  3. **Framework Semantics (`distinct` with `nullable`):** Inspection of `Illuminate\Validation\Validator` (lines 207–232) and `ValidatesAttributes::validateDistinct` (line 881) confirms that `'distinct'` is not an implicit validation rule. For cash or transfer tenders where `check_id` is `null`, the `'nullable'` rule causes the validator to skip all subsequent non-implicit rules (including `'distinct'`). Thus, multiple cash/transfer items (`check_id: null`) will not falsely collide, while duplicated integer check IDs will be flagged and rejected.

---

### 1.2 `CashMovementController.php` (Persistence & Lifecycle Layer)
- **File:** `pos-backend/app/Http/Controllers/Api/CashMovementController.php`
- **Method `store()` (Lines 145–178):**
  ```php
  145:             DB::transaction(function () use ($validated, $shift, $user, $authorizedBy, &$createdMovements) {
  146:                 $totalAmountPaid = 0;
  147: 
  148:                 foreach ($validated['payments'] as $payment) {
  149:                     $amount = $payment['amount'];
  150:                     $method = $payment['payment_method'];
  151:                     $checkId = $payment['check_id'] ?? null;
  152: 
  153:                     $totalAmountPaid += $amount;
  154: 
  155:                     $movement = CashMovement::create([
  156:                         'cash_shift_id' => $shift->id,
  157:                         'user_id' => $user->id,
  158:                         'authorized_by' => $authorizedBy,
  159:                         'supplier_id' => $validated['supplier_id'] ?? null,
  160:                         'check_id' => $checkId,
  161:                         'amount' => $amount,
  162:                         'payment_method' => $method,
  163:                         'type' => $validated['type'],
  164:                         'category' => $validated['category'] ?? null,
  165:                         'expense_category_id' => $validated['expense_category_id'] ?? null,
  166:                         'receipt_file_url' => $validated['receipt_file_url'] ?? null,
  167:                         'description' => $validated['description'] ?? null,
  168:                         'receipt_number' => $validated['receipt_number'] ?? null,
  169:                     ]);
  170: 
  171:                     $createdMovements[] = $movement;
  172: 
  173:                     // Si se usó un cheque, endosarlo
  174:                     if ($method === 'check' && $checkId) {
  175:                         $check = ThirdPartyCheck::find($checkId);
  176:                         $check->update(['status' => 'endorsed']);
  177:                     }
  178:                 }
  ```
- **Observations on `store()` Gaps:**
  1. **Line 175 (TOCTOU Concurrency Race - V-10):** Uses `ThirdPartyCheck::find($checkId)` without pessimistic locking (`lockForUpdate()`) and without verifying `status === 'in_wallet'`. Two simultaneous requests from different cashier terminals can pass request validation concurrently, enter the transaction, and both mark the check endorsed, crediting two suppliers.
  2. **Line 176 (Orphaned Check Endorsements - V-08):** Updates `'status' => 'endorsed'` but leaves `supplier_id` as `NULL` and `endorsement_note` as `NULL`. Commercial and legal traceability to the recipient supplier is lost.
  3. **Lines 145–171 (Batching - V-09):** Each split-tender item generates an isolated `CashMovement` record. No `batch_uuid` is currently generated or stored.
- **Method `destroy()` (Lines 235–241):**
  ```php
  235:                 // Revertir estado del cheque
  236:                 if ($movement->payment_method === 'check' && $movement->check_id) {
  237:                     $check = ThirdPartyCheck::find($movement->check_id);
  238:                     if ($check) {
  239:                         $check->update(['status' => 'in_wallet']);
  240:                     }
  241:                 }
  ```
- **Observations on `destroy()` Gaps:**
  1. **Line 239 (Asymmetric Void Reversal - V-11):** Resets `status` to `'in_wallet'`, but leaves `supplier_id` and `endorsement_note` populated with stale historical data from the voided transaction.

---

### 1.3 Database Schema Verification
- **Command executed:** `php artisan model:show ThirdPartyCheck`
  - Table: `third_party_checks`
  - Columns present:
    - `id` (bigint unsigned)
    - `bank_name` (varchar 255)
    - `check_number` (varchar 255)
    - `amount` (decimal 10,2)
    - `issue_date` (date)
    - `payment_date` (date)
    - `issuer_name` (varchar 255)
    - `issuer_cuit` (varchar 255)
    - `customer_id` (bigint unsigned, nullable)
    - `sale_id` (bigint unsigned, nullable)
    - `supplier_id` (bigint unsigned, nullable, foreign key to `suppliers`) -> **ALREADY EXISTS IN SCHEMA**
    - `cash_shift_id` (bigint unsigned, nullable)
    - `status` (enum: `'in_wallet'`,`'deposited'`,`'endorsed'`,`'rejected'`)
    - `endorsement_note` (varchar 255, nullable) -> **ALREADY EXISTS IN SCHEMA**
    - `created_at`, `updated_at` (datetime)
  - Observer registered: `App\Observers\ThirdPartyCheckObserver@updated`
    - Inspected `app/Observers/ThirdPartyCheckObserver.php:12–20`: The observer explicitly logs `endorsement_note` whenever `status` is updated to `'endorsed'`. Populating `endorsement_note` in `CashMovementController` immediately activates full audit logging!
- **Command executed:** `php artisan model:show CashMovement`
  - Table: `cash_movements`
  - Columns present:
    - `id`, `cash_shift_id`, `user_id`, `authorized_by`, `deleted_by`, `supplier_id`, `check_id`, `amount`, `payment_method`, `type`, `category`, `expense_category_id`, `receipt_file_url`, `description`, `receipt_number`, `created_at`, `updated_at`, `deleted_at`.
  - Column `batch_uuid`: **DOES NOT EXIST** in the MySQL table, nor is it in migrations or `$fillable`.

---

### 1.4 Baseline Test Suite Execution
- **Command executed:** `php artisan test`
- **Result:**
  ```text
  Tests:    199 passed (882 assertions)
  Duration: 17.94s
  ```
- **Observations on Existing Coverage:**
  - `Tests\Feature\ThirdPartyCheckTest`: Tests check listing and basic manual status update (`/api/third-party-checks/{id}/status`).
  - `Tests\Feature\PhaseP3PerformanceAndQualityTest`: Tests cache invalidation for `expense` cash movement.
  - **Zero tests** exist for `type = 'supplier_payment'`.
  - **Zero tests** exist for duplicate check rejection via `distinct`.
  - **Zero tests** exist for check face-value match validation.
  - **Zero tests** exist for check endorsement assignment of `supplier_id` and `endorsement_note`.
  - **Zero tests** exist for void reversal clearing `supplier_id` and `endorsement_note`.

---

## 2. Logic Chain

1. **V-01 (Duplicate Check Selection):**
   - Observation: `StoreCashMovementRequest.php:49–64` does not include `'distinct'` on `payments.*.check_id`.
   - Consequence: An array payload containing `[{amount: 50000, check_id: 10, payment_method: 'check'}, {amount: 50000, check_id: 10, payment_method: 'check'}]` evaluates each element in isolation.
   - Mechanism: Both elements query `ThirdPartyCheck::find(10)` while it is still `'in_wallet'`. Both pass validation.
   - Inference: Adding `'distinct'` to `payments.*.check_id` enforces that the set of check IDs in the request must be unique across all elements, directly preventing duplicate check settlement before database execution begins.

2. **V-02 (Check Face-Value Mutation):**
   - Observation: `StoreCashMovementRequest.php:45` checks only `numeric` and `min:0.01`.
   - Consequence: A payload where `amount = 12000` for a check with face value `$50,000` is accepted by the validator.
   - Mechanism: The controller writes `$movement->amount = 12000`, credits the supplier balance by `$12,000`, and marks the `$50,000` check as `'endorsed'`. The difference ($38,000) is irrevocably lost to accounting reconciliation.
   - Inference: Adding a validator closure on `payments.*.amount` that checks `ThirdPartyCheck::find($checkId)->amount == $value` guarantees that only the exact face value of the physical instrument can be credited.

3. **V-10 (Multi-Terminal Concurrency Race):**
   - Observation: `CashMovementController.php:175` uses `ThirdPartyCheck::find($checkId)` without `lockForUpdate()` and without an explicit `in_wallet` guard.
   - Consequence: In multi-terminal deployments, two concurrent HTTP requests that pass initial validation before either transaction commits will both find the check record and both execute `update(['status' => 'endorsed'])`.
   - Mechanism: Two cashiers settle two separate supplier debts using the exact same physical check.
   - Inference: Acquiring a pessimistic row lock via `ThirdPartyCheck::where('id', $checkId)->lockForUpdate()->first()` inside `DB::transaction()` forces concurrent transactions to serialize. Re-verifying `$check->status === 'in_wallet'` ensures the second transaction aborts with an exception, causing an atomic rollback.

4. **V-08 & V-11 (Traceability & Asymmetric Void Reversal):**
   - Observation: In `store()`, line 176 sets only `status => 'endorsed'`, ignoring `supplier_id` and `endorsement_note` (even though both columns exist in `third_party_checks`). In `destroy()`, line 239 sets `status => 'in_wallet'`, leaving `supplier_id` and `endorsement_note` dangling.
   - Consequence: An endorsed check lacks proof of which supplier received it, and a voided check retains obsolete endorsement metadata upon returning to the active wallet.
   - Inference: Setting `supplier_id` and `endorsement_note` in `store()`, and nulling them out in `destroy()`, establishes symmetric state transitions across the full lifecycle of the check.

5. **V-09 (`batch_uuid` Considerations):**
   - Observation: `batch_uuid` was proposed in `REMEDIATION_REPORT.md` Section 4.8 / 6.3, but the column does not exist in `cash_movements` table or `$fillable`.
   - Consequence: Passing `'batch_uuid' => $batchUuid` directly into `CashMovement::create()` would trigger a SQL error (`Unknown column 'batch_uuid'`).
   - Inference: Generating `$batchUuid = (string) Str::uuid();` within `store()` is safe, but persisting it to `cash_movements` requires an explicit migration (`add_batch_uuid_to_cash_movements_table`) and `$fillable` update, OR passing it into existing metadata fields (such as `description` or response JSON).

---

## 3. Caveats

1. **Database Migration for `batch_uuid`:** The database currently has NO `batch_uuid` column in `cash_movements`. If the implementer wishes to persist `batch_uuid` in the database, a new Laravel migration must be created and executed, and `batch_uuid` must be added to `CashMovement::$fillable`. If schema alterations are restricted, `$batchUuid` can be included in the response payload and movement descriptions without schema changes.
2. **`request()->input(...)` vs `$this->input(...)`:** In `StoreCashMovementRequest`, accessing parent array elements within an attribute closure should use `$this->input("payments.{$index}")` or `$this->all()['payments'][$index]`, which is guaranteed to be available during form request validation.
3. **Float Comparison Precision:** In the check amount validation closure, comparing database decimal values (strings or floats) must use float casting with epsilon tolerance (e.g. `abs((float)$check->amount - (float)$value) > 0.009`) to prevent false positives caused by PHP floating-point representation.
4. **Middleware on `destroy`:** Voiding a cash movement via `DELETE /api/cash-movements/{id}` is protected by `role.or.pin` middleware. Automated tests for `destroy` must provide an authorized session token or admin PIN.

---

## 4. Conclusion & Precise Implementation Plan

The backend codebase is in a clean baseline state (199/199 tests passing), and the necessary database columns (`supplier_id`, `endorsement_note`) already exist on `third_party_checks`. The required modifications are localized to two primary files:

### 4.1 Target 1: `app/Http/Requests/StoreCashMovementRequest.php`

**Exact Insertion Points:**
- **Lines 45–46 (`payments.*.amount`):** Replace single-line rules with a closure verifying face-value equality against `ThirdPartyCheck`.
- **Lines 49–52 (`payments.*.check_id`):** Add `'distinct'` rule.

```php
            // Array de pagos (para pagos mixtos)
            'payments' => ['required', 'array', 'min:1'],
            'payments.*.amount' => [
                'required',
                'numeric',
                'min:0.01',
                function ($attribute, $value, $fail) {
                    $segments = explode('.', $attribute);
                    $index = $segments[1] ?? null;
                    if ($index !== null) {
                        $payment = $this->input("payments.{$index}");
                        if (($payment['payment_method'] ?? null) === 'check' && !empty($payment['check_id'])) {
                            $check = ThirdPartyCheck::find($payment['check_id']);
                            if ($check && abs((float)$check->amount - (float)$value) > 0.009) {
                                $fail("El monto (\${$value}) no coincide con el valor nominal del cheque (\${$check->amount}).");
                            }
                        }
                    }
                },
            ],
            'payments.*.payment_method' => ['required', 'string', 'in:cash,transfer,check'],

            // Validación específica si el pago incluye cheque
            'payments.*.check_id' => [
                'nullable',
                'integer',
                'distinct',
                'required_if:payments.*.payment_method,check',
                // El cheque debe existir y estar in_wallet
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

### 4.2 Target 2: `app/Http/Controllers/Api/CashMovementController.php`

**Exact Insertion Points:**
- **In `store()` (Lines 145–178):**
  - Generate `$batchUuid = (string) \Illuminate\Support\Str::uuid();`.
  - Replace `ThirdPartyCheck::find($checkId)` with `ThirdPartyCheck::where('id', $checkId)->lockForUpdate()->first()`.
  - Add guard: `if (! $check || $check->status !== 'in_wallet') throw new \Exception(...)`.
  - Update check with `status => 'endorsed'`, `supplier_id => $validated['supplier_id'] ?? null`, and detailed `endorsement_note`.
- **In `destroy()` (Lines 235–241):**
  - Reset `status => 'in_wallet'`, `supplier_id => null`, and `endorsement_note => null`.

```php
// In store():
                    // Si se usó un cheque, endosarlo con bloqueo pesimista
                    if ($method === 'check' && $checkId) {
                        $check = ThirdPartyCheck::where('id', $checkId)->lockForUpdate()->first();
                        if (! $check || $check->status !== 'in_wallet') {
                            throw new \Exception("El cheque #{$checkId} ya no se encuentra disponible en cartera.");
                        }
                        $check->update([
                            'status' => 'endorsed',
                            'supplier_id' => $validated['supplier_id'] ?? null,
                            'endorsement_note' => 'Endosado a proveedor en Movimiento #' . $movement->id . ' (' . ($movement->receipt_number ?? 'S/N') . ')',
                        ]);
                    }

// In destroy():
                // Revertir estado del cheque simétricamente
                if ($movement->payment_method === 'check' && $movement->check_id) {
                    $check = ThirdPartyCheck::find($movement->check_id);
                    if ($check) {
                        $check->update([
                            'status' => 'in_wallet',
                            'supplier_id' => null,
                            'endorsement_note' => null,
                        ]);
                    }
                }
```

---

## 5. Verification Method

### 5.1 Test Execution Commands
The implementer and verifier can run the following automated suite:
```bash
# In c:\laragon\www\Sistema_POS\pos-backend:
php artisan test
```

### 5.2 Required New Automated Feature Test Suite
Create `pos-backend/tests/Feature/CashMovementSupplierPaymentTest.php` to independently verify all five vulnerability fixes:

```php
<?php

namespace Tests\Feature;

use App\Models\BusinessSetting;
use App\Models\Customer;
use App\Models\Supplier;
use App\Models\ThirdPartyCheck;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class CashMovementSupplierPaymentTest extends TestCase
{
    use RefreshDatabase;

    protected $admin;
    protected $shift;
    protected $supplier;
    protected $check;

    protected function setUp(): void
    {
        parent::setUp();
        $this->admin = User::factory()->create(['role' => 'admin']);
        $this->actingAsAdmin($this->admin);

        BusinessSetting::updateOrCreate(
            ['key' => 'license_features_dict'],
            ['value' => json_encode(['checks' => true, 'expenses' => true])]
        );

        $this->shift = $this->crearTurnoAbierto(1000.00, $this->admin);
        $this->supplier = Supplier::create([
            'name' => 'Distribuidora Mayorista SA',
            'balance' => 100000.00,
        ]);

        $customer = Customer::create(['name' => 'Cliente Test', 'document_number' => '20123456789']);
        $this->check = ThirdPartyCheck::create([
            'customer_id' => $customer->id,
            'bank_name' => 'Banco Galicia',
            'check_number' => 'CHK-9901',
            'amount' => 50000.00,
            'issue_date' => now(),
            'payment_date' => now(),
            'issuer_name' => 'Empresa Cliente',
            'issuer_cuit' => '30712345678',
            'status' => 'in_wallet',
        ]);
    }

    public function test_v01_rejects_duplicate_check_id_in_payload(): void
    {
        $response = $this->postJson('/api/cash-movements', [
            'type' => 'supplier_payment',
            'supplier_id' => $this->supplier->id,
            'payments' => [
                ['amount' => 50000.00, 'payment_method' => 'check', 'check_id' => $this->check->id],
                ['amount' => 50000.00, 'payment_method' => 'check', 'check_id' => $this->check->id],
            ],
        ]);

        $response->assertStatus(422)
            ->assertJsonValidationErrors(['payments.0.check_id', 'payments.1.check_id']);
    }

    public function test_v02_rejects_mismatched_check_face_value(): void
    {
        $response = $this->postJson('/api/cash-movements', [
            'type' => 'supplier_payment',
            'supplier_id' => $this->supplier->id,
            'payments' => [
                ['amount' => 12000.00, 'payment_method' => 'check', 'check_id' => $this->check->id],
            ],
        ]);

        $response->assertStatus(422)
            ->assertJsonValidationErrors(['payments.0.amount']);
    }

    public function test_v08_v10_endorses_check_with_supplier_and_note(): void
    {
        $response = $this->postJson('/api/cash-movements', [
            'type' => 'supplier_payment',
            'supplier_id' => $this->supplier->id,
            'receipt_number' => 'REC-00123',
            'payments' => [
                ['amount' => 50000.00, 'payment_method' => 'check', 'check_id' => $this->check->id],
                ['amount' => 10000.00, 'payment_method' => 'cash'],
            ],
        ]);

        $response->assertStatus(201);

        $this->check->refresh();
        $this->assertEquals('endorsed', $this->check->status);
        $this->assertEquals($this->supplier->id, $this->check->supplier_id);
        $this->assertStringContainsString('REC-00123', $this->check->endorsement_note);

        $this->supplier->refresh();
        $this->assertEquals(40000.00, (float) $this->supplier->balance);
    }

    public function test_v11_destroy_reverts_check_status_and_clears_supplier(): void
    {
        // 1. Crear pago a proveedor
        $response = $this->postJson('/api/cash-movements', [
            'type' => 'supplier_payment',
            'supplier_id' => $this->supplier->id,
            'receipt_number' => 'REC-00124',
            'payments' => [
                ['amount' => 50000.00, 'payment_method' => 'check', 'check_id' => $this->check->id],
            ],
        ]);
        $response->assertStatus(201);
        $movementId = $response->json('movements.0.id');

        // 2. Anular movimiento
        $delResponse = $this->deleteJson("/api/cash-movements/{$movementId}");
        $delResponse->assertStatus(200);

        // 3. Verificar estado revertido de forma simétrica
        $this->check->refresh();
        $this->assertEquals('in_wallet', $this->check->status);
        $this->assertNull($this->check->supplier_id);
        $this->assertNull($this->check->endorsement_note);

        // 4. Verificar balance de proveedor restaurado
        $this->supplier->refresh();
        $this->assertEquals(100000.00, (float) $this->supplier->balance);
    }
}
```

### 5.3 Invalidation Conditions
- If Laravel's `'distinct'` rule on `payments.*.check_id` fails when multiple cash payments (`check_id: null`) are submitted, `'distinct:ignore_null'` or a custom closure must be used.
- If MySQL deadlocks occur under high load, ensure the pessimistic lock queries records in consistent order (`orderBy('id')`).
