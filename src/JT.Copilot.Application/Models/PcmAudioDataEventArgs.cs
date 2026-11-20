namespace JT.Copilot.Application.Models;

public sealed class PcmAudioDataEventArgs(ReadOnlyMemory<byte> pcmData, double level) : EventArgs
{
    public ReadOnlyMemory<byte> PcmData { get; } = pcmData;

    public double Level { get; } = level;
}
