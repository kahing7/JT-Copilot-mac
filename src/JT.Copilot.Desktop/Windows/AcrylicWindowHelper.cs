using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;

namespace JT.Copilot.Desktop.Windows;

internal enum AcrylicShape
{
    Circle,
    RoundedRectangle
}

internal static class AcrylicWindowHelper
{
    private const int WindowCompositionAttributeAccentPolicy = 19;
    private const int AccentEnableAcrylicBlurBehind = 4;
    private const byte TintRed = 0x13;
    private const byte TintGreen = 0x1C;
    private const byte TintBlue = 0x25;

    public static bool Apply(
        Window window,
        double opacityPercent,
        AcrylicShape shape)
    {
        var windowHandle = new WindowInteropHelper(window).Handle;
        if (windowHandle == nint.Zero)
        {
            return false;
        }

        var alpha = (byte)Math.Clamp(opacityPercent / 100d * 220d, 0, 220);
        var gradientColor = (uint)(alpha << 24 | TintBlue << 16 | TintGreen << 8 | TintRed);
        var policy = new AccentPolicy
        {
            AccentState = AccentEnableAcrylicBlurBehind,
            AccentFlags = 2,
            GradientColor = gradientColor
        };

        var policySize = Marshal.SizeOf<AccentPolicy>();
        var policyPointer = Marshal.AllocHGlobal(policySize);
        try
        {
            Marshal.StructureToPtr(policy, policyPointer, fDeleteOld: false);
            var data = new WindowCompositionAttributeData
            {
                Attribute = WindowCompositionAttributeAccentPolicy,
                Data = policyPointer,
                SizeOfData = policySize
            };

            var compositionApplied = SetWindowCompositionAttribute(windowHandle, ref data);
            ApplyWindowRegion(window, windowHandle, shape);
            return compositionApplied;
        }
        finally
        {
            Marshal.FreeHGlobal(policyPointer);
        }
    }

    private static void ApplyWindowRegion(
        Window window,
        nint windowHandle,
        AcrylicShape shape)
    {
        var dpi = GetDpiForWindow(windowHandle);
        var scale = dpi <= 0 ? 1d : dpi / 96d;
        var width = Math.Max(1, (int)Math.Round(window.Width * scale));
        var height = Math.Max(1, (int)Math.Round(window.Height * scale));

        var radius = shape == AcrylicShape.Circle
            ? Math.Max(width, height)
            : (int)Math.Round(18 * scale);
        var region = CreateRoundRectRgn(0, 0, width + 1, height + 1, radius, radius);
        if (region != nint.Zero)
        {
            SetWindowRgn(windowHandle, region, redraw: true);
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct AccentPolicy
    {
        public int AccentState;
        public int AccentFlags;
        public uint GradientColor;
        public int AnimationId;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct WindowCompositionAttributeData
    {
        public int Attribute;
        public nint Data;
        public int SizeOfData;
    }

    [DllImport("user32.dll")]
    private static extern bool SetWindowCompositionAttribute(
        nint windowHandle,
        ref WindowCompositionAttributeData data);

    [DllImport("user32.dll")]
    private static extern uint GetDpiForWindow(nint windowHandle);

    [DllImport("gdi32.dll")]
    private static extern nint CreateRoundRectRgn(
        int left,
        int top,
        int right,
        int bottom,
        int widthEllipse,
        int heightEllipse);

    [DllImport("user32.dll")]
    private static extern int SetWindowRgn(
        nint windowHandle,
        nint region,
        bool redraw);
}
