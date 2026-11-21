import AppKit
import SwiftUI
import JTCopilotCore

struct GuidanceView: View {
    @ObservedObject var model: AppModel
    @State private var directionsExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            header

            Rectangle()
                .fill(Theme.border.opacity(0.65))
                .frame(height: 1)

            HStack(alignment: .top, spacing: 14) {
                guidanceColumn
                    .frame(width: 260)

                verticalDivider

                frameworkColumn
                    .frame(width: 190)

                verticalDivider

                resultColumn
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 14)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(width: 820, height: 380)
        .background(
            FrostedBackground(
                cornerRadius: 18,
                tint: Theme.panel.opacity(0.45 * model.guidanceOpacityScale),
                material: .underWindowBackground,
                blurOpacity: 0.2
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        ZStack {
            WindowDragArea(clampsToVisibleFrame: true)

            HStack(spacing: 9) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 2) {
                    Text("表达引导")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(model.sessionStatus.isEmpty ? "等待开始" : model.sessionStatus)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                .allowsHitTesting(false)

                Spacer()

                CloseIconButton {
                    model.dismissGuidance()
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 10)
            .padding(.top, 7)
        }
        .frame(height: 56)
    }

    private var guidanceColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            nextSentenceCard

            ScrollView {
                directionsDisclosure
                    .padding(.trailing, 4)
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private var frameworkColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel(text: "文档模板")
                templatePicker

                HStack(spacing: 0) {
                    Text("当前识别：")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                    Text(model.detectedTemplateLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.accent)
                }
                .padding(.top, 7)

                DividerLine()
                    .padding(.vertical, 14)

                Text("当前框架")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                frameworkList
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollIndicators(.hidden)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var resultColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: "实时转录")

            liveTranscriptPanel
                .padding(.top, 8)

            DividerLine()
                .padding(.vertical, 12)

            HStack(alignment: .center, spacing: 8) {
                SectionLabel(text: model.replacementMessage.isEmpty ? "优化结果" : model.replacementMessage)
                Spacer()
                Button("复制结果") {
                    model.copyOptimizedText()
                }
                .buttonStyle(CommandButtonStyle())
                .disabled(model.optimizedTranscript.isEmpty && model.liveTranscript.isEmpty)
            }

            ScrollView {
                Text(model.optimizedTranscript.isEmpty
                     ? "会话结束后，智谱会在这里给出优化后的全文。"
                     : model.optimizedTranscript)
                    .font(.system(size: 12))
                    .lineSpacing(5)
                    .foregroundStyle(model.optimizedTranscript.isEmpty ? Theme.textTertiary : Theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .textSelection(.enabled)
                    .padding(.top, 8)
                    .padding(.trailing, 4)
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private var liveTranscriptPanel: some View {
        Text(model.liveTranscript.isEmpty ? "开始口述后，识别文字会显示在这里。" : model.liveTranscript)
            .font(.system(size: 13))
            .lineSpacing(4)
            .foregroundStyle(model.liveTranscript.isEmpty ? Theme.textTertiary : Theme.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 62, maxHeight: 62, alignment: .topLeading)
            .lineLimit(4)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Theme.panelRaised.opacity(0.88))
            )
    }

    private var verticalDivider: some View {
        Rectangle()
            .fill(Theme.border.opacity(0.65))
            .frame(width: 1)
            .frame(maxHeight: .infinity)
    }

    private var templatePicker: some View {
        Menu {
            ForEach(model.documentTemplateOptions) { option in
                Button(option.displayName) {
                    model.selectedDocumentTemplate = option
                }
            }
        } label: {
            HStack {
                Text(model.selectedDocumentTemplate?.displayName ?? "自动识别")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
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
        .padding(.top, 8)
    }

    private var frameworkList: some View {
        VStack(alignment: .leading, spacing: 7) {
            if model.frameworkItems.isEmpty {
                Text("开始口述后自动生成结构框架。")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
            } else {
                ForEach(model.frameworkItems.indices, id: \.self) { index in
                    HStack(alignment: .top, spacing: 7) {
                        Circle()
                            .fill(Theme.accent)
                            .frame(width: 4, height: 4)
                            .padding(.top, 7)
                        Text(model.frameworkItems[index])
                            .font(.system(size: 12))
                            .lineSpacing(3)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var nextSentenceCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("下一句")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.accent)
            Text(model.nextSentence.isEmpty ? "等待引导" : model.nextSentence)
                .font(.system(size: 13, weight: .semibold))
                .lineSpacing(4)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Theme.panelRaised.opacity(0.9))
        )
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Theme.accentStrong)
                .frame(width: 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    private var directionsDisclosure: some View {
        DisclosureGroup(isExpanded: $directionsExpanded) {
            VStack(alignment: .leading, spacing: 0) {
                directionList

                if !model.missingPointItems.isEmpty {
                    Text("可能遗漏")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.warning)
                        .padding(.top, 14)
                    missingList
                        .padding(.top, 8)
                }
            }
            .padding(.top, 8)
        } label: {
            HStack(spacing: 8) {
                Text("可展开方向")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                Text("\(model.directionItems.count) 条")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .tint(Theme.textSecondary)
    }

    private var directionList: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.directionItems.isEmpty {
                Text("识别到内容后会给出可展开的写作方向。")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
            } else {
                ForEach(model.directionItems.indices, id: \.self) { index in
                    Text(model.directionItems[index])
                        .font(.system(size: 12))
                        .lineSpacing(3)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var missingList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(model.missingPointItems.indices, id: \.self) { index in
                Text(model.missingPointItems[index])
                    .font(.system(size: 12))
                    .lineSpacing(3)
                    .foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
