# System design

Current macOS source version: **0.2.2**. Historical design choices and acceptance observations remain in dated documents under `decisions/`, `plans/` and `testing/`.

## Application and UI

`StatusBootstrap` owns a shared `AppModel` and the native status item/popover controller. SwiftUI renders account rows, settings, login progress and switch progress from that model. A popover presentation can be rebuilt; in-flight state belongs to the model, so cancellation and progress must survive view recreation. Unconfirmed selections are ephemeral.

`AppModel` coordinates account loading, settings, usage refresh, optional reminders and warmup. Account mutations are gated. Switching cancels and awaits background requests before changing credentials. Browser login is cancellable and uses the installed Codex app-server; no tokens or OAuth callback material are pasted into the UI.

## Account storage and recovery

`AccountStore` manages profile files and active-account metadata with atomic writes and private permissions. Shared Codex history/configuration is not replaced during switching. Saved account profiles are sensitive local files, not encrypted account vaults.

`SwitchCoordinator` implements the handoff through `SwitchService.swift`: close Desktop, save the original credential, activate the target, read and verify its identity, commit active-account metadata, and reopen Desktop. Failure before a committed target triggers bounded recovery; a Desktop reopen failure after commit must not silently revert the selected identity.

`SwitchRecoveryStore` records an interrupted transaction and an encrypted short-lived rollback snapshot. New journals use a user-private local key (`local-v2`); the key provider rejects unsafe permissions and symlinks. Older journal/key formats remain readable for recovery compatibility. Do not remove these compatibility paths as unused code while they may be required to recover a user's pending transaction.

Recovery data, credentials and authentication material never belong in logs, repository fixtures, website output or release artifacts. In-process gating does not claim to lock unrelated applications writing the same Codex home.

## Codex processes

`CodexClient` speaks the installed executable's app-server protocol over child-process pipes, with bounded requests, cancellation and explicit process cleanup. Login completion has a bounded wait and a visible cancellation action. Error output and identity failures stay distinct from success.

`DesktopController` targets Codex Desktop applications and reopens the selected app. Desktop closure can interrupt active work; the UI requires confirmation. It does not terminate unrelated CLI sessions. A request accepted by the OS is not by itself proof that a usable Desktop window exists.

## Usage semantics

Service quota windows are normalized by duration. Weekly and optional exact 300-minute five-hour quotas are separate; plan-specific display rules apply. Cached quota can remain visible after refresh failure. Exhaustion warnings are based on zero remaining quota, not stale state.

`LocalSessionUsageScanner` reads local session and archive files incrementally, handles partial lines, deduplicates supported replay/copy forms, and reports today's and the last 30 calendar days' totals. Day boundaries are Beijing time. These totals cover the device's readable records and have no account identifier. A same-day derived cache can be displayed during startup scanning and is explicitly marked refreshing. Session bodies are not written to the summary cache.

`APITokenValuation` estimates supported model components using declared rates. Unknown models and incomplete components remain unpriced; this is not a subscription bill.

## Build and publication

`CITATION.cff` supplies the package version; automated checks enforce client and website alignment. Local `.app`/DMG scripts sign and verify the exact built artifact. Tag publication validates the remote main commit and runs tests. Release notes state whether the artifact is Developer ID signed and notarized or only ad-hoc signed.

The bilingual static website exposes readable content and consistent project metadata. Sitemap, canonical and language links support discovery; they do not demonstrate search indexing or traffic growth. See [discovery documentation](discoverability.md).
