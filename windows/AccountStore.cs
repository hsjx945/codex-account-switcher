using System.Text.Json;
using System.Text.Json.Serialization;

namespace CodexAccountSwitcher.Windows;

public sealed class AccountProfile
{
    [JsonPropertyName("id")] public Guid Id { get; set; }
    [JsonPropertyName("displayName")] public string DisplayName { get; set; } = "";
    [JsonPropertyName("nickname")] public string? Nickname { get; set; }
    [JsonPropertyName("email")] public string? Email { get; set; }
    [JsonPropertyName("accountID")] public string? AccountID { get; set; }
    [JsonPropertyName("planType")] public string? PlanType { get; set; }
    [JsonPropertyName("createdAt")] public DateTimeOffset CreatedAt { get; set; }
    [JsonPropertyName("lastUsedAt")] public DateTimeOffset? LastUsedAt { get; set; }
    [JsonIgnore] public string Label => Nickname ?? Email ?? DisplayName;
}

public sealed class AccountRegistry
{
    [JsonPropertyName("activeAccountID")] public Guid? ActiveAccountID { get; set; }
    [JsonPropertyName("accounts")] public List<AccountProfile> Accounts { get; set; } = [];
}

public sealed class AccountStore
{
    public static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };
    public string BaseDirectory { get; }
    public string CodexHome { get; }
    public string ActiveAuthPath => Path.Combine(CodexHome, "auth.json");
    public string JournalPath => Path.Combine(BaseDirectory, "switch-journal.json");
    public string BackupPath => Path.Combine(BaseDirectory, "switch-backup.dpapi");
    private string RegistryPath => Path.Combine(BaseDirectory, "accounts.json");

    public AccountStore(string? baseDirectory = null, string? codexHome = null)
    {
        BaseDirectory = baseDirectory ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Codex Account Switcher");
        var configuredHome = Environment.GetEnvironmentVariable("CODEX_HOME");
        CodexHome = codexHome ?? (!string.IsNullOrWhiteSpace(configuredHome)
            ? Path.GetFullPath(configuredHome)
            : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".codex"));
        Directory.CreateDirectory(BaseDirectory);
        Directory.CreateDirectory(Path.Combine(BaseDirectory, "accounts"));
    }

    public AccountRegistry Load()
    {
        if (!File.Exists(RegistryPath)) return new();
        return JsonSerializer.Deserialize<AccountRegistry>(File.ReadAllText(RegistryPath), JsonOptions)
            ?? throw new InvalidDataException("Account registry is empty.");
    }

    public void Save(AccountRegistry registry) => AtomicWrite(RegistryPath, JsonSerializer.SerializeToUtf8Bytes(registry, JsonOptions));
    public string ProfileHome(Guid id) => Path.Combine(BaseDirectory, "accounts", id.ToString().ToUpperInvariant());
    public string ProfileAuthPath(Guid id) => Path.Combine(ProfileHome(id), "auth.json");

    public static void AtomicWrite(string path, byte[] bytes)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var temporary = path + ".switcher-" + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
            {
                stream.Write(bytes);
                stream.Flush(flushToDisk: true);
            }
            if (File.Exists(path)) File.Replace(temporary, path, null);
            else File.Move(temporary, path);
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }

    public AccountProfile ImportCurrent(Identity identity)
    {
        var registry = Load();
        if (registry.Accounts.Count != 0) throw new InvalidOperationException("The current account is already registered.");
        if (!File.Exists(ActiveAuthPath)) throw new FileNotFoundException("No active Codex login was found.");
        var profile = NewProfile(identity);
        Directory.CreateDirectory(ProfileHome(profile.Id));
        AtomicWrite(ProfileAuthPath(profile.Id), File.ReadAllBytes(ActiveAuthPath));
        registry.Accounts.Add(profile);
        registry.ActiveAccountID = profile.Id;
        try { Save(registry); }
        catch { Directory.Delete(ProfileHome(profile.Id), recursive: true); throw; }
        return profile;
    }

    public AccountProfile AddLoggedIn(Guid id, Identity identity)
    {
        var registry = Load();
        if (registry.Accounts.Count == 0 && File.Exists(ActiveAuthPath))
            throw new InvalidOperationException("Import the current Codex account before adding another.");
        var source = ProfileAuthPath(id);
        if (!File.Exists(source)) throw new FileNotFoundException("The browser sign-in did not create a Codex credential.");
        var profile = NewProfile(identity, id);
        if (registry.Accounts.Any(p => Identity.Matches(identity, p)))
            throw new InvalidOperationException("This account is already saved.");
        var first = registry.Accounts.Count == 0;
        if (first) AtomicWrite(ActiveAuthPath, File.ReadAllBytes(source));
        registry.Accounts.Add(profile);
        if (first) { registry.ActiveAccountID = id; profile.LastUsedAt = DateTimeOffset.UtcNow; }
        try { Save(registry); }
        catch { if (first) File.Delete(ActiveAuthPath); throw; }
        return profile;
    }

    public void Rename(Guid id, string nickname)
    {
        var registry = Load();
        var profile = registry.Accounts.Single(p => p.Id == id);
        profile.Nickname = string.IsNullOrWhiteSpace(nickname) ? null : nickname.Trim();
        Save(registry);
    }

    private static AccountProfile NewProfile(Identity identity, Guid? id = null) => new()
    {
        Id = id ?? Guid.NewGuid(), DisplayName = identity.Email ?? identity.AccountID ?? "Codex account",
        Email = identity.Email, AccountID = identity.AccountID, PlanType = identity.PlanType,
        CreatedAt = DateTimeOffset.UtcNow
    };
}
