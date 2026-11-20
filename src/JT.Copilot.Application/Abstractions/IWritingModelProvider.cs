using JT.Copilot.Application.Models;

namespace JT.Copilot.Application.Abstractions;

public interface IWritingModelProvider
{
    Task<WritingGuidance> AnalyzeAsync(
        string transcript,
        WritingGuidance? previousGuidance,
        CancellationToken cancellationToken = default);

    Task<string> OptimizeAsync(
        string transcript,
        CancellationToken cancellationToken = default);

    Task<string> OptimizeSegmentsAsync(
        IReadOnlyList<string> transcriptSegments,
        CancellationToken cancellationToken = default);
}
