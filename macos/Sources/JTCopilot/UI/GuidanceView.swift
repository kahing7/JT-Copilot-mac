import AppKit
import SwiftUI
import JTCopilotCore

struct GuidanceView: View {
    @ObservedObject var model: AppModel
    var reduceTransparency: Bool? = nil

    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @State private var directionsExpanded = false

    private var shouldReduceTransparency: Bool {
        reduceTransparency ?? systemReduceTransparency
    }

    private var tokens: GlassTokens {
        GlassTokens(
            colorScheme: .dark,
            reduceTransparency: shouldReduceTransparency,
            opacityScale: model.guidanceOpacityScale
        )
    }

    var body: some View {
        GlassPanel(
            reduceTransparency: shouldReduceTransparency,
            opacityScale: model.guidanceOpacityScale,
            isPresented: model.isGuidanceVisible,
            colorScheme: .dark
        ) {
            VStack(spacing: GlassMetrics.moduleGap) {
                header

                HStack(spacing: GlassMetrics.moduleGap) {
                    guidanceColumn
                        .frame(width: 260)

                    frameworkColumn
                        .frame(width: 230)

                    resultColumn
                        .frame(maxWidth: .infinity)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(width: GlassMetrics.panelWidth, height: GlassMetrics.panelHeight)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: GlassMetrics.iconTextSpacing) {
                IconChip(systemName: "waveform", tint: GlassIconTint.blue)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text("表达引导")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(tokens.textPrimary)

                        if model.isProcessing {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(GlassIconTint.blue)
                        }
                    }

                    Text(statusText)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(statusColor)
                        .lineLimit(1)
                }

                Spacer()
                Color.clear.frame(width: 34)
            }
            .padding(.leading, 4)
            .allowsHitTesting(false)

            WindowDragArea(usesNativeWindowDrag: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            CloseIconButton(helpText: model.isRecording ? "结束引导并优化全文" : "关闭") {
                model.endGuidanceSession()
            }
            .padding(.trailing, 2)
        }
        .frame(height: 32)
    }

    private var guidanceColumn: some View {
        VStack(spacing: GlassMetrics.moduleGap) {
            GlassModule {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: GlassMetrics.iconTextSpacing) {
                        IconChip(systemName: "sparkles", tint: GlassIconTint.blue)
                        Text("下一句")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(tokens.textPrimary)

                        Spacer()

                        if !guidanceHistory.isEmpty {
                            Text("\(guidanceHistory.count) 条历史")
                                .font(.system(size: 10.5, weight: .regular))
                                .foregroundStyle(tokens.textTertiary)
                        }
                    }

                    guidanceHistoryScroll
                }
            }
            .frame(height: 108)

            GlassModule {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: GlassMetrics.iconTextSpacing) {
                        IconChip(systemName: "circle.lefthalf.filled", tint: GlassIconTint.orange)
                        Text("面板浓度")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(tokens.textPrimary)
                        Spacer()
                        Text("\(Int(model.guidanceOpacityPercent.rounded()))%")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(tokens.textSecondary)
                    }

