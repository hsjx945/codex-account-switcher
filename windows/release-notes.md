## Windows preview / Windows 测试版

This is an **unsigned Windows 10/11 x64 installer** for the fork's account switcher. Download `Codex-Account-Switcher-Setup-win-x64.exe` and verify its SHA-256 file before running it. Windows SmartScreen may warn about the unsigned publisher.

这是本 fork 的 **未签名 Windows 10/11 x64 安装包**。下载 `Codex-Account-Switcher-Setup-win-x64.exe`，运行前核对 SHA-256。Windows SmartScreen 可能提示发布者未经验证。

- Finds the Windows Codex CLI on `PATH` or in the Codex desktop app's local `bin` directory; `CODEX_SWITCHER_CODEX_PATH` can point to `codex.exe`. A WSL-only CLI is insufficient. / 可从 Windows `PATH` 或 Codex 桌面版的本地 `bin` 目录查找 CLI；也可用 `CODEX_SWITCHER_CODEX_PATH` 指定 `codex.exe`。仅安装 WSL 版 CLI 不够。
- This update fixes current-account import when the desktop app's CLI is not on `PATH` and shows a useful error when app-server exits. / 本次修复了桌面版 CLI 不在 `PATH` 时的当前账号导入，并在 app-server 退出时显示可操作的错误信息。
- Supports browser sign-in, current-account import, manual account switching, quota lookup, and nicknames. / 支持浏览器登录、导入当前账号、手动切换、查询额度和账号备注。
- Close Codex / ChatGPT Desktop before switching, then reopen it after success. / 切换前关闭 Codex／ChatGPT 桌面端，成功后自行重新打开。
- Account profiles stay under `%LOCALAPPDATA%\Codex Account Switcher`; uninstalling the app does not remove these sensitive local profiles. / 账号档案保留在本机 `%LOCALAPPDATA%\Codex Account Switcher`；卸载程序不会删除这些敏感数据。

The installer is built and install/uninstall tested on a Windows CI runner with synthetic credentials. Real browser sign-in and switching between two authorized accounts on a user's Windows machine remain unverified. / 安装包已在 Windows CI 机器完成构建和安装／卸载测试，账号切换测试使用合成凭据；真实 Windows 账号登录与双账号切换尚未验收。
