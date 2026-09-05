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

## Build 7 results

- `scripts/run-swift-tests.sh`: exit 0; 66 tests in 11 suites passed. The script explicitly disables Swift Testing parallel execution: concurrent short-lived process fixtures exceeded their existing two-second deadlines under load, while an isolated handshake passed in 0.385 seconds and the final full serial suite passed in 6.484 seconds. Timeouts were not loosened.
- `scripts/run-core-checks.sh`: exit 0, `Core checks passed`.
- `scripts/package-local-app.sh`: exit 0; release build and strict ad-hoc signature verification passed.
- `git diff --check`: passed.
- Four native SwiftUI card renderings inspected; fixtures contain synthetic accounts only.
- Existing local app bundle was updated, its previous bundle retained under `.build/runtime-backup`, and the updated executable started at the existing local app path. The final process was observed at that same executable path. Installed executable SHA-256 matches the built artifact: `1c6de98c6609dec12d50fe0baa7934fadcb1d34b0e88a1c92c3de770e77de1de`.
- Test/build logs are retained under `.build/audit-evidence/`. Native menu interaction remains unverified because accessibility retrieval times out; the successful launch is not a claim of interactive UI acceptance.
- A committed recovery journal left by cleanup failure can still cause a Desktop reopen retry at next startup. Error reporting is corrected; exactly-once cross-process reopen semantics are outside this patch.

## Follow-up: collapsed account list (build 8)

A user screenshot exposed a real regression in build 7: the quota and token total remained visible, but both account cards disappeared. The two saved profiles were still present. `ViewThatFits` selected a zero-height scroll view under the menu host's compact height proposal. The previous isolated card render checks could not catch this container-level failure.

The fix restores intrinsic layout for one or two accounts and an explicit 520-point scroll viewport for larger lists. A whole-popover test now checks both unconstrained AppKit fitting size and SwiftUI rendering under a 100-point height proposal, for two and five synthetic accounts. The same test was run against build 7 source: both compact cases failed with rendered height 100. With the fix, both cases pass. Local packaging build number advances from 7 to 8; semantic version remains 0.2.0. This is a local fork update, not a new public upstream release.

Build 8 acceptance: the complete suite passed (67 tests, 11 suites; exit 0), release packaging and strict signing verification passed (exit 0), and the installed executable hash matches the build: `7b647f8326f589c2183c44385dc4070ae8bba2f71a5fa69d44100ee748743fa9`. The previous build 7 app bundle is retained under `.build/runtime-backup-build7/`; no account data was changed. The updated application was started at the existing local app path. CUA still times out retrieving this native menu, so the new constrained whole-popover regression test is verified, while a live click/screenshot after replacement remains unverified. Build 8 logs are retained under `.build/audit-evidence/`.

## Follow-up: current Token consumption and source limits (build 9)

The user requires current consumption rather than historical totals. A read-only live probe of the two saved account profiles using the installed official `codex-cli 0.153.1` and `account/usage/read` succeeded for both. Both returned daily buckets whose latest date was 2026-09-04; neither returned a 2026-09-05 bucket or a server update timestamp. No credentials or account identifiers were included in the probe output.

The locally generated experimental app-server schema confirms that account-wide activity supplies `dailyUsageBuckets` (`startDate`, `tokens`). It does not declare the bucket timezone or a freshness guarantee. `thread/tokenUsage/updated` is a thread-scoped notification, not an account-wide cross-device live total. The existing local session scanner is a separate local-machine source and cannot safely attribute shared session records to accounts.

Consequently a successful request must not turn a daily aggregate into a realtime value. Missing today's data must not fall back to yesterday or to zero; successful-read timestamps must be distinct from source date and from weekly-quota refresh time. Realtime scope clarification (local-machine total versus per-account cross-device total) is pending.

Build 9 implements a separate unavailable realtime primary value and explicitly dated, non-realtime official daily summaries. Each account has an independent in-flight/error state and optional last-successful-token-read timestamp; older cache files remain compatible without inventing a timestamp. Today's daily-summary coverage is labelled separately, and a manual refresh action is available. The date basis remains explicitly Beijing time; the source bucket timezone is not asserted.

