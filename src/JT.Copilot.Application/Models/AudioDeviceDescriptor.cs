namespace JT.Copilot.Application.Models;

public sealed record AudioDeviceDescriptor(string Id, string DisplayName, bool IsDefault = false)
{
    public override string ToString() => DisplayName;
}
