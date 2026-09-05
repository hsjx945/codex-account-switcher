# Live account usage follow-up

Scope: menu-bar five-hour/week quota, direct switching, automatic token refresh,
and account-specific token presentation. Based on `2b24f5a`, matching the existing
UI development line; main and the earlier UI worktree are preserved.

- Menu title now orders five-hour / weekly remaining percentages. Missing windows
  remain `—`; stale results retain `!`; identity conflicts hide the quota.
- Clicking an inactive account starts the existing transactional switch immediately.
- Recovery reuses an already authorized Keychain key in memory for the lifetime of
  its actor. ACL, encryption, and denial behavior are unchanged. The installed app
  uses ad-hoc signing with a cdhash requirement; no valid signing identities were
  available. This change does not guarantee prompt-free access after app restarts
  or rebuilds. No real account switch or Keychain prompt was completed for testing.
- Each account shows its own server-reported current-day token bucket. Automatic
  account polling is 30 seconds; local incremental event scanning remains 1 second.
  No refresh button remains in the token area. Missing account data stays `—`.
- Local token event and session metadata schemas sampled on this machine lacked
  billing-account identity. The shared local aggregate is explicitly unassigned;
  it is not allocated by whichever account happens to be active. Local and remote
  totals cover different scopes and must not be added together.

Validation:

- `scripts/run-swift-tests.sh`: 88 tests in 11 suites passed, including incremental
  updates, account isolation, compact popover sizing and recovery-key reuse.
- `scripts/run-core-checks.sh`: `Core checks passed`.
- `scripts/package-local-app.sh`: release build and strict codesign verification
  passed. Installed at the pre-existing main-worktree app path; previous app kept
  beside it as `Codex Account Switcher.before-live-usage.app`.
- Runtime PID 45802 uses that installed path. Built and installed executable
  SHA-256 both `42733f723890af4319dd5a07e41ddc47824128169e5d8f1e9bede2e9cccecf40`.
- Native UI automation timed out selecting the menu-only app; Finder capture was
  blank. Actual menu rendering and end-to-end account switching remain unverified.

Status: partial. Historical local account attribution and unconditional password-free
switching remain unavailable; neither synthetic tests nor installing a binary proves them.
