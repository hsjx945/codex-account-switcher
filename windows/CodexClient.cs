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
            var explicitPath = Environment.GetEnvironmentVariable("CODEX_SWITCHER_CODEX_PATH");
            ProcessStartInfo info;
            if (!string.IsNullOrWhiteSpace(explicitPath))
            {
                if (!Path.IsPathFullyQualified(explicitPath) || !File.Exists(explicitPath) ||
                    !explicitPath.EndsWith(".exe", StringComparison.OrdinalIgnoreCase))
                    throw new InvalidOperationException("CODEX_SWITCHER_CODEX_PATH must point to an existing codex.exe.");
                info = new ProcessStartInfo(explicitPath);
                info.ArgumentList.Add("app-server"); info.ArgumentList.Add("--stdio");
            }
            else
            {
                info = new ProcessStartInfo(Environment.GetEnvironmentVariable("ComSpec") ?? "cmd.exe");
                info.ArgumentList.Add("/d"); info.ArgumentList.Add("/s"); info.ArgumentList.Add("/c");
                info.ArgumentList.Add("codex app-server --stdio");
            }
            info.UseShellExecute = false;
            info.CreateNoWindow = true;
            info.RedirectStandardInput = true;
            info.RedirectStandardOutput = true;
            info.RedirectStandardError = true;
            info.Environment["CODEX_HOME"] = codexHome;
            process = Process.Start(info) ?? throw new InvalidOperationException("Codex CLI could not start.");
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
            if (line is null) throw new IOException("Codex app-server closed its connection.");
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
