# Milestone 6: readable cards and truthful current-day tokens

Date: 2026-09-04

## Delivered

- Expanded the popover to 420 pt and increased account, usage, reset-time, token, and model typography.
- Replaced several compact text labels with accessible SF Symbols while retaining the important numbers.
- Removed the active-account leading rail and strengthened the full-card active background and outline.
- Fixed header alignment with `当前` immediately before a fixed-width `PRO 5X`, `PRO 20X`, or `PLUS` badge.
- Suppressed five-hour usage for both official Pro plan types: `prolite` (`PRO 5X`) and `pro` (`PRO 20X`).
- Replaced the active account's missing current-day server bucket with Beijing-day local session token deltas and model attribution.
- Rendered uncovered server periods as `—`, not a misleading zero.
- Reduced local scanner overhead by skipping unrelated JSONL record types and avoiding repeated buffer-prefix copies.

## Evidence

- `swift build`
- `./scripts/run-core-checks.sh`
- `swift test --disable-xctest --enable-swift-testing` compiled the test bundle; the selected Command Line Tools environment has no `xctest`, so execution remains unverified
- real packaged menu-bar popover captured at `.build/artifacts/tiny-codex-switcher-0.5.1-final.png`
- ad-hoc signature and DMG checksum verification

The final real popup displayed a nonzero current-day local total and per-model values within a short startup observation window, showed `—` for an uncovered seven-day server period, hid five-hour usage for the real `PRO 5X` account, retained equal usage tracks, and showed no active leading rail. No account switch, warmup, or notification was triggered.

Artifact: `Tiny-Codex-Switcher-0.5.1-arm64.dmg`, `2,339,874` bytes. SHA-256: `6bfc2f4286e705b515339333d97af210d29b2e84cff67668519cd1a45b26fec4`.
