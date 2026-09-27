using System.Drawing;
using System.Windows.Forms;

namespace CodexAccountSwitcher.Windows;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        ApplicationConfiguration.Initialize();
        Application.Run(new SwitcherForm());
    }
}

internal sealed class SwitcherForm : Form
{
    private readonly AccountStore store = new();
    private readonly CodexClient codex = new();
    private readonly AccountSwitcher switcher;
    private readonly ListView accounts = new() { View = View.Details, FullRowSelect = true, MultiSelect = false, Dock = DockStyle.Fill };
    private readonly Label status = new() { AutoSize = false, Dock = DockStyle.Bottom, Height = 50, TextAlign = ContentAlignment.MiddleLeft };
    private readonly NotifyIcon tray;
    private readonly Button import = new() { Text = "导入当前账号 / Import current", AutoSize = true };
    private readonly Button add = new() { Text = "添加账号 / Add", AutoSize = true };
    private readonly Button activate = new() { Text = "切换 / Switch", AutoSize = true };
    private readonly Button quota = new() { Text = "查看额度 / Quota", AutoSize = true };
    private readonly Button rename = new() { Text = "备注 / Rename", AutoSize = true };
    private readonly Button cancel = new() { Text = "取消 / Cancel", AutoSize = true, Enabled = false };
    private CancellationTokenSource? operation;
    private bool exiting;

    public SwitcherForm()
    {
        switcher = new AccountSwitcher(store, codex);
        Text = "Codex Account Switcher · Windows";
        Width = 710; Height = 425; MinimumSize = new Size(560, 320);
        StartPosition = FormStartPosition.CenterScreen;
        accounts.Columns.Add("账号 / Account", 300);
        accounts.Columns.Add("套餐 / Plan", 100);
        accounts.Columns.Add("状态 / Status", 150);
        var actions = new FlowLayoutPanel { Dock = DockStyle.Top, AutoSize = true, WrapContents = true, Padding = new Padding(8) };
        actions.Controls.AddRange([import, add, activate, quota, rename, cancel]);
        Controls.Add(accounts); Controls.Add(status); Controls.Add(actions);
        import.Click += async (_, _) => await RunAsync(ImportAsync);
        add.Click += async (_, _) => await RunAsync(AddAsync);
        activate.Click += async (_, _) => await RunAsync(SwitchAsync);
        quota.Click += async (_, _) => await RunAsync(QuotaAsync);
        rename.Click += (_, _) => RenameSelected();
        cancel.Click += (_, _) => operation?.Cancel();
        var menu = new ContextMenuStrip();
        menu.Items.Add("打开 / Open", null, (_, _) => ShowWindow());
        menu.Items.Add("退出 / Exit", null, (_, _) => { exiting = true; Close(); });
        tray = new NotifyIcon { Icon = SystemIcons.Application, Text = "Codex Account Switcher", Visible = true, ContextMenuStrip = menu };
        tray.DoubleClick += (_, _) => ShowWindow();
        FormClosing += (_, e) => { if (!exiting) { e.Cancel = true; Hide(); } };
        FormClosed += (_, _) => { operation?.Cancel(); tray.Visible = false; tray.Dispose(); };
        Shown += async (_, _) =>
        {
            RefreshAccounts();
            if (switcher.HasPendingRecovery) await RunAsync(async token =>
            {
                await switcher.RecoverAsync(token);
                status.Text = "已恢复中断的账号切换 / Interrupted switch recovered.";
            });
        };
        status.Text = "账号数据仅保存在本机。切换前请关闭 Codex / ChatGPT 桌面应用。";
    }

    private void ShowWindow() { Show(); WindowState = FormWindowState.Normal; Activate(); }

    private AccountProfile? Selected()
    {
        if (accounts.SelectedItems.Count == 0) return null;
        var id = (Guid)accounts.SelectedItems[0].Tag!;
        return store.Load().Accounts.FirstOrDefault(p => p.Id == id);
    }

