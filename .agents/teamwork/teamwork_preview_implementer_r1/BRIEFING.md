# Task Briefing: Shift Layout Desktop Refactor

## Objective
Refactor the UI layouts for the Shift Detail ("Detalle del Turno") dialog and Shift Close Summary ("Cierre de Turno") screen in `pos-frontend` to make them wider and utilize a multi-column desktop-friendly design, eliminating the need for excessive vertical scrolling.

## Target Files
1. `lib/features/reports/presentation/pages/general_audit_screen.dart` (`_showShiftDetail`)
2. `lib/features/cash_register/presentation/pages/cash_shift_summary_screen.dart`

## Key Requirements & Architectural Decisions
1. **GeneralAuditScreen (`_showShiftDetail`)**:
   - Expanded modal width constraint from `500` to `900` pixels.
   - Restructured the header into a unified 4-item horizontal row (`Caja`, `Apertura`, `Fecha Inicio`, `Fecha Cierre`).
   - Grouped "Desglose de Ventas" and "Balance de Caja" into side-by-side balanced panels using `Row` and `Expanded`.
   - Restructured the "Auditoría de Ventas" list into a responsive multi-column layout using `LayoutBuilder` and `Wrap` (2 columns on desktop width > 550px).
   - Replaced deprecated `withOpacity` with standard color.

2. **CashShiftSummaryScreen**:
   - Expanded main `ConstrainedBox` from `maxWidth: 500` to `maxWidth: 900`.
   - Restructured the page into a 2-column desktop layout using `LayoutBuilder`:
     - **Left Column**: "Balance de Caja" containing Fondo Inicial, cash movements (ingresos, gastos, retiros, pagos proveedores, reintegros), Efectivo Esperado, Efectivo Físico, and the FALTANTE/SOBRANTE KPI badge.
     - **Right Column**: "Desglose de Ventas" containing Efectivo, Tarjeta, Transferencia, Recargos, Cuenta Corriente, and Cheques, followed directly by the primary action buttons ("Imprimir Cierre Z y Salir" and "Continuar sin imprimir").
   - Implemented compact vertical spacing and paddings ensuring the action buttons are immediately visible without scrolling on standard desktop viewports (e.g., 1280x800, 1024x768).
   - Wrapped text and headers with `Expanded` and `Wrap` to prevent RenderFlex overflow even with dense check data or varying window dimensions.
   - Retained responsive vertical column fallback when width is < 650px.

3. **Strict Constraints**:
   - No version control / git commit operations.
