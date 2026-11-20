using JT.Copilot.Application.Models;

namespace JT.Copilot.Application.Abstractions;

public interface ITextInsertionTarget : IDisposable
{
    bool IsActive { get; }

    string DisplayName { get; }
}

public interface ITextInsertionService
{
    Task<ITextInsertionTarget?> CaptureTargetAsync(
        CancellationToken cancellationToken = default);

    Task<TextInsertionResult> InsertAsync(
        string text,
        ITextInsertionTarget target,
        CancellationToken cancellationToken = default);

    Task<TextInsertionResult> UpdateLiveDraftAsync(
        string previousText,
        string currentText,
        ITextInsertionTarget target,
        CancellationToken cancellationToken = default);

    Task<TextReplacementResult> ReplaceSessionTextAsync(
        string expectedText,
        string replacementText,
        ITextInsertionTarget target,
        CancellationToken cancellationToken = default);
}
