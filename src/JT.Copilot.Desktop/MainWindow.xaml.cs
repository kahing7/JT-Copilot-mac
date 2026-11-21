using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;
using JT.Copilot.Desktop.ViewModels;
using JT.Copilot.Desktop.Windows;
using JT.Copilot.Domain.ValueObjects;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

namespace JT.Copilot.Desktop;

public partial class MainWindow : Window
{
    private const int GwlExStyle = -20;
    private const int WsExToolWindow = 0x00000080;
    private const int WsExNoActivate = 0x08000000;
    private const int WmMouseActivate = 0x0021;
    private const int MaNoActivate = 3;
    private const uint MonitorDefaultToNearest = 2;
    private const uint SwpNoSize = 0x0001;
    private const uint SwpNoZOrder = 0x0004;
    private const uint SwpNoActivate = 0x0010;
    private const double GuidanceCursorGap = 44;

    private readonly IServiceProvider _serviceProvider;
    private readonly MainWindowViewModel _viewModel;
    private readonly ILogger<MainWindow> _logger;
    private readonly DispatcherTimer _placementSaveTimer;
    private readonly DispatcherTimer _guidanceFollowTimer;
    private GuidanceWindow? _guidanceWindow;
    private bool _isInitialized;
    private bool _isClosing;

    public MainWindow(
        MainWindowViewModel viewModel,
        IServiceProvider serviceProvider,
        ILogger<MainWindow> logger)
    {
        _viewModel = viewModel;
        _serviceProvider = serviceProvider;
        _logger = logger;
        DataContext = viewModel;
        InitializeComponent();

        _placementSaveTimer = new DispatcherTimer
        {
            Interval = TimeSpan.FromMilliseconds(500)
        };
        _placementSaveTimer.Tick += OnPlacementSaveTimerTick;

        _guidanceFollowTimer = new DispatcherTimer
        {
            Interval = TimeSpan.FromMilliseconds(50)
        };
        _guidanceFollowTimer.Tick += OnGuidanceFollowTimerTick;

        _viewModel.SettingsRequested += OnSettingsRequested;
        _viewModel.CloseRequested += OnCloseRequested;
        _viewModel.PropertyChanged += OnViewModelPropertyChanged;
        LocationChanged += OnLocationChanged;
    }

    private async void MainWindow_OnLoaded(object sender, RoutedEventArgs e)
    {
        try
        {
            await _viewModel.InitializeAsync();
            RestorePlacement();
            _isInitialized = true;
            Opacity = 1;
            ApplyAcrylicAppearance();
        }
        catch (Exception exception)
        {
            _viewModel.ReportStartupFailure(exception.Message);
            RestoreFallbackPlacement();
            _isInitialized = true;
            Opacity = 1;
            ApplyAcrylicAppearance();
        }
    }

    private void MainWindow_OnSourceInitialized(object? sender, EventArgs e)
    {
        var windowHandle = new WindowInteropHelper(this).Handle;
        var extendedStyle = GetWindowLongPtr(windowHandle, GwlExStyle).ToInt64();
        SetWindowLongPtr(
            windowHandle,
            GwlExStyle,
            new nint(extendedStyle | WsExToolWindow | WsExNoActivate));

        HwndSource.FromHwnd(windowHandle)?.AddHook(WindowMessageHook);
        ApplyAcrylicAppearance();
    }

    private void MainWindow_OnClosing(object? sender, CancelEventArgs e)
    {
        if (_isClosing)
        {
            return;
        }

        _isClosing = true;
        _placementSaveTimer.Stop();
        _guidanceFollowTimer.Stop();
        _viewModel.SettingsRequested -= OnSettingsRequested;
        _viewModel.CloseRequested -= OnCloseRequested;
        _viewModel.PropertyChanged -= OnViewModelPropertyChanged;
        LocationChanged -= OnLocationChanged;
        _guidanceWindow?.Close();

        if (_isInitialized)
        {
            _viewModel
                .SaveWindowPlacementAsync(Left, Top)
                .GetAwaiter()
                .GetResult();
        }
    }

