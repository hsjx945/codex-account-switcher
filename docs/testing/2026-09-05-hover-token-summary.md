# Single-line token summary

User accepted removing account-level Token display because reliable live attribution
is unavailable. Account cards now contain identity/quota/warmup only. The bottom row
is labeled 今日消耗 Token, with K/M/B total and combined API estimate. An asterisk
marks partial price coverage; details retain the priced-subtotal label and unknown
models. This remains local usage, not a new account attribution mechanism.

Model and component details move to a native SwiftUI popover attached to the side.
A cancellable one-second hover task opens it; leaving before one second cancels.
Click/accessibility action also toggles it. Leaving the source after opening does
not close it immediately, allowing interaction with detail content; normal native
popover dismissal applies. Source disappearance cancels the task and closes details.

Validation: 95 Swift tests pass, including K/M/B boundaries, collapsed summary sizing
and expanded details rendering. Native synthetic renders are in .build/hover-summary.png
and .build/hover-summary.png.details.png. Release build and strict codesign passed.
Installed at the pre-existing app path, previous app preserved as
Codex Account Switcher.before-hover-summary.app. PID 82386 runs the installed build;
SHA-256 equals the built executable:
12b949d93f68e77570d5b67d5b05ebbdad4650799e70ba2d3fcf051bd75935e6.

Actual menu selection still times out through native UI automation, so real pointer
hover timing and screen-edge placement remain unverified. Synthetic rendering does
not establish those interaction outcomes. No credentials or real usage fixtures saved.
