import AppKit
import Foundation
import SwiftUI
import JTCopilotCore

struct SettingsView: View {
    @ObservedObject var model: AppModel
    var onClose: () -> Void

    @State private var window: NSWindow?
    @State private var dragStart: NSPoint?

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SectionLabel(text: "麦克风")
                    microphoneMenu
                        .padding(.top, 8)

                    sectionGap

                    SectionLabel(text: "系统权限")
                    VStack(spacing: 9) {
                        permissionRow(
                            title: "麦克风",
                            status: model.microphoneStatus,
                            actionTitle: model.microphoneStatus == "已授权" ? "打开设置" : "授权"
                        ) {
                            if model.microphoneStatus == "已授权" {
                                Permissions.openMicrophoneSettings()
                            } else {
                                model.requestMicrophoneAccess()
                            }
                        }

                        permissionRow(
                            title: "语音识别",
                            status: model.speechStatus,
                            actionTitle: model.speechStatus == "已授权" ? "打开设置" : "授权"
                        ) {
                            if model.speechStatus == "已授权" {
                                Permissions.openSpeechSettings()
                            } else {
                                model.requestSpeechAccess()
                            }
                        }

                        permissionRow(
                            title: "辅助功能",
                            status: model.accessibilityStatus,
                            actionTitle: model.accessibilityStatus == "已授权" ? "打开设置" : "授权"
                        ) {
                            if model.accessibilityStatus == "已授权" {
                                Permissions.openAccessibilitySettings()
                            } else {
                                model.requestAccessibilityAccess()
                            }
                        }
                    }
                    .padding(.top, 10)

                    Text("辅助功能用于全局快捷键和向其他应用写入文字；授权后如仍无法使用，请重启应用。")
                        .font(.system(size: 11))
                        .lineSpacing(3)
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.top, 8)
                        .fixedSize(horizontal: false, vertical: true)

                    sectionGap

                    SectionLabel(text: "全局快捷键")
                    hotkeyRow
                        .padding(.top, 8)
                    if !model.hotkeyError.isEmpty {
                        Text(model.hotkeyError)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.danger)
                            .padding(.top, 6)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("同时按下组合键，例如 ⌃⇧J T。录制时按 Esc 取消。")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.top, 6)

                    sectionGap

                    SectionLabel(text: "业务术语纠正")
                    TextEditor(text: $model.customVocabulary)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textPrimary)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(height: 110)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Theme.panelRaised)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Theme.border, lineWidth: 1)
                        )
                        .padding(.top, 8)
                    Text("每行格式：标准词=误识别1,误识别2")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.top, 6)

                    sectionGap

                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("窗口置顶")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text("保持悬浮球位于其他窗口上方")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        Toggle("", isOn: $model.isTopmost)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }

                    sectionGap

                    opacityRow(
                        title: "悬浮球透明度",
                        value: $model.orbOpacityPercent,
                        range: 35...100
                    )

                    opacityRow(
                        title: "引导面板透明度",
                        value: $model.guidanceOpacityPercent,
                        range: 40...100
                    )

                    sectionGap

                    SectionLabel(text: "录音文件")
                    HStack(spacing: 8) {
                        Text(model.recordingsDirectoryPath)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .padding(.horizontal, 10)
                            .frame(height: 36)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Theme.panelRaised)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(Theme.border, lineWidth: 1)
                            )

                        Button("打开") {
                            model.openRecordingsFolder()
                        }
                        .buttonStyle(CommandButtonStyle())
                        .frame(width: 60)
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal, 18)
                .padding(.top, 4)
                .padding(.bottom, 18)
            }

            footer
        }
        .frame(width: 440, height: 620)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("设置")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("JT Copilot · macOS")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
            }

            Spacer()

            CloseIconButton(action: onClose)
        }
        .padding(.leading, 18)
        .padding(.trailing, 10)
        .padding(.top, 8)
        .frame(height: 58)
        .background(WindowReader { window = $0 })
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    guard let window else { return }
                    if dragStart == nil {
                        dragStart = window.frame.origin
                    }
                    guard let dragStart else { return }
                    window.setFrameOrigin(
                        NSPoint(
                            x: dragStart.x + value.translation.width,
                            y: dragStart.y - value.translation.height
                        )
                    )
                }
                .onEnded { _ in
                    dragStart = nil
                }
        )
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("关闭", action: onClose)
                .buttonStyle(CommandButtonStyle())
                .frame(width: 88)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
        .frame(height: 58)
    }

    private var microphoneMenu: some View {
        Menu {
            ForEach(model.audioDevices) { device in
                Button(device.displayName) {
                    model.selectedMicrophone = device
                }
            }
        } label: {
            HStack {
                Text(model.selectedMicrophone?.displayName ?? "默认麦克风")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Theme.panelRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }

    private var hotkeyRow: some View {
        HStack(spacing: 8) {
            Text(model.hotkeyText)
                .font(.system(size: 12))
                .foregroundStyle(model.isCapturingHotkey ? Theme.accent : Theme.textPrimary)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(height: 36)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Theme.panelRaised)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(
                            model.isCapturingHotkey ? Theme.accent : Theme.border,
                            lineWidth: model.isCapturingHotkey ? 1.5 : 1
                        )
                )

            Button("修改") {
                model.beginHotkeyCapture()
            }
            .buttonStyle(CommandButtonStyle())
            .frame(width: 58)

            Button("默认") {
                model.restoreDefaultHotkey()
            }
            .buttonStyle(CommandButtonStyle())
            .frame(width: 58)
        }
    }

    private func permissionRow(
        title: String,
        status: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(status)
                .font(.system(size: 11))
                .foregroundStyle(status == "已授权" ? Theme.accent : Theme.warning)
            Button(actionTitle, action: action)
                .font(.system(size: 11))
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                .frame(width: 62, alignment: .trailing)
        }
    }

    private func opacityRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionLabel(text: title)
                Spacer()
                Text(String(format: "%.0f%%", value.wrappedValue))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
            }
            Slider(value: value, in: range, step: 5)
                .tint(Theme.accent)
        }
        .padding(.bottom, 14)
    }

    private var sectionGap: some View {
        DividerLine()
            .padding(.top, 18)
            .padding(.bottom, 16)
    }
}
