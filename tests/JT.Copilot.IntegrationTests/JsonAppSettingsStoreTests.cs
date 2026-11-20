using System.IO;
using JT.Copilot.Application.Models;
using JT.Copilot.Infrastructure.Storage;

namespace JT.Copilot.IntegrationTests;

public sealed class JsonAppSettingsStoreTests
{
    [Fact]
    public async Task SaveAndLoad_RoundTripsSettingsThroughJson()
    {
        var directory = Path.Combine(
            Path.GetTempPath(),
            "JT.Copilot.Tests",
            Guid.NewGuid().ToString("N"));
        var settingsPath = Path.Combine(directory, "settings.json");

        try
        {
            var store = new JsonAppSettingsStore(settingsPath);
            var expected = new AppSettings
            {
                PreferredMicrophoneDeviceId = "2",
                Hotkey = "Ctrl+Shift+J+T",
                CustomVocabulary = "CRM系统=新奥尔良系统",
                GuidanceTemplate = DocumentTemplate.ProjectManagement,
                IsTopmost = false,
                WindowLeft = 120,
                WindowTop = 80,
                IsExpanded = false
            };

            await store.SaveAsync(expected);
            var actual = await store.LoadAsync();

            Assert.Equal(expected, actual);
            Assert.True(File.Exists(settingsPath));
        }
        finally
        {
            if (Directory.Exists(directory))
            {
                Directory.Delete(directory, recursive: true);
            }
        }
    }
}