    private void RefreshAccounts()
    {
        var registry = store.Load();
        accounts.Items.Clear();
        foreach (var profile in registry.Accounts)
        {
            var row = new ListViewItem(profile.Label) { Tag = profile.Id };
            row.SubItems.Add(profile.PlanType ?? "—");
            row.SubItems.Add(registry.ActiveAccountID == profile.Id ? "当前 / Active" : "已保存 / Saved");
            accounts.Items.Add(row);
        }
        import.Enabled = registry.Accounts.Count == 0 && File.Exists(store.ActiveAuthPath);
    }

    private async Task ImportAsync(CancellationToken token)
    {
        var identity = await codex.ReadIdentityAsync(store.CodexHome, token);
        var profile = store.ImportCurrent(identity);
        status.Text = "已导入 / Imported: " + profile.Label;
    }

    private async Task AddAsync(CancellationToken token)
    {
        if (store.Load().Accounts.Count == 0 && File.Exists(store.ActiveAuthPath))
            throw new InvalidOperationException("请先导入当前账号 / Import the current account first.");
        var id = Guid.NewGuid();
        var home = store.ProfileHome(id);
        Directory.CreateDirectory(home);
        try
        {
            status.Text = "请在浏览器完成登录。最多等待 10 分钟 / Complete sign-in in the browser (10 min).";
            var identity = await codex.LoginAsync(home, token);
            var profile = store.AddLoggedIn(id, identity);
            status.Text = "已添加 / Added: " + profile.Label;
        }
        catch
        {
            if (!store.Load().Accounts.Any(p => p.Id == id) && Directory.Exists(home)) Directory.Delete(home, recursive: true);
            throw;
        }
    }

    private async Task SwitchAsync(CancellationToken token)
    {
        var target = Selected() ?? throw new InvalidOperationException("请先选择账号 / Select an account.");
        if (store.Load().ActiveAccountID == target.Id) return;
        var answer = MessageBox.Show(this,
            $"切换至 {target.Label}？请先关闭 Codex / ChatGPT 桌面应用，正在运行的任务可能中断。\n\nSwitch to {target.Label}? Close the desktop app first; running work may be interrupted.",
            "确认切换 / Confirm switch", MessageBoxButtons.YesNo, MessageBoxIcon.Warning);
        if (answer != DialogResult.Yes) return;
        await switcher.SwitchAsync(target.Id, token);
        status.Text = "切换成功。现在可以重新打开桌面应用 / Switched. Reopen the desktop app.";
    }

    private async Task QuotaAsync(CancellationToken token)
    {
        var target = Selected() ?? throw new InvalidOperationException("请先选择账号 / Select an account.");
        status.Text = target.Label + ": " + await codex.ReadQuotaAsync(store.ProfileHome(target.Id), token);
    }

    private void RenameSelected()
    {
        var target = Selected();
        if (target is null) return;
        using var dialog = new Form { Text = "备注 / Nickname", Width = 370, Height = 145, StartPosition = FormStartPosition.CenterParent };
        var input = new TextBox { Text = target.Nickname ?? "", Dock = DockStyle.Top };
        var save = new Button { Text = "保存 / Save", DialogResult = DialogResult.OK, Dock = DockStyle.Bottom };
        dialog.Controls.Add(input); dialog.Controls.Add(save); dialog.AcceptButton = save;
        if (dialog.ShowDialog(this) == DialogResult.OK) { store.Rename(target.Id, input.Text); RefreshAccounts(); }
    }

    private async Task RunAsync(Func<CancellationToken, Task> action)
    {
        if (operation is not null) return;
        operation = new CancellationTokenSource();
        foreach (Control control in Controls.OfType<FlowLayoutPanel>().SelectMany(p => p.Controls.Cast<Control>())) control.Enabled = false;
        cancel.Enabled = true;
        try { await action(operation.Token); RefreshAccounts(); }
        catch (Exception error)
        {
            RefreshAccounts();
            status.Text = "操作失败 / Operation failed: " + error.Message;
            MessageBox.Show(this, error.Message, "Codex Account Switcher", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
        finally
        {
            operation.Dispose(); operation = null;
            foreach (Control control in Controls.OfType<FlowLayoutPanel>().SelectMany(p => p.Controls.Cast<Control>())) control.Enabled = true;
            RefreshAccounts();
        }
    }
}
