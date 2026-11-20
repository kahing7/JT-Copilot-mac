using JT.Copilot.Application.Text;

namespace JT.Copilot.UnitTests;

public sealed class LiveTextDiffTests
{
    [Theory]
    [InlineData("我", "我想", 1, 0, 1)]
    [InlineData("我想介绍", "我想介绍一下", 4, 0, 2)]
    [InlineData("她有三个能力", "它有三个能力", 0, 6, 6)]
    [InlineData("功能介绍完了", "功能介绍", 4, 2, 0)]
    public void Calculate_ProducesMinimalEdits(
        string previous,
        string current,
        int prefixLength,
        int charactersToDelete,
        int charactersToInsert)
    {
        var diff = LiveTextDiffCalculator.Calculate(previous, current);

        Assert.Equal(prefixLength, diff.CommonPrefixLength);
        Assert.Equal(charactersToDelete, diff.CharactersToDelete);
        Assert.Equal(charactersToInsert, diff.CharactersToInsert);
    }
}
