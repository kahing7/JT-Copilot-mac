using JT.Copilot.Application.Guidance;
using JT.Copilot.Application.Models;

namespace JT.Copilot.Application.Abstractions;

public interface IDocumentFrameworkEngine
{
    DocumentFrameworkResult Build(string transcript, DocumentTemplate template);
}
