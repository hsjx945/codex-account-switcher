# Tiny Codex Switcher decision ledger

| ID | Stable decision | Alternatives rejected | Verification |
| --- | --- | --- | --- |
| D001 | Use S001 at pinned commit as the only inherited codebase | New app, Electron, multi-repo code merge | Git parent and MIT license |
| D002 | Preserve one shared `~/.codex` history and configuration pool | Separate full homes and duplicated history | Store paths and handoff |
| D003 | Manual, confirmed account selection only | Automatic quota rotation | UI flow and non-goals |
| D004 | Official app-server over stdio for OAuth, identity, and usage | Browser cookies, private web APIs, local network service | CodexClient and O001 |
| D005 | File-backed profiles plus AES-GCM rollback backup with Keychain key | Plaintext rollback file, silent best-effort copy | Encryption and permission tests |
| D006 | Persist every transaction phase and recover on startup | Memory-only stages | Interrupted activation test |
| D007 | Preserve a verified committed target on Desktop reopen failure | Roll back a successfully committed account | Committed recovery test |
| D008 | Serialize account mutations and app-server profile operations | Parallel per-profile refresh during switching | Shared AccountOperationGate |
| D009 | Do not touch real `~/.codex` in automated tests | End-to-end mutation of user credentials | Temporary-path fixtures |
| D010 | Do not close the task-hosting ChatGPT app for acceptance | Self-terminating live switch during development | Closeout reports real switch unverified |
| D011 | Treat the user's completed two-account Plus switch as live A/B acceptance | Repeating a credential-changing switch during this milestone | User confirmation on 2026-09-04 |
| D012 | Default to the full sign-in email; store an optional nickname and offer email, nickname, or both as a global display style | Reusing the historical email local-part as the default label | Legacy decode and nickname persistence checks |
| D013 | Sort the active account first only in the presentation layer and use a fixed low-saturation gray-blue background | Reordering the registry or using a vivid accent color | `displayedAccounts` and AccountRow |
| D014 | Use official `account/usage/read` daily buckets for per-account totals; show locally scanned model totals separately for all accounts on this Mac | Falsely attributing rollout models to an account without a reliable account ID | RPC and synthetic JSONL delta checks |
| D015 | Keep 5-hour warmup experimental, disabled by default, once per account per local day, and skip an active server window | Silent always-on pings or automatic account rotation | Legacy settings, history, model selection, and fake-exec checks |
| D016 | Defer Claude subscription switching/quota to a separate provider milestone; consider read-only local Claude statistics first | Mixing unrelated credential and quota semantics into the Codex data path | Research note and public API boundary |
| D017 | Show the active account with both presentation-first ordering, a low-saturation row, and an explicit Current capsule | Relying on color or ordering alone | AccountRow source and build; packaged visual capture remains unavailable |
| D018 | Five-hour reset reminders are opt-in and request macOS authorization only when enabled | Prompting at launch or enabling silently | Legacy settings and fake permission checks |
| D019 | Deduplicate reminders by the server-provided five-hour reset timestamp persisted per profile | Repeated notification on every five-minute refresh | Reset detector and cache migration checks |
| D020 | A notification action may switch directly only when Desktop is absent; while Desktop runs, active status gets a specific warning and every other independently observed status remains unknown and requires confirmation | Treating a separate app-server's idle result as proof that Desktop is idle | Fake thread/list status matrix and switch-disposition checks |
| D021 | Read `account.planType` from official `account/read`, distinguish Plus/Pro/Pro Lite badges, format all account-row timestamps as Chinese Beijing time, and render a 5-hour row only for an exact server-provided 300-minute window | Guessing a plan from quota size, conflating Pro Lite with Pro, hard-hiding all Pro windows, system-locale English dates, or content-driven bar widths | Account identity fixtures, Beijing formatter check, weekly-only window check, and fixed AccountRow bar width |
| D022 | Expand the popover to 400 pt, remove the non-informative initials avatar, label `prolite` as `PRO 5X` and `pro` as `PRO 20X`, and distinguish the active account with a dynamic neutral card plus a thin accent rail, outline, and explicit badge | A cramped 326 pt layout, large colored selection fills, hard-coded gray-blue backgrounds, or color-only state | Packaged 0.5.0 popover screenshot, plan badge tests, and source inspection |

Open material questions: incremental rollout indexing, statistics completeness UI, project-to-account bindings, usage alerts, and an optional Claude provider. Public signing, notarization, and release remain separately authorized actions.
