## 2026-09-28T02:16:30Z
You are teamwork_preview_worker_tests.
Your assigned working directory is:
c:\laragon\www\Sistema_POS\pos-frontend\.agents\teamwork\teamwork_preview_worker_tests

CRITICAL FIRST STEP:
Read the authoritative user request at:
c:\laragon\www\Sistema_POS\pos-frontend\.agents\teamwork\ORIGINAL_REQUEST.md
Also read the project architecture at:
c:\laragon\www\Sistema_POS\pos-frontend\PROJECT.md
And read the comprehensive survey reports:
- c:\laragon\www\Sistema_POS\pos-frontend\.agents\teamwork\teamwork_preview_explorer_survey_1\analysis.md
- c:\laragon\www\Sistema_POS\pos-frontend\.agents\teamwork\teamwork_preview_explorer_survey_2\analysis.md
- c:\laragon\www\Sistema_POS\pos-frontend\.agents\teamwork\teamwork_preview_explorer_survey_3\analysis.md

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

WRITE OWNERSHIP:
You own exclusively:
- Files in `c:\laragon\www\Sistema_POS\pos-frontend\test\features\cash_movements\`
- Files inside `c:\laragon\www\Sistema_POS\pos-frontend\.agents\teamwork\teamwork_preview_worker_tests\`
DO NOT modify any file inside `lib/` (the application code is in Read-Only audit mode).

YOUR MISSION (Requirement R5):
Create professional Flutter automated tests that:
1. Formally reproduce the payment logic bugs:
   - Duplicate Check Bug: reproduce how absence of filtering allows selecting the same check twice and how duplicate check items inflate `_totalAmount` and create duplicate payment payloads.
   - Check Face-Value Decoupling: reproduce how "Pagar Restante" logic overwrites check nominal values.
   - Comma-decimal parsing failure: reproduce how `double.tryParse('150,50')` fails without comma normalization.
   - State desynchronization on supplier change: reproduce how payments are preserved across supplier changes.
2. Formally verify the proposed fixes and defensive logic:
   - Verify that subtracting selected checks from available checks prevents duplicate selection.
   - Verify that adding a defensive guard `if (_payments.any((p) => p.checkId == checkId)) return;` rejects duplicate check addition.
   - Verify that locking check amount to `checkObj.amount` prevents face value tampering.
   - Verify that normalized parsing (`text.replaceAll(',', '.')`) correctly parses Argentine format numbers.
   - Verify that resetting payments on supplier switch isolates supplier ledger entries.

RUN & VERIFY:
Execute the tests using `run_command` (e.g. `flutter test test/features/cash_movements/...`). Ensure all written tests execute and PASS cleanly.
Document the exact command line, test output, pass count, and execution time in your `handoff.md`.

Deliver a 5-component handoff report in `handoff.md` and notify parent when complete via send_message. Keep `progress.md` updated as your liveness heartbeat.
