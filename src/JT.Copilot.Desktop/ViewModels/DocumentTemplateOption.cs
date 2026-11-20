using JT.Copilot.Application.Models;

namespace JT.Copilot.Desktop.ViewModels;

public sealed record DocumentTemplateOption(DocumentTemplate Value, string DisplayName)
{
    public override string ToString() => DisplayName;
}

public static class DocumentTemplateCatalog
{
    public static IReadOnlyList<DocumentTemplateOption> All { get; } =
    [
        new(DocumentTemplate.Auto, "自动识别"),
        new(DocumentTemplate.ProjectManagement, "项目管理文档"),
        new(DocumentTemplate.Prd, "PRD"),
        new(DocumentTemplate.WeeklyReport, "周报"),
        new(DocumentTemplate.Solution, "方案文档")
    ];

    public static string GetDisplayName(DocumentTemplate template)
    {
        return All.FirstOrDefault(option => option.Value == template)?.DisplayName
            ?? template switch
            {
                DocumentTemplate.General => "通用写作",
                _ => "自动识别"
            };
    }
}
