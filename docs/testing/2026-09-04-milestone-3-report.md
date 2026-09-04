# Tiny Codex Switcher milestone 3 report

Date: 2026-09-04

## Implemented

- explicit, low-saturation `Active` / `当前` capsule on the presentation-first account row;
- opt-in five-hour reset reminders, with permission requested only when enabled;
- fresh official window-transition confirmation and persisted per-profile reset dedupe;
- native foreground notification action routed only by local profile UUID;
- official `thread/list` preflight and fail-closed switch policy;
- direct switch only when Desktop is absent; an independent idle result is not treated as proof of Desktop idleness;
- blocking confirmation for active, not-loaded, malformed, errored, timed-out, or otherwise unknown task state.

## Verification

| Check | Result |
| --- | --- |
| `swift build` | Passed |
| `swift test` | Test bundle compiled and linked; this Command Line Tools environment does not execute the Swift Testing bundle |
| `./scripts/run-core-checks.sh` | Executed and passed |
| Notification switch policy | Executed; idle direct, active/unknown confirm, same-account no-op, mutation blocked |
| Reset transition and dedupe | Compiled in Swift Testing; executable core check verifies persisted dedupe and legacy migration |
| Official task status fixture | Executed; active thread blocks direct switching |
| Permission injection | Executed with a fake service; authorization is requested on enable and reminders remain legacy-default off |
| Real notification permission/delivery | Intentionally not triggered |
| Real credential switch | Intentionally not repeated; the user already confirmed the two-account path before this milestone |
| Local package | `Tiny-Codex-Switcher-0.4.0-arm64.dmg` |
| `codesign --verify --deep --strict` | Passed with local ad-hoc signature |
| `hdiutil verify` | Passed |

Artifact size: `2,343,715` bytes. SHA-256: `358dfde58f7944650ed6a2a6ad80634f175c26b0ca8711faf5d35e40ea47e8ca`.

## Runtime smoke test

The packaged 0.4.0 menu-bar executable launched from the release app and remained alive until terminated by exact PID. No permission prompt, notification delivery, warmup, or account switch was triggered.

The menu-bar-only `LSUIElement` popover timed out in the available accessibility capture surface. Visual appearance is therefore unverified; source layout, compilation, packaging, signature, and process launch are verified.

## Reliability boundary

- A reminder requires a fresh official response that advances the five-hour reset window; local wall-clock passage alone is insufficient.
- Its dedupe marker is durably written before delivery and rolled back on a reported delivery failure. A process crash in the narrow interval before delivery can suppress, rather than duplicate, that reminder.
- `active` is a positive running-task signal. A separate app-server cannot prove the running Desktop daemon is idle, so every non-active observation while Desktop runs still requires confirmation.
- Notification actions never bypass the existing journaled, identity-verified switch coordinator.
