namespace JT.Copilot.Application.Models;

public sealed record TextInsertionResult(bool Success, string Message)
{
    public static TextInsertionResult Succeeded { get; } = new(true, string.Empty);
}

public sealed record TextReplacementResult(bool Success, string Message)
{
    public static TextReplacementResult Succeeded { get; } = new(true, string.Empty);
}
