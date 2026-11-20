using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Automation.Text;
using JT.Copilot.Application.Abstractions;
using JT.Copilot.Application.Models;
using Microsoft.Extensions.Logging;

namespace JT.Copilot.Infrastructure.Windows;

public sealed class WindowsTextInsertionService : ITextInsertionService
{
    private readonly ILogger<WindowsTextInsertionService> _logger;

    public WindowsTextInsertionService(ILogger<WindowsTextInsertionService> logger)
    {
        _logger = logger;
    }

    public Task<ITextInsertionTarget?> CaptureTargetAsync(
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var windowHandle = GetForegroundWindow();

        if (windowHandle == nint.Zero)
        {
            return Task.FromResult<ITextInsertionTarget?>(null);
        }

        GetWindowThreadProcessId(windowHandle, out var processId);
        if (processId == (uint)Environment.ProcessId)
        {
            return Task.FromResult<ITextInsertionTarget?>(null);
        }

        var focusedElement = AutomationElement.FocusedElement;
        if (focusedElement is null
            || focusedElement.Current.ProcessId != processId
            || focusedElement.Current.IsPassword)
        {
            return Task.FromResult<ITextInsertionTarget?>(null);
        }

        TextPattern? textPattern = null;
        TextPatternRange? startRange = null;

        if (focusedElement.TryGetCurrentPattern(TextPattern.Pattern, out var pattern)
            && pattern is TextPattern availableTextPattern)
        {
            textPattern = availableTextPattern;
            startRange = availableTextPattern.GetSelection().FirstOrDefault()?.Clone();
        }

        var processName = GetProcessName((int)processId);
        var displayName = string.IsNullOrWhiteSpace(focusedElement.Current.Name)
            ? processName
            : $"{processName} · {focusedElement.Current.Name}";

        return Task.FromResult<ITextInsertionTarget?>(
            new WindowsTextInsertionTarget(
                windowHandle,
                processId,
                focusedElement,
                textPattern,
                startRange,
                displayName));
    }

    public async Task<TextInsertionResult> InsertAsync(
        string text,
        ITextInsertionTarget target,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrEmpty(text))
        {
            return TextInsertionResult.Succeeded;
        }

        if (target is not WindowsTextInsertionTarget windowsTarget)
        {
            return new TextInsertionResult(false, "目标编辑器类型不受支持。");
        }

        if (!windowsTarget.IsActive)
        {
            return new TextInsertionResult(false, "焦点已离开原编辑器，文字未自动写入。");
        }

