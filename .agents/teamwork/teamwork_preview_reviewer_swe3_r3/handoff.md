# Handoff Report - SWE Light Adversarial Reviewer (Round 3)

## 1. What the prior attempt got wrong

### Issue 1: Unhandled `TypeError` in `PermissionGuard` on non-Map route arguments
- **Input:** Navigating to a guarded route with non-Map arguments (e.g. `Navigator.pushNamed(context, '/catalog', arguments: 'item_123')`, integer IDs, or custom model objects).
- **Expected:** `PermissionGuard` safely checks route arguments and renders without crashing.
- **Actual:** `type 'String' is not a subtype of type 'Map<String, dynamic>?' in type cast` threw during `_checkAndAutoPrompt` and `build`, crashing the widget tree.
- **Root cause:** Hard cast `ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?` was used in `_PermissionGuardState` without runtime type guard `rawArgs is Map`.

### Issue 2: Screen remained unlocked and resurrected global ephemeral PIN across logout
- **Input:** User unlocked a `PermissionGuard` screen using Admin PIN (`_temporaryUnlockedPin = '1234'`). User then logged out (`auth.logout()`), which wiped `apiClient.globalEphemeralPin` to null.
- **Expected:** Screen locks, `_temporaryUnlockedPin` is cleared, and `apiClient.globalEphemeralPin` remains null.
- **Actual:** When `AuthProvider.notifyListeners()` triggered during logout, `PermissionGuard.build()` rebuilt before the route was replaced. Because `_temporaryUnlockedPin` was retained in local widget state, `build()` re-injected `_injectScreenPin('1234')`, resurrecting the admin PIN into `ApiClient` and displaying protected content.
- **Root cause:** `_PermissionGuardState` lacked authentication session and user identity invalidation logic.

### Issue 3: In-situ verified PIN cache persisted across sessions
- **Input:** User triggered a 403 in-situ prompt caching the supervisor PIN (`_lastVerifiedPin`) for 2 seconds. User logged out immediately within that 2-second window.
- **Expected:** `setGlobalEphemeralPin(null)` clears all ephemeral and cached PIN states completely.
- **Actual:** `_lastVerifiedPin` was not cleared in `setGlobalEphemeralPin(null)`, allowing subsequent requests within 2 seconds to reuse the previous user's verified PIN.
- **Root cause:** Missing reset of `_lastVerifiedPin` and `_lastVerifiedPinTime` in `ApiClient.setGlobalEphemeralPin(null)`.

### Issue 4: HTTP method case sensitivity and Content-Length casing
- **Input:** Requests created with lowercase method `http.Request('get', url)` or capitalized header `Content-Length`.
- **Expected:** `ApiClient` normalizes method to uppercase and strips `Content-Length` regardless of key casing on 403 retry.
- **Actual:** Strict `method == 'GET'` missed lowercase `'get'`; `..remove('content-length')` missed `'Content-Length'`.
- **Root cause:** Lack of `.toUpperCase()` normalization and case-sensitive map key removal.

---

## 2. What I changed

- **`lib/core/presentation/widgets/permission_guard.dart`**:
  - Replaced hard casts with safe extractor `_extractInjectedPin(BuildContext context)`.
  - Added `_isAuthActive(AuthProvider auth)` guard to invalidate `_temporaryUnlockedPin` and cleanup `ApiClient` ephemeral PIN when session is unauthenticated.
  - Added `_lastUserIdentity` tracking to purge unlocked state if the authenticated user changes.
- **`lib/core/network/api_client.dart`**:
  - In `setGlobalEphemeralPin(null)`: also clears `_lastVerifiedPin = null` and `_lastVerifiedPinTime = null`.
  - Normalized `method = request.method.toUpperCase()` in `send()`.
  - In 403 retry: replaced `..remove('content-length')` with `..removeWhere((k, _) => k.toLowerCase() == 'content-length')`.
- **`test/core/presentation/widgets/permission_guard_test.dart`**:
  - Added adversarial test: `Route with non-Map arguments does not crash with TypeError`.
  - Added adversarial test: `Logging out invalidates PermissionGuard temporary pin and leaves globalEphemeralPin null`.
  - Updated `TestAuthProvider` with `currentUser`, `isAuthenticated`, and `simulateLogout`.
- **`test/core/network/api_client_test.dart`**:
  - Added adversarial test: `setGlobalEphemeralPin(null) purges cached verified pin preventing cross-session reuse`.
  - Added adversarial test: `lowercase get method injects ephemeral pin and preserves case-insensitive headers on retry`.

---

## 3. Verification Record

- **Deep Verification (ran actual tests):**
  - Ran adversarial reproduction test: `flutter test test/core/presentation/widgets/permission_guard_test.dart --plain-name "non-Map"` -> Reproduced `_TypeError: type 'String' is not a subtype of type 'Map<String, dynamic>?' in type cast`. Fixed and verified passing.
  - Ran adversarial reproduction test: `flutter test test/core/presentation/widgets/permission_guard_test.dart --plain-name "Logging out invalidates"` -> Reproduced `Expected: null, Actual: '1234'`. Fixed and verified passing.
  - `flutter test test/core/presentation/widgets/permission_guard_test.dart`: 11/11 passing tests.
  - `flutter test test/core/network/api_client_test.dart`: 10/10 passing tests.
  - Targeted test suites: `flutter test test/core/presentation/widgets/permission_guard_test.dart test/core/network/api_client_test.dart test/core/network/in_situ_pin_interception_test.dart test/core/network/adversarial_in_situ_interception_test.dart test/features/auth/in_situ_pin_dialog_flow_test.dart test/features/auth/providers/auth_provider_test.dart` -> 41/41 passing tests.
  - Full test suite: `flutter test` -> 227/227 passing tests (0 failures, 0 regressions).
  - Code analysis: `flutter analyze` -> Completed with 0 issues found.
- **Shallow Verification (manual only):**
  - Inspected `PermissionGuard` route argument handling, authentication lifecycle hooks, and `ApiClient` header injection logic against R1, R2, R3.
- **Unverified aspects:**
  - Real Windows desktop executable running against live remote Laravel server network sockets (tested via mock HTTP client and widget tests).

---

## 4. Known Issues

- `Minor Robustness Risk`: None.
- `Fatal Functional Bug`: None.
- `Shallow Verification`: None.

---

## 5. Remaining risk & next step

- **Remaining Risk:** All requirements R1, R2, R3 and edge cases (type casting, navigation stack transitions, LIFO route popping, route replacement, session logout, concurrent 403 retry, cached verified PIN purge) are strictly covered and verified across 227 automated tests.
- **Next Step:** Ready for final audit.
