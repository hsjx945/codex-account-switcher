# Value sections and explicit switch confirmation

- Hover exit cancels the one-second timer and closes the side popover immediately.
- Summary has blue token and orange estimated-value cards; no asterisk. Partial
  valuation coverage is labeled 已计价 in the value heading, preserving truthfulness.
- Inactive account clicks set a pending target. Only the affirmative alert button
  starts the switch; cancel clears the pending target. The formerly direct idle
  notification switch path now also asks for confirmation.

Validation: 95 Swift tests passed; release build and strict signature verification
passed. Synthetic native summary rendered at 420 pt and visually reviewed at
.build/value-sections.png. Installed at existing app path; previous binary retained
as Codex Account Switcher.before-value-confirm.app. Native menu automation still
returns timeout: real hover-exit and confirmation interaction remain unverified.
No real account switch was executed by this task. User confirmation is required.
