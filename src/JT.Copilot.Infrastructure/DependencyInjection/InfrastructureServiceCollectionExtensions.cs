using JT.Copilot.Application.Abstractions;
using JT.Copilot.Application.Services;
using JT.Copilot.Infrastructure.Audio;
using JT.Copilot.Infrastructure.Storage;
using JT.Copilot.Infrastructure.Windows;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

namespace JT.Copilot.Infrastructure.DependencyInjection;

public static class InfrastructureServiceCollectionExtensions
{
    public static IServiceCollection AddInfrastructure(this IServiceCollection services)
    {
        services.AddSingleton<IAppSettingsStore>(provider =>
            new JsonAppSettingsStore(
                AppPaths.SettingsFilePath,
                provider.GetRequiredService<ILogger<JsonAppSettingsStore>>()));
        services.AddSingleton<IAudioCaptureService, WaveAudioCaptureService>();
        services.AddSingleton<IGlobalHotkeyService, GlobalHotkeyService>();
        services.AddSingleton<IVoiceCaptureCoordinator, VoiceCaptureCoordinator>();

        return services;
    }
}
