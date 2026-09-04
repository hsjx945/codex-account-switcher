# Codex account switcher source audit

## Scope and method

This audit verifies the accepted fork direction rather than reopening product selection. Research was performed on 2026-09-04 with three query strategies:

1. breadth: `Codex account switcher macOS SwiftUI`;
2. implementation boundary: `Codex multi account manager auth.json account/read`;
3. due diligence: `Codex account switcher license Swift menu bar rollback`.

The local baseline, source files, tests, package manifest, release script, and license were inspected before external candidates. Four additional repositories were shallow-cloned with blob filtering for source inspection. Observed research transfer was about 16 MiB.

## Candidate matrix

| ID | Candidate and pinned revision | License checked | Useful evidence | Decision |
| --- | --- | --- | --- | --- |
| S001 | `liuzhao1225/codex-account-switcher@1e406ab9b5e8fb8e8a1286354916740676b35f2a` | MIT | Native SwiftUI shell, app-server RPC, profile store, packaging and tests | Adopt as sole code baseline |
| S002 | `4LAU/codex-profile-switcher@4f2f313b5156be84341f21ce43a73b501ff5dc3a` | MIT | Transaction service, startup identity gate, Keychain-backed design | Requirement comparison only; no copied code |
| S003 | `pengshengege/CodexAccountSwitcher@f67fc681e6eae969462dca71c42eebe5af8daa36` | MIT | Isolated login, file and Keychain vault boundaries | Requirement comparison only; no copied code |
| S004 | `edihasaj/codex-account-switcher@5acfb58360969746fc75718d52113db5cc10c5e3` | MIT | Two isolated Desktop instances using separate homes | Reject: different runtime model |
| S005 | `ZOONGG/codex-swap-account@f3e2073a46fb5c74b1246ca05ac5c9ebfe4613a9` | MIT | Windows rollback and overlay failure modes | Requirement comparison only; wrong platform and stack |

## Source anchors

- S001: [baseline SwitchService](https://github.com/liuzhao1225/codex-account-switcher/blob/1e406ab9b5e8fb8e8a1286354916740676b35f2a/Sources/CodexAccountSwitcher/SwitchService.swift) and [baseline tests](https://github.com/liuzhao1225/codex-account-switcher/blob/1e406ab9b5e8fb8e8a1286354916740676b35f2a/Tests/CodexAccountSwitcherTests/SwitchServiceTests.swift) establish the switch order and missing crash persistence.
- S002: [ProfileTransactionService](https://github.com/4LAU/codex-profile-switcher/blob/4f2f313b5156be84341f21ce43a73b501ff5dc3a/Sources/CodexProfileCore/Profiles/ProfileTransactionService.swift) and [StartupIdentityGate](https://github.com/4LAU/codex-profile-switcher/blob/4f2f313b5156be84341f21ce43a73b501ff5dc3a/Sources/CodexProfileSwitcherApp/StartupIdentityGate.swift) confirm transaction and identity-gate vocabulary. The Tiny implementation was independently written against its own protocols.
- S003: [KeychainVault](https://github.com/pengshengege/CodexAccountSwitcher/blob/f67fc681e6eae969462dca71c42eebe5af8daa36/Sources/SwitcherCore/KeychainVault.swift) and [CodexAuthFileManager](https://github.com/pengshengege/CodexAccountSwitcher/blob/f67fc681e6eae969462dca71c42eebe5af8daa36/Sources/SwitcherCore/CodexAuthFileManager.swift) confirm separation between credential-file operations and key storage.
- S004: [CodexAccountSwitcher.swift](https://github.com/edihasaj/codex-account-switcher/blob/5acfb58360969746fc75718d52113db5cc10c5e3/Sources/CodexAccountSwitcher.swift) uses independent `CODEX_HOME` plus Desktop data directories, which conflicts with the accepted shared-history approach.
- S005: [AuthSwitchService.cs](https://github.com/ZOONGG/codex-swap-account/blob/f3e2073a46fb5c74b1246ca05ac5c9ebfe4613a9/src/CodexProfileOverlay.Core/Services/AuthSwitchService.cs) demonstrates a Windows-specific rollback surface and was not used as source code.
- O001: [OpenAI app-server README](https://github.com/openai/codex/blob/048a936a23b88c8653f4820e68f987de10e3c583/codex-rs/app-server/README.md) documents the account JSON-RPC surface.

## Recommendation and residual uncertainty

Keep S001 as the only inherited codebase. Independently implement journaled recovery, Keychain-protected rollback encryption, and serialization in the fork. Do not adopt multi-instance Desktop launching or automatic quota-based rotation.

The installed Codex app-server is version `0.153.0-alpha.5`; protocol drift remains possible. Runtime integration therefore needs a real non-secret smoke test before public distribution. Real two-account switching is intentionally not run while this task itself is hosted by the same ChatGPT desktop application.

No separate visual-reference set was needed: the accepted task preserves the existing menu layout and does not introduce a large information-architecture change.
