import SwiftUI

enum GlassIconTint {
    static let blue = Color(hex: 0x0A84FF)
    static let green = Color(hex: 0x30D158)
    static let gray = Color(hex: 0x8E8E93)
    static let orange = Color(hex: 0xFF9F0A)
}

struct IconChip: View {
    let systemName: String
    let tint: Color
    var size: CGFloat = GlassMetrics.iconSize

    var body: some View {
        Circle()
            .fill(tint)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: systemName)
                    .font(.system(size: size * 0.44, weight: .semibold))
                    .foregroundStyle(Color.white)
            }
            .accessibilityHidden(true)
    }
}
