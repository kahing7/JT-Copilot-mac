using JT.Copilot.Application.Guidance;
using JT.Copilot.Application.Models;

namespace JT.Copilot.UnitTests;

public sealed class LocalDocumentFrameworkEngineTests
{
    private readonly LocalDocumentFrameworkEngine _engine = new();

    [Fact]
    public void DetectTemplate_RecognizesProjectManagementContext()
    {
        var template = _engine.DetectTemplate(
            "我现在准备写一篇项目管理的文档，需要说明项目背景、业务目标和验收标准");

        Assert.Equal(DocumentTemplate.ProjectManagement, template);
    }

    [Theory]
    [InlineData("我现在准备写一篇项目管理的文档", "先交代一下项目背景")]
    [InlineData("先交代一下项目背景，当前存在交付延期", "接下来对齐项目的业务目标")]
    [InlineData("业务目标是把交付准时率提升到百分之九十五", "说明项目范围和边界")]
    [InlineData("项目范围包括三个业务团队", "介绍项目规划和关键里程碑")]
    [InlineData("规划分为两个阶段，十一月完成里程碑一", "说明干系人与职责")]
    [InlineData("干系人包括产品和研发团队，由项目经理负责", "补充风险和依赖")]
    [InlineData("风险主要是供应商依赖，需要提前准备备选", "给出交付物和验收标准")]
    public void Build_AdvancesProjectManagementPrompt(
        string transcript,
        string expectedNextSentence)
    {
        var result = _engine.Build(transcript, DocumentTemplate.Auto);

        Assert.Equal(DocumentTemplate.ProjectManagement, result.Template);
        Assert.Equal(expectedNextSentence, result.Guidance.NextSentence);
    }

    [Fact]
    public void Build_ManualTemplateDoesNotRequireAutoDetection()
    {
        var result = _engine.Build("先写需求背景", DocumentTemplate.Prd);

        Assert.Equal(DocumentTemplate.Prd, result.Template);
        Assert.Equal("说明目标用户和使用场景", result.Guidance.NextSentence);
    }
}
