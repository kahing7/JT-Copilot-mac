namespace JT.Copilot.Domain.ValueObjects;

public readonly record struct WindowPlacement(double Left, double Top)
{
    public bool IsFinite => double.IsFinite(Left) && double.IsFinite(Top);

    public static bool TryCreate(double? left, double? top, out WindowPlacement placement)
    {
        var candidate = new WindowPlacement(left ?? double.NaN, top ?? double.NaN);
        if (!candidate.IsFinite)
        {
            placement = default;
            return false;
        }

        placement = candidate;
        return true;
    }
}
