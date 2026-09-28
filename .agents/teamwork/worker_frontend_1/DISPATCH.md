## 2026-09-28T03:42:35Z
You are worker_frontend_1 (Role: Frontend Implementer & Test Engineer).
Working directory: c:\laragon\www\Sistema_POS\pos-frontend\.agents\teamwork\worker_frontend_1\

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

EXCLUSIVE WRITE OWNERSHIP:
- c:\laragon\www\Sistema_POS\pos-frontend\lib\features\cash_movements\presentation\widgets\movement_form_dialog.dart
- c:\laragon\www\Sistema_POS\pos-frontend\test\features\cash_movements\presentation\widgets\movement_form_dialog_test.dart
- c:\laragon\www\Sistema_POS\pos-frontend\test\features\cash_movements\adversarial_mixed_tender_challenge_test.dart

DO NOT touch any git commands or create git commits.

Tasks:
1. Read the user request: c:\laragon\www\Sistema_POS\pos-frontend\.agents\teamwork\ORIGINAL_REQUEST.md
2. Read the remediation specification: c:\laragon\www\Sistema_POS\pos-frontend\REMEDIATION_REPORT.md (§6.1, §4.1-4.6, §5)
3. Read the frontend exploration findings: c:\laragon\www\Sistema_POS\pos-frontend\.agents\teamwork\explorer_1\handoff.md
4. Modify c:\laragon\www\Sistema_POS\pos-frontend\lib\features\cash_movements\presentation\widgets\movement_form_dialog.dart:
   - Add _sanitizeAndParse(String text) helper (supporting comma decimals, thousand dots/commas, and returning quantized 2-decimal double).
   - In _totalAmount: use _sanitizeAndParse and round to 2 decimals.
   - In _addPayment():
     - Use _sanitizeAndParse for amount.
     - Add duplicate check guard: check if _payments already contains _currentCheckId for method == 'check'. Show SnackBar if duplicate.
     - Enforce face value: finalAmount is checkObj.amount when method is 'check'.
     - Safe firstWhere on checks list.
   - In _submit():
     - Use _sanitizeAndParse.
     - Guard against silent discard: if text is not empty and pendingAmount <= 0, show error SnackBar and abort.
     - Auto-add: only auto-add check if not already present in _payments.
     - Strict pre-submit barrier: verify checkIds has no duplicates.
     - V-03 overpayment & vuelto handling: if totalPaid > debt and hasCheck, show confirmation AlertDialog for cash vuelto to drawer.
   - In _executeSubmit(): call context.read<CheckProvider>().loadChecks() after supplier fetch.
   - In build(): reactive availableChecks filter: checkProv.checks.where((c) => c.status == 'in_wallet' && !selectedCheckIds.contains(c.id)).toList().
   - In _type dropdown onChanged: if _type != 'supplier_payment', set _selectedSupplierId = null, remove check payments from _payments, reset current check.
   - In _selectedSupplierId dropdown onChanged: unconditionally clear _payments, clear _paymentAmountController, and null out _currentCheckId if supplier changes.
   - In "Pagar Restante": block if _currentPaymentMethod == 'check', quantize remaining debt to 2 decimals, alert if remaining <= 0.
   - In Check Dropdown: provide dynamic key ValueKey('check_dropdown_${selectedCheckIds.length}_$_currentCheckId') and controlled value.
5. In test/features/cash_movements/presentation/widgets/movement_form_dialog_test.dart and test/features/cash_movements/adversarial_mixed_tender_challenge_test.dart:
   - Update tests that previously verified bug presence so they assert the remediated behavior (e.g. duplicate check is prevented/rejected, comma decimals parse correctly, Pagar Restante is blocked for checks, etc.).
6. Run verification:
   - flutter analyze lib/features/cash_movements/
   - flutter test test/features/cash_movements/
   Ensure all 53+ tests pass cleanly.
7. Document exact changes, analysis results, and test outputs in c:\laragon\www\Sistema_POS\pos-frontend\.agents\teamwork\worker_frontend_1\handoff.md.
8. Send completion message back to parent.