Build 9 validation: 70 tests across 11 suites passed (6.321 seconds), including current-day coverage, zero-versus-missing, failed-read timestamp preservation, legacy cache compatibility, midnight boundaries, and the full-popover compact-height regression. Chinese light and English dark fixture renders were visually inspected; all four language/theme layouts were generated. Release packaging and strict signature verification passed. The installed executable matches the built artifact SHA-256 `b1b6af0c21e7feacb4601cd33b24968b56c5010dc8bfa373e7047f3ad2c1fcfe`; process PID 99202 was observed at the existing local app path. Build 8 is retained under `.build/runtime-backup-build8/`. Native accessibility retrieval still times out, so live menu interaction remains unverified. Account-wide realtime numeric consumption remains unavailable from the verified source; this update corrects presentation and does not claim to supply that metric.

Independent verifier accepted the bounded Token-date/source semantics with no blocking findings. It independently ran core checks (exit 0), confirmed the 70-test log and compact-popover regression, and inspected all four fixture layouts. Realtime-source availability and native menu interaction remain explicitly unverified/unavailable as stated above.

## Local realtime Token implementation (build 10)

Public-source research established that local realtime usage is feasible even though the account-wide daily endpoint is delayed. The existing local scanner was not wired into the application lifecycle. The implementation target is today's local-machine usage, updated when Codex writes a usage event, with an explicit Beijing natural-day basis. Shared session data must not be assigned wholesale to the currently selected account.

Current installed Codex logs additionally contain top-level `token_usage_record` records with `response_id`, per-request `usage`, and turn/thread cumulative usage. An independent, read-only sample of today's local files found 35 files with these modern records and no legacy-only usage files. Per-request totals equal input plus output; cached input and reasoning output are subsets and must not be added again. Modern records normally precede a matching legacy `token_count` event, so counting both would duplicate usage. Parent-thread cumulative counters need not match the modern thread totals, making unique request records a stronger counting source for this runtime. The reference reader emits aggregates only; it does not emit account/session/response identifiers or conversation content.

