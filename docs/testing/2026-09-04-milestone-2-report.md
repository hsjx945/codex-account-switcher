# Tiny Codex Switcher milestone 2 report

Date: 2026-09-04

## User-confirmed runtime

The user confirmed that a second Plus account was added and the real account-switch workflow completed successfully. This milestone did not repeat a credential-changing live switch.

## Implemented

- full email as the default label, optional nickname editing, and three display styles;
- active account presentation-first sorting and a low-saturation selected background;
- official per-account today/7-day/30-day token totals;
- local all-account model totals from available Codex rollout records;
- experimental scheduled warmup, disabled by default;
- one-attempt-per-account-per-day history, active-window fail-closed checks, verified small-model selection, read-only ephemeral execution, timeout, and persisted confirmed/unconfirmed/failed outcome.

## Verification

| Check | Result |
| --- | --- |
| `swift build` | Passed |
| `swift test` | Test bundle compiled and linked; this Command Line Tools environment still does not execute the Swift Testing bundle |
| `./scripts/run-core-checks.sh` | Executed and passed |
| JSONL scanner fixture | Executed; verified Sol 100, duplicate cumulative event 0, Luna delta 60, and timestamps with/without fractional seconds |
| Official daily bucket fixture | Executed; verified the 2,300-token bucket |
| Warmup fixture | Executed against a fake executable; verified Luna selection and no real account request |
| Warmup safety fixtures | Executed; null daily metrics stay unavailable, large-only model lists are skipped, and stalled execution times out |
| Legacy settings | Executed; verified email style, token display on, and warmup off |
| Local package | `Tiny-Codex-Switcher-0.3.0-arm64.dmg` |
| `codesign --verify --deep --strict` | Passed with local ad-hoc signature |
| `hdiutil verify` | Passed |
| SHA-256 sidecar | Passed |

Artifact size: `2,269,441` bytes. SHA-256: `c4286e739e1e1e5f56ab134b7c97524051addd08ca096f2bb2c68ee4ff2b5439`.

## Runtime smoke test

The packaged 0.3.0 menu-bar executable launched from the release app and remained alive until it was terminated by exact PID. The prior installed switcher process was left running. No account switch or real warmup was triggered.

The menu-bar-only app still does not expose its popover through the available accessibility capture surface; visual appearance is therefore not claimed as verified. Source-level layout, build, process launch, and non-destructive behavior are verified.

## Data semantics and remaining limits

- Per-account totals are server daily buckets. Model totals are local estimates across all accounts on this Mac because rollout records lack a reliable account identifier.
- Local model coverage can be incomplete when sessions were deleted, archived elsewhere, or written with an unknown schema.
- Community evidence supports the warmup hypothesis, but OpenAI does not document a guarantee that one request refreshes or starts the five-hour window.
- No real warmup was executed in this milestone.
