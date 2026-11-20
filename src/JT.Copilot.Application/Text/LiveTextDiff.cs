namespace JT.Copilot.Application.Text;

public readonly record struct LiveTextDiff(int CommonPrefixLength, int CharactersToDelete, int CharactersToInsert);

public static class LiveTextDiffCalculator
{
    public static LiveTextDiff Calculate(string previousText, string currentText)
    {
        previousText ??= string.Empty;
        currentText ??= string.Empty;
        var maximum = Math.Min(previousText.Length, currentText.Length);
        var prefixLength = 0;

        while (prefixLength < maximum
            && previousText[prefixLength] == currentText[prefixLength])
        {
            prefixLength++;
        }

        if (prefixLength > 0
            && prefixLength < previousText.Length
            && char.IsHighSurrogate(previousText[prefixLength - 1]))
        {
            prefixLength--;
        }

        return new LiveTextDiff(
            prefixLength,
            previousText.Length - prefixLength,
            currentText.Length - prefixLength);
    }
}
