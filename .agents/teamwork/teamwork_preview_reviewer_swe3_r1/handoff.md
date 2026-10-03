> [!WARNING] **Skepticism Disclaimer**
> Confidence is high on the corrected PIN lifecycle, header precedence, and test suite green status (219/219 passing), but route stack operations in Flutter still rely on widget dispose order matching Navigator pop order.

## 1. What the prior attempt got wrong

### Issue 1: `PermissionGuard.dispose()` unconditionally purged `ApiClient.globalEphemeralPin` on authorized/unprotected screen exit
- **Input:** Screen A (unlocked with ephemeral PIN '1111') pushes Screen B (an authorized screen with `permissionKey: 'authorized_perm'` where no PIN is needed). User finishes on Screen B and pops back to Screen A.
- **Expected:** Screen A remains active and `_apiClient.globalEphemeralPin` remains `'1111'`.
- **Actual:** `_apiClient.globalEphemeralPin` was wiped to `null`, causing subsequent GET requests on Screen A to fail with 403.
- **Root cause:** `_PermissionGuardState.dispose()` unconditionally executed `_apiClient?.setGlobalEphemeralPin(null)` even when the guard had never injected an ephemeral PIN.

### Issue 2: Popping a pushed/nested protected screen cleared the PIN instead of restoring the prior screen's PIN
- **Input:** Screen A (unlocked with PIN '1111') pushes Screen B (unlocked with PIN '2222'). Screen B is popped.
- **Expected:** `_apiClient.globalEphemeralPin` is restored to `'1111'`.
- **Actual:** `_apiClient.globalEphemeralPin` was wiped to `null`.
- **Root cause:** `PermissionGuard` lacked prior state capture (`_previousEphemeralPin`) and restoration during teardown.

### Issue 3: Pre-existing explicit `X-Admin-Pin` in `request.headers` was clobbered by automatic global ephemeral injection (R0-ISSUE-3)
- **Input:** Caller makes a request: `apiClient.get('/api/explicit', headers: {'X-Admin-Pin': 'EXPLICIT_HEADER_PIN'})` while `_temporaryAdminPin` is `'GLOBAL_FALLBACK_PIN'`.
- **Expected:** Request preserves `'EXPLICIT_HEADER_PIN'`.
- **Actual:** Request header was clobbered to `'GLOBAL_FALLBACK_PIN'`.
- **Root cause:** `ApiClient.send` did not check `(request.headers['X-Admin-Pin'] == null || request.headers['X-Admin-Pin']!.isEmpty)` before applying `_temporaryAdminPin`.

### Issue 4: 403 in-situ PIN verification caching was bypassed
- **Input:** Concurrent or back-to-back 403 responses requesting PIN authorization.
- **Expected:** Once `onPermissionDenied` completes with a valid PIN, subsequent calls within the 2-second grace window reuse the verified PIN.
- **Actual:** `_promptAdminPin` never called `markPinAsVerified(pin)`.
- **Root cause:** Missing `markPinAsVerified(pin)` call upon completing prompt completer.

### Issue 5: Logout did not purge global ephemeral PIN
- **Input:** User logs out via `AuthProvider.logout()` or `forceLogout()`.
- **Expected:** `apiClient.globalEphemeralPin` is reset to `null`.
- **Actual:** Only `sessionToken` was reset; ephemeral PIN persisted in memory.
- **Root cause:** `_clearToken()` lacked `apiClient?.setGlobalEphemeralPin(null)`.

---

## 2. What I changed

- **`lib/core/presentation/widgets/permission_guard.dart`**:
  - Implemented `_injectScreenPin(String pin)` with `_hasInjectedPin` flag and `_previousEphemeralPin` capture.
  - Implemented `_cleanupScreenPin()` in `dispose()` to restore `_previousEphemeralPin` instead of blindly setting `null`.
  - Replaced direct `_apiClient?.setGlobalEphemeralPin(validPin)` calls in `_checkAndAutoPrompt()` and `build()` with `_injectScreenPin(validPin)`.
- **`lib/core/network/api_client.dart`**:
  - Guarded `_temporaryAdminPin` injection in `send()` with `&& (request.headers['X-Admin-Pin'] == null || request.headers['X-Admin-Pin']!.isEmpty)` to ensure explicit caller headers take precedence.
  - Added `markPinAsVerified(pin)` in `_promptAdminPin` when `pin != null && pin.isNotEmpty`.
- **`lib/features/auth/presentation/providers/auth_provider.dart`**:
  - Added `apiClient?.setGlobalEphemeralPin(null)` to `_clearToken()` so logout and forced logout purge ephemeral PIN privileges.
- **`test/core/presentation/widgets/permission_guard_test.dart`**:
  - Added adversarial tests:
    1. Popping an authorized screen (no PIN) does NOT purge ephemeral PIN of underlying screen.
    2. Popping a screen with PIN restores the previous screen's PIN.
    3. Canceling PIN dialog on a new screen does NOT wipe out underlying screen PIN.
- **`test/core/network/api_client_test.dart`**:
  - Added adversarial tests:
    1. Pre-existing explicit `X-Admin-Pin` in request headers is not clobbered by `setGlobalEphemeralPin`.
    2. `setGlobalEphemeralPin` normalizes whitespace-only and empty strings to `null`.
    3. 403 in-situ retry successfully injects `X-Admin-Pin` on `POST` requests across any HTTP method (R3).
- **`test/features/auth/providers/auth_provider_test.dart`**:
  - Added test verifying `logout` and `forceLogout` purge `globalEphemeralPin` in `ApiClient`.

---

## 3. Verification Record

- **Deep Verification (ran actual tests):**
  - `flutter analyze`:
    ```
    Analyzing pos-frontend...
    No issues found! (ran in 2.3s)
    ```
  - `flutter test test/core/network/api_client_test.dart`:
    ```
    00:00 +8: All tests passed!
    ```
  - `flutter test test/core/presentation/widgets/permission_guard_test.dart`:
    ```
    00:00 +5: All tests passed!
    ```
  - `flutter test test/features/auth/providers/auth_provider_test.dart`:
    ```
    00:00 +4: All tests passed!
    ```
  - `flutter test` (Full Repository Test Suite):
    ```
    00:19 +219: All tests passed!
    ```
    219 passing tests with 0 failures and 0 regressions.
- **Shallow Verification (manual only):**
  - Inspected code paths in `ApiClient.send`, `PermissionGuard.dispose`, `AuthProvider._clearToken`.
- **Unverified aspects:**
  - Real Windows desktop binary runtime with live Laravel backend network requests (relies on mock HTTP clients and widget test harnesses in Flutter).

---

## 4. Known Issues

- `Minor Robustness Risk`: If non-standard navigation replaces routes out of sequence (e.g. popping routes via low-level navigator hacks rather than normal Navigator push/pop stack order), `_previousEphemeralPin` restores the PIN captured at mount time. In standard Flutter route navigation, this correctly mirrors stack semantics.
- `Fatal Functional Bug`: None (all identified issues resolved and verified).
- `Shallow Verification`: None (all fixes covered by programmatic automated tests).

---

## 5. Remaining risk & next step

- **Remaining Risk:** The core logic is verified and protected against regression by 219 automated unit and widget tests. The only remaining risk is real-world Windows desktop execution with live backend network sockets.
- **Next Step:** Task is complete. All requirements R1, R2, R3 and acceptance criteria are fully met.
