using System.Diagnostics;
using System.Text.Json;

namespace CodexAccountSwitcher.Windows;

public sealed record Identity(string? AccountID, string? Email, string? PlanType)
{
    public static Identity FromAccountRead(JsonElement result)
    {
        if (!result.TryGetProperty("account", out var account) || account.ValueKind != JsonValueKind.Object)
            throw new InvalidDataException("Codex did not return a signed-in account.");
        var id = Get(account, "accountId") ?? Get(account, "accountID") ?? Get(account, "chatgptAccountId") ?? Get(account, "id");
        var email = Get(account, "email");
        if (id is null && email is null) throw new InvalidDataException("Codex did not return an account identity.");
        return new(id, email, Get(account, "planType"));
    }

    private static string? Get(JsonElement value, string name) =>
        value.TryGetProperty(name, out var child) && child.ValueKind == JsonValueKind.String
            ? string.IsNullOrWhiteSpace(child.GetString()) ? null : child.GetString()!.Trim()
            : null;

    public static bool Matches(Identity identity, AccountProfile profile)
    {
        if (profile.AccountID is not null && identity.AccountID is not null)
            return string.Equals(profile.AccountID, identity.AccountID, StringComparison.Ordinal);
        return profile.Email is not null && identity.Email is not null &&
               string.Equals(profile.Email, identity.Email, StringComparison.OrdinalIgnoreCase);
    }
}

public interface ICodexIdentityReader
{
    Task<Identity> ReadIdentityAsync(string codexHome, CancellationToken cancellation = default);
}

public sealed class CodexClient : ICodexIdentityReader
{
    public async Task<Identity> ReadIdentityAsync(string codexHome, CancellationToken cancellation = default)
    {
        using var session = new Session(codexHome);
        await session.InitializeAsync(cancellation);
        var result = await session.RequestAsync(1, "account/read", new { refreshToken = false }, TimeSpan.FromSeconds(20), cancellation);
        return Identity.FromAccountRead(result);
    }

    public async Task<Identity> LoginAsync(string codexHome, CancellationToken cancellation = default)
    {
        using var session = new Session(codexHome);
        await session.InitializeAsync(cancellation);
        var start = await session.RequestAsync(1, "account/login/start", new
        {
            type = "chatgpt", useHostedLoginSuccessPage = true, appBrand = "codex"
        }, TimeSpan.FromSeconds(20), cancellation);
        if (!start.TryGetProperty("authUrl", out var value) ||
            !Uri.TryCreate(value.GetString(), UriKind.Absolute, out var url) ||
            url.Scheme != Uri.UriSchemeHttps)
            throw new InvalidDataException("Codex returned an invalid sign-in URL.");
        Process.Start(new ProcessStartInfo(url.AbsoluteUri) { UseShellExecute = true });
        var completion = await session.NotificationAsync("account/login/completed", TimeSpan.FromMinutes(10), cancellation);
        if (!completion.TryGetProperty("success", out var success) || success.ValueKind != JsonValueKind.True)
            throw new InvalidOperationException("Browser sign-in did not complete.");
        var account = await session.RequestAsync(2, "account/read", new { refreshToken = false }, TimeSpan.FromSeconds(20), cancellation);
        return Identity.FromAccountRead(account);
    }

