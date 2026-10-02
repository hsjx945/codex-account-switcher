using System.Text;
using System.Text.Json;
using CodexAccountSwitcher.Windows;

if (args.SequenceEqual(["app-server", "--stdio"]))
{
    if (Environment.GetEnvironmentVariable("CODEX_SWITCHER_TEST_EXIT") == "1") return;
    while (await Console.In.ReadLineAsync() is { } line)
    {
        using var request = JsonDocument.Parse(line);
        if (!request.RootElement.TryGetProperty("id", out var id)) continue;
        var method = request.RootElement.GetProperty("method").GetString();
        object result = method switch
        {
            "initialize" => new { protocolVersion = "2025-01-01" },
            "account/read" => new { account = new { accountId = "fixture-account", email = "fixture@example.test", planType = "plus" } },
            _ => throw new Exception("Unexpected fixture request: " + method)
        };
        await Console.Out.WriteLineAsync(JsonSerializer.Serialize(new { id = id.GetInt32(), result }));
        await Console.Out.FlushAsync();
    }
    return;
}

var root = Path.Combine(Path.GetTempPath(), "switcher-tests-" + Guid.NewGuid().ToString("N"));
try
{
    var store = new AccountStore(Path.Combine(root, "data"), Path.Combine(root, "codex"));
    var first = new Identity("account-1", "one@example.test", "plus");
    Directory.CreateDirectory(store.CodexHome);
    File.WriteAllText(store.ActiveAuthPath, "synthetic credential", Encoding.UTF8);
    var imported = store.ImportCurrent(first);
    if (store.Load().ActiveAccountID != imported.Id ||
        !File.Exists(store.ProfileAuthPath(imported.Id))) throw new Exception("Current account import failed.");
    var secondId = Guid.NewGuid();
    Directory.CreateDirectory(store.ProfileHome(secondId));
    File.WriteAllText(store.ProfileAuthPath(secondId), "second synthetic credential", Encoding.UTF8);
    var second = store.AddLoggedIn(secondId, new Identity("account-2", "two@example.test", "pro"));
    if (store.Load().Accounts.Count != 2 || store.Load().ActiveAccountID != imported.Id)
        throw new Exception("Adding a second account changed the active account.");
    store.Rename(second.Id, "Second");
    if (store.Load().Accounts.Single(p => p.Id == second.Id).Nickname != "Second")
        throw new Exception("Nickname was not saved.");
    if (!Identity.Matches(new Identity("account-2", "different@example.test", null), second) ||
        Identity.Matches(new Identity("wrong", "two@example.test", null), second) ||
        !Identity.Matches(new Identity(null, "TWO@example.test", null), second))
        throw new Exception("Identity comparison is incorrect.");
    using var response = JsonDocument.Parse("{\"account\":{\"accountId\":\"account-2\",\"email\":\"two@example.test\"}}");
    if (!Identity.Matches(Identity.FromAccountRead(response.RootElement), second))
        throw new Exception("Codex account/read parsing failed.");
    if (OperatingSystem.IsWindows())
    {
        var original = Environment.GetEnvironmentVariable("CODEX_SWITCHER_CODEX_PATH");
        var originalPath = Environment.GetEnvironmentVariable("Path");
        var originalLocal = Environment.GetEnvironmentVariable("LOCALAPPDATA");
        var fixture = Environment.ProcessPath ?? throw new Exception("Test executable path unavailable.");
        try
        {
            Environment.SetEnvironmentVariable("CODEX_SWITCHER_CODEX_PATH", fixture);
            if (CodexExecutableLocator.Locate() != fixture) throw new Exception("Explicit CLI was not located.");
            var actual = await new CodexClient().ReadIdentityAsync(store.CodexHome);
            if (actual.AccountID != "fixture-account" || actual.Email != "fixture@example.test")
                throw new Exception("Codex app-server process exchange failed.");
            Environment.SetEnvironmentVariable("CODEX_SWITCHER_TEST_EXIT", "1");
            try { await new CodexClient().ReadIdentityAsync(store.CodexHome); throw new Exception("Closed app-server was accepted."); }
            catch (IOException error) when (error.Message.Contains("exit code 0")) { }
            finally { Environment.SetEnvironmentVariable("CODEX_SWITCHER_TEST_EXIT", null); }

            Environment.SetEnvironmentVariable("CODEX_SWITCHER_CODEX_PATH", null);
            var localBin = Path.Combine(root, "local", "OpenAI", "Codex", "bin", "fixture-version");
            Directory.CreateDirectory(localBin);
            var bundled = Path.Combine(localBin, "codex.exe");
            File.Copy(fixture, bundled);
            Environment.SetEnvironmentVariable("LOCALAPPDATA", Path.Combine(root, "local"));
            Environment.SetEnvironmentVariable("Path", Path.Combine(root, "empty"));
            if (CodexExecutableLocator.Locate() != bundled) throw new Exception("Codex Desktop bundled CLI was not located.");

            File.Delete(bundled);
            var shimDir = Path.Combine(root, "cli with spaces");
            Directory.CreateDirectory(shimDir);
            File.WriteAllText(Path.Combine(shimDir, "codex.cmd"), "@echo off\r\n\"" + fixture + "\" %*\r\n");
            Environment.SetEnvironmentVariable("Path", shimDir);
            if ((await new CodexClient().ReadIdentityAsync(store.CodexHome)).AccountID != "fixture-account")
                throw new Exception("Codex command shim process exchange failed.");
        }
        finally
        {
            Environment.SetEnvironmentVariable("CODEX_SWITCHER_CODEX_PATH", original);
            Environment.SetEnvironmentVariable("Path", originalPath);
            Environment.SetEnvironmentVariable("LOCALAPPDATA", originalLocal);
        }

        var switcher = new AccountSwitcher(store, new SyntheticIdentityReader());
        await switcher.SwitchAsync(second.Id);
        if (store.Load().ActiveAccountID != second.Id ||
            File.ReadAllText(store.ActiveAuthPath) != "second synthetic credential" || switcher.HasPendingRecovery)
            throw new Exception("Verified switch did not commit correctly.");
        File.WriteAllText(store.ProfileAuthPath(imported.Id), "wrong account");
        try { await switcher.SwitchAsync(imported.Id); throw new Exception("Mismatched target was accepted."); }
        catch (InvalidOperationException error) when (error.Message.Contains("different account")) { }
        if (store.Load().ActiveAccountID != second.Id ||
            File.ReadAllText(store.ActiveAuthPath) != "second synthetic credential" || switcher.HasPendingRecovery)
            throw new Exception("Failed switch did not restore the original account.");
    }
    Console.WriteLine("Windows account store and identity tests passed.");
}
finally { if (Directory.Exists(root)) Directory.Delete(root, recursive: true); }

internal sealed class SyntheticIdentityReader : ICodexIdentityReader
{
    public Task<Identity> ReadIdentityAsync(string codexHome, CancellationToken cancellation = default)
    {
        var credential = File.ReadAllText(Path.Combine(codexHome, "auth.json"));
        return Task.FromResult(credential switch
        {
            "synthetic credential" => new Identity("account-1", "one@example.test", "plus"),
            "second synthetic credential" => new Identity("account-2", "two@example.test", "pro"),
            _ => new Identity("wrong", null, null)
        });
    }
}
