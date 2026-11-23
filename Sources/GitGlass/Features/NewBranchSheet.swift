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

// MARK: - 新建分支弹窗

/// 独立的「新建分支」入口。以前只有一个藏在「切换分支」面板左下角的小字链接，
/// 顶栏下拉菜单被替换成选择器之后，那个入口对多数人等于不存在。
/// 现在菜单 / 胶囊右键 / 侧栏仓库右键 / 历史详情都能调起这个弹窗。
struct NewBranchSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// nil = 基于当前 HEAD；否则是提交号 / 分支名（历史页「从此提交新建分支」）。
    let startPoint: String?
    @State private var name: String
    @FocusState private var focused: Bool

    /// initialName 只给离屏快照用（验证重名 / 非法字符的报错态）。
    init(startPoint: String?, initialName: String = "") {
        self.startPoint = startPoint
        _name = State(initialValue: initialName)
    }

    private var localBranchNames: [String] {
        state.branches.filter { !$0.isRemote }.map(\.name)
    }

    private var validation: String? {
        BranchNameValidator.error(name, existing: localBranchNames)
    }

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && validation == nil
    }

    private var baseLabel: String {
        if let startPoint, !startPoint.isEmpty {
            return String(startPoint.prefix(7))
        }
        let current = state.status.branch
        return current.isEmpty ? "当前 HEAD" : current
    }

    private var baseCaption: String {
        startPoint == nil ? "当前分支" : "选中的提交"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 标题
            VStack(alignment: .leading, spacing: 4) {
                Text("新建分支")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                Text("从\(baseCaption)切出一个新分支，创建后自动切换过去。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            // 起点卡片
            HStack(spacing: 9) {
                Image(systemName: startPoint == nil ? "arrow.triangle.branch" : "circle.dashed")
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
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(GlassPalette.blue.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))

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
        .onAppear { focused = true }
    }

    private func create() {
        guard canCreate else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = startPoint
        dismiss()
        Task { await state.createBranch(trimmed, from: base) }
    }
}
