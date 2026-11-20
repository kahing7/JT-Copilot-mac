using System.Buffers.Binary;
using System.Diagnostics;
using System.IO;
using JT.Copilot.Application.Abstractions;
using JT.Copilot.Application.Models;
using JT.Copilot.Infrastructure.Storage;
using Microsoft.Extensions.Logging;
using NAudio.Wave;

namespace JT.Copilot.Infrastructure.Audio;

public sealed class WaveAudioCaptureService : IAudioCaptureService
{
    private readonly ILogger<WaveAudioCaptureService> _logger;
    private readonly object _writerLock = new();
    private readonly Stopwatch _stopwatch = new();

    private WaveIn? _waveIn;
    private WaveFileWriter? _writer;
    private TaskCompletionSource<AudioCaptureResult>? _stopCompletion;
    private string? _recordingPath;
    private bool _canceling;

    public WaveAudioCaptureService(ILogger<WaveAudioCaptureService> logger)
    {
        _logger = logger;
    }

    public event EventHandler<AudioLevelChangedEventArgs>? LevelChanged;

    public event EventHandler<PcmAudioDataEventArgs>? PcmDataAvailable;

    public bool IsCapturing => _waveIn is not null && _writer is not null;

    public IReadOnlyList<AudioDeviceDescriptor> GetInputDevices()
    {
        try
        {
            var deviceCount = WaveIn.DeviceCount;
            var devices = new List<AudioDeviceDescriptor>(deviceCount);

            for (var index = 0; index < deviceCount; index++)
            {
                var capabilities = WaveIn.GetCapabilities(index);
                devices.Add(new AudioDeviceDescriptor(
                    index.ToString(),
                    capabilities.ProductName,
                    IsDefault: index == 0));
            }

            return devices;
        }
        catch (Exception exception)
        {
            _logger.LogWarning(exception, "Unable to enumerate recording devices.");
            return [];
        }
    }

    public Task StartAsync(string? deviceId, CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();

        if (IsCapturing)
        {
            return Task.CompletedTask;
        }

        var deviceNumber = ResolveDeviceNumber(deviceId);
        Directory.CreateDirectory(AppPaths.RecordingsDirectory);
        _recordingPath = Path.Combine(
            AppPaths.RecordingsDirectory,
            $"recording-{DateTime.Now:yyyyMMdd-HHmmss}-{Guid.NewGuid():N}.wav");

        var waveIn = new WaveIn
        {
            DeviceNumber = deviceNumber,
            WaveFormat = new WaveFormat(16_000, 16, 1),
            BufferMilliseconds = 50,
            NumberOfBuffers = 3
        };

        var writer = new WaveFileWriter(_recordingPath, waveIn.WaveFormat);
        waveIn.DataAvailable += OnDataAvailable;
        waveIn.RecordingStopped += OnRecordingStopped;

        try
        {
            waveIn.StartRecording();
            _waveIn = waveIn;
            _writer = writer;
            _canceling = false;
            _stopwatch.Restart();
        }
        catch
        {
            waveIn.DataAvailable -= OnDataAvailable;
            waveIn.RecordingStopped -= OnRecordingStopped;
            waveIn.Dispose();
            writer.Dispose();
            DeleteCurrentRecording();
            throw;
        }

        return Task.CompletedTask;
    }

    public async Task<AudioCaptureResult> StopAsync(CancellationToken cancellationToken = default)
    {
        if (_waveIn is null)
        {
            throw new InvalidOperationException("当前没有正在进行的录音。");
        }

        _stopCompletion = new TaskCompletionSource<AudioCaptureResult>(
            TaskCreationOptions.RunContinuationsAsynchronously);

        using var registration = cancellationToken.Register(
            () => _stopCompletion.TrySetCanceled(cancellationToken));

        _waveIn.StopRecording();
        return await _stopCompletion.Task.ConfigureAwait(false);
    }

    public void Cancel()
    {
        _canceling = true;

        if (_waveIn is not null)
        {
            try
            {
                _waveIn.StopRecording();
            }
            catch (Exception exception)
            {
                _logger.LogDebug(exception, "Recording device was already stopped during cancellation.");
            }
        }

        DisposeCaptureResources();
        DeleteCurrentRecording();
    }

    public void Dispose()
    {
        Cancel();
        _waveIn?.Dispose();
        _writer?.Dispose();
        _waveIn = null;
        _writer = null;
    }

    private int ResolveDeviceNumber(string? deviceId)
    {
        if (WaveIn.DeviceCount <= 0)
        {
            throw new InvalidOperationException("未检测到可用的麦克风。");
        }

        return int.TryParse(deviceId, out var deviceNumber)
            && deviceNumber >= 0
            && deviceNumber < WaveIn.DeviceCount
                ? deviceNumber
                : 0;
    }

    private void OnDataAvailable(object? sender, WaveInEventArgs eventArgs)
    {
        lock (_writerLock)
        {
            _writer?.Write(eventArgs.Buffer, 0, eventArgs.BytesRecorded);
        }

        var span = eventArgs.Buffer.AsSpan(0, eventArgs.BytesRecorded);
        var peak = 0;

        for (var offset = 0; offset + 1 < span.Length; offset += sizeof(short))
        {
            var sample = Math.Abs((int)BinaryPrimitives.ReadInt16LittleEndian(span[offset..]));
            peak = Math.Max(peak, sample);
        }

        // Speech is usually low amplitude before gain is applied by ASR providers.
        var level = Math.Clamp(peak / 32768d * 4d, 0d, 1d);
        LevelChanged?.Invoke(this, new AudioLevelChangedEventArgs(level));
        PcmDataAvailable?.Invoke(
            this,
            new PcmAudioDataEventArgs(
                eventArgs.Buffer.AsMemory(0, eventArgs.BytesRecorded).ToArray(),
                level));
    }

    private void OnRecordingStopped(object? sender, StoppedEventArgs eventArgs)
    {
        _stopwatch.Stop();
        var duration = _stopwatch.Elapsed;
        var filePath = _recordingPath;

        DisposeCaptureResources();

        if (_canceling)
        {
            DeleteCurrentRecording();
            _stopCompletion?.TrySetCanceled();
            return;
        }

        if (eventArgs.Exception is not null)
        {
            DeleteCurrentRecording();
            _stopCompletion?.TrySetException(eventArgs.Exception);
            return;
        }

        if (string.IsNullOrWhiteSpace(filePath) || !File.Exists(filePath))
        {
            _stopCompletion?.TrySetException(
                new InvalidOperationException("录音文件未能正确保存。"));
            return;
        }

        _stopCompletion?.TrySetResult(new AudioCaptureResult(filePath!, duration));
    }

    private void DisposeCaptureResources()
    {
        lock (_writerLock)
        {
            _writer?.Dispose();
            _writer = null;
        }

        if (_waveIn is not null)
        {
            _waveIn.DataAvailable -= OnDataAvailable;
            _waveIn.RecordingStopped -= OnRecordingStopped;
            _waveIn.Dispose();
            _waveIn = null;
        }
    }

    private void DeleteCurrentRecording()
    {
        if (string.IsNullOrWhiteSpace(_recordingPath))
        {
            return;
        }

        try
        {
            File.Delete(_recordingPath);
        }
        catch (IOException exception)
        {
            _logger.LogDebug(exception, "Unable to delete canceled recording.");
        }
        finally
        {
            _recordingPath = null;
        }
    }
}
