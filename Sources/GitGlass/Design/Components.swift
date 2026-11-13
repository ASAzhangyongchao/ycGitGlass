import SwiftUI
import AppKit
import GitCore

// MARK: - 通用玻璃容器

struct GlassCard<Content: View>: View {
    var title: String? = nil
    var icon: String? = nil
    var subtitle: String? = nil
    /// 长说明收进标题行的小问号弹泡，不再独占一行。
    var help: String? = nil
    /// 教学步骤（配合 help 显示在弹泡里；helpSteps 有值时弹泡升级为分步教学）
    var helpSteps: [TeachingTip.Step] = []
    /// 教学脚注（彩蛋 / 注意事项）
    var helpFootnote: String? = nil
    var tint: Color? = nil
    var padding: CGFloat = 18
    @ViewBuilder var content: Content
    @State private var showHelp = false
    @State private var helpDismissTask: Task<Void, Never>?

    init(title: String? = nil, icon: String? = nil, subtitle: String? = nil,
         help: String? = nil, helpSteps: [TeachingTip.Step] = [],
         helpFootnote: String? = nil,
         tint: Color? = nil, padding: CGFloat = 18,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.subtitle = subtitle
        self.help = help
        self.helpSteps = helpSteps
        self.helpFootnote = helpFootnote
        self.tint = tint
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if title != nil || subtitle != nil || help != nil {
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(tint ?? GlassPalette.accent)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        if let title {
                            Text(title).font(.system(size: 14, weight: .semibold))
                        }
                        if let subtitle {
                            Text(subtitle).font(.system(size: 11.5)).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    if let help {
                        Button {
                            showHelp = true
                        } label: {
                            Image(systemName: "questionmark.circle")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(showHelp ? GlassPalette.accent : Color.secondary)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help(help)
                        .popover(isPresented: $showHelp, arrowEdge: .bottom) {
                            TeachingTipView(tip: TeachingTip(
                                title: title ?? "使用说明",
                                intro: help,
                                steps: helpSteps,
                                footnote: helpFootnote
                            ))
                        }
                        .onChange(of: showHelp) { _, shown in
                            // 打开 12 秒后自动消失（事件任务，非 Timer）
                            helpDismissTask?.cancel()
                            if shown {
                                helpDismissTask = Task { @MainActor in
                                    try? await Task.sleep(for: .seconds(12))
                                    if !Task.isCancelled { showHelp = false }
                                }
                            }
                        }
                        .onDisappear { helpDismissTask?.cancel() }
                    }
                }
            }
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: 20, tint: tint)
        .cardShadow()
    }
}

struct SectionTitle: View {
    let title: String
    var caption: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 13, weight: .semibold))
            if let caption {
                Text(caption).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - 统计块

struct StatTile: View {
    let value: String
    let label: String
    let icon: String
    var tint: Color = GlassPalette.blue
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                Spacer()
            }
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: 16, interactive: true)
        .hoverLift(hovering)
        .onHover { hovering = $0 }
        .animation(Motion.spring, value: value)
    }
}

// MARK: - 动作按钮

struct ActionButton: View {
    let title: String
    let icon: String
    var tint: Color? = nil
    var prominent = false
    /// 紧凑模式：图标+更小字号+收紧内边距，用于一行要放下多个按钮的场景
    var compact = false
    var disabled = false
    var helpText = ""
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Group {
            if prominent {
                baseButton.prominentAction().tint(tint ?? GlassPalette.accent)
            } else {
                baseButton.glassAction().tint(tint ?? .primary)
            }
        }
        .disabled(disabled)
        .hoverLift(hovering && !disabled, scale: compact ? 1.015 : 1.02)
        .onHover { hovering = $0 }
        .help(helpText.isEmpty ? title : helpText)
    }

    private var baseButton: some View {
        Button(action: action) {
            if compact {
                // 紧凑：仅图标，尺寸 12，提示文字放 help
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 24)
            } else {
                Label(title, systemImage: icon)
                    .font(.system(size: 12.5, weight: .semibold))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
            }
        }
    }
}

struct SmallIconButton: View {
    let icon: String
    var tint: Color? = nil
    var helpText = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 24)
        }
        .glassAction()
        .tint(tint ?? .primary)
        .help(helpText)
    }
}

// MARK: - 徽标

struct StatusBadge: View {
    let text: String
    var tint: Color = GlassPalette.blue

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.16), in: Capsule())
            .foregroundStyle(tint)
    }
}

