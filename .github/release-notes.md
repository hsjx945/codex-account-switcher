# Codex Account Switcher 0.2.2

## English

Native macOS menu-bar account switching for authorized Codex accounts. Requires Apple Silicon, macOS 14+, and an installed Codex executable.

- Keep browser sign-in cancellation accessible after closing and reopening the popover.
- Improve account rows, settings and switch confirmation readability.
- Show same-day saved local Token totals while rebuilding today's and the last 30 days' deduplicated history. Totals are device-wide, not per account.
- Fix stale core assertions and the native UI render command; remove the superseded HTML prototype and unused menu components.
- Align the app, packaging, client and website on 0.2.2, with version checks in CI.
- Update English/Chinese documentation and search/AI discovery metadata. Discoverability support does not guarantee indexing or traffic growth.

Download the DMG and checksum below. Read **Artifact signing** before installation; signing/notarization status is added by the workflow based on the artifact actually built. Switching closes and reopens Codex Desktop and may interrupt running Desktop work. Local tests use synthetic data; real-account switching is a separate acceptance step.

## 简体中文

面向有权使用的 Codex 账号的 macOS 原生菜单栏切换工具。需要 Apple Silicon、macOS 14 或更高版本，以及已安装的 Codex 可执行程序。

- 修复等待浏览器登录时关闭再打开弹窗后无法取消的问题。
- 提升账号行、设置和切换确认的可读性。
- 扫描今日和近 30 天历史时，明确显示当日已保存的去重 Token 总量；统计为设备级，不属于单个账号。
- 修复核心检查旧断言和原生界面渲染入口，删除已被替代的 HTML 原型与闲置菜单组件。
- 应用、打包、客户端和网站统一为 0.2.2，并纳入 CI 校验。
- 更新中英双语说明及搜索引擎/AI 检索元数据。支持被发现不等于保证收录或流量增长。

请下载下方 DMG 与校验文件，安装前阅读 **安装包签名**。工作流按实际构建结果追加签名/公证状态。切换会关闭并重开 Codex Desktop，可能中断运行中的 Desktop 任务。自动测试使用合成数据，真实账号切换需要单独验收。
