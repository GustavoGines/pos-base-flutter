## 2026-10-02T14:59:22Z
You are the SWE Light Orchestrator. Your working directory is c:/laragon/www/Sistema_POS/pos-frontend/.agents/teamwork/swe_3/.
Please read c:/laragon/www/Sistema_POS/MEMORY.md and c:/laragon/www/Sistema_POS/pos-frontend/.agents/teamwork/ORIGINAL_REQUEST.md.

Task Requirements:
Este es un cambio autocontenido; mantengan el equipo pequeño y enfocado.
Working directory: c:/laragon/www/Sistema_POS/pos-frontend
Integrity mode: development

### R1. Restaurar el PIN Efímero Global en PermissionGuard
Se debe restaurar la inyección del PIN global en `PermissionGuard` (usando `setGlobalEphemeralPin` en el `ApiClient`) para que la pantalla mantenga su estado de desbloqueo mientras esté viva.

### R2. Limitar la inyección automática del PIN a peticiones seguras (GET)
Modificar `ApiClient` (`lib/core/network/api_client.dart`) para que la inyección automática del encabezado `X-Admin-Pin` a partir de `_temporaryAdminPin` ocurra únicamente si el método HTTP es `GET`. Para peticiones `POST`, `PUT`, `DELETE` o `PATCH`, el `ApiClient` NO debe inyectar automáticamente el `X-Admin-Pin`.

### R3. Preservar la inyección explícita del PIN
El método `withAdminPin` del `ApiClient` y el mecanismo de reintento en el interceptor de errores 403 (donde se usa el PIN recién ingresado) DEBEN poder inyectar el `X-Admin-Pin` en CUALQUIER método HTTP (POST, PUT, etc.). La restricción de "Solo GET" de R2 aplica exclusivamente a la inyección automática en el flujo regular basada en el `_temporaryAdminPin` global del `PermissionGuard`.

## Acceptance Criteria
- [ ] Ejecutar `flutter analyze` y asegurar 0 advertencias/errores.
- [ ] Ejecutar `flutter test` en el frontend y asegurar que pasen todos los tests automatizados sin romper la lógica existente.
- [ ] El código de `ApiClient` inyectando `X-Admin-Pin` debe verse similar a `if (method == 'GET' && _temporaryAdminPin != null) ...` en lugar de inyectarlo a ciegas en todos los métodos.
- [ ] Seguridad estricta: NO ejecutar comandos git que muten el historial (no git commit, no git push, no git merge).

When finished, deliver your handoff report and notify the Sentinel.
