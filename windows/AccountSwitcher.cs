using System.Diagnostics;
using System.Security.Cryptography;
using System.Text.Json;

namespace CodexAccountSwitcher.Windows;

public sealed class SwitchJournal
{
    public Guid OriginalAccountID { get; set; }
    public Guid TargetAccountID { get; set; }
    public string Phase { get; set; } = "prepared";
}

public sealed class AccountSwitcher(AccountStore store, ICodexIdentityReader codex)
{
    public bool HasPendingRecovery => File.Exists(store.JournalPath);

    public async Task RecoverAsync(CancellationToken cancellation = default)
    {
        if (!HasPendingRecovery) return;
        var journal = JsonSerializer.Deserialize<SwitchJournal>(File.ReadAllText(store.JournalPath))
            ?? throw new InvalidDataException("Switch journal is invalid.");
        var registry = store.Load();
        if (journal.Phase == "committed")
        {
            var target = registry.Accounts.Single(p => p.Id == journal.TargetAccountID);
            if (registry.ActiveAccountID != target.Id ||
                !Identity.Matches(await codex.ReadIdentityAsync(store.CodexHome, cancellation), target))
                throw new InvalidOperationException("The committed account cannot be verified. Recovery files were preserved.");
            ClearRecovery();
            return;
        }
        var original = registry.Accounts.Single(p => p.Id == journal.OriginalAccountID);
        if (!File.Exists(store.BackupPath)) throw new FileNotFoundException("Encrypted switch backup is missing.");
        var bytes = ProtectedData.Unprotect(File.ReadAllBytes(store.BackupPath), null, DataProtectionScope.CurrentUser);
        AccountStore.AtomicWrite(store.ActiveAuthPath, bytes);
        var identity = await codex.ReadIdentityAsync(store.CodexHome, cancellation);
        if (!Identity.Matches(identity, original))
            throw new InvalidOperationException("The original account could not be verified. Recovery files were preserved.");
        registry.ActiveAccountID = original.Id;
        store.Save(registry);
        ClearRecovery();
    }

    public async Task SwitchAsync(Guid targetID, CancellationToken cancellation = default)
    {
        await RecoverAsync(cancellation);
        EnsureDesktopClosed();
        var registry = store.Load();
        var original = registry.Accounts.Single(p => p.Id == registry.ActiveAccountID);
        var target = registry.Accounts.Single(p => p.Id == targetID);
        if (original.Id == target.Id) return;
        if (!File.Exists(store.ActiveAuthPath) || !File.Exists(store.ProfileAuthPath(targetID)))
            throw new FileNotFoundException("An account credential is missing.");
        var originalBytes = File.ReadAllBytes(store.ActiveAuthPath);
        var backup = ProtectedData.Protect(originalBytes, null, DataProtectionScope.CurrentUser);
        AccountStore.AtomicWrite(store.BackupPath, backup);
        var journal = new SwitchJournal { OriginalAccountID = original.Id, TargetAccountID = target.Id };
        WriteJournal(journal);
        try
        {
            AccountStore.AtomicWrite(store.ProfileAuthPath(original.Id), originalBytes);
            journal.Phase = "originalSaved"; WriteJournal(journal);
            AccountStore.AtomicWrite(store.ActiveAuthPath, File.ReadAllBytes(store.ProfileAuthPath(target.Id)));
            journal.Phase = "targetActivated"; WriteJournal(journal);
            if (!Identity.Matches(await codex.ReadIdentityAsync(store.CodexHome, cancellation), target))
                throw new InvalidOperationException("Codex reported a different account after switching.");
            journal.Phase = "targetVerified"; WriteJournal(journal);
            registry.ActiveAccountID = target.Id;
            target.LastUsedAt = DateTimeOffset.UtcNow;
            store.Save(registry);
            journal.Phase = "committed"; WriteJournal(journal);
            ClearRecovery();
        }
        catch (Exception switchError)
        {
            if (journal.Phase == "committed") throw;
            try { await RecoverAsync(CancellationToken.None); }
            catch (Exception recoveryError)
            {
                throw new AggregateException("Switch failed and the previous account could not be verified. Recovery files were preserved.", switchError, recoveryError);
            }
            throw;
        }
    }

    private static void EnsureDesktopClosed()
    {
        var names = new[] { "Codex", "ChatGPT" };
        foreach (var name in names)
        {
            using var processes = new ProcessCollection(Process.GetProcessesByName(name));
            if (processes.Items.Length > 0)
                throw new InvalidOperationException("Close the Codex / ChatGPT desktop app before switching, then retry. Running tasks may be interrupted.");
        }
    }

    private sealed class ProcessCollection(Process[] items) : IDisposable
    {
        public Process[] Items => items;
        public void Dispose() { foreach (var process in items) process.Dispose(); }
    }

    private void WriteJournal(SwitchJournal journal) =>
        AccountStore.AtomicWrite(store.JournalPath, JsonSerializer.SerializeToUtf8Bytes(journal));

    private void ClearRecovery()
    {
        if (File.Exists(store.JournalPath)) File.Delete(store.JournalPath);
        if (File.Exists(store.BackupPath)) File.Delete(store.BackupPath);
    }
}
