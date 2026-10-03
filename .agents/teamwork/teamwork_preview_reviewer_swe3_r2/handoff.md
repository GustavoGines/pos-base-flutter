> [!WARNING] **Skepticism Disclaimer**
> Confidence is very high after breaking the prior implementation with an adversarial test reproducing real navigation flows (`pushReplacementNamed` in `GlobalAppBar`) and proving that the owner-aware LIFO stack in `ApiClient` completely prevents teardown clobbering across 223/223 automated tests.

## 1. What the prior attempt got wrong

### Issue: Route replacement (`pushReplacementNamed` / `pushReplacement`) wiped active screen ephemeral PIN to `null`
- **Input:** User on Screen A (unlocked with PIN `'1111'`) navigates to Screen B using top bar navigation (`GlobalAppBar.pushReplacementNamed`, which is the primary navigation mechanism across POS screens) unlocking Screen B with PIN `'2222'` (or the same PIN).
- **Expected:** Screen B mounts and becomes the active screen, with `apiClient.globalEphemeralPin == '2222'`, allowing GET requests on Screen B to succeed.
- **Actual:** Screen B briefly mounted with `'2222'`, but during the replacement transition Flutter disposed Screen A. Screen A's `_cleanupScreenPin()` unconditionally executed `_apiClient?.setGlobalEphemeralPin(_previousEphemeralPin)` where Screen A's captured `_previousEphemeralPin` was `null`. This immediately wiped `apiClient.globalEphemeralPin` to `null` while Screen B was alive on screen, causing subsequent GET requests on Screen B to fail with 403 Forbidden.
- **Root cause:** `_PermissionGuardState` relied on a local scalar `_previousEphemeralPin` variable captured at mount time. Because `Navigator.pushReplacement` mounts the destination widget BEFORE disposing the replaced widget, the replaced widget's teardown overwrote the new screen's active PIN. Moreover, if an underlying screen rebuilt (due to inherited widget, theme, or provider updates), it risked re-injecting its PIN and hijacking the top of the route stack.

---

## 2. What I changed

- **`lib/core/network/api_client.dart`**:
  - Upgraded `setGlobalEphemeralPin(String? pin, [Object? owner])` to manage an owner-aware stack (`_ephemeralPinStack = List<MapEntry<Object, String>>`).
  - When `owner != null`:
    - Adding/updating a PIN preserves existing stack positions on rebuilds (prevents underlying screens from hijacking active PIN) and appends new routes to the top.
    - Removing an owner (`pin == null`) purges only that owner from the stack and seamlessly restores the top of the remaining stack (`_ephemeralPinStack.last.value`) or `null` if empty.
  - When `owner == null`: direct scalar setter maintained for backward compatibility and test ergonomics (`setGlobalEphemeralPin(null)` on logout purges all stacked PINs).
- **`lib/core/presentation/widgets/permission_guard.dart`**:
  - Removed flawed local scalar `_previousEphemeralPin` state tracking.
  - Updated `_injectScreenPin(pin)` to delegate lifecycle ownership to `apiClient.setGlobalEphemeralPin(pin, this)`.
  - Updated `_cleanupScreenPin()` in `dispose()` to unregister its own ownership via `apiClient.setGlobalEphemeralPin(null, this)`, preventing replaced routes from ever clobbering the active screen's PIN.
- **`test/core/presentation/widgets/permission_guard_test.dart`**:
  - Added adversarial tests:
    1. `pushReplacement from Screen A to Screen B preserves Screen B PIN`: reproduced the failure (actual `<null>`) and verified the fix (`'2222'`).
    2. `pushReplacement from Screen A to Screen B without PIN clears globalEphemeralPin`: verified that replacing a protected screen with an unprotected screen correctly clears the ephemeral PIN to `null`.
    3. `Screen A rebuild underneath active Screen B does not hijack top of stack`: verified that provider/state notifications rebuilding underlying routes do not clobber top-of-stack ephemeral PIN.
    4. `3-level route stack restores LIFO correctly at each pop`: verified sequential multi-level push & pop (`A('1111') -> B('2222') -> C('3333') -> pop C -> B('2222') -> pop B -> A('1111') -> pop A -> null`).

---

## 3. Verification Record

- **Deep Verification (ran actual tests):**
  - Ran failing reproduction test:
    `flutter test test/core/presentation/widgets/permission_guard_test.dart`
    Expected: `'2222'`, Actual: `<null>`. (Failed as predicted).
  - Re-ran after fix:
    `flutter test test/core/presentation/widgets/permission_guard_test.dart`: 9/9 passing tests.
  - `flutter test test/core/network/api_client_test.dart`: 8/8 passing tests.
  - `flutter test test/core/network/adversarial_in_situ_interception_test.dart test/core/network/in_situ_pin_interception_test.dart test/features/auth/providers/auth_provider_test.dart`: 17/17 passing tests.
  - Full test suite: `flutter test`: 223/223 passing tests (0 failures, 0 regressions).
  - Code analysis: `flutter analyze`: Completed with 0 issues found.
- **Shallow Verification (manual only):**
  - Inspected code paths in `GlobalAppBar` (`Navigator.pushReplacementNamed`) and verified stack semantics with Flutter's widget lifecycle order.
- **Unverified aspects:**
  - Real Windows desktop executable running against live remote Laravel server network sockets (relies on mock HTTP client suites).

---

## 4. Known Issues

- `Minor Robustness Risk`: If an external component modifies `ApiClient.setGlobalEphemeralPin(pin)` directly without an owner while routes are stacked, it overwrites the active PIN until the next route lifecycle event. Normal application code only uses `PermissionGuard` and `AuthProvider._clearToken()` (logout), so this only affects synthetic test mocks.
- `Fatal Functional Bug`: None.
- `Shallow Verification`: None.

---

## 5. Remaining risk & next step

- **Remaining Risk:** The core logic, edge cases (LIFO popping, route replacement, multi-route nesting, background route rebuilds, 403 in-situ retry, logout purging) are thoroughly verified and guarded by 223 automated unit and widget tests.
- **Next Step:** Task is complete. All requirements R1, R2, R3 and acceptance criteria are satisfied with zero regressions and zero static analysis warnings.
