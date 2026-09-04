# Tiny Codex Switcher handoff

Date: 2026-09-04

Accepted source: ChatGPT conversation `6a9a1f51-6f84-83e8-9664-98f3b9b12e6f`

Upstream baseline: `liuzhao1225/codex-account-switcher@1e406ab9b5e8fb8e8a1286354916740676b35f2a`

The original conversation referenced a longer generated document that was not attached to the task. This file records the accepted decisions visible in the conversation and the implementation boundary used by this repository. It does not claim byte-for-byte identity with the missing document.

## Objective

Deliver a native macOS menu-bar application that lets one person add authorized ChatGPT/Codex accounts, see the active identity and usage windows, and manually switch accounts without Terminal commands.

The safety invariant is:

> A switch ends with a verified target account, or restores and verifies the exact original account. It must not silently stop between identities.

## Required first milestone

- preserve the existing SwiftUI menu-bar product and shared `~/.codex` history/configuration;
- serialize login, usage refresh, account deletion, and account switching;
- persist a `SwitchJournal` before changing the active credential;
- encrypt the exact rollback credential with an AES-GCM key stored in macOS Keychain;
- verify the target through the official Codex app-server `account/read` method;
- restore the original registry entry, exact credential, identity, and prior Desktop running state on failure;
- recover an interrupted transaction at application startup;
- preserve a verified committed target if only Desktop reopening failed;
- use temporary directories and fake credentials in automated tests; never test against the user's real `~/.codex`.

## Product scope

Included:

- macOS 14+, Apple Silicon personal build;
- English and Simplified Chinese;
- browser OAuth through Codex app-server;
- manually confirmed switching;
- active-account indication, 5-hour and weekly usage, reset time, cached/stale state;
- ChatGPT.app and legacy Codex.app discovery;
- launch at login;
- local `.app` packaging and checksum.

Deferred until the transaction core is stable:

- project-to-account bindings;
- “switch and open project” shortcuts;
- broader credential backends beyond official file mode;
- signed/notarized public distribution.

Excluded:

- automatic account rotation or quota evasion;
- account pools or multi-user sharing;
- third-party relays, remote control, telemetry, or cloud credential upload;
- browser-cookie reading or private ChatGPT web API reverse engineering;
- killing unrelated CLI processes.

## Source and license boundary

- The only code baseline is the MIT-licensed `liuzhao1225/codex-account-switcher` commit above.
- Other switchers are evidence for common requirements only unless their exact license and source are re-audited.
- No code, UI assets, README prose, or commits are copied from other candidates.
- OpenAI Codex app-server is used as an installed external executable over stdio; its source is not vendored.

## Acceptance

The first milestone is acceptable when:

1. `swift test` passes, including encrypted-backup and interrupted-switch cases.
2. `./scripts/run-core-checks.sh` passes.
3. A local arm64 `.app` packages and passes `codesign --verify`.
4. The package contains no credentials or private account data.
5. Real two-account switching is reported separately and remains unverified until the user chooses to perform it outside the task-hosting ChatGPT process.
