using JT.Copilot.Application.Models;
using JT.Copilot.Application.Text;

namespace JT.Copilot.UnitTests;

public sealed class DomainTermCorrectorTests
{
    private readonly DomainTermCorrector _corrector = new();
    private readonly string _defaultVocabulary = new AppSettings().CustomVocabulary;

    [Theory]
    [InlineData("我们的新奥尔良系统支持积分队里区", "我们的CRM系统支持积分兑礼")]
    [InlineData("欧克，这个功能可以", "OK，这个功能可以")]
    [InlineData("crm ok prd api kpi", "CRM OK PRD API KPI")]
    public void Correct_RepairsKnownBusinessTerms(string input, string expected)
    {
        Assert.Equal(expected, _corrector.Correct(input, _defaultVocabulary));
    }

    [Fact]
    public void Correct_CustomAliasOverridesBuiltInAlias()
    {
        const string vocabulary = "客户关系管理=crm,西阿艾姆";

        var corrected = _corrector.Correct("crm 和 西阿艾姆", vocabulary);

        Assert.Equal("客户关系管理 和 客户关系管理", corrected);
    }

    [Fact]
    public void Correct_DoesNotTurnLegitimateChineseQuestionIntoOk()
    {
        Assert.Equal("这样可以吗", _corrector.Correct("这样可以吗", _defaultVocabulary));
        Assert.Equal(
            "支持积分兑礼，OK吗",
            _corrector.Correct("支持积分兑礼，可以吗", _defaultVocabulary));
    }

    [Fact]
    public void GetHotwords_IncludesCustomStandardsBeforeDefaults()
    {
        var hotwords = _corrector.GetHotwords("积分兑礼=积分对礼\n客户关系管理=CRM");

        Assert.Contains("积分兑礼", hotwords);
        Assert.Contains("客户关系管理", hotwords);
        Assert.Contains("项目管理", hotwords);
    }
}
