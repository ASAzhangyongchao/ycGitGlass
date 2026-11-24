import SwiftUI
import GitCore

// MARK: - 分支名校验（弹窗与选择器的内联输入行共用同一套规则）

enum BranchNameValidator {
    /// 返回错误文案；nil 表示可用。空串不报错，交给按钮的 disabled 处理。
    static func error(_ raw: String, existing: [String]) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        if name.count > 128 { return "分支名最长 128 个字符" }
        if name.hasPrefix("-") { return "分支名不能以 - 开头" }
        if name.contains(" ") || name.contains("\t") { return "分支名不能包含空格或制表符" }
        let banned = Set("~^:?*[\\")
        if name.contains(where: { banned.contains($0) }) { return "不能包含 ~ ^ : ? * [ \\ 这些字符" }
        if name.hasPrefix("/") || name.hasSuffix("/") || name.contains("//") { return "斜杠用法不合法（不能以 / 开头结尾，也不能连续）" }
        if name.contains("..") || name.contains("@{") { return "分支名格式不合法" }
        if name.hasSuffix(".") || name.hasSuffix(".lock") { return "不能以 . 或 .lock 结尾" }
        if existing.contains(name) { return "已存在同名本地分支，换一个名字" }
        return nil
    }
}

// MARK: - 起点

/// 新建分支的起点。`.head` 走 `git checkout -b <name>`，其余走 `git checkout -b <name> <ref>`。
enum StartPointSelection: Equatable {
    case head
    case branch(String)
    case commit(String)
    case custom

    /// 传给 GitService 的 ref；`.head` / 空值返回 nil。
    func effectiveRef(customRef: String) -> String? {
        let value: String
        switch self {
        case .head: return nil
        case .branch(let ref), .commit(let ref): value = ref
        case .custom: value = customRef
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// 与 `GitService.isValidRefToken` 共用同一套白名单：起点会被拼进 `git checkout -b` 的 argv，
/// UI 前置提示，GitService 落命令前再校验一次，规则不落在两处。
enum StartPointValidator {
    static func error(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "请填写分支名或提交号" }
        guard GitService.isValidRefToken(value) else {
            return "只支持分支名 / 提交号（字母、数字、_ . - /），不支持 ~ ^ 等相对引用"
        }
        return nil
    }
}

// MARK: - 起点下拉列表

/// 起点选择列表：当前 HEAD / 本地分支 / 远程分支 / 最近提交 / 自定义。
/// 单独抽成 View 是为了能在离屏快照里直接渲染（popover 点不到）。
struct StartPointList: View {
    let locals: [Branch]
    let remotes: [Branch]
    let commits: [Commit]
    let currentBranch: String
    let selection: StartPointSelection
    let onSelect: (StartPointSelection) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    row(.head, icon: "arrow.triangle.branch",
                        title: "当前分支 HEAD",
                        subtitle: currentBranch.isEmpty ? nil : currentBranch)

                    if !locals.isEmpty {
                        group("本地分支")
                        ForEach(locals) { branch in
                            row(.branch(branch.name), icon: nil, title: branch.name,
                                subtitle: branch.isCurrent ? "当前" : (branch.upstream.isEmpty ? nil : "跟踪 \(branch.upstream)"),
                                mono: true)
                        }
                    }

                    if !remotes.isEmpty {
                        group("远程分支")
                        ForEach(remotes) { branch in
                            row(.branch(branch.name), icon: "cloud", title: branch.name, subtitle: nil, mono: true)
                        }
                    }

                    if !commits.isEmpty {
                        group("最近提交")
                        ForEach(Array(commits.prefix(8))) { commit in
                            row(.commit(commit.hash), icon: nil, title: commit.shortHash,
                                subtitle: commit.subject, mono: true)
                        }
                    }
                }
                .padding(8)
            }