        try
        {
            var clipboardResult = await ReplaceSelectionWithClipboardAsync(
                text,
                windowsTarget,
                cancellationToken).ConfigureAwait(false);
            return clipboardResult;
        }
        catch (Exception exception) when (
            exception is InvalidOperationException
            or COMException
            or ExternalException)
        {
            _logger.LogError(exception, "Unable to insert the transcript into the active editor.");
            return new TextInsertionResult(false, $"文字写入失败：{exception.Message}");
        }
    }

    public async Task<TextReplacementResult> ReplaceSessionTextAsync(
        string expectedText,
        string replacementText,
        ITextInsertionTarget target,
        CancellationToken cancellationToken = default)
    {
        if (target is not WindowsTextInsertionTarget windowsTarget)
        {
            return new TextReplacementResult(false, "目标编辑器类型不受支持。");
        }

        if (!windowsTarget.IsActive)
        {
            return new TextReplacementResult(false, "焦点已离开原编辑器，优化全文未自动替换。");
        }

        if (windowsTarget.TextPattern is null || windowsTarget.StartRange is null)
        {
            return new TextReplacementResult(false, "当前编辑器不支持可靠的文本范围定位，优化全文未自动替换。");
        }

        try
        {
            var selected = await InvokeOnUiThreadAsync(() =>
            {
                var currentSelection = windowsTarget.TextPattern
                    .GetSelection()
                    .FirstOrDefault()
                    ?.Clone();

                if (currentSelection is null)
                {
                    return null;
                }

                var sessionRange = windowsTarget.StartRange.Clone();
                sessionRange.MoveEndpointByRange(
                    TextPatternRangeEndpoint.End,
                    currentSelection,
                    TextPatternRangeEndpoint.Start);

                return sessionRange;
            }, cancellationToken).ConfigureAwait(false);

            string? existingText = null;
            if (selected is not null)
            {
                existingText = await InvokeOnUiThreadAsync(
                    () => selected.GetText(-1),
                    cancellationToken).ConfigureAwait(false);
            }

            var rangeToReplace = IsEquivalent(existingText, expectedText)
                ? selected
                : await FindTextRangeAsync(
                    windowsTarget.TextPattern,
                    expectedText,
                    cancellationToken).ConfigureAwait(false);

            if (rangeToReplace is null || !IsEquivalent(rangeToReplace.GetText(-1), expectedText))
            {
                return new TextReplacementResult(
                    false,
                    "未能可靠定位本次会话写入的完整文字，已保留优化结果供手动替换。");
            }

            await InvokeOnUiThreadAsync(
                () => rangeToReplace.Select(),
                cancellationToken).ConfigureAwait(false);

            var pasteResult = await ReplaceSelectionWithClipboardAsync(
                replacementText,
                windowsTarget,
                cancellationToken).ConfigureAwait(false);

            return pasteResult.Success
                ? TextReplacementResult.Succeeded
                : new TextReplacementResult(false, pasteResult.Message);
        }
        catch (Exception exception) when (
            exception is ElementNotAvailableException
            or InvalidOperationException
            or COMException
            or ExternalException)
        {
            _logger.LogError(exception, "Unable to replace the session text.");
            return new TextReplacementResult(
                false,
                $"优化全文替换失败：{exception.Message}");
        }
    }

    private async Task<TextInsertionResult> ReplaceSelectionWithClipboardAsync(
        string text,
        WindowsTextInsertionTarget target,
        CancellationToken cancellationToken)
    {
        if (!target.IsActive)
        {
            return new TextInsertionResult(false, "焦点已离开原编辑器，文字未自动写入。");
        }

        var backup = await InvokeOnUiThreadAsync(() =>
        {
            var data = TryGetClipboardData();
            SetClipboardText(text);
            return data;
        }, cancellationToken).ConfigureAwait(false);

        try
        {
            await Task.Delay(70, cancellationToken).ConfigureAwait(false);
            if (!target.IsActive)
            {
                return new TextInsertionResult(false, "写入前焦点已变化，文字未自动输入。");
            }

            SendPasteShortcut();
            await Task.Delay(220, cancellationToken).ConfigureAwait(false);
            return TextInsertionResult.Succeeded;
        }
        finally
        {
            await InvokeOnUiThreadAsync(
                () => RestoreClipboard(backup),
                CancellationToken.None).ConfigureAwait(false);
        }
    }

    private async Task<TextPatternRange?> FindTextRangeAsync(
        TextPattern textPattern,
        string expectedText,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(expectedText))
        {
            return null;
        }

        return await InvokeOnUiThreadAsync(() =>
        {
            try
            {
                return textPattern.DocumentRange.FindText(
                    expectedText,
                    backward: false,
                    ignoreCase: false);
            }
            catch (ArgumentException)
            {
                return null;
            }
        }, cancellationToken).ConfigureAwait(false);
    }

    private static Task InvokeOnUiThreadAsync(Action action, CancellationToken cancellationToken)
    {
        return InvokeOnUiThreadAsync(
            () =>
            {
                action();
                return true;
            },
            cancellationToken);
    }

    private static async Task<T> InvokeOnUiThreadAsync<T>(
        Func<T> action,
        CancellationToken cancellationToken)
    {
        var dispatcher = System.Windows.Application.Current?.Dispatcher;
        if (dispatcher is null || dispatcher.CheckAccess())
        {
            return action();
        }

        return await dispatcher.InvokeAsync(action, System.Windows.Threading.DispatcherPriority.Send, cancellationToken);
    }

    private static IDataObject? TryGetClipboardData()
    {
        try
        {
            return Clipboard.GetDataObject();
        }
        catch (ExternalException)
        {
            return null;
        }
    }

    private static void SetClipboardText(string text)
    {
        for (var attempt = 1; attempt <= 3; attempt++)
        {
            try
            {
                Clipboard.SetText(text);
                return;
            }
            catch (ExternalException) when (attempt < 3)
            {
                Thread.Sleep(40);
            }
        }
    }

    private static void RestoreClipboard(IDataObject? data)
    {
        if (data is null)
        {
            return;
        }

        try
        {
            Clipboard.SetDataObject(data, copy: true);
        }
        catch (ExternalException)
        {
        }
    }

    private static void SendPasteShortcut()
    {
        var inputs = new[]
        {
            CreateKeyboardInput(0x11, keyUp: false),
            CreateKeyboardInput(0x56, keyUp: false),
            CreateKeyboardInput(0x56, keyUp: true),
            CreateKeyboardInput(0x11, keyUp: true)
        };

        SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<Input>());
    }

    private static Input CreateKeyboardInput(ushort virtualKey, bool keyUp)
    {
        return new Input
        {
            Type = 1,
            Data = new InputUnion
            {
                Keyboard = new KeyboardInput
                {
                    VirtualKey = virtualKey,
                    Flags = keyUp ? 0x0002u : 0u
                }
            }
        };
    }

    private static bool IsEquivalent(string? actual, string expected)
    {
        if (actual is null)
        {
            return false;
        }

        static string Normalize(string value) =>
            value.Replace("\r\n", "\n", StringComparison.Ordinal).Trim();

        return string.Equals(Normalize(actual), Normalize(expected), StringComparison.Ordinal);
    }

    private static string GetProcessName(int processId)
    {
        try
        {
            return Process.GetProcessById(processId).ProcessName;
        }
        catch (ArgumentException)
        {
            return "未知应用";
        }
    }

    private sealed class WindowsTextInsertionTarget(
        nint windowHandle,
        uint processId,
        AutomationElement focusedElement,
        TextPattern? textPattern,
        TextPatternRange? startRange,
        string displayName) : ITextInsertionTarget
    {
        public nint WindowHandle { get; } = windowHandle;

        public uint ProcessId { get; } = processId;

        public AutomationElement FocusedElement { get; } = focusedElement;

        public TextPattern? TextPattern { get; } = textPattern;

        public TextPatternRange? StartRange { get; } = startRange;

        public bool IsActive =>
            GetForegroundWindow() == WindowHandle
            && AutomationElement.FocusedElement?.Current.ProcessId == ProcessId;

        public string DisplayName { get; } = displayName;

        public void Dispose()
        {
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct Input
    {
        public uint Type;
        public InputUnion Data;
    }

    [StructLayout(LayoutKind.Explicit)]
    private struct InputUnion
    {
        [FieldOffset(0)]
        public MouseInput Mouse;

        [FieldOffset(0)]
        public KeyboardInput Keyboard;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KeyboardInput
    {
        public ushort VirtualKey;
        public ushort ScanCode;
        public uint Flags;
        public uint Time;
        public nint ExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MouseInput
    {
        public int X;
        public int Y;
        public uint MouseData;
        public uint Flags;
        public uint Time;
        public nint ExtraInfo;
    }

    [DllImport("user32.dll")]
    private static extern nint GetForegroundWindow();

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(nint windowHandle, out uint processId);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(
        uint inputCount,
        Input[] inputs,
        int inputSize);
}
