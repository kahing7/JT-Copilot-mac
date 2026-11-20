namespace JT.Copilot.Application.Models;

public sealed class LiveTranscriptEventArgs(string text, bool isFinal) : EventArgs
{
    public string Text { get; } = text;

    public bool IsFinal { get; } = isFinal;
}