    public async Task<string> ReadQuotaAsync(string codexHome, CancellationToken cancellation = default)
    {
        using var session = new Session(codexHome);
        await session.InitializeAsync(cancellation);
        var result = await session.RequestAsync(1, "account/rateLimits/read", new { }, TimeSpan.FromSeconds(20), cancellation);
        var buckets = new List<JsonElement>();
        if (result.TryGetProperty("rateLimits", out var primary)) buckets.Add(primary);
        if (result.TryGetProperty("rateLimitsByLimitId", out var byId) && byId.ValueKind == JsonValueKind.Object)
            buckets.AddRange(byId.EnumerateObject().Select(item => item.Value));
        var windows = new List<(int Minutes, double Remaining)>();
        foreach (var bucket in buckets)
            foreach (var name in new[] { "primary", "secondary" })
                if (bucket.ValueKind == JsonValueKind.Object && bucket.TryGetProperty(name, out var window) &&
                    window.ValueKind == JsonValueKind.Object &&
                    window.TryGetProperty("usedPercent", out var used) && used.TryGetDouble(out var usedPercent) &&
                    window.TryGetProperty("windowDurationMins", out var duration) && duration.TryGetInt32(out var minutes))
                    windows.Add((minutes, Math.Clamp(100 - usedPercent, 0, 100)));
        var fiveHour = windows.FirstOrDefault(w => w.Minutes == 300);
        var weekly = windows.FirstOrDefault(w => w.Minutes >= 10080);
        var parts = new List<string>();
        if (fiveHour.Minutes != 0) parts.Add($"5h {fiveHour.Remaining:0}%");
        if (weekly.Minutes != 0) parts.Add($"Weekly {weekly.Remaining:0}%");
        return parts.Count == 0 ? "Quota unavailable" : string.Join(" · ", parts);
    }

    private sealed class Session : IDisposable
    {
        private readonly Process process;
        private readonly CancellationTokenSource lifetime = new();
        private readonly Task stderrDrain;

        public Session(string codexHome)
        {
            var executable = CodexExecutableLocator.Locate();
            ProcessStartInfo info;
            if (executable.EndsWith(".cmd", StringComparison.OrdinalIgnoreCase))
            {
                info = new ProcessStartInfo(Environment.GetEnvironmentVariable("ComSpec") ?? "cmd.exe");
                // cmd.exe needs the outer pair of quotes as well as the quoted shim path.
                // ArgumentList would escape those quotes before cmd.exe parses them.
                info.Arguments = $"/d /s /c \"\"{executable}\" app-server --stdio\"";
            }
            else
            {
                info = new ProcessStartInfo(executable);
                info.ArgumentList.Add("app-server");
                info.ArgumentList.Add("--stdio");
            }
            info.UseShellExecute = false;
            info.CreateNoWindow = true;
            info.RedirectStandardInput = true;
            info.RedirectStandardOutput = true;
            info.RedirectStandardError = true;
            info.Environment["CODEX_HOME"] = codexHome;
            try { process = Process.Start(info) ?? throw new InvalidOperationException("Codex CLI could not start."); }
            catch (System.ComponentModel.Win32Exception error)
            {
                throw new InvalidOperationException("无法启动 Codex CLI。请确认 Codex 桌面应用或 CLI 已正确安装。", error);
            }
            stderrDrain = Task.Run(async () => { try { await process.StandardError.ReadToEndAsync(lifetime.Token); } catch (OperationCanceledException) { } });
        }

        public async Task InitializeAsync(CancellationToken cancellation)
        {
            await RequestAsync(0, "initialize", new { clientInfo = new { name = "codex_account_switcher", title = "Codex Account Switcher", version = "0.2.2" } }, TimeSpan.FromSeconds(20), cancellation);
            await SendAsync(new { method = "initialized", @params = new { } }, cancellation);
        }

        public async Task<JsonElement> RequestAsync(int id, string method, object parameters, TimeSpan timeout, CancellationToken cancellation)
        {
            await SendAsync(new { id, method, @params = parameters }, cancellation);
            using var linked = CancellationTokenSource.CreateLinkedTokenSource(cancellation, lifetime.Token);
            linked.CancelAfter(timeout);
            while (true)
            {
                var message = await ReadAsync(linked.Token);
                if (!message.TryGetProperty("id", out var responseId) || responseId.ValueKind != JsonValueKind.Number || responseId.GetInt32() != id) continue;
                if (message.TryGetProperty("error", out var error) && error.ValueKind != JsonValueKind.Null)
                    throw new InvalidOperationException("Codex app-server rejected " + method + ".");
                if (!message.TryGetProperty("result", out var result)) throw new InvalidDataException("Codex response has no result.");
                return result.Clone();
            }
        }

