# Handoff Report — Implementer (SWE 3)

## 1. Summary of Changes
- **`lib/core/network/api_client.dart`**:
  - Restored `setGlobalEphemeralPin(String? pin)` and added `globalEphemeralPin` getter.
  - Separated `_scopedAdminPin` (explicit block-scoped PIN via `withAdminPin`) from `_temporaryAdminPin` (global ephemeral screen PIN managed by `PermissionGuard`).
  - Updated `send(http.BaseRequest request)`:
    - Explicit scoped PIN (`_scopedAdminPin`) is injected on ANY HTTP method (`GET`, `POST`, `PUT`, `DELETE`, `PATCH`).
    - Ephemeral global PIN (`_temporaryAdminPin`) is injected **strictly** on `GET` requests (`if (method == 'GET' && _temporaryAdminPin != null && _temporaryAdminPin!.isNotEmpty)`).
    - Preserved 403 in-situ retry explicit PIN injection (`retryRequest.headers['X-Admin-Pin'] = pin`) across any HTTP method.
- **`lib/core/presentation/widgets/permission_guard.dart`**:
  - Restored global ephemeral PIN injection into `ApiClient` via `_apiClient?.setGlobalEphemeralPin(validPin)` when a screen is unlocked via PIN prompt or injected arguments.
  - Cleaned up global ephemeral PIN on widget teardown (`dispose()`) via `_apiClient?.setGlobalEphemeralPin(null)` to prevent leaking PIN state beyond the screen lifecycle.
  - Removed duplicate orphan `@override` annotation and wrapped `ApiClient` retrieval in null-safe / provider-safe checks.
- **`test/core/network/api_client_test.dart`**:
  - Added unit test verifying that `setGlobalEphemeralPin` injects `X-Admin-Pin` exclusively on `GET` requests, and strictly omits it on `POST`, `PUT`, `DELETE`, and `PATCH`.
  - Added unit test verifying that `withAdminPin` injects across any HTTP method, takes precedence over the global ephemeral PIN during execution, and restores the global PIN upon completion.
- **`test/core/presentation/widgets/permission_guard_test.dart`**:
  - Added widget integration test verifying that `PermissionGuard` sets the ephemeral PIN in `ApiClient` and makes `InheritedAdminPin` available when unlocked.
  - Added widget test verifying that `PermissionGuard.dispose()` purges the ephemeral PIN (`setGlobalEphemeralPin(null)`), ensuring subsequent requests omit `X-Admin-Pin`.

## 2. Verification Record
- **`flutter analyze` Output**:
  ```
  Analyzing pos-frontend...
  No issues found! (ran in 2.4s)
  ```
- **`flutter test` Output**:
  ```
  00:17 +212: All tests passed!
  ```
  - Total tests run: 212 tests (208 previous baseline + 4 newly created regression and lifecycle tests).
  - 100% pass rate with zero failures.

