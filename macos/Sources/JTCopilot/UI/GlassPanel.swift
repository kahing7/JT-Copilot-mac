import AppKit
import SwiftUI

enum GlassMetrics {
    static let panelWidth: CGFloat = 820
    static let panelHeight: CGFloat = 260
    static let panelRadius: CGFloat = 26
    static let panelPadding: CGFloat = 12
    static let moduleRadius: CGFloat = 14
    static let moduleGap: CGFloat = 8
    static let modulePadding: CGFloat = 12
    static let iconSize: CGFloat = 24
    static let iconTextSpacing: CGFloat = 10
    static let sliderModuleHeight: CGFloat = 80
}

struct GlassTokens {
    let isDark: Bool
    let reduceTransparency: Bool

    let glassTint: Color
    let panelSolid: Color
    let moduleTint: Color
    let moduleSolid: Color
    let glassBorder: Color
    let glassHighlight: Color
    let glassLowlight: Color
    let moduleBorder: Color
    let moduleHighlight: Color
    let sliderTrack: Color

    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color

    init(
        colorScheme: ColorScheme,
        reduceTransparency: Bool,
        opacityScale: Double
    ) {
        let scale = min(max(opacityScale, 0), 1)
        let dark = colorScheme == .dark
        self.isDark = dark
        self.reduceTransparency = reduceTransparency

        if dark {
            glassTint = Color(hex: 0x26262A, alpha: 0.56 + 0.10 * scale)
            panelSolid = Color(hex: 0x1C1C1E)
            moduleTint = Color.white.opacity(0.064 + 0.016 * scale)
            moduleSolid = Color(hex: 0x2C2C2E)
            glassBorder = Color.white.opacity(0.28)
            glassHighlight = Color.white.opacity(0.18)
            glassLowlight = Color.black.opacity(0.12)
            moduleBorder = Color.white.opacity(0.22)
            moduleHighlight = Color.white.opacity(0.30)
            sliderTrack = Color.white.opacity(0.14)
            textPrimary = Color.white.opacity(0.96)
            textSecondary = Color.white.opacity(0.78)
            textTertiary = Color.white.opacity(0.66)
        } else {
            glassTint = Color.white.opacity(0.58 + 0.14 * scale)
            panelSolid = Color(hex: 0xF2F2F7)
            moduleTint = Color.white.opacity(0.30 + 0.02 * scale)
            moduleSolid = Color.white
            glassBorder = Color.white.opacity(0.44)
            glassHighlight = Color.white.opacity(0.55)
            glassLowlight = Color.black.opacity(0.08)
            moduleBorder = Color.white.opacity(0.52)
            moduleHighlight = Color.white.opacity(0.62)
            sliderTrack = Color.black.opacity(0.10)
            textPrimary = Color.black.opacity(0.88)
            textSecondary = Color.black.opacity(0.68)
            textTertiary = Color.black.opacity(0.56)
        }
    }
}

struct GlassTokensKey: EnvironmentKey {
    static let defaultValue = GlassTokens(
        colorScheme: .dark,
        reduceTransparency: false,
        opacityScale: 1
    )
}

extension EnvironmentValues {
    var glassTokens: GlassTokens {
        get { self[GlassTokensKey.self] }
        set { self[GlassTokensKey.self] = newValue }
    }
}

struct GlassPanel<Content: View>: View {
    var reduceTransparency: Bool
    var opacityScale: Double
    var isPresented: Bool
    var colorSchemeOverride: ColorScheme?
    @ViewBuilder var content: Content

    @Environment(\.colorScheme) private var environmentColorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    init(
        reduceTransparency: Bool,
        opacityScale: Double = 1,
        isPresented: Bool = true,
        colorScheme: ColorScheme? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.reduceTransparency = reduceTransparency
        self.opacityScale = opacityScale
        self.isPresented = isPresented
        self.colorSchemeOverride = colorScheme
        self.content = content()
    }

    private var resolvedColorScheme: ColorScheme {
        colorSchemeOverride ?? environmentColorScheme
    }

    private var tokens: GlassTokens {
        GlassTokens(
            colorScheme: resolvedColorScheme,
            reduceTransparency: reduceTransparency,
            opacityScale: opacityScale
        )
    }

    var body: some View {
        let palette = tokens
        let shape = RoundedRectangle(cornerRadius: GlassMetrics.panelRadius, style: .continuous)

        ZStack {
            if reduceTransparency {
                shape.fill(palette.panelSolid)
            } else {
                GlassBackdropView(isDark: palette.isDark)
                shape.fill(palette.glassTint)
                GlassNoiseLayer()
                    .opacity(0.045)
                    .blendMode(.overlay)
            }

            content
                .padding(GlassMetrics.panelPadding)
        }
        .clipShape(shape)
        .overlay {
            ZStack {
                shape.strokeBorder(palette.glassBorder, lineWidth: 1)
                shape
                    .inset(by: 0.5)
                    .strokeBorder(palette.glassLowlight, lineWidth: 0.5)
                shape.strokeBorder(
                    LinearGradient(
                        colors: [palette.glassHighlight, .clear],
                        startPoint: .top,
                        endPoint: .center
                    ),
                    lineWidth: 1
                )
            }
        }
        .shadow(
            color: .black.opacity(reduceTransparency ? 0.08 : 0.10),
            radius: 1,
            x: 0,
            y: 1
        )
        .shadow(
            color: .black.opacity(reduceTransparency ? 0.12 : 0.18),
            radius: reduceTransparency ? 10 : 16,
            x: 0,
            y: reduceTransparency ? 8 : 12
        )
        .shadow(
            color: .black.opacity(reduceTransparency ? 0 : 0.12),
            radius: reduceTransparency ? 0 : 32,
            x: 0,
            y: reduceTransparency ? 0 : 32
        )
        .environment(\.glassTokens, palette)
        .scaleEffect(isVisible ? 1 : 0.96)
        .opacity(isVisible ? 1 : 0)
        .animation(
            reduceMotion ? nil : .timingCurve(0.32, 0.72, 0, 1, duration: 0.22),
            value: isVisible
        )
        .onAppear {
            isVisible = isPresented
        }
        .onChange(of: isPresented) { _, presented in
            if reduceMotion {
                isVisible = presented
            } else if presented {
                isVisible = false
                DispatchQueue.main.async {
                    isVisible = true
                }
            } else {
                isVisible = false
            }
        }
    }
}

private struct GlassBackdropView: NSViewRepresentable {
    var isDark: Bool

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.material = .popover
        view.state = .active
        view.isEmphasized = true
        view.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = .popover
        nsView.state = .active
        nsView.isEmphasized = true
        nsView.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
    }
}

private struct GlassNoiseLayer: View {
    var body: some View {
        Image(nsImage: GlassNoiseTexture.image)
            .resizable(resizingMode: .tile)
            .interpolation(.none)
            .allowsHitTesting(false)
    }
}

private enum GlassNoiseTexture {
    static let image: NSImage = {
        let pixelSize = 128
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(pixelSize)" height="\(pixelSize)">
          <filter id="noise" x="0" y="0" width="100%" height="100%">
            <feTurbulence type="fractalNoise" baseFrequency="0.82" numOctaves="4" stitchTiles="stitch"/>
            <feColorMatrix type="saturate" values="0"/>
          </filter>
          <rect width="100%" height="100%" filter="url(#noise)"/>
        </svg>
        """

        guard
            let data = svg.data(using: .utf8),
            let image = NSImage(data: data)
        else {
            return NSImage(size: NSSize(width: pixelSize, height: pixelSize))
        }
        return image
    }()
}