                    SliderBar(
                        value: $model.guidanceOpacityPercent,
                        tint: GlassIconTint.orange,
                        accessibilityLabel: "引导面板浓度"
                    )
                }
            }
            .frame(height: GlassMetrics.sliderModuleHeight)
        }
    }

    private var guidanceHistoryScroll: some View {
        let history = guidanceHistory
        let current = model.nextSentence.trimmingCharacters(in: .whitespacesAndNewlines)

        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 7) {
                    if history.isEmpty && current.isEmpty {
                        Text("等待引导")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(tokens.textTertiary)
                            .id("guidance-empty")
                    }

                    ForEach(Array(history.enumerated()), id: \.offset) { index, sentence in
                        HStack(alignment: .top, spacing: 7) {
                            Circle()
                                .fill(tokens.textTertiary)
                                .frame(width: 4, height: 4)
                                .padding(.top, 6)

                            Text(sentence)
                                .font(.system(size: 11, weight: .regular))
                                .lineSpacing(2)
                                .foregroundStyle(tokens.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .id("guidance-history-\(index)")
                    }

                    if !current.isEmpty {
                        HStack(alignment: .top, spacing: 7) {
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(GlassIconTint.blue)
                                .frame(width: 3)

                            Text(current)
                                .font(.system(size: 13, weight: .semibold))
                                .lineSpacing(3)
                                .foregroundStyle(tokens.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .id("guidance-current")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.trailing, 4)
            }
            .scrollIndicators(.visible)
            .onAppear {
                scrollGuidanceHistoryToLatest(proxy)
            }
            .onChange(of: history.last) { _, _ in
                scrollGuidanceHistoryToLatest(proxy)
            }
            .onChange(of: current.isEmpty) { wasEmpty, isEmpty in
                if wasEmpty && !isEmpty {
                    scrollGuidanceHistoryToLatest(proxy)
                }
            }
        }
    }

    private var guidanceHistory: [String] {
        GuidanceHistory.visibleHistory(
            model.nextSentenceHistory,
            current: model.nextSentence
        )
    }

    private func scrollGuidanceHistoryToLatest(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            let target = model.nextSentence
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
                ? "guidance-empty"
                : "guidance-current"
            proxy.scrollTo(target, anchor: .bottom)
        }
    }

    private var frameworkColumn: some View {
        GlassModule {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: GlassMetrics.iconTextSpacing) {
                    IconChip(systemName: "doc.text.fill", tint: GlassIconTint.green)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("写作框架")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(tokens.textPrimary)
                        Text(model.detectedTemplateLabel)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(GlassIconTint.green)
                    }

                    Spacer()
                    templatePicker
                }

                Rectangle()
                    .fill(tokens.moduleBorder)
                    .frame(height: 0.5)
                    .padding(.vertical, 8)

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        frameworkList
                        directionToggle

                        if directionsExpanded {
                            directionList
                            missingPoints
                        }
                    }
                    .padding(.trailing, 3)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private var resultColumn: some View {
        GlassModule {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: GlassMetrics.iconTextSpacing) {
                    IconChip(systemName: "captions.bubble.fill", tint: GlassIconTint.gray)
                    Text("实时转录")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tokens.textPrimary)

                    Spacer()

                    if model.isProcessing {
                        HStack(spacing: 5) {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(GlassIconTint.blue)
                            Text("优化中")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(tokens.textSecondary)
                        }
                    }
                }

                Text(model.liveTranscript.isEmpty ? "开始口述后，识别文字会显示在这里。" : model.liveTranscript)
                    .font(.system(size: 12, weight: .regular))
                    .lineSpacing(3)
                    .foregroundStyle(
                        model.liveTranscript.isEmpty ? tokens.textTertiary : tokens.textPrimary
                    )
                    .lineLimit(3)
                    .frame(height: 42, alignment: .topLeading)

                Rectangle()
                    .fill(tokens.moduleBorder)
                    .frame(height: 0.5)
                    .padding(.vertical, 2)

                HStack(spacing: 8) {
                    Text(model.isProcessing
                         ? "正在优化全文"
                         : (model.replacementMessage.isEmpty ? "优化结果" : model.replacementMessage))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(tokens.textSecondary)
                        .lineLimit(1)

                    Spacer()

                    if !model.isProcessing {
                        Button {
                            model.copyOptimizedText()
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(tokens.textSecondary)
                                .frame(width: 22, height: 22)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(model.optimizedTranscript.isEmpty && model.liveTranscript.isEmpty)
                        .help("复制优化结果")
                    }
                }

                ScrollView {
                    Text(model.optimizedTranscript.isEmpty
                         ? (model.isProcessing
                            ? "正在检查重复表达和逻辑衔接…"
                            : "会话结束后，优化后的全文会显示在这里。")
                         : model.optimizedTranscript)
                        .font(.system(size: 12, weight: .regular))
                        .lineSpacing(3)
                        .foregroundStyle(
                            model.optimizedTranscript.isEmpty
                                ? tokens.textTertiary
                                : tokens.textPrimary
                        )
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .textSelection(.enabled)
                        .padding(.trailing, 3)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private var statusText: String {
        guard model.apiKeyStatus == "已安全配置" else {
            return "本地引导 · 未配置智谱 Key"
        }
        if model.isProcessing {
            return "正在优化全文，请稍候…"
        }
        return model.sessionStatus.isEmpty ? "等待开始" : model.sessionStatus
    }

    private var statusColor: Color {
        model.apiKeyStatus == "已安全配置" ? tokens.textSecondary : Theme.warning
    }

    private var templatePicker: some View {
        Menu {
            ForEach(model.documentTemplateOptions) { option in
                Button(option.displayName) {
                    model.selectedDocumentTemplate = option
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(model.selectedDocumentTemplate?.displayName ?? "自动")
                    .font(.system(size: 10.5, weight: .semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(tokens.textSecondary)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(
                Capsule()
                    .fill(tokens.moduleTint)
            )
            .overlay(
                Capsule()
                    .strokeBorder(tokens.moduleBorder, lineWidth: 0.5)
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("切换文档模板")
    }

    private var frameworkList: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.frameworkItems.isEmpty {
                Text("开始口述后自动生成结构框架。")
                    .font(.system(size: 12, weight: .regular))
                    .lineSpacing(3)
                    .foregroundStyle(tokens.textTertiary)
            } else {
                ForEach(model.frameworkItems.indices, id: \.self) { index in
                    HStack(alignment: .top, spacing: 7) {
                        Circle()
                            .fill(GlassIconTint.green)
                            .frame(width: 5, height: 5)
                            .padding(.top, 6)

                        Text(model.frameworkItems[index])
                            .font(.system(size: 12, weight: .regular))
                            .lineSpacing(3)
                            .foregroundStyle(tokens.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var directionToggle: some View {
        Button {
            withAnimation(.easeOut(duration: 0.16)) {
                directionsExpanded.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Text("写作方向")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tokens.textSecondary)
                Text("\(model.directionItems.count) 条")
                    .font(.system(size: 10.5, weight: .regular))
                    .foregroundStyle(tokens.textTertiary)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(tokens.textTertiary)
                    .rotationEffect(.degrees(directionsExpanded ? 180 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(directionsExpanded ? "收起写作方向" : "展开写作方向")
    }

    private var directionList: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.directionItems.isEmpty {
                Text("识别到内容后会给出可展开的写作方向。")
                    .font(.system(size: 11.5, weight: .regular))
                    .lineSpacing(3)
                    .foregroundStyle(tokens.textTertiary)
            } else {
                ForEach(model.directionItems.indices, id: \.self) { index in
                    Text(model.directionItems[index])
                        .font(.system(size: 11.5, weight: .regular))
                        .lineSpacing(3)
                        .foregroundStyle(tokens.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var missingPoints: some View {
        Group {
            if !model.missingPointItems.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("可能遗漏")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(GlassIconTint.orange)

                    ForEach(model.missingPointItems.indices, id: \.self) { index in
                        Text(model.missingPointItems[index])
                            .font(.system(size: 11.5, weight: .regular))
                            .lineSpacing(3)
                            .foregroundStyle(Theme.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}
