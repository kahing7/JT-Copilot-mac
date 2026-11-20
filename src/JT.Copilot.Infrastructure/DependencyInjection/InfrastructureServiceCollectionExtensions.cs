using System.Net.Http;
using JT.Copilot.Application.Abstractions;
using JT.Copilot.Application.Guidance;
using JT.Copilot.Application.Services;
using JT.Copilot.Application.Text;
using JT.Copilot.Infrastructure.Audio;
using JT.Copilot.Infrastructure.Security;
using JT.Copilot.Infrastructure.Storage;
using JT.Copilot.Infrastructure.Windows;
using JT.Copilot.Infrastructure.Zhipu;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

namespace JT.Copilot.Infrastructure.DependencyInjection;

public static class InfrastructureServiceCollectionExtensions
{
    public static IServiceCollection AddInfrastructure(this IServiceCollection services)
    {
        services.AddSingleton(_ => new HttpClient
        {
            Timeout = TimeSpan.FromSeconds(90)
        });
        services.AddSingleton<IAppSettingsStore>(provider =>
            new JsonAppSettingsStore(
                AppPaths.SettingsFilePath,
                provider.GetRequiredService<ILogger<JsonAppSettingsStore>>()));
        services.AddSingleton<IZhipuApiKeyStore>(provider =>
            new ZhipuApiKeyStore(
                AppPaths.ZhipuApiKeyFilePath,
                provider.GetRequiredService<ILogger<ZhipuApiKeyStore>>()));
        services.AddSingleton<DomainTermCorrector>();
        services.AddSingleton<IDocumentFrameworkEngine, LocalDocumentFrameworkEngine>();
        services.AddSingleton<ISpeechRecognitionProvider, ZhipuSpeechRecognitionProvider>();
        services.AddSingleton<IWritingModelProvider, ZhipuWritingModelProvider>();
        services.AddSingleton<VoskModelProvisioner>();
        services.AddSingleton<IStreamingSpeechRecognitionProvider, VoskStreamingSpeechRecognitionProvider>();
        services.AddSingleton<IAudioCaptureService, WaveAudioCaptureService>();
        services.AddSingleton<IGlobalHotkeyService, GlobalHotkeyService>();
        services.AddSingleton<ITextInsertionService, WindowsTextInsertionService>();
        services.AddSingleton<IVoiceCaptureCoordinator, VoiceCaptureCoordinator>();

        return services;
    }
}
