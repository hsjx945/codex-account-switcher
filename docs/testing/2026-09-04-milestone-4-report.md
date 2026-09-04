# Tiny Codex Switcher milestone 4 report

Date: 2026-09-04

## Implemented

- fixed 78-point usage-bar width so five-hour and weekly rows align;
- Chinese `M月d日 HH:mm` formatting in the `Asia/Shanghai` time zone for quota resets and warmup records;
- official `account/read.account.planType` parsing and persisted Plus/Pro metadata;
- `PLUS` / `PRO` / `PRO LITE` account-row badges;
- server-driven five-hour visibility: the row appears only when a normalized exact 300-minute window exists, regardless of plan name.

## Data semantics

Plan identity comes from the official app-server account response and is never inferred from quota percentages. A Pro account with no 300-minute window shows only weekly usage. If the backend later returns an exact 300-minute window, the row appears automatically without a client update.

Primary sources: [OpenAI app-server account documentation](https://github.com/openai/codex/blob/main/codex-rs/app-server/README.md#auth-endpoints) and [GetAccountResponse schema](https://github.com/openai/codex/blob/main/codex-rs/app-server-protocol/schema/json/v2/GetAccountResponse.json).

## Verification boundary

Automated checks cover official plan decoding, backward-compatible profile storage, Beijing timestamp output, exact-window normalization, and executable core behavior. The packaged 0.4.1 menu-bar popover was opened through its real `LSUIElement` menu item and captured at `.build/artifacts/tiny-codex-switcher-0.4.1-final.png`; it shows equal-width usage tracks, Chinese Beijing timestamps, `PLUS`, `PRO LITE`, and `当前` without clipping.

| Check | Result |
| --- | --- |
| `swift build` | Passed |
| `swift test` | Test bundle compiled and linked; this environment did not print a Swift Testing execution summary |
| `./scripts/run-core-checks.sh` | Executed and passed |
| Real packaged popover | Opened and visually verified without switching accounts |
| `codesign --verify --deep --strict` | Passed with local ad-hoc signature |
| `hdiutil verify` | Passed |

Artifact: `Tiny-Codex-Switcher-0.4.1-arm64.dmg`, `2,345,442` bytes. SHA-256: `63b55ef4aa53e25192b12ae1c67b4dac8e33e8fd0ba60c78b85090576e15ad9b`.
