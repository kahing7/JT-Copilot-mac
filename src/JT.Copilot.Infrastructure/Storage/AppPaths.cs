namespace JT.Copilot.Infrastructure.Storage;

public static class AppPaths
{
    public static string RootDirectory { get; } = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "JT Copilot");

    public static string SettingsFilePath { get; } = Path.Combine(RootDirectory, "settings.json");

    public static string RecordingsDirectory { get; } = Path.Combine(RootDirectory, "recordings");
}
