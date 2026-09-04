# Five-hour reset notifications and guarded switching

Date: 2026-09-04

## Objective

Make the current account unmistakable, notify the user when a saved account's known five-hour reset time passes, and provide a notification action that switches only after a Codex Desktop task-safety check.

## User flow

1. The active account appears first with a visible `Current` capsule and low-saturation row background.
2. The user explicitly enables five-hour reset reminders in Settings. Only then does macOS request notification permission.
3. After a previously known five-hour `resetsAt` passes, a fresh official response must advance the window to a later reset time. The app then sends one notification and persists the prior reset timestamp for dedupe.
4. The notification includes `Switch to this account`.
5. On action:
   - if the target is already active, do nothing;
   - if Codex Desktop is not running, switch directly;
   - while Desktop runs, use app-server only as a positive active signal; an independently observed idle result remains unknown and requires confirmation;
   - if an active thread exists, show a blocking confirmation before switching;
   - if task state cannot be verified, fail closed and show the same confirmation with an unknown-state warning.

## Non-goals

- no automatic account rotation;
- no task interruption or cancellation API;
- no notification permission request at application launch;
- no private ChatGPT endpoint, browser cookie, process injection, or session-content inspection;
- no direct switch when task state is active or unknown.

## Architecture

- `QuotaNotificationService`: native `UserNotifications` permission and local delivery.
- `SwitcherAppDelegate`: registers the actionable category before launch completion and routes action payloads to `AppModel`.
- `CodexClient.readDesktopTaskState`: reads official `thread/list` status, paginates safely, and returns idle/active/unknown.
- `FiveHourResetDetector`: pure transition function that deduplicates reset timestamps.
- `UsageCacheEntry.lastNotifiedFiveHourResetAt`: backward-compatible persistent deduplication.
- `AppModel.handleNotificationSwitchRequest`: applies direct/confirm decision and reuses the existing crash-safe switch coordinator.

## Security and privacy

- Notification content shows the selected visible account label, while the action payload routes only by local profile UUID; neither contains credentials or account IDs.
- Task inspection reads status only. It does not request turns, items, prompts, tool outputs, or session contents.
- Active and unknown states require an explicit modal confirmation.
- Notification actions and switch operations remain serialized through the existing switch coordinator and operation gate.

## Migration and rollback

New settings and cache fields decode with defaults (`false` and `nil`). Disabling reminders stops future delivery but preserves the last-notified timestamp to prevent old resets from being replayed. Removing the feature requires deleting the setting/UI/service wiring; existing JSON remains backward compatible.

## Validation

- legacy settings/cache decoding;
- pure reset detector transition and deduplication tests;
- fake app-server idle, active, malformed, pagination, and timeout cases;
- fake notification permission/delivery checks in executable core checks;
- notification switch disposition tests for same account, idle, active, unknown, and mutation in progress;
- `swift build`, `swift test`, executable core checks, release package, signature and DMG verification;
- real notification permission and destructive account switch are not triggered during automated acceptance.

## Acceptance criteria

- current account has a clear textual capsule;
- reminders are opt-in and permission denial leaves the setting off;
- one reset timestamp produces at most one notification per account;
- action payload cannot target a missing account;
- active or unknown task state never switches without confirmation;
- only an absent Desktop permits direct action; every action still reuses the verified switch transaction;
- no real account switch or task interruption occurs in tests.

Open questions: none. The user explicitly requested this workflow; safety defaults are fail-closed.
