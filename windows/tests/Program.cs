using System.Text;
using System.Text.Json;
using CodexAccountSwitcher.Windows;

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
