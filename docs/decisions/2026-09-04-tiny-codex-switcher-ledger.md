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

Open material questions: none for milestones 1-3. Public signing identity, notarization, project bindings, and real two-account acceptance are separate later decisions.
