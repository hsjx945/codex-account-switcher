# Compact summary and Pro menu quota

- Pro and Pro Lite reuse the account-card capability rule: menu bar displays only
  weekly remaining quota, even if cached data includes a five-hour window. Plus
  retains five-hour / weekly order. Accessibility text uses the same rule.
- Summary retains total tokens, per-model tokens/API estimates and priced subtotal.
  Removed component breakdown, explanatory paragraph and last-event timestamp from
  visible layout. Explanations and valuation caveats remain in hover help.
- Title and subtotal 15 pt, model rows 14 pt, total 20 pt; primary foreground.
- Local event monitoring and independent 30-second account polling remain enabled.
  Additional account-usage thread-detail probe produced no usable thread mapping.
  Per-account real-time token attribution remains unresolved: local logs lack billed
  account identity and older running processes may keep an earlier account after a
  switch. No active-account-based attribution heuristic was introduced.

Verification: 94 Swift tests / 12 suites passed; release build and strict codesign
passed; `.build/compact-summary.png` is a synthetic native render, visually reviewed.
Installed to existing app path with previous binary retained as
`Codex Account Switcher.before-compact-summary.app`. Native menu automation still
returned timeout; actual post-install menu rendering remains unverified.

Status: partial because reliable per-account live attribution is still unavailable.
