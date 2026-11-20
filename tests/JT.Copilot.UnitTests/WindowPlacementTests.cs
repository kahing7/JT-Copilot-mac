using JT.Copilot.Domain.ValueObjects;

namespace JT.Copilot.UnitTests;

public sealed class WindowPlacementTests
{
    [Theory]
    [InlineData(10d, 20d)]
    [InlineData(-500.5, 1200.25)]
    public void TryCreate_AcceptsFiniteCoordinates(double left, double top)
    {
        var created = WindowPlacement.TryCreate(left, top, out var placement);

        Assert.True(created);
        Assert.Equal(left, placement.Left);
        Assert.Equal(top, placement.Top);
    }

    [Theory]
    [InlineData(null, 20d)]
    [InlineData(10d, null)]
    [InlineData(double.NaN, 20d)]
    [InlineData(10d, double.PositiveInfinity)]
    public void TryCreate_RejectsMissingOrNonFiniteCoordinates(double? left, double? top)
    {
        var created = WindowPlacement.TryCreate(left, top, out _);

        Assert.False(created);
    }
}
