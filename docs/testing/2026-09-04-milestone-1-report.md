# Tiny Codex Switcher milestone 1 report

Date: 2026-09-04

## Automated verification

| Check | Result |
| --- | --- |
| `swift test` | Passed; includes success, rollback, interrupted activation, committed reopen retry, encrypted backup permissions, and non-reentrant operation-gate coverage |
| `./scripts/run-core-checks.sh` | Passed |
| `git diff --check` | Passed before closeout |
| Task diff secret-pattern scan | Passed; no access token, refresh token, bearer token, or API-key pattern found |
| `swift build -c release` | Passed |
| `codesign --verify --deep --strict <app>` | Passed with local ad-hoc signature |
| `hdiutil verify <dmg>` | Passed |
| `shasum -a 256 -c <sidecar>` | Passed |

Automated tests used temporary directories, fake account IDs, fake credentials, and a fixed test-only encryption key. They did not point `AccountStore` at the user's real `~/.codex`.

## Runtime smoke test

The packaged menu-bar executable launched from the release `.app`. Without initiating a switch, it discovered one active local account and persisted one usage-cache entry. The process then exited normally. No second account was added, no active credential was replaced, and the task-hosting ChatGPT Desktop process was not closed.

The menu popover could not be captured through the available accessibility surface because the application is an `LSUIElement` menu-bar-only process. Visual layout is therefore unverified in this milestone; process launch and the non-destructive account/usage path are verified.

## Artifact

- file: `.build/artifacts/Tiny-Codex-Switcher-0.2.0-arm64.dmg`
- size: `1,835,139` bytes
- SHA-256: `cb35d0ad302c4d1a6b813d3ff15c47ab4a78f8262862257a63642c825378b358`
- executable: Mach-O 64-bit arm64
- bundle version: `0.2.0` (`CFBundleVersion` 7)
- distribution status: local ad-hoc build, not Apple-notarized

## Recovery behavior

- Before mutation, the app writes an AES-GCM encrypted rollback snapshot and a `switch-journal.json` phase record under its user-only Application Support recovery directory.
- The 256-bit encryption key is stored as a this-device-only generic password in macOS Keychain.
- Before commit, a failure restores the exact original credential, original registry ID, verified original identity, and prior Desktop running state.
- After a verified commit, a Desktop reopen failure keeps the target account and retries completion at the next application launch.
- A missing or invalid recovery key, backup, or identity does not clear the journal silently; the app surfaces the failure.

## Not verified

- live A-to-B and B-to-A switching with two real accounts;
- a real production Keychain rollback entry created during a live switch;
- visual popover interaction through accessibility automation;
- Apple Developer ID signing, notarization, stapling, public release, or push CI.
