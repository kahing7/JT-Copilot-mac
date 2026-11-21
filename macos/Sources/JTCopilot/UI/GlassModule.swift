import SwiftUI

struct GlassModule<Content: View>: View {
    @Environment(\.glassTokens) private var tokens
    @State private var isHovering = false
    @ViewBuilder var content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(
            cornerRadius: GlassMetrics.moduleRadius,
            style: .continuous
        )

        content
            .padding(GlassMetrics.modulePadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(shape.fill(tokens.moduleTint))
            .overlay {
                ZStack {
                    shape.strokeBorder(tokens.moduleBorder, lineWidth: 0.5)
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [tokens.moduleHighlight, .clear],
                            startPoint: .top,
                            endPoint: .center
                        ),
                        lineWidth: 0.75
                    )
                }
            }
            .brightness(isHovering ? 0.04 : 0)
            .animation(.easeOut(duration: 0.16), value: isHovering)
            .onHover { isHovering = $0 }
    }
}
