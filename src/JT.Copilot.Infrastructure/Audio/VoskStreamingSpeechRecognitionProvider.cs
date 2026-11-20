using System.Diagnostics;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using JT.Copilot.Application.Abstractions;
using JT.Copilot.Application.Models;
using Microsoft.Extensions.Logging;
using Vosk;

namespace JT.Copilot.Infrastructure.Audio;

public sealed partial class VoskStreamingSpeechRecognitionProvider : IStreamingSpeechRecognitionProvider
{
    private readonly VoskModelProvisioner _modelProvisioner;
    private readonly ILogger<VoskStreamingSpeechRecognitionProvider> _logger;
    private readonly SemaphoreSlim _gate = new(1, 1);
    private Model? _model;
    private VoskRecognizer? _recognizer;
    private string _lastPartial = string.Empty;
    private bool _disposed;

    public VoskStreamingSpeechRecognitionProvider(
        VoskModelProvisioner modelProvisioner,
        ILogger<VoskStreamingSpeechRecognitionProvider> logger)
    {
        _modelProvisioner = modelProvisioner;
        _logger = logger;
    }

    public event EventHandler<LiveTranscriptEventArgs>? TranscriptChanged;

    public bool IsAvailable => _model is not null;

    public async Task<bool> InitializeAsync(CancellationToken cancellationToken = default)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        await _gate.WaitAsync(cancellationToken).ConfigureAwait(false);

        try
        {
            if (_model is not null)
            {
                return true;
            }

            var modelPath = await _modelProvisioner
                .EnsureModelAsync(cancellationToken)
                .ConfigureAwait(false);
            _model = await Task.Run(() => new Model(modelPath), cancellationToken).ConfigureAwait(false);
            return true;
        }
        catch (Exception exception)
        {
            _logger.LogWarning(exception, "Unable to initialize the local Vosk model.");
            return false;
        }
        finally
        {
            _gate.Release();
        }
    }

    public void StartSession()
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        if (_model is null)
        {
            return;
        }

        lock (_gate)
        {
            _recognizer?.Dispose();
            _recognizer = new VoskRecognizer(_model, 16_000.0f);
            _recognizer.SetWords(false);
            _recognizer.SetPartialWords(false);
            _lastPartial = string.Empty;
        }
    }

    public void PushAudio(ReadOnlyMemory<byte> pcmAudio)
    {
        if (_recognizer is null || pcmAudio.IsEmpty)
        {
            return;
        }

        lock (_gate)
        {
            var bytes = pcmAudio.ToArray();
            if (_recognizer.AcceptWaveform(bytes, bytes.Length))
            {
                var finalText = NormalizeText(ParseText(_recognizer.Result(), "text"));
                _lastPartial = string.Empty;
                if (!string.IsNullOrWhiteSpace(finalText))
                {
                    TranscriptChanged?.Invoke(this, new LiveTranscriptEventArgs(finalText, isFinal: true));
                }
                return;
            }

            var partialText = NormalizeText(ParseText(_recognizer.PartialResult(), "partial"));
            if (!string.IsNullOrWhiteSpace(partialText)
                && !string.Equals(partialText, _lastPartial, StringComparison.Ordinal))
            {
                _lastPartial = partialText;
                TranscriptChanged?.Invoke(this, new LiveTranscriptEventArgs(partialText, isFinal: false));
            }
        }
    }

    public string EndSession()
    {
        lock (_gate)
        {
            if (_recognizer is null)
            {
                return string.Empty;
            }

            var finalText = NormalizeText(ParseText(_recognizer.FinalResult(), "text"));
            _recognizer.Dispose();
            _recognizer = null;
            _lastPartial = string.Empty;
            return finalText;
        }
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        lock (_gate)
        {
            _recognizer?.Dispose();
            _recognizer = null;
            _model?.Dispose();
            _model = null;
        }

        _gate.Dispose();
    }

    private static string ParseText(string json, string propertyName)
    {
        try
        {
            using var document = JsonDocument.Parse(json);
            return document.RootElement.TryGetProperty(propertyName, out var value)
                ? value.GetString() ?? string.Empty
                : string.Empty;
        }
        catch (JsonException)
        {
            return string.Empty;
        }
    }

    private static string NormalizeText(string value)
    {
        return CjkSpaceRegex()
            .Replace(value.Trim(), string.Empty)
            .Replace("  ", " ", StringComparison.Ordinal);
    }

    [GeneratedRegex(@"(?<=\p{IsCJKUnifiedIdeographs}) (?=\p{IsCJKUnifiedIdeographs})")]
    private static partial Regex CjkSpaceRegex();
}
