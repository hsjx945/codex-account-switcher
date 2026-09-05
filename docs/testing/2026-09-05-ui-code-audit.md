# Quota menu and native app audit — 2026-09-05

## Scope and baseline

The requested change is a compact menu-bar quota summary, followed by a strict audit and fixes for the native macOS application. Baseline: `610f5b4`, branch `codex/tiny-codex-switcher`. A concurrent task changed the shared checkout to upstream `main`, so this task uses isolated branch `codex/quota-ui-audit`. No unrelated changes, credentials, or account databases belong in this diff.

## UI and data corrections

- The menu bar shows the logo and current account's weekly remaining percentage; account names stay in the popover. Missing or unverified quota is `—`; a failed refresh with cached quota carries `!`. The existing percentage preference remains available.
- Percentage text cannot wrap, including `100%`. Account list height selects a scrollable layout when its content exceeds 520 points.
- English reset dates use English formatting; reset tooltips identify the existing UTC+8 time basis. Chinese remains unchanged.
- Token rows and total identify cached data during startup/refresh and after a failed token request. A successful weekly request no longer disguises a failed token request. Date captions describe the most recent date shared by all accounts.
- A failed nickname save keeps the editor open. Settings become active only after persistence succeeds; failed persistence does not enable warmup or change the visible saved setting.
- Quota normalization and token totals reject invalid values or overflow instead of trapping or fabricating zero. Blank account IDs/emails cannot authenticate a saved blank identity.

## Core findings and repair

An independent review covered client parsing, process lifecycle, the serialized operation gate, account storage, switch recovery, notification handling, and model state. Repairs and fault tests cover out-of-range JSON numbers, cancelled queued operations, distinction between Desktop reopen and recovery cleanup failures, reporting of failed registry restoration, bounded termination of a stuck warmup child, and blank identities.

## Verification method

`scripts/run-swift-tests.sh` now passes the selected toolchain's Testing framework search path to the generated SwiftPM runner, not just the test target. Previously the runner could compile with `canImport(Testing) == false` and discover no tests. The script retains a test-discovery guard.

The executable fixture suite is `scripts/run-core-checks.sh`. It uses temporary storage, fake credentials, and fake Codex processes. Native card renders use real `AccountRow` SwiftUI views with synthetic accounts, not live account data:

```sh
swiftc -parse-as-library Sources/CodexAccountSwitcher/Models.swift Sources/CodexAccountSwitcher/Localization.swift Sources/CodexAccountSwitcher/AccountRow.swift Checks/RenderUIChecks.swift -framework AppKit -framework SwiftUI -o /tmp/quota-ui-render
/tmp/quota-ui-render .build/ui-checks
```

All four Chinese/English and light/dark renders are inspected for full percentage text, long-name truncation, reset dates, and cache labels. Rendered fixtures do not prove a live menu-bar interaction or actual account switching.

## Remaining boundary

The in-process operation gate cannot serialize another program changing the active Codex credential simultaneously. This round does not introduce a system-wide lock or claim cross-process account-switch atomicity. No real account switch, login, Keychain permission change, notification permission change, or public release is performed as a test.

Live desktop accessibility access to this menu-only app has timed out. Packaging/process identity and rendered fixtures must be reported separately from interactive native UI acceptance.

## Final results

- `scripts/run-swift-tests.sh`: exit 0; 66 tests in 11 suites passed. The script explicitly disables Swift Testing parallel execution: concurrent short-lived process fixtures exceeded their existing two-second deadlines under load, while an isolated handshake passed in 0.385 seconds and the final full serial suite passed in 6.484 seconds. Timeouts were not loosened.
- `scripts/run-core-checks.sh`: exit 0, `Core checks passed`.
- `scripts/package-local-app.sh`: exit 0; release build and strict ad-hoc signature verification passed.
- `git diff --check`: passed.
- Four native SwiftUI card renderings inspected; fixtures contain synthetic accounts only.
- Existing local app bundle was updated, its previous bundle retained under `.build/runtime-backup`, and the updated executable started at the existing local app path. The final process was observed at that same executable path. Installed executable SHA-256 matches the built artifact: `1c6de98c6609dec12d50fe0baa7934fadcb1d34b0e88a1c92c3de770e77de1de`.
- Test/build logs are retained under `.build/audit-evidence/`. Native menu interaction remains unverified because accessibility retrieval times out; the successful launch is not a claim of interactive UI acceptance.
- A committed recovery journal left by cleanup failure can still cause a Desktop reopen retry at next startup. Error reporting is corrected; exactly-once cross-process reopen semantics are outside this patch.