Source references: [ccusage parser](https://github.com/ccusage/ccusage/blob/603a90bf3e4aec37623bfdd237b4484dcdd0bfa4/rust/adapters/codex/src/parser.rs), [Codex Token Monitor](https://github.com/gouwenct/Codex-Token-Monitor/blob/a9ac20406f1a12fe796d824b20b34f0a405e665c/src/extension.js), and [Codex Switcher attribution](https://github.com/senoldogann/codex-switcher/blob/5fd52943961015395f4d8e0e876ca4dab58f22de/Sources/CodexSwitcher/SessionTokenParser.swift). These were reviewed as design evidence; they were not installed or executed. The account-switch-history approach is an estimate and cannot prove external/concurrent-client identity.

Live-source acceptance before packaging: a standalone probe compiled from the production scanner ran for ten seconds against the existing local log root. It emitted seven monitoring snapshots and observed the current-day total increase from 264,909,160 to 265,697,099 without restarting; subsequent polling intervals were approximately 1.03–1.27 seconds. Re-reading unique modern requests with an independent Python implementation, cut off at the final scanner timestamp, produced exactly 265,697,099 across 2,135 unique responses. Evidence is in `.build/audit-evidence/live-token-probe.jsonl` and `live-token-reference-comparison.json`; these are aggregate-only ignored artifacts. This verifies the real data/monitoring path, independently of the native menu rendering.

The UI centralizes current local-machine usage and a second-resolution event timestamp in the total row. Account cards retain only their explicitly dated non-realtime official daily summary. Local usage is not attributed to saved accounts because the shared records contain no verified account identity. Synthetic Chinese-light/English-dark realtime-state layouts and the simplified account-card layout were visually inspected.

### User-directed Tokei alignment

The user subsequently selected `cclank/tokei` as the reference. The audited revision is `72bbb5e5a7421faeaa3ec27e08f53e4bf709f997`. Its repository does not declare a license; the implementation therefore uses independently written Swift based on the documented behavior, with no bundled Tokei source, Python runtime, price fetcher, or installer. The scope remains Codex local Token usage inside this account-switching app.

The relevant presentation contract is total usage plus mutually exclusive non-cached input, cache-read input, and output, with optional per-model disclosure. Raw Codex input already contains cached input, and raw output already contains reasoning. Hence total = raw input + output = non-cached input + cached input + output; reasoning is not added again. Incomplete breakdowns stay unavailable rather than being manufactured as zeros. Reference: [Tokei calculation contract](https://github.com/cclank/tokei/blob/72bbb5e5a7421faeaa3ec27e08f53e4bf709f997/CALCULATION.md#L54-L59) and [Codex panel](https://github.com/cclank/tokei/blob/72bbb5e5a7421faeaa3ec27e08f53e4bf709f997/Tokei/Sources/Tokei/PanelView.swift#L619-L639).

For legacy logs, adopt last-request usage with consecutive full cumulative-snapshot duplicate suppression; choose the most complete physical copy of a logical session; and remove inherited parent prefixes using full usage keys and parent relationships, with conservative multi-event matching when a parent identifier is absent. Do not drop events merely because they form a rapid burst. Tokei's audited parser does not support the installed runtime's modern `token_usage_record`, so response-ID-based counting and one-second polling remain in place. References: [snapshot logic](https://github.com/cclank/tokei/blob/72bbb5e5a7421faeaa3ec27e08f53e4bf709f997/usage.30s.py#L2980-L3017), [canonical files](https://github.com/cclank/tokei/blob/72bbb5e5a7421faeaa3ec27e08f53e4bf709f997/usage.30s.py#L2825-L2854), and [prefix matching](https://github.com/cclank/tokei/blob/72bbb5e5a7421faeaa3ec27e08f53e4bf709f997/usage.30s.py#L2462-L2495).

### Final build 10 acceptance

The user requested main-agent-only execution; active delegated work was stopped, and the main agent completed the final numeric validation, layout correction, tests, packaging, installation and verification. Expanded small model lists now use intrinsic rows; the final rendered fixture exposed blank ScrollView contents, which this correction resolves. Lists above five models retain a bounded scroll viewport.

- Final full suite: 87 tests in 11 suites passed (3.990 seconds); core checks and release packaging/strict signature verification passed. Chinese light and English dark layouts were rendered; final Chinese light model rows were visually verified. Full-popover compact-height tests remain passing.
- Final production-scanner probe emitted seven snapshots in ten seconds, increasing from 314,150,065 to 314,207,849 Tokens. At the final timestamp the independent reader matched all six checks: total, non-cached input, cached input, output, model sum, and component sum. There were 2,519 unique modern requests, four models, no unknown model usage and no incomplete breakdowns in this sample.
- Installed local version: 0.2.0 (build 10), process PID 85135 at the existing app path. Built and installed executable SHA-256: `19d387a029a410607c4af3def91258dbb538aa393252458d9682cf9810e62338`. Build 9 is retained under `.build/runtime-backup-build9/` in the original checkout. No account data or credentials were modified.
- Native accessibility retrieval still times out after launch. Actual process identity and live scanner behavior are verified; clicking the installed menu and its rendered desktop appearance remain unverified. No public release, tag or upstream push is performed.
- Evidence logs and aggregate-only probes remain ignored under `.build/audit-evidence/`. The original checkout's source is preserved.

## Compact quota display correction (build 11)

The user reported a dash in the menu bar despite a 91% current-account card, and requested removal of the explanatory text. The menu presentation previously gated available quota on successful active-identity verification, while unavailable identity was deliberately quiet in the card list. The menu now displays the selected registry account's available quota consistently with its card; an explicit identity mismatch still hides it. This presentation fallback does not change switch verification or claim a successful identity read.

Removed official daily-summary/status rows from account cards and model disclosure/status/long explanation from the Token section. The primary surface retains account identity, quota/reset dates, local today's Token total, and three component totals. Source/timestamp details remain in the Token section's hover help.

Validation: 87 tests passed (3.953 seconds), including a new AppModel regression with 91% cached quota and an unavailable identity reader; core checks, release packaging, strict signing and diff whitespace checks passed. An initial test fixture lacked the synthetic credential required by AccountStore and failed before exercising the behavior; the corrected fixture passed. Synthetic native account and Token layouts were rendered and visually inspected. Installed build 11 process PID 2217 and executable SHA-256 `a00048665decb7b6f7591400fe0ee47f67cae2753240c0c9aeeeaae974283e1f` match the artifact; build 10 is backed up. Native AX retrieval still times out, so installed menu interaction remains unverified. No account switching, credential changes, public release or upstream push occurred.
