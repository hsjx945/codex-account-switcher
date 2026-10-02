# Windows build

This directory contains the Windows tray version of Codex Account Switcher. It targets Windows 10/11 x64 and uses the locally installed Codex CLI. It provides browser sign-in, current-account import, account switching, quota lookup, and nicknames. The macOS-only local token charts, reminders, automatic warmup, and start-at-login setting are not implemented in this Windows UI.

## Install and use

1. Install and sign in to the official Codex desktop app. The switcher looks for `codex.exe` on Windows `PATH` and under `%LOCALAPPDATA%\OpenAI\Codex\bin\<version>\`. It also accepts the `codex.cmd` command shim on `PATH`. If none is found, install the Windows Codex CLI so `codex --version` works in a new Command Prompt window, or set `CODEX_SWITCHER_CODEX_PATH` to the full path of `codex.exe`. A WSL-only CLI cannot be launched by this Windows application. The CLI supplies the app-server used for browser login and identity checks.
2. Download `Codex-Account-Switcher-Setup-win-x64.exe` and its SHA-256 file from the [Windows preview GitHub Release](https://github.com/hsjx945/codex-account-switcher/releases). Verify the checksum, then run the installer. The preview is unsigned, so Windows SmartScreen may show a warning.
3. If Codex is already signed in, click **Import current**. Otherwise click **Add** and finish sign-in in your browser. Each added account is authorized through Codex's own login flow.
4. Close the Codex / ChatGPT desktop application before switching. Select a saved account and click **Switch**. Reopen the desktop app after the success message. The app never terminates CLI sessions or desktop tasks itself.

The app stays in the system tray when its window is closed. Use **Exit** in the tray menu to quit. Browser login can be cancelled in the window.

This Windows preview has a separate, simpler interface from the macOS menu bar app. The macOS token charts, reminders, automatic warmup, and start-at-login setting are not yet present on Windows.

## Local build

On Windows with the .NET 8 SDK and Inno Setup 6:

```powershell
./scripts/package-windows.ps1
./scripts/test-windows-installer.ps1
```

Run `windows/artifacts/Codex-Account-Switcher-Setup-win-x64.exe`. The installed app does not require a separately installed .NET runtime. Uninstalling removes the application but preserves saved profiles under `%LOCALAPPDATA%\Codex Account Switcher`.

## Storage and recovery

Profiles and the registry are stored under `%LOCALAPPDATA%\Codex Account Switcher`; the active Codex credential remains under `%CODEX_HOME%\auth.json` or `%USERPROFILE%\.codex\auth.json`. Profile credential files are sensitive. Do not synchronize, share, or submit that directory. The app writes credentials using temporary files and atomic replacement. Before each switch it stores a Windows DPAPI encrypted rollback copy and a journal. On startup it verifies a committed target or restores and verifies the original account. If verification fails, the journal and backup remain for recovery.

The Windows and macOS apps use the same registry field names but have separate local profile directories. Copying raw profile files between computers is not an installation or migration flow.

The CI installer build, synthetic tests, and silent install/uninstall check do not prove a real Windows login, two-account switch, or desktop relaunch. Those require acceptance on a Windows machine with authorized accounts.
