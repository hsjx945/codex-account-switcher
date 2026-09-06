# Recovery key without Keychain password prompts

User reported a login-password prompt and switch failure after installing the app in
Applications. Screenshot status -128 matches errSecUserCanceled in the local macOS
Security SDK. It does not establish that the entered password was incorrect. The
installed application has an ad-hoc cdhash signing requirement; legacy key access
was tied to Keychain authorization. No pending switch journal existed before update.

New switches use an AES-256-GCM backup with a random key under the existing recovery
folder, owner-only directory 0700 and key file 0600. This replaces Keychain protection
with the same OS-user permission boundary as existing local account credentials;
processes running as that user are within this boundary. The tradeoff was disclosed
in the conversation. Existing Keychain entries and credentials are not read or changed.

Local key reads check owner, type, permissions, length, link count and reject symlinks.
Creation is exclusive, initially private, and flushed before preparing the journal.
New journals record local-v2. Legacy journals retain their original format and use
noninteractive Keychain lookup only, never creating a replacement key on recovery.
Missing or unsafe local keys fail closed and preserve the journal and encrypted backup.
Unknown journal key formats fail closed. An interrupted key creation leaves invalid
material rather than silently replacing a key that could protect a pending backup.

Verification:

- 99 Swift tests / 13 suites passed: includes local encryption, restart recovery,
  missing-key preservation, symlink/permission rejection and legacy journal decoding.
- Core checks passed. Release build and strict codesign verification passed.
- macOS reports a deprecation warning for the legacy-only noninteractive Keychain
  query flag; compilation succeeds. Normal new switches do not call that provider.
- Updated /Applications/Codex Account Switcher.app; preserved the previous app under
  .build/before-local-recovery. Runtime PID 63470 uses the Applications path.
- Built and installed executable SHA-256 match:
  66d50deffedbed2cbf644af315bb61f2dc400900e0a237d8c363f743949e9946.
- Native app selection timed out. No real account switch was executed, respecting
  the user's requirement to personally confirm before switching. End-to-end live
  switching is therefore unverified, not a claimed pass.

Application switch confirmation remains required. No system login password reset,
Keychain ACL modification, secret export, real credential fixture, or public release.
