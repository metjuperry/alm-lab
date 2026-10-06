# Warehouse app tests

Reqnroll + Playwright + MSTest tests cover the model-driven app and the Warehouse
Picking code app. Build once for discovery; rebuild after editing `.feature` files.

## Offline checks

```bash
dotnet test --filter "TestCategory!=live"
```

Offline tests cover bindings and authentication helpers. They do not prove the
deployed application works.

## Live setup

Use a dedicated Test sandbox with the current app, stock plugins, grocery data and
connector deployed. Assign distinct non-admin accounts the platform base role,
Warehouse manager / Warehouse worker roles and access to both apps and the
connector connection.

Copy `.env.example` to `.env` and configure:

- `TXC_USER_WAREHOUSE_MANAGER_USERNAME` / `_PASSWORD`
- `TXC_USER_WAREHOUSE_FLOOR_WORKER_USERNAME` / `_PASSWORD`
- The corresponding `_OTP_SECRET` only when a dedicated test account uses TOTP.

The login step signs in, caches a session under `.auth/`, and re-authenticates when
needed. Real environment variables override `.env`. Never commit passwords,
authenticator seeds, `.env`, or `.auth/`.

Set `TXC_ENVIRONMENT_URL`, `TXC_APP_NAME` and **`TXC_CODEAPP_URL`** to the deployed
Test apps. The code-app URL has no implicit localhost fallback. For a deliberate
local preview, start the server yourself and supply its URL.

```powershell
dotnet build
pwsh bin/Debug/net10.0/playwright.ps1 install chromium
dotnet test --filter "TestCategory=live"
```

For interactive MFA, set `TXC_HEADLESS=false` and run the `TestCategory=auth`
scenario once. Push approval and other non-TOTP challenges cannot be automated by
storing an authenticator seed.

## Repeatability

Picking scenarios create uniquely named grocery items and opening movements as
the worker. Cleanup uses a separate manager session, deletes only that scenario's
movements (outbound first), then deletes its item. Cleanup failures are reported,
not ignored. Existing learner stock is not consumed by the scenarios. These paths
require live rehearsal; a successful build is not proof of their runtime behavior.

`Features/Planned/` and `Features/Discovered/` are proposals, not executable tests
until reviewed, bound and promoted into `Features/`.

## GitHub Actions

Wait for the matching Test deployment before dispatching `test`. Set repository
variable `TXC_CODEAPP_URL`, secret `DATAVERSE_TEST_URL`, and the persona credential
secrets listed above. The workflow installs Chromium/system dependencies and
uploads reports, screenshots and traces. Artifacts may contain application data;
keep test data nonsensitive and access restricted.

Other settings include `TXC_HEADLESS`, `TXC_TIMEOUT`, `TXC_SLOWMO`,
`TXC_SCREENSHOT_ON_FAILURE`, `TXC_TRACING_ENABLED`, and `TXC_OUTPUT_PATH`.
An explicit `TXC_STORAGE_STATE_PATH` is a single captured account session, not a
replacement for distinct persona accounts in the full suite.
