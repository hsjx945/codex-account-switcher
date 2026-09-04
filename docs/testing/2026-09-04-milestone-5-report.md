# Milestone 5: roomier account cards and Pro labels

Date: 2026-09-04

## Delivered

- Expanded the menu-bar popover from 326 pt to 400 pt.
- Removed the initials avatar from both the main account cards and account-management rows.
- Increased card spacing, padding, corner radius, typography, and fixed usage-track size.
- Replaced the full gray-blue active fill with a dynamic system-neutral card, thin accent rail, subtle outline, and explicit `当前` badge.
- Displayed official `prolite` as `PRO 5X` and `pro` as `PRO 20X`; Plus remains `PLUS`.

## Evidence

- `swift test --disable-xctest --enable-swift-testing` compiled the test bundle; the selected Command Line Tools environment has no `xctest`, so test execution remains unverified
- `./scripts/run-core-checks.sh`
- ad-hoc signed local 0.5.0 application and verified DMG
- real menu-bar popover opened without switching accounts and captured at `.build/artifacts/tiny-codex-switcher-0.5.0-final.png`
- account-management page opened and captured at `.build/artifacts/tiny-codex-switcher-0.5.0-manage-final.png`

The real popup shows two accounts, equal 104 pt usage tracks, Chinese Beijing reset times, the active account first, and no initials avatar. No account switch, warmup, or notification was triggered during verification.

Artifact: `Tiny-Codex-Switcher-0.5.0-arm64.dmg`, `2,337,254` bytes. SHA-256: `daccc3993d65db3198b12b164bb94c38f278f4ff30888845724f714d794cfe59`.
