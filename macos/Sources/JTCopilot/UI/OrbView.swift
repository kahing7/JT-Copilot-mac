import AppKit
import SwiftUI

struct OrbView: View {
    @ObservedObject var model: AppModel
    @State private var isHovering = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.panel.opacity(isHovering ? 0.94 : 0.9))

            if model.isRecording {
                Circle()
                    .fill(Theme.danger.opacity(0.1))
                    .frame(width: 58, height: 58)
            }

            Group {
                if model.isRecording {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Theme.textPrimary)
                        .frame(width: 10, height: 10)
                } else {
                    Image(systemName: "mic")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
            .frame(width: 48, height: 48)
            .help(model.microphoneActionLabel)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(model.microphoneActionLabel)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                model.toggleRecording()
            }
            .allowsHitTesting(false)

            statusDot
                .offset(x: 22, y: -22)
        }
        .frame(width: 64, height: 64)
        .opacity(model.orbOpacityScale)
        .contentShape(Circle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.16)) {
                isHovering = hovering
            }
        }
        .contextMenu {
            Button("设置") {
                model.openSettings()
            }

            Button(model.isGuidanceVisible ? "隐藏引导面板" : "显示引导面板") {
                model.toggleGuidance()
            }

            Button(model.isTopmost ? "取消窗口置顶" : "窗口置顶") {
                model.toggleTopmost()
            }

            Divider()

            Button("退出") {
                model.exitApp()
            }
        }
        .padding(4)
        .frame(width: 72, height: 72)
        .overlay {
            WindowDragArea(onClick: model.toggleRecording)
                .clipShape(Circle())
        }
    }

    private var statusDot: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 7, height: 7)
            .overlay(
                Circle().strokeBorder(Theme.panel.opacity(0.9), lineWidth: 1)
            )
    }

    private var dotColor: Color {
        if model.isRecording {
            return Theme.danger
        }
        if model.hasError {
            return Theme.warning
        }
        return Theme.textSecondary.opacity(0.6)
    }
}
