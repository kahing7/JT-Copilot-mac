using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using JT.Copilot.Desktop.ViewModels;

namespace JT.Copilot.Desktop.Windows;

public partial class GuidanceWindow : Window
{
    private MainWindowViewModel? _viewModel;

    public GuidanceWindow()
    {
        InitializeComponent();
    }

    private void GuidanceWindow_OnSourceInitialized(object? sender, EventArgs e)
    {
        var windowHandle = new WindowInteropHelper(this).Handle;
        var extendedStyle = GetWindowLongPtr(windowHandle, -20).ToInt64();
        SetWindowLongPtr(windowHandle, -20, new nint(extendedStyle | 0x08000000));
        ApplyAcrylicAppearance();
    }

    private void GuidanceWindow_OnDataContextChanged(
        object sender,
        DependencyPropertyChangedEventArgs e)
    {
        if (_viewModel is not null)
        {
            _viewModel.PropertyChanged -= OnViewModelPropertyChanged;
        }

        _viewModel = e.NewValue as MainWindowViewModel;
        if (_viewModel is not null)
        {
            _viewModel.PropertyChanged += OnViewModelPropertyChanged;
        }

        ApplyAcrylicAppearance();
    }

    private void GuidanceWindow_OnClosed(object? sender, EventArgs e)
    {
        if (_viewModel is not null)
        {
            _viewModel.PropertyChanged -= OnViewModelPropertyChanged;
            _viewModel = null;
        }
    }

    private void CloseButton_OnClick(object sender, RoutedEventArgs e)
    {
        Close();
    }

    private void OnViewModelPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(MainWindowViewModel.GuidanceOpacityPercent))
        {
            ApplyAcrylicAppearance();
        }
    }

    private void ApplyAcrylicAppearance()
    {
        if (_viewModel is null)
        {
            return;
        }

        AcrylicWindowHelper.Apply(
            this,
            _viewModel.GuidanceOpacityPercent,
            AcrylicShape.RoundedRectangle);
    }

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW", SetLastError = true)]
    private static extern nint GetWindowLongPtr(nint windowHandle, int index);

    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW", SetLastError = true)]
    private static extern nint SetWindowLongPtr(nint windowHandle, int index, nint newValue);
}
