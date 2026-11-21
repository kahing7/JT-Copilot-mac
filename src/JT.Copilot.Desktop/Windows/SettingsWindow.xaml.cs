using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using JT.Copilot.Application.Hotkeys;
using JT.Copilot.Desktop.ViewModels;

namespace JT.Copilot.Desktop.Windows;

public partial class SettingsWindow : Window
{
    private readonly MainWindowViewModel _viewModel;
    private readonly HashSet<int> _capturedKeys = [];
    private bool _isCapturingHotkey;
    private HotkeyModifiers _capturedModifiers;

    public SettingsWindow(MainWindowViewModel viewModel)
    {
        _viewModel = viewModel;
        DataContext = viewModel;
        InitializeComponent();
    }

    private void SettingsWindow_OnSourceInitialized(object? sender, EventArgs e)
    {
        var windowHandle = new WindowInteropHelper(this).Handle;
        var extendedStyle = GetWindowLongPtr(windowHandle, -20).ToInt64();
        SetWindowLongPtr(windowHandle, -20, new nint(extendedStyle | 0x00000080));
    }

    private void Header_OnMouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (e.LeftButton == MouseButtonState.Pressed)
        {
            DragMove();
        }
    }

    private void CloseButton_OnClick(object sender, RoutedEventArgs e)
    {
        Close();
    }

    private void ModifyHotkeyButton_OnClick(object sender, RoutedEventArgs e)
    {
        BeginHotkeyCapture();
    }

    private async void DefaultHotkeyButton_OnClick(object sender, RoutedEventArgs e)
    {
        EndHotkeyCapture();
        await _viewModel.RestoreDefaultHotkeyAsync();
    }

    private void HotkeyBox_OnPreviewMouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        e.Handled = true;
        BeginHotkeyCapture();
    }

    private void HotkeyBox_OnPreviewKeyDown(object sender, KeyEventArgs e)
    {
        if (!_isCapturingHotkey)
        {
            return;
        }

        e.Handled = true;
        var key = e.Key == Key.System ? e.SystemKey : e.Key;

        if (key == Key.Escape)
        {
            EndHotkeyCapture();
            _viewModel.CancelHotkeyCapture();
            return;
        }

        _capturedModifiers = GetCurrentModifiers();

        if (IsModifierKey(key))
        {
            _viewModel.PreviewHotkey(_capturedModifiers, _capturedKeys);
            return;
        }

        var virtualKey = KeyInterop.VirtualKeyFromKey(key);
        if (virtualKey != 0)
        {
            _capturedKeys.Add(virtualKey);
            _viewModel.PreviewHotkey(_capturedModifiers, _capturedKeys);
        }
    }

    private async void HotkeyBox_OnPreviewKeyUp(object sender, KeyEventArgs e)
    {
        if (!_isCapturingHotkey)
        {
            return;
        }

        var key = e.Key == Key.System ? e.SystemKey : e.Key;
        if (IsModifierKey(key))
        {
            return;
        }

        var virtualKey = KeyInterop.VirtualKeyFromKey(key);
        if (!_capturedKeys.Contains(virtualKey))
        {
            return;
        }

        e.Handled = true;
        var virtualKeys = _capturedKeys.ToArray();
        EndHotkeyCapture();

        if (!HotkeyGesture.TryCreate(_capturedModifiers, virtualKeys, out var gesture))
        {
            _viewModel.CancelHotkeyCapture();
            _viewModel.ReportHotkeyError("组合无效，需要 Ctrl、Alt 或 Win 修饰键。");
            return;
        }

        await _viewModel.ApplyHotkeyAsync(gesture);
    }

    private void HotkeyBox_OnLostKeyboardFocus(object sender, KeyboardFocusChangedEventArgs e)
    {
        if (_isCapturingHotkey)
        {
            EndHotkeyCapture();
            _viewModel.CancelHotkeyCapture();
        }
    }

    private void BeginHotkeyCapture()
    {
        _capturedKeys.Clear();
        _capturedModifiers = GetCurrentModifiers();
        _isCapturingHotkey = true;
        _viewModel.BeginHotkeyCapture();
        HotkeyBox.Focus();
        Keyboard.Focus(HotkeyBox);
    }

    private void EndHotkeyCapture()
    {
        _isCapturingHotkey = false;
        _capturedKeys.Clear();
    }

    private static HotkeyModifiers GetCurrentModifiers()
    {
        var modifiers = HotkeyModifiers.None;
        var wpfModifiers = Keyboard.Modifiers;

        if (wpfModifiers.HasFlag(ModifierKeys.Control))
        {
            modifiers |= HotkeyModifiers.Control;
        }

        if (wpfModifiers.HasFlag(ModifierKeys.Shift))
        {
            modifiers |= HotkeyModifiers.Shift;
        }

        if (wpfModifiers.HasFlag(ModifierKeys.Alt))
        {
            modifiers |= HotkeyModifiers.Alt;
        }

        if (wpfModifiers.HasFlag(ModifierKeys.Windows))
        {
            modifiers |= HotkeyModifiers.Windows;
        }

        return modifiers;
    }

    private static bool IsModifierKey(Key key)
    {
        return key is Key.LeftCtrl or Key.RightCtrl
            or Key.LeftShift or Key.RightShift
            or Key.LeftAlt or Key.RightAlt
            or Key.LWin or Key.RWin;
    }

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW", SetLastError = true)]
    private static extern nint GetWindowLongPtr(nint windowHandle, int index);

    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW", SetLastError = true)]
    private static extern nint SetWindowLongPtr(nint windowHandle, int index, nint newValue);
}