            // 自定义入口固定在底部，不随分支 / 提交列表滚动，永远点得到
            Divider()
            row(.custom, icon: "pencil", title: "自定义 ref / 提交号…", subtitle: nil)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
        }
        .frame(width: 300)
        .frame(maxHeight: 380)
    }

    @ViewBuilder
    private func group(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 8)
            .padding(.top, 7)
            .padding(.bottom, 1)
    }

    private func row(_ target: StartPointSelection, icon: String?, title: String,
                     subtitle: String?, mono: Bool = false) -> some View {
        let isSelected = selection == target
        return Button {
            onSelect(target)
        } label: {
            HStack(spacing: 7) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                        .foregroundStyle(GlassPalette.blue)
                        .frame(width: 14)
                } else {
                    Color.clear.frame(width: 14, height: 1)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular,
                                      design: mono ? .monospaced : .default))
                        .lineLimit(1)
                    if let subtitle, !subtitle.isEmpty {
                        Text(String(subtitle.prefix(34)))
                            .font(.system(size: 9.5, design: mono ? .monospaced : .default))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(GlassPalette.blue)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(isSelected ? GlassPalette.blue.opacity(0.12) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 新建分支弹窗

/// 独立的「新建分支」入口。以前只有一个藏在「切换分支」面板左下角的小字链接，
/// 顶栏下拉菜单被替换成选择器之后，那个入口对多数人等于不存在。
/// 现在菜单 / 胶囊右键 / 侧栏仓库右键 / 历史详情 / 分支选择器行右键都能调起这个弹窗。
///
/// 起点默认当前 HEAD，弹窗内可改成任意本地 / 远程分支、最近提交或自定义 ref；
/// 历史详情与分支选择器行右键会预填起点，仍然允许在弹窗里覆盖。
struct NewBranchSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// nil = 基于当前 HEAD；否则是提交号 / 分支名（调用方预填，弹窗内可再改）。
    let startPoint: String?
    @State private var name: String
    @State private var selection: StartPointSelection
    @State private var customRef: String
    @State private var showStartPicker = false
    @FocusState private var focused: Bool

    /// initialName 只给离屏快照用（验证重名 / 非法字符的报错态）。
    init(startPoint: String?, initialName: String = "") {
        self.startPoint = startPoint
        _name = State(initialValue: initialName)
        _customRef = State(initialValue: "")
        let trimmed = startPoint?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            _selection = State(initialValue: .head)
        } else if Self.looksLikeHash(trimmed) {
            _selection = State(initialValue: .commit(trimmed))
        } else {
            // onAppear 会拿真实分支列表再精确校正（分支 / 自定义）
            _selection = State(initialValue: .branch(trimmed))
        }
    }

    private static func looksLikeHash(_ value: String) -> Bool {
        value.count >= 7 && value.allSatisfy { "0123456789abcdefABCDEF".contains($0) }
    }

    private var localBranchNames: [String] {
        state.branches.filter { !$0.isRemote }.map(\.name)
    }

    private var validation: String? {
        BranchNameValidator.error(name, existing: localBranchNames)
    }

    private var isCustom: Bool {
        if case .custom = selection { return true }
        return false
    }

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && validation == nil
            && (!isCustom || StartPointValidator.error(customRef) == nil)
    }

    private var effectiveStartPoint: String? {
        selection.effectiveRef(customRef: customRef)
    }

    private var baseCaption: String {
        switch selection {
        case .head: return "当前分支 HEAD"
        case .branch: return "分支"
        case .commit: return "选中的提交"
        case .custom: return "自定义起点"
        }
    }

    private var baseLabel: String {
        switch selection {
        case .head:
            return state.status.branch.isEmpty ? "当前 HEAD" : state.status.branch
        case .branch(let ref):
            return ref.isEmpty ? "—" : ref
        case .commit(let hash):
            return hash.isEmpty ? "—" : String(hash.prefix(7))
        case .custom:
            let value = customRef.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? "未填写" : value
        }
    }

    private var startIcon: String {
        switch selection {
        case .head, .branch: return "arrow.triangle.branch"
        case .commit: return "circle.dashed"
        case .custom: return "pencil"
        }
    }

    private var intro: String {
        switch selection {
        case .head: return "从当前分支的 HEAD 切出新分支，创建后自动切换过去。"
        case .branch: return "从所选分支切出新分支，创建后自动切换过去。"
        case .commit: return "从选中的提交切出新分支，创建后自动切换过去。"
        case .custom: return "从填写的起点切出新分支，创建后自动切换过去。"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 标题
            VStack(alignment: .leading, spacing: 4) {
                Text("新建分支")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                Text(intro)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            startPointCard

            // 名称输入
            VStack(alignment: .leading, spacing: 7) {
                Text("分支名")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextField("例如 feature/login", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, design: .monospaced))
                    .focused($focused)
                    .onSubmit { create() }

                // 常用前缀：点一下直接带入，省得每次手敲
                HStack(spacing: 6) {
                    ForEach(["feature/", "fix/", "hotfix/", "chore/"], id: \.self) { prefix in
                        Button {
                            if !name.hasPrefix(prefix) { name = prefix + name }
                            focused = true
                        } label: {
                            Text(prefix)
                                .font(.system(size: 10, design: .monospaced))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(GlassPalette.blue)
                        .background(GlassPalette.blue.opacity(0.10), in: Capsule())
                        .help("以 \(prefix) 开头")
                    }
                }

                if let validation {
                    Label(validation, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 10.5))
                        .foregroundStyle(GlassPalette.rose)
                } else {
                    Text("支持 / 分层命名，如 feature/payment-refactor")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }

            Divider()

            HStack(spacing: 10) {
                Text("⌘⏎ 或回车创建")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("创建并切换") { create() }
                    .prominentAction()
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCreate)
            }
        }
        .padding(24)
        .frame(width: 440)
        .background(GlassBackground())
        .onAppear {
            focused = true
            normalizeInjectedStartPoint()
        }
    }

    // MARK: 起点选择卡片

    private var startPointCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 用 Button + popover 而不是 Menu：Menu 会把 label 压成系统下拉按钮，
            // 双行内容（标题 + 值）与自定义底色都会被吞掉。
            Button {
                showStartPicker.toggle()
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: startIcon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(GlassPalette.blue)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("基于 · \(baseCaption)")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.tertiary)
                        Text(baseLabel)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(GlassPalette.blue.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(GlassPalette.blue.opacity(showStartPicker ? 0.35 : 0.0), lineWidth: 1)
            }
            .help("点开可改起点：当前 HEAD / 本地分支 / 远程分支 / 最近提交 / 自定义 ref")
            .popover(isPresented: $showStartPicker, arrowEdge: .bottom) {
                StartPointList(locals: state.localBranches,
                               remotes: state.remoteBranches,
                               commits: state.commits,
                               currentBranch: state.status.branch,
                               selection: selection) { picked in
                    selection = picked
                    showStartPicker = false
                }
            }

            if isCustom {
                VStack(alignment: .leading, spacing: 5) {
                    TextField("例如 origin/main 或 a1b2c3d", text: $customRef)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                    if let error = StartPointValidator.error(customRef) {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(GlassPalette.rose)
                    } else {
                        Text("可填本地 / 远程分支名或完整提交号；创建后自动切换过去")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    /// 调用方注入的起点按真实数据分类：分支名 → 分支，hash → 提交，
    /// 其余（如相对引用、标签）落到自定义输入框，用户可继续编辑。
    private func normalizeInjectedStartPoint() {
        guard let raw = startPoint?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return }
        if state.branches.contains(where: { $0.name == raw }) {
            selection = .branch(raw)
        } else if Self.looksLikeHash(raw) {
            selection = .commit(raw)
        } else if raw.contains("/") {
            selection = .branch(raw)
        } else {
            selection = .custom
            customRef = raw
        }
    }

    private func create() {
        guard canCreate else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = effectiveStartPoint
        dismiss()
        Task { await state.createBranch(trimmed, from: base) }
    }
}
