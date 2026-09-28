# Reviewer R2 Briefing: Desktop Layout Refactoring & Hardening

## Overview
Review Round 2 subjected both `GeneralAuditScreen` (`lib/features/reports/presentation/pages/general_audit_screen.dart`) and `CashShiftSummaryScreen` (`lib/features/cash_register/presentation/pages/cash_shift_summary_screen.dart`) to adversarial probe testing under extreme font scaling (1.25x-1.4x), small touch viewports (1024x768, 600x800), rapid open/close lifecycle, bare/null data shapes, and alternative API payloads.

## Defect Summary Discovered & Fixed in R2
1. **Stock Movements Tab Header Overflow (Counterpart to R1 fix in Tab 1):**
   - In `_StockMovementsTab`, the header `Row` containing title and subtitle had an unconstrained `Column`. On viewports <= 600px, it threw `RenderFlex overflowed by 280 pixels on the right`.
   - Fixed by wrapping in `Expanded` with spacer.
2. **_ShiftSalesList JSON Format and Null Date Crash:**
   - When API returns standard `{ "data": [...] }`, `json.decode` yielded a `Map`, crashing `_ShiftSalesList` with type error.
   - When `created_at` was null, `DateTime.parse(null)` threw a `FormatException`.
   - Fixed by supporting both `List` and `Map['data']`, and parsing dates using `DateTime.tryParse`.
3. **_ShiftSalesList Infinite Loading Spinner on Null ApiClient:**
   - If `apiClient == null`, `_fetchSales` returned early without turning off `_loading = false`, locking the widget into an endless `CircularProgressIndicator`.
   - Fixed by resetting `_loading = false`.
