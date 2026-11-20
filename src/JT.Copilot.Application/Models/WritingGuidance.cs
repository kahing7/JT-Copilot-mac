namespace JT.Copilot.Application.Models;

public sealed record WritingGuidance(
    IReadOnlyList<string> Framework,
    string NextSentence,
    IReadOnlyList<string> Directions,
    IReadOnlyList<string> MissingPoints,
    DocumentTemplate Template = DocumentTemplate.Auto)
{
    public static WritingGuidance Empty { get; } = new([], string.Empty, [], [], DocumentTemplate.Auto);
}

public sealed record WritingSessionUpdate(
    string StableTranscript,
    string DraftTranscript,
    WritingGuidance Guidance,
    string StatusText,
    string OptimizedTranscript = "",
    string ReplacementMessage = "");

public sealed class WritingSessionUpdateEventArgs(WritingSessionUpdate update) : EventArgs
{
    public WritingSessionUpdate Update { get; } = update;
}
