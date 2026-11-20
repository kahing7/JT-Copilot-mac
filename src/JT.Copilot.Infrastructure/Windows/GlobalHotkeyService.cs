using System.ComponentModel;
using System.Runtime.InteropServices;
using JT.Copilot.Application.Abstractions;
using JT.Copilot.Application.Hotkeys;

namespace JT.Copilot.Infrastructure.Windows;

public sealed class GlobalHotkeyService : IGlobalHotkeyService
{
    private const int WhKeyboardLl = 13;
    private const int WmKeyDown = 0x0100;
    private const int WmKeyUp = 0x0101;
    private const int WmSysKeyDown = 0x0104;
    private const int WmSysKeyUp = 0x0105;
    private const int VkEscape = 0x1B;
    private const int VkControl = 0x11;
    private const int VkMenu = 0x12;
    private const int VkShift = 0x10;
    private const int VkLeftWindows = 0x5B;
    private const int VkRightWindows = 0x5C;
    private const int GwlExStyle = -20;
    private const long WsExNoActivate = 0x08000000;

    private readonly LowLevelKeyboardProc _keyboardProcedure;
    private readonly HashSet<int> _pressedKeys = [];
    private nint _hookHandle;
    private HotkeyGesture _gesture = HotkeyGesture.Default;
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

    public bool CaptureEscape { get; set; }

    public HotkeyGesture Gesture => _gesture;

    public void Start(HotkeyGesture gesture)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        ArgumentNullException.ThrowIfNull(gesture);

        if (IsRunning)
        {
            _gesture = gesture;
            return;
        }

        _gesture = gesture;
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

    public void Reconfigure(HotkeyGesture gesture)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        ArgumentNullException.ThrowIfNull(gesture);

        var previousGesture = _gesture;
        var wasRunning = IsRunning;
        Stop();

        try
        {
            Start(gesture);
        }
        catch
        {
            _gesture = previousGesture;
            if (wasRunning)
            {
                Start(previousGesture);
            }

            throw;
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
        _pressedKeys.Clear();
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
            var virtualKey = keyboardEvent.VirtualKeyCode;

            // Settings and other activating in-app dialogs must receive their own keys.
            if (ShouldBypassHookForInAppDialog())
            {
                return CallNextHookEx(_hookHandle, code, wParam, lParam);
            }

            if (message is WmKeyDown or WmSysKeyDown)
            {
                _pressedKeys.Add(virtualKey);
            }
            else if (message is WmKeyUp or WmSysKeyUp)
            {
                _pressedKeys.Remove(virtualKey);
            }

            if (virtualKey == VkEscape && CaptureEscape
                && message is WmKeyDown or WmSysKeyDown)
            {
                _triggerDown = false;
                CancelRequested?.Invoke(this, EventArgs.Empty);
                return 1;
            }

            var isGestureKey = _gesture.VirtualKeys.Contains(virtualKey);
            if (isGestureKey
                && message is WmKeyDown or WmSysKeyDown
                && AreRequiredModifiersDown())
            {
                if (!_triggerDown && _gesture.VirtualKeys.All(_pressedKeys.Contains))
                {
                    _triggerDown = true;
                    Pressed?.Invoke(this, EventArgs.Empty);
                }

                return 1;
            }

            if (_triggerDown && message is WmKeyUp or WmSysKeyUp)
            {
                if (isGestureKey)
                {
                    _triggerDown = false;
                    Released?.Invoke(this, EventArgs.Empty);
                    return 1;
                }

                if (HotkeyGesture.IsModifierVirtualKey(virtualKey))
                {
                    _triggerDown = false;
                    Released?.Invoke(this, EventArgs.Empty);
                }
            }
        }

        return CallNextHookEx(_hookHandle, code, wParam, lParam);
    }

    private bool AreRequiredModifiersDown()
    {
        var modifiers = _gesture.Modifiers;

        if (modifiers.HasFlag(HotkeyModifiers.Control) && !IsModifierDown(VkControl))
        {
            return false;
        }

        if (modifiers.HasFlag(HotkeyModifiers.Shift) && !IsModifierDown(VkShift))
        {
            return false;
        }

        if (modifiers.HasFlag(HotkeyModifiers.Alt) && !IsModifierDown(VkMenu))
        {
            return false;
        }

        return !modifiers.HasFlag(HotkeyModifiers.Windows)
            || IsModifierDown(VkLeftWindows)
            || IsModifierDown(VkRightWindows);
    }

    private static bool IsModifierDown(int virtualKey)
    {
        return (GetAsyncKeyState(virtualKey) & 0x8000) != 0;
    }

    private static bool ShouldBypassHookForInAppDialog()
    {
        var foregroundWindow = GetForegroundWindow();
        if (foregroundWindow == nint.Zero)
        {
            return false;
        }

        GetWindowThreadProcessId(foregroundWindow, out var processId);
        if (processId != (uint)Environment.ProcessId)
        {
            return false;
        }

        var extendedStyle = GetWindowLongPtr(foregroundWindow, GwlExStyle).ToInt64();
        return (extendedStyle & WsExNoActivate) == 0;
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

    [DllImport("user32.dll")]
    private static extern nint GetForegroundWindow();

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(nint windowHandle, out uint processId);

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW", SetLastError = true)]
    private static extern nint GetWindowLongPtr(nint windowHandle, int index);
}
