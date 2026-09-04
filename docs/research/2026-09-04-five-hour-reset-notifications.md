# 5-hour reset notifications and safe switching research

Date: 2026-09-04

## Research question

Find mature implementations for quota-reset reminders, actionable macOS notifications, and protection against switching while Codex is running a task.

## Search rounds

1. `Codex usage notification macOS account switcher Swift UserNotifications`, `Claude Code usage alert reset notification macOS`
2. `codexbar usage notification UserNotifications`, `Claude account switcher quota alert notification`
3. OpenAI app-server `thread/list status active` and Apple notification action/delegate documentation

## Candidate matrix

| Candidate (pinned revision) | License | Useful evidence | Missing boundary |
|---|---|---|---|
| CodexBar `392310c665485f8d57c93881e7416c5ebf69d8ef` | MIT | Native authorization, stable IDs, quota transition and dedupe tests | No account-switch action |
| xjoker/codex-switch `a3392f6155f137149f44cd3a81337d35ec6739b5` | MIT | Defers switching when an interactive process is detected | Process scan is best-effort |
| 4LAU/codex-profile-switcher `4f2f313b5156be84341f21ce43a73b501ff5dc3a` | MIT | Identity gate and transactional rollback | No notifications or task-state check |
| claude-code-account-switcher `e31072c4179ec71910e4dafc22cf99964ed53a98` | MIT | Active-account label and per-account cache | No native notifications |
| claude-codex-monitor `7e637ce35f8537e0869f2219269957143da33957` | MIT | Reset reminders and per-account dedupe | Usage pace is not task state |
| claude-usage-monitor `3770ae984695d45db1ce32c473a47232ff0b8f46` | MIT in package metadata | Per-account alert state and click-to-foreground | Session activity is heuristic |

## Primary-source findings

- Apple requires categories/actions to be registered at launch and the notification-center delegate to be installed before launch finishes. A foreground action can route a UUID into the app delegate.
- OpenAI app-server documents `thread/list` statuses `notLoaded`, `idle`, `active`, and `systemError`. `active` is a positive running-turn signal in the observable daemon.
- A separate app-server process cannot prove global liveness for every Desktop/CLI process. `notLoaded`, errors, malformed results, timeouts, and pagination uncertainty remain `unknown`.

Primary references:

- [OpenAI Codex app-server README](https://github.com/openai/codex/blob/048a936a23b88c8653f4820e68f987de10e3c583/codex-rs/app-server/README.md)
- [UNUserNotificationCenterDelegate](https://developer.apple.com/documentation/UserNotifications/UNUserNotificationCenterDelegate)
- [Handling notification actions](https://developer.apple.com/documentation/usernotifications/handling-notifications-and-notification-related-actions)
- [Declaring actionable notification types](https://developer.apple.com/documentation/usernotifications/declaring-your-actionable-notification-types)

## Adopted design

1. Reminder is opt-in; permission is requested only when enabled.
2. Passing the old timestamp is insufficient. A fresh official response must advance the five-hour window.
3. Dedupe is persisted per profile and prior reset timestamp; failed delivery does not consume it.
4. Payload routes only by local profile UUID and contains no credentials or tokens.
5. The foreground action enters `AppModel` before switching.
6. Direct switching requires Desktop to be absent. An independently spawned app-server cannot prove that the running Desktop daemon is idle.
7. While Desktop runs, `active` produces a specific warning; `idle`, `notLoaded`, system error, malformed/partial data, timeout, or an unreachable daemon remains unknown and requires confirmation.
8. Existing transactional `SwitchCoordinator` remains the only credential mutation path.

## Reliability boundary

The notification says quota is *expected to have refreshed*: it observes an official reset-window transition, not a billed test request. Task-state detection cannot prove the absence of activity in every unrelated CLI/app-server process. Unknown state never causes a silent switch.

## Claude scope recommendation

Claude usage and switching is valuable as a separate provider adapter after this Codex path is stable. Do not mix Claude credentials into the current coordinator: auth storage, usage source, process model, and liveness signals need independent research and tests. The UI shell and provider-neutral statistics model can be reused later.
