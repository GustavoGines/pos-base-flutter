# Original User Request

## Request — 2026-10-02T18:38:42Z

Este es un cambio autocontenido; mantengan el equipo pequeño y enfocado.

Working directory: c:/laragon/www/Sistema_POS/pos-frontend

## Requirements

### R1. Solucionar Overflow en Diálogo de Aumento Masivo
Modificar `BulkPriceUpdateDialog` (en `catalog_screen.dart` o donde resida) para envolver su contenido en un `SingleChildScrollView` (o estructura flexible similar) para evitar el error "Bottom overflowed by X pixels" en resoluciones pequeñas.

### R2. Asegurar Acciones Destructivas Huérfanas
Reemplazar las llamadas directas de borrado por `AdminPinDialog.protectAction` en los siguientes lugares:
1. **Presupuestos (`quotes_list_screen.dart`)**: Proteger el borrado individual y masivo usando el permiso correspondiente.
2. **Proveedores (`suppliers_screen.dart`)**: Proteger el borrado de proveedor usando el permiso correspondiente.
3. **Usuarios (`users_manager_screen.dart`)**: Refactorizar `_deleteEmployee` para que use `protectAction(permissionKey: AppPermissions.manageUsers)` en lugar del `.verify()` genérico.

### R3. Limpiar Usos de `InheritedAdminPin` (Eliminar Vector de Riesgo)
Analizar y eliminar las consultas directas a `InheritedAdminPin.of(context)` en las pantallas de caja (`cash_movements_screen.dart`), reportes (`general_audit_screen.dart`, `reports_screen.dart`, `expense_analysis_tab.dart`, `internal_consumption_report_view.dart`) y `mobile_dashboard_screen.dart`. Reemplazar estos usos por llamadas estándar al `provider` o `protectAction` según corresponda. Si `InheritedAdminPin` ya no tiene utilidad, remover el widget padre de `PermissionGuard`.

### R4. Mejorar UI/UX de la Lista de Empleados
En la vista de gestión de usuarios (`users_manager_screen.dart`), cuando un empleado tiene muchos permisos, la UI se satura de "chips" (etiquetas) verdes. Rediseñar esta visualización de forma más limpia y profesional. Por ejemplo: colapsar los permisos si son más de 3 o 4 mostrando un chip "+N permisos", o agruparlos visualmente por categoría. El objetivo es que la tarjeta del empleado mantenga un tamaño manejable y estético.

## Acceptance Criteria

### Verificación UI y Código
- [ ] Al achicar la ventana al máximo y abrir "Aumento Masivo de Precios", el contenido debe ser scrolleable sin arrojar errores de RenderFlex Overflow.
- [ ] Intentar borrar un presupuesto o proveedor sin permisos debe invocar automáticamente el modal de PIN.
- [ ] La lista de empleados debe verse limpia incluso si un cajero tiene los 25 permisos asignados, sin estirar la tarjeta excesivamente.
- [ ] El código debe compilar limpiamente. Ejecutar `flutter analyze` y asegurar 0 problemas.
- [ ] Ejecutar `flutter test` y asegurar que la suite completa (incluyendo navegación y seguridad) siga pasando correctamente al 100%.
- [ ] Seguridad estricta: NO ejecutar comandos git que muten el historial (no git commit, no git push, no git merge).
