# Windows build

This directory contains the Windows tray version of Codex Account Switcher. It targets Windows 10/11 x64 and uses the locally installed Codex CLI. It provides browser sign-in, current-account import, account switching, quota lookup, and nicknames. The macOS-only local token charts, reminders, automatic warmup, and start-at-login setting are not implemented in this Windows UI.

## Install and use

1. Install and sign in to the official [ChatGPT desktop app](https://help.openai.com/en/articles/20001276-moving-to-the-new-chatgpt-desktop-app) or Codex app, and install the official Codex CLI so `codex` works in a new Command Prompt window. The CLI supplies the app-server used for browser login and identity checks.
2. Download the `codex-account-switcher-windows-test` artifact from a successful CI run, verify the SHA-256 file, unzip it, and start `CodexAccountSwitcher.Windows.exe`. This CI artifact is an unsigned test build. Windows SmartScreen may show a warning.
3. If Codex is already signed in, click **Import current**. Otherwise click **Add** and finish sign-in in your browser. Each added account is authorized through Codex's own login flow.
4. Close the Codex / ChatGPT desktop application before switching. Select a saved account and click **Switch**. Reopen the desktop app after the success message. The app never terminates CLI sessions or desktop tasks itself.

The app stays in the system tray when its window is closed. Use **Exit** in the tray menu to quit. Browser login can be cancelled in the window.

## Local build

On Windows with the .NET 8 SDK:

```powershell
dotnet run --project windows/tests/CodexAccountSwitcher.Tests.csproj --configuration Release
dotnet publish windows/CodexAccountSwitcher.Windows.csproj --configuration Release --runtime win-x64 --self-contained true -p:PublishSingleFile=true --output windows/artifacts/app
```

Run `windows/artifacts/app/CodexAccountSwitcher.Windows.exe`. The app does not require a separately installed .NET runtime when built this way.

## Storage and recovery

Profiles and the registry are stored under `%LOCALAPPDATA%\Codex Account Switcher`; the active Codex credential remains under `%CODEX_HOME%\auth.json` or `%USERPROFILE%\.codex\auth.json`. Profile credential files are sensitive. Do not synchronize, share, or submit that directory. The app writes credentials using temporary files and atomic replacement. Before each switch it stores a Windows DPAPI encrypted rollback copy and a journal. On startup it verifies a committed target or restores and verifies the original account. If verification fails, the journal and backup remain for recovery.

The Windows and macOS apps use the same registry field names but have separate local profile directories. Copying raw profile files between computers is not an installation or migration flow.

The CI build and synthetic tests do not prove a real Windows login, two-account switch, or desktop relaunch. Those require acceptance on a Windows machine with authorized accounts.
