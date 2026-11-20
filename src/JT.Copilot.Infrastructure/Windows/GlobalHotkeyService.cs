using System.ComponentModel;
using System.Runtime.InteropServices;
using JT.Copilot.Application.Abstractions;

namespace JT.Copilot.Infrastructure.Windows;

public sealed class GlobalHotkeyService : IGlobalHotkeyService
{
    private const int WhKeyboardLl = 13;
    private const int WmKeyDown = 0x0100;
    private const int WmKeyUp = 0x0101;
    private const int WmSysKeyDown = 0x0104;
    private const int WmSysKeyUp = 0x0105;
    private const int VkEscape = 0x1B;
    private const int VkSpace = 0x20;
    private const int VkControl = 0x11;
    private const int VkMenu = 0x12;

    private readonly LowLevelKeyboardProc _keyboardProcedure;
    private nint _hookHandle;
    private bool _triggerDown;
    private bool _disposed;

    public GlobalHotkeyService()
    {
        _keyboardProcedure = HookCallback;
    }

    public event EventHandler? Pressed;

    public event EventHandler? Released;

    public event EventHandler? CancelRequested;

    public bool IsRunning => _hookHandle != nint.Zero;

    public void Start()
    {
        ObjectDisposedException.ThrowIf(_disposed, this);

        if (IsRunning)
        {
            return;
        }

        _hookHandle = SetWindowsHookEx(
            WhKeyboardLl,
            _keyboardProcedure,
            GetModuleHandle(null),
            0);

        if (_hookHandle == nint.Zero)
        {
            throw new Win32Exception(Marshal.GetLastWin32Error(), "无法安装全局键盘监听。");
        }
    }

    public void Stop()
    {
        if (_hookHandle == nint.Zero)
        {
            return;
        }

        UnhookWindowsHookEx(_hookHandle);
        _hookHandle = nint.Zero;
        _triggerDown = false;
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        Stop();
        _disposed = true;
    }

    private nint HookCallback(int code, nint wParam, nint lParam)
    {
        if (code >= 0)
        {
            var message = unchecked((int)wParam);
            var keyboardEvent = Marshal.PtrToStructure<KbdLlHookStruct>(lParam);

            if (keyboardEvent.VirtualKeyCode == VkEscape && _triggerDown
                && message is WmKeyDown or WmSysKeyDown)
            {
                _triggerDown = false;
                CancelRequested?.Invoke(this, EventArgs.Empty);
                return 1;
            }

            if (keyboardEvent.VirtualKeyCode == VkSpace
                && message is WmKeyDown or WmSysKeyDown
                && IsModifierDown(VkControl)
                && IsModifierDown(VkMenu))
            {
                if (!_triggerDown)
                {
                    _triggerDown = true;
                    Pressed?.Invoke(this, EventArgs.Empty);
                }

                return 1;
            }

            if (keyboardEvent.VirtualKeyCode == VkSpace
                && message is WmKeyUp or WmSysKeyUp
                && _triggerDown)
            {
                _triggerDown = false;
                Released?.Invoke(this, EventArgs.Empty);
                return 1;
            }
        }

        return CallNextHookEx(_hookHandle, code, wParam, lParam);
    }

    private static bool IsModifierDown(int virtualKey)
    {
        return (GetAsyncKeyState(virtualKey) & 0x8000) != 0;
    }

    private delegate nint LowLevelKeyboardProc(int code, nint wParam, nint lParam);

    [StructLayout(LayoutKind.Sequential)]
    private readonly struct KbdLlHookStruct
    {
        public readonly int VirtualKeyCode;
        public readonly int ScanCode;
        public readonly int Flags;
        public readonly int Time;
        public readonly nint ExtraInfo;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern nint SetWindowsHookEx(
        int hookId,
        LowLevelKeyboardProc callback,
        nint moduleHandle,
        uint threadId);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UnhookWindowsHookEx(nint hookHandle);

    [DllImport("user32.dll")]
    private static extern nint CallNextHookEx(
        nint hookHandle,
        int code,
        nint wParam,
        nint lParam);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern nint GetModuleHandle(string? moduleName);

    [DllImport("user32.dll")]
    private static extern short GetAsyncKeyState(int virtualKey);
}