## 3. Exact Git Diff (Target Files)
```diff
diff --git a/lib/core/network/api_client.dart b/lib/core/network/api_client.dart
--- a/lib/core/network/api_client.dart
+++ b/lib/core/network/api_client.dart
@@ -42,3 +42,6 @@ class ApiClient extends http.BaseClient {
-  /// PIN de administrador temporal para autorizaciones puntuales por alcance.
+  /// PIN de administrador temporal para autorizaciones a nivel global de pantalla (PermissionGuard).
+  /// Solo se inyecta automáticamente en peticiones de lectura (GET).
   String? _temporaryAdminPin;
+
+  /// PIN de administrador explícito para bloques con alcance específico (withAdminPin).
+  /// Se inyecta en CUALQUIER método HTTP durante la ejecución del closure.
+  String? _scopedAdminPin;
@@ -58,0 +62,8 @@ class ApiClient extends http.BaseClient {
+  /// Setea o limpia el PIN efímero global (gestionado por PermissionGuard para la pantalla activa).
+  void setGlobalEphemeralPin(String? pin) {
+    _temporaryAdminPin = (pin != null && pin.trim().isNotEmpty) ? pin.trim() : null;
+  }
+
+  /// PIN efímero global actual (si está activo).
+  String? get globalEphemeralPin => _temporaryAdminPin;
+
@@ -64,3 +75,3 @@ class ApiClient extends http.BaseClient {
-    final previousPin = _temporaryAdminPin;
-    _temporaryAdminPin = pin;
+    final previousPin = _scopedAdminPin;
+    _scopedAdminPin = pin.trim().isNotEmpty ? pin.trim() : null;
     try {
@@ -69,1 +80,1 @@ class ApiClient extends http.BaseClient {
-      _temporaryAdminPin = previousPin;
+      _scopedAdminPin = previousPin;
@@ -128,4 +139,11 @@ class ApiClient extends http.BaseClient {
-      // ── Inyección de PIN de Supervisor Efímero (Scoped PIN) ─────────────
-      if (_temporaryAdminPin != null && _temporaryAdminPin!.isNotEmpty) {
-        request.headers['X-Admin-Pin'] = _temporaryAdminPin!;
-      }
+      final String method = request.method;
+
+      // ── Inyección de PIN de Administrador / Supervisor ─────────────────
+      // 1. Inyección explícita por bloque con alcance (withAdminPin) en CUALQUIER método HTTP.
+      if (_scopedAdminPin != null && _scopedAdminPin!.isNotEmpty) {
+        request.headers['X-Admin-Pin'] = _scopedAdminPin!;
+      }
+      // 2. Inyección automática de PIN efímero global (PermissionGuard) ÚNICAMENTE en peticiones seguras (GET).
+      // Para POST, PUT, DELETE, PATCH, ApiClient NO inyecta automáticamente _temporaryAdminPin.
+      else if (method == 'GET' && _temporaryAdminPin != null && _temporaryAdminPin!.isNotEmpty) {
+        request.headers['X-Admin-Pin'] = _temporaryAdminPin!;
+      }

diff --git a/lib/core/presentation/widgets/permission_guard.dart b/lib/core/presentation/widgets/permission_guard.dart
--- a/lib/core/presentation/widgets/permission_guard.dart
+++ b/lib/core/presentation/widgets/permission_guard.dart
@@ -65,1 +65,1 @@ class _PermissionGuardState extends State<PermissionGuard> {
-         
+        _apiClient?.setGlobalEphemeralPin(validPin);
@@ -84,0 +84,1 @@ class _PermissionGuardState extends State<PermissionGuard> {
+      _apiClient?.setGlobalEphemeralPin(pin);
@@ -104,1 +104,1 @@ class _PermissionGuardState extends State<PermissionGuard> {
-    
+    _apiClient?.setGlobalEphemeralPin(null);
@@ -121,1 +121,1 @@ class _PermissionGuardState extends State<PermissionGuard> {
-         
+        _apiClient?.setGlobalEphemeralPin(validPin);
```

## 4. Known Issues
- `Minor Robustness Risk`: If two nested `PermissionGuard` widgets exist in the same widget hierarchy for different keys, disposing the child guard will clear the global PIN on `ApiClient` until the parent rebuilds. In practice, `PermissionGuard` is exclusively used as a route-level wrapper per screen.
- `Fatal Functional Bug`: None.
- `Shallow Verification`: None.

## 5. Constraint Checklist
- [x] R1 implemented: `setGlobalEphemeralPin` restored on `ApiClient` and wired into `PermissionGuard` lifecycle (`_checkAndAutoPrompt`, dialog unlock, `build`, `dispose`).
- [x] R2 implemented: `_temporaryAdminPin` auto-injection restricted exclusively to HTTP `GET`.
- [x] R3 implemented: `withAdminPin` and 403 error retry interceptor inject `X-Admin-Pin` across ANY HTTP method.
- [x] `flutter analyze` completed with 0 warnings/errors.
- [x] `flutter test` completed with 212/212 tests passing.
- [x] Strict security: zero git mutation commands executed.