        public async Task<JsonElement> NotificationAsync(string method, TimeSpan timeout, CancellationToken cancellation)
        {
            using var linked = CancellationTokenSource.CreateLinkedTokenSource(cancellation, lifetime.Token);
            linked.CancelAfter(timeout);
            while (true)
            {
                var message = await ReadAsync(linked.Token);
                if (message.TryGetProperty("method", out var name) && name.GetString() == method &&
                    message.TryGetProperty("params", out var parameters)) return parameters.Clone();
            }
        }

        private async Task SendAsync(object value, CancellationToken cancellation)
        {
            await process.StandardInput.WriteLineAsync(JsonSerializer.Serialize(value).AsMemory(), cancellation);
            await process.StandardInput.FlushAsync(cancellation);
        }

        private async Task<JsonElement> ReadAsync(CancellationToken cancellation)
        {
            var line = await process.StandardOutput.ReadLineAsync(cancellation);
            if (line is null)
            {
                try { await process.WaitForExitAsync(cancellation).WaitAsync(TimeSpan.FromSeconds(2), cancellation); }
                catch (TimeoutException) { }
                var code = process.HasExited ? $" (exit code {process.ExitCode})" : "";
                throw new IOException("Codex app-server 已退出" + code + "。请在命令提示符运行 codex app-server，检查 Codex 安装；若使用 WSL，请安装 Windows 版 Codex CLI。错误输出不会写入账号切换器。 / Codex app-server exited" + code + ". Check the Windows Codex CLI installation.");
            }
            using var document = JsonDocument.Parse(line);
            return document.RootElement.Clone();
        }

        public void Dispose()
        {
            lifetime.Cancel();
            if (!process.HasExited) process.Kill(entireProcessTree: true);
            process.Dispose();
            lifetime.Dispose();
            _ = stderrDrain;
        }
    }
}

public static class CodexExecutableLocator
{
    public static string Locate()
    {
        var explicitPath = Environment.GetEnvironmentVariable("CODEX_SWITCHER_CODEX_PATH");
        if (!string.IsNullOrWhiteSpace(explicitPath))
        {
            if (IsExe(explicitPath)) return explicitPath;
            throw new InvalidOperationException("CODEX_SWITCHER_CODEX_PATH 必须指向现有的 Windows codex.exe。 / It must point to an existing Windows codex.exe.");
        }

        foreach (var directory in (Environment.GetEnvironmentVariable("Path") ?? Environment.GetEnvironmentVariable("PATH") ?? "")
                     .Split(';', StringSplitOptions.RemoveEmptyEntries))
        {
            var path = directory.Trim().Trim('"');
            if (!Path.IsPathFullyQualified(path)) continue;
            var exe = Path.Combine(path, "codex.exe");
            if (IsExe(exe)) return exe;
        }

        var local = Environment.GetEnvironmentVariable("LOCALAPPDATA");
        if (!string.IsNullOrWhiteSpace(local))
        {
            var bin = Path.Combine(local, "OpenAI", "Codex", "bin");
            if (Directory.Exists(bin))
                foreach (var version in Directory.EnumerateDirectories(bin)
                             .OrderByDescending(Directory.GetLastWriteTimeUtc))
                {
                    var exe = Path.Combine(version, "codex.exe");
                    if (IsExe(exe)) return exe;
                }
        }

        foreach (var directory in (Environment.GetEnvironmentVariable("Path") ?? Environment.GetEnvironmentVariable("PATH") ?? "")
                     .Split(';', StringSplitOptions.RemoveEmptyEntries))
        {
            var path = directory.Trim().Trim('"');
            if (!Path.IsPathFullyQualified(path)) continue;
            var shim = Path.Combine(path, "codex.cmd");
            if (File.Exists(shim)) return shim;
        }
        throw new FileNotFoundException("找不到 Windows Codex CLI。请安装 Codex CLI，或设置 CODEX_SWITCHER_CODEX_PATH 指向 codex.exe；仅打开 Codex 桌面应用不会提供命令行连接。 / Windows Codex CLI was not found.");
    }

    private static bool IsExe(string path) => Path.IsPathFullyQualified(path) &&
        path.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) && File.Exists(path);
}
