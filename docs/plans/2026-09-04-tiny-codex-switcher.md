# Tiny Codex Switcher accepted implementation plan

## Objective and non-goals

Build a personal macOS menu-bar Codex account switcher from the pinned S001 baseline. The first milestone hardens identity switching and produces an installable local build. It does not add automatic rotation, remote services, browser-cookie access, project binding, or public release automation.

## Runtime and components

- macOS 14+, Swift 6.2+ and SwiftUI `MenuBarExtra`;
- `AccountStore` actor for profile metadata and atomic credential installation;
- `AccountOperationGate` actor for serial account operations;
- `SwitchCoordinator` actor for transaction ordering;
- `SwitchRecoveryStore` actor for journal and AES-GCM rollback storage;
- macOS Keychain generic-password item for the 256-bit rollback key;
- Codex app-server over stdio for identity, OAuth, and usage;
- `DesktopController` for `com.openai.codex`, `/Applications/ChatGPT.app`, and legacy `/Applications/Codex.app`.

## Transaction

1. Resolve target and registered original identity.
2. Read the exact active credential.
3. Encrypt it and persist `SwitchJournal.prepared` before mutation.
4. Record whether Desktop was running, then close it only if necessary.
5. Save the outgoing refreshed credential into its profile.
6. Atomically activate the target credential.
7. Verify target account ID or email through `account/read`.
8. Commit the target registry ID.
9. Reopen Desktop only if it was running.
10. Delete journal and encrypted rollback file.

Every completed phase is written atomically. Any failure before commit restores the encrypted original bytes, commits the original registry ID, verifies the original identity, restores Desktop state, and then clears recovery data. A post-commit reopen failure preserves the verified target and leaves the journal for startup retry.

## Startup recovery

- no journal: continue normal startup;
- phase `committed`: verify target, reopen Desktop if previously running, clear recovery;
- any earlier phase: restore and verify original, reopen if previously running, clear recovery;
- missing key, missing backup, identity mismatch, or filesystem failure: keep evidence and show an actionable error; do not silently continue.

## Security and privacy

- profile directories `0700`, credential, journal, and backup files `0600`;
- no credential contents in logs, errors, tests, docs, Git, or UI;
- rollback key uses `AfterFirstUnlockThisDeviceOnly` Keychain accessibility;
- AES-GCM provides confidentiality and integrity for short-lived rollback data;
- automated tests use fixed fake keys and temporary paths only;
- no network listener, telemetry, proxy, browser-cookie access, or cloud sync.

## Validation and acceptance

- unit: success, failures, exact rollback bytes, committed restart, interrupted activation, encryption and permissions;
- core checks: storage, app-server JSONL, usage normalization, timer behavior, failure visibility;
- build: debug and release SwiftPM builds;
- package: ad-hoc signed arm64 `.app`, `codesign --verify`, SHA-256;
- real UI: launch the packaged menu-bar app without switching the hosting account;
- real double-account switch: explicitly reported as unverified until run outside the task-hosting Desktop session.

## Milestones

1. Pinned upstream and license/source audit.
2. Transaction coordinator, encrypted recovery, startup recovery, and serialization.
3. Automated verification and local installable build.
4. User-run real two-account acceptance.
5. Deferred: project binding and switch-and-open workflows.

## Stop conditions

Stop before public release, notarization, real account mutation, or closing the task-hosting ChatGPT app without an exact new user instruction. Stop and preserve recovery evidence if Keychain or identity verification fails.