struct BusyBadge: View {
    let label: String

    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(label).font(.system(size: 11.5, weight: .medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .glassPill()
        .transition(.scale.combined(with: .opacity))
    }
}

// MARK: - 空状态与提示

struct EmptyStateView: View {
    let title: String
    let message: String
    let icon: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(GlassPalette.accent.opacity(0.75))
            Text(title).font(.system(size: 16, weight: .semibold))
            Text(message)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            if let actionTitle, let action {
                ActionButton(title: actionTitle, icon: "plus", prominent: true, action: action)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }
}

struct InfoHint: View {
    let text: String
    var tint: Color = GlassPalette.blue
    var icon: String = "lightbulb.fill"

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).font(.system(size: 12)).foregroundStyle(tint)
            Text(text).font(.system(size: 11.5)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// 错误 / 成功提示：手动关闭，不引入任何自动消失定时器。
struct NoticeBanner: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 10) {
            if let error = state.errorMessage {
                banner(title: error, detail: state.errorSuggestion, icon: "exclamationmark.triangle.fill",
                       tint: GlassPalette.rose) {
                    state.dismissError()
                } detailDisclosure: {
                    if let raw = state.errorDetail, !raw.isEmpty {
                        DisclosureGroup("查看原始信息") {
                            ScrollView {
                                Text(raw)
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 110)
                        }
                        .font(.system(size: 11))
                    }
                }
            }
            if let notice = state.notice {
                banner(title: notice, detail: nil, icon: "checkmark.circle.fill",
                       tint: GlassPalette.mint) {
                    state.dismissNotice()
                } detailDisclosure: { EmptyView() }
            }
        }
        .animation(Motion.spring, value: state.errorMessage)
        .animation(Motion.spring, value: state.notice)
    }

    @ViewBuilder
    private func banner<Detail: View>(
        title: String, detail: String?, icon: String, tint: Color,
        onClose: @escaping () -> Void,
        @ViewBuilder detailDisclosure: () -> Detail
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon).foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 12.5, weight: .semibold))
                    if let detail, !detail.isEmpty {
                        Text(detail).font(.system(size: 11.5)).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            detailDisclosure()
        }
        .padding(14)
        .frame(maxWidth: 560, alignment: .leading)
        .glassSurface(cornerRadius: 16, tint: tint.opacity(0.12))
        .cardShadow()
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - 输入表单

struct TextInputSheet: View {
    let title: String
    let placeholder: String
    let confirmTitle: String
    var hint: String = ""
    @Binding var text: String
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(.system(size: 17, weight: .semibold))
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
                .focused($focused)
                .onSubmit { confirm() }
            if !hint.isEmpty { InfoHint(text: hint) }
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(confirmTitle) { confirm() }
                    .prominentAction()
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
        .background(GlassBackground())
        .onAppear { focused = true }
    }

    private func confirm() {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        onConfirm()
        dismiss()
    }
}

// MARK: - 差异文本（单次 AttributedString 渲染，避免逐行视图开销）

struct DiffTextView: View {
    let text: String

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            Text(attributed)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .background(.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var attributed: AttributedString {
        var result = AttributedString()
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).prefix(500)
        for raw in lines {
            let line = String(raw)
            var piece = AttributedString(line + "\n")
            piece.font = .system(size: 11, design: .monospaced)
            if line.hasPrefix("+") && !line.hasPrefix("+++") {
                piece.backgroundColor = Color.green.opacity(0.13)
                piece.foregroundColor = Color(red: 0.12, green: 0.48, blue: 0.28)
            } else if line.hasPrefix("-") && !line.hasPrefix("---") {
                piece.backgroundColor = Color.red.opacity(0.11)
                piece.foregroundColor = Color(red: 0.72, green: 0.20, blue: 0.24)
            } else if line.hasPrefix("@@") {
                piece.foregroundColor = GlassPalette.violet
            } else if line.hasPrefix("diff ") || line.hasPrefix("index ") {
                piece.foregroundColor = .secondary
            } else {
                piece.foregroundColor = .primary
            }
            result += piece
        }
        return result
    }
}

// MARK: - 系统交互

@MainActor
func copyToPasteboard(_ text: String) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
}

@MainActor
func chooseFolder(message: String, canCreate: Bool = true) -> String? {
    let panel = NSOpenPanel()
    panel.message = message
    panel.prompt = "选择"
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = canCreate
    panel.resolvesAliases = true
    guard panel.runModal() == .OK, let url = panel.url else { return nil }
    return url.path
}

/// 远程源 / 自定义平台共用的双字段表单。
struct TwoFieldSheet: View {
    let title: String
    let firstLabel: String
    let firstPlaceholder: String
    var secondLabel: String? = nil
    var secondPlaceholder: String? = nil
    var confirmTitle = "确定"
    var hint = ""
    let onConfirm: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var first = ""
    @State private var second = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.system(size: 17, weight: .semibold))
            VStack(alignment: .leading, spacing: 6) {
                Text(firstLabel).font(.system(size: 11.5)).foregroundStyle(.secondary)
                TextField(firstPlaceholder, text: $first)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12.5))
                    .focused($focused)
            }
            if let secondLabel {
                VStack(alignment: .leading, spacing: 6) {
                    Text(secondLabel).font(.system(size: 11.5)).foregroundStyle(.secondary)
                    TextField(secondPlaceholder ?? "", text: $second)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12.5))
                }
            }
            if !hint.isEmpty { InfoHint(text: hint) }
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(confirmTitle) {
                    onConfirm(first.trimmingCharacters(in: .whitespacesAndNewlines),
                              second.trimmingCharacters(in: .whitespacesAndNewlines))
                    dismiss()
                }
                .prominentAction()
                .keyboardShortcut(.defaultAction)
                .disabled(first.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 440)
        .background(GlassBackground())
        .onAppear { focused = true }
    }
}


// MARK: - 标题栏图标按钮（悬停浮出文字说明）

struct ToolbarIconButton: View {
    let icon: String
    let label: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 22)
                .background(hovering ? Color.primary.opacity(0.10) : Color.primary.opacity(0.04),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(alignment: .bottom) { hoverLabel }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .onHover { hovering = $0 }
        .help(help)
    }

    @ViewBuilder
    private var hoverLabel: some View {
        if hovering {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.98),
                            in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
                .fixedSize()
                .offset(y: 28)
                .zIndex(10)
        }
    }
}
