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

    private readonly IServiceProvider _serviceProvider;
    private readonly MainWindowViewModel _viewModel;
    private readonly ILogger<MainWindow> _logger;
    private readonly DispatcherTimer _placementSaveTimer;
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
            PositionGuidanceWindow();
            return;
        }

        _guidanceWindow?.Close();
        _guidanceWindow = null;
    }

    private void PositionGuidanceWindow()
    {
        if (_guidanceWindow is null)
        {
            return;
        }

        var right = Left + Width + 12;
        if (right + _guidanceWindow.Width <= SystemParameters.VirtualScreenLeft + SystemParameters.VirtualScreenWidth)
        {
            _guidanceWindow.Left = right;
        }
        else
        {
            _guidanceWindow.Left = Math.Max(
                SystemParameters.VirtualScreenLeft,
                Left - _guidanceWindow.Width - 12);
        }

        _guidanceWindow.Top = Math.Max(
            SystemParameters.VirtualScreenTop,
            Math.Min(
                Top,
                SystemParameters.VirtualScreenTop
                + SystemParameters.VirtualScreenHeight
                - _guidanceWindow.Height));
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

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW", SetLastError = true)]
    private static extern nint GetWindowLongPtr(nint windowHandle, int index);

    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW", SetLastError = true)]
    private static extern nint SetWindowLongPtr(nint windowHandle, int index, nint newValue);
}
