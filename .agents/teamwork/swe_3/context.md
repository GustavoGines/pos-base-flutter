# SWE Light Orchestrator Context — swe_3

## Mission
Execute the self-contained frontend security refactor:
1. R1: Restore ephemeral global PIN in PermissionGuard using `setGlobalEphemeralPin` on `ApiClient` so the screen stays unlocked while active.
2. R2: Restrict automatic `X-Admin-Pin` injection from `_temporaryAdminPin` in `ApiClient` (`lib/core/network/api_client.dart`) to GET requests ONLY.
3. R3: Preserve explicit PIN injection (`withAdminPin` and 403 error retry interceptor) for ANY HTTP method.
4. Programmatic Verification:
   - `flutter analyze` with 0 issues / warnings.
   - `flutter test` passing completely.
   - Verify code structure in `ApiClient` matches `if (method == 'GET' && _temporaryAdminPin != null) ...`.
   - Strictly NO git commits or version control mutations.

## Working Directory
`c:/laragon/www/Sistema_POS/pos-frontend/.agents/teamwork/swe_3/`
