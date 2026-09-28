# Execution Plan: Full-Stack Remediation (V-01 to V-11)

## Stage 1: Survey & Specification Mining
- Dispatch 2 Explorers and 1 Spec Miner to verify the current state of both codebases against `REMEDIATION_REPORT.md`:
  - `explorer_1`: Examine `pos-frontend/lib/features/cash_movements/presentation/widgets/movement_form_dialog.dart` and current tests.
  - `explorer_2`: Examine `pos-backend/app/Http/Requests/StoreCashMovementRequest.php` and `CashMovementController.php`.
  - `spec_miner_1`: Cross-check the 11 vulnerabilities (V-01 through V-11) and extract exact insertion points.

## Stage 2: Implementation (Workers)
- Dispatch `worker_backend_1`: Apply patches to `StoreCashMovementRequest.php` and `CashMovementController.php`. Run syntax check / tests.
- Dispatch `worker_frontend_1`: Apply patches to `movement_form_dialog.dart`. Run flutter analyze / flutter test.

## Stage 3: Verification & Test Suites (Workers / Test Writers)
- Verify frontend test suite (53 tests in `test/features/cash_movements/`).
- Create/run backend automated tests in `pos-backend/tests/` verifying `distinct` check validation, check face value validation, pessimistic locking, batch_uuid, and void reversal.

## Stage 4: Review & Adversarial Challenge
- Dispatch 2 Reviewers (`reviewer_1`, `reviewer_2`) to audit code diffs, interface conformance, and quality.
- Dispatch 2 Challengers (`challenger_1`, `challenger_2`) to test edge cases, race conditions, and UI flows.
- Dispatch 1 Forensic Auditor (`auditor_1`) to perform strict integrity checks.

## Stage 5: Gate & Parent Reporting
- Aggregate verdicts in `GATE_STATUS.md`.
- Ensure all criteria pass (Clean audit, passing tests, Approved reviews).
- Synthesize findings and report completion to parent Sentinel via `send_message`.