    private void Orb_OnMouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (e.LeftButton == MouseButtonState.Pressed
            && !IsButtonSource(e.OriginalSource as DependencyObject))
        {
            DragMove();
        }
    }

    private void OnLocationChanged(object? sender, EventArgs e)
    {
        if (!_isInitialized || _isClosing)
        {
            return;
        }

        _placementSaveTimer.Stop();
        _placementSaveTimer.Start();
    }

    private void OnViewModelPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(MainWindowViewModel.OrbOpacityPercent))
        {
            ApplyAcrylicAppearance();
        }

        if (e.PropertyName == nameof(MainWindowViewModel.IsGuidanceVisible))
        {
            UpdateGuidanceWindowVisibility();
        }
    }

    private void ApplyAcrylicAppearance()
    {
        AcrylicWindowHelper.Apply(
            this,
            _viewModel.OrbOpacityPercent,
            AcrylicShape.Circle);
    }

    private static bool IsButtonSource(DependencyObject? source)
    {
        while (source is not null)
        {
            if (source is ButtonBase)
            {
                return true;
            }

            source = VisualTreeHelper.GetParent(source);
        }

        return false;
    }

    private void UpdateGuidanceWindowVisibility()
    {
        if (_viewModel.IsGuidanceVisible)
        {
            if (_guidanceWindow is not null)
            {
                return;
            }

            _guidanceWindow = _serviceProvider.GetRequiredService<GuidanceWindow>();
            _guidanceWindow.DataContext = _viewModel;
            _guidanceWindow.Closed += (_, _) =>
            {
                _guidanceWindow = null;
                _viewModel.IsGuidanceVisible = false;
            };
            _guidanceWindow.Show();
            PositionGuidanceWindowNearCursor();
            _guidanceFollowTimer.Start();
            return;
        }

        _guidanceFollowTimer.Stop();
        _guidanceWindow?.Close();
        _guidanceWindow = null;
    }

    private void OnGuidanceFollowTimerTick(object? sender, EventArgs e)
    {
        PositionGuidanceWindowNearCursor();
    }

    private void PositionGuidanceWindowNearCursor()
    {
        if (_guidanceWindow is null
            || !GetCursorPos(out var cursor)
            || !TryGetMonitorWorkArea(cursor, out var workArea, out var scaleX, out var scaleY))
        {
            return;
        }

        var windowHandle = new WindowInteropHelper(_guidanceWindow).Handle;
        if (windowHandle == nint.Zero)
        {
            return;
        }

        var width = (int)Math.Round(_guidanceWindow.ActualWidth * scaleX);
        var height = (int)Math.Round(_guidanceWindow.ActualHeight * scaleY);
        var gap = (int)Math.Round(GuidanceCursorGap * scaleX);

        var x = cursor.X + gap;
        if (x + width > workArea.Right)
        {
            x = cursor.X - width - gap;
        }

        var y = cursor.Y - height / 2;
        x = ClampToRange(x, workArea.Left, workArea.Right - width);
        y = ClampToRange(y, workArea.Top, workArea.Bottom - height);

        SetWindowPos(
            windowHandle,
            nint.Zero,
            x,
            y,
            0,
            0,
            SwpNoSize | SwpNoZOrder | SwpNoActivate);
    }

    private async void OnPlacementSaveTimerTick(object? sender, EventArgs e)
    {
        _placementSaveTimer.Stop();
        await _viewModel.SaveWindowPlacementAsync(Left, Top);
    }

    private void OnSettingsRequested(object? sender, EventArgs e)
    {
        try
        {
            var settingsWindow = _serviceProvider.GetRequiredService<SettingsWindow>();
            settingsWindow.Topmost = true;
            settingsWindow.ShowDialog();
        }
        catch (Exception exception)
        {
            _logger.LogError(exception, "Unable to open the settings window.");
            MessageBox.Show(
                $"设置窗口无法打开。\n\n{exception.Message}",
                "JT Copilot",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
        }
    }

    private void OnCloseRequested(object? sender, EventArgs e)
    {
        Close();
    }

    private void RestorePlacement()
    {
        var settings = _viewModel.Settings;
        if (WindowPlacement.TryCreate(settings.WindowLeft, settings.WindowTop, out var placement)
            && IsPlacementVisible(placement))
        {
            Left = placement.Left;
            Top = placement.Top;
            return;
        }

        RestoreFallbackPlacement();
    }

    private void RestoreFallbackPlacement()
    {
        var workArea = SystemParameters.WorkArea;
        Left = workArea.Right - Width - 24;
        Top = workArea.Bottom - Height - 24;
    }

    private bool IsPlacementVisible(WindowPlacement placement)
    {
        var right = placement.Left + Width;
        var bottom = placement.Top + Height;
        return placement.Left < SystemParameters.VirtualScreenLeft + SystemParameters.VirtualScreenWidth
            && right > SystemParameters.VirtualScreenLeft
            && placement.Top < SystemParameters.VirtualScreenTop + SystemParameters.VirtualScreenHeight
            && bottom > SystemParameters.VirtualScreenTop;
    }

    private nint WindowMessageHook(nint hwnd, int message, nint wParam, nint lParam, ref bool handled)
    {
        if (message == WmMouseActivate)
        {
            handled = true;
            return MaNoActivate;
        }

        return nint.Zero;
    }

    private static bool TryGetMonitorWorkArea(
        NativePoint point,
        out NativeRect workArea,
        out double scaleX,
        out double scaleY)
    {
        workArea = default;
        scaleX = 1;
        scaleY = 1;

        var monitor = MonitorFromPoint(point, MonitorDefaultToNearest);
        if (monitor == nint.Zero)
        {
            return false;
        }

        var monitorInfo = new MonitorInfo
        {
            Size = Marshal.SizeOf<MonitorInfo>()
        };
        if (!GetMonitorInfo(monitor, ref monitorInfo))
        {
            return false;
        }

        workArea = monitorInfo.WorkArea;
        if (GetDpiForMonitor(monitor, 0, out var dpiX, out var dpiY) == 0)
        {
            scaleX = dpiX / 96d;
            scaleY = dpiY / 96d;
        }

        return true;
    }

    private static int ClampToRange(int value, int minimum, int maximum)
    {
        return maximum < minimum
            ? minimum
            : Math.Clamp(value, minimum, maximum);
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NativePoint
    {
        public int X;
        public int Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeRect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MonitorInfo
    {
        public int Size;
        public NativeRect Monitor;
        public NativeRect WorkArea;
        public uint Flags;
    }

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetCursorPos(out NativePoint point);

    [DllImport("user32.dll")]
    private static extern nint MonitorFromPoint(NativePoint point, uint flags);

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetMonitorInfo(nint monitor, ref MonitorInfo monitorInfo);

    [DllImport("shcore.dll")]
    private static extern int GetDpiForMonitor(
        nint monitor,
        int dpiType,
        out uint dpiX,
        out uint dpiY);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetWindowPos(
        nint windowHandle,
        nint insertAfter,
        int x,
        int y,
        int width,
        int height,
        uint flags);

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW", SetLastError = true)]
    private static extern nint GetWindowLongPtr(nint windowHandle, int index);

    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW", SetLastError = true)]
    private static extern nint SetWindowLongPtr(nint windowHandle, int index, nint newValue);
}
