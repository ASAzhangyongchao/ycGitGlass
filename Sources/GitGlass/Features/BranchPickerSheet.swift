import SwiftUI
import GitCore

/// 分支选择器：搜索 + 本地/远程分页 + 按远程源分组折叠树。
/// 替代原先塞满一长条的下拉菜单——分支多时可搜索、可折叠，不再"堵"。
struct BranchPickerSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Scope: String, CaseIterable, Identifiable {
        case local = "本地"
        case remote = "远程"
        var id: String { rawValue }
    }

    @State private var scope: Scope = .local
    @State private var query = ""
    @State private var collapsedSources: Set<String> = []
    @FocusState private var searchFocused: Bool

    private var filteredLocal: [Branch] {
        let branches = state.localBranches
        let keyword = query.trimmingCharacters(in: .whitespaces)
        guard !keyword.isEmpty else { return branches }
        return branches.filter { $0.name.localizedCaseInsensitiveContains(keyword) }
    }

    /// 远程分支按源分组（origin / upstream …），组内再过滤关键字
    private var remoteGroups: [(source: String, branches: [Branch])] {
        let keyword = query.trimmingCharacters(in: .whitespaces)
        let grouped = Dictionary(grouping: state.remoteBranches) { branch -> String in
            branch.name.split(separator: "/", maxSplits: 1).first.map(String.init) ?? "其他"
        }
        return grouped
            .filter { group in
                keyword.isEmpty
                    || group.key.localizedCaseInsensitiveContains(keyword)
                    || group.value.contains { $0.name.localizedCaseInsensitiveContains(keyword) }
            }
            .map { source, branches in
                let filtered = keyword.isEmpty
                    ? branches
                    : branches.filter {
                        $0.name.localizedCaseInsensitiveContains(keyword)
                            || source.localizedCaseInsensitiveContains(keyword)
                    }
                return (source, filtered.sorted {
                    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                })
            }
            .sorted { $0.source.localizedCaseInsensitiveCompare($1.source) == .orderedAscending }
    }

    private var totalCountLabel: String {
        switch scope {
        case .local: return "\(filteredLocal.count) 个本地分支"
        case .remote: return "\(state.remoteBranches.count) 个远程分支 · \(remoteGroups.count) 个来源"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            searchField
            scopeTabs

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if scope == .local {
                        localList
                    } else {
                        remoteTree
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(minHeight: 300, maxHeight: 420)

            footer
        }
        .padding(20)
        .frame(width: 460)
        .background(GlassBackground())
        .onAppear { searchFocused = true }
    }

    // MARK: 头部

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("切换分支")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Text(totalCountLabel)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            HelpQuestionButton(tip: Teachings.mergeBranches, arrowEdge: .bottom)
            if state.isBusy {
                BusyBadge(label: state.busyLabel)
            }
            SmallIconButton(icon: "xmark", helpText: "关闭") { dismiss() }
        }
    }

    // MARK: 搜索

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField("搜索分支名…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused($searchFocused)
            if !query.isEmpty {
                Button {
                    withComfortableAnimation(reduceMotion) { query = "" }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .glassSurface(cornerRadius: 11)
    }

    // MARK: 本地 / 远程 分页

    private var scopeTabs: some View {
        HStack(spacing: 0) {
            ForEach(Scope.allCases) { item in
                let selected = scope == item
                Button {
                    withComfortableAnimation(reduceMotion) { scope = item }
                } label: {
                    HStack(spacing: 6) {
                        Text(item.rawValue)
                            .font(.system(size: 12, weight: selected ? .semibold : .medium))
                        Text(item == .local ? "\(state.localBranches.count)" : "\(state.remoteBranches.count)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(selected ? .primary : .secondary)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(GlassPalette.blue.opacity(0.16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(GlassPalette.blue.opacity(0.22), lineWidth: 1)
                            )
                            .transition(.opacity)
                    }
                }
                .animation(reduceMotion ? nil : Motion.snappy, value: scope)
            }
        }
        .padding(3)
        .glassSurface(cornerRadius: 12)
    }

    // MARK: 本地列表

    @ViewBuilder
    private var localList: some View {
        if filteredLocal.isEmpty {
            emptyHint(query.isEmpty ? "还没有本地分支" : "没有匹配「\(query)」的本地分支")
        } else {
            ForEach(Array(filteredLocal.enumerated()), id: \.element.id) { index, branch in
                branchRow(
                    name: branch.name,
                    subtitle: branch.upstream.isEmpty ? nil : "跟踪 \(branch.upstream)",
                    isCurrent: branch.isCurrent,
                    tint: GlassPalette.blue
                ) {
                    checkout(branch)
                }
                .staggered(index)
            }
        }
    }

    // MARK: 远程树（按源分组可折叠）

    @ViewBuilder
    private var remoteTree: some View {
        if remoteGroups.isEmpty {
            emptyHint(query.isEmpty ? "还没有远程分支，先抓取一次" : "没有匹配「\(query)」的远程分支")
        } else {
            ForEach(remoteGroups, id: \.source) { group in
                SourceGroupNode(
                    source: group.source,
                    count: group.branches.count,
                    collapsed: collapsedSources.contains(group.source),
                    onToggle: {
                        withComfortableAnimation(reduceMotion) {
                            if collapsedSources.contains(group.source) {
                                collapsedSources.remove(group.source)
                            } else {
                                collapsedSources.insert(group.source)
                            }
                        }
                    }
                ) {
                    ForEach(group.branches) { branch in
                        branchRow(
                            name: String(branch.name.split(separator: "/", maxSplits: 1).dropFirst().joined()),
                            subtitle: branch.upstream.isEmpty ? nil : "跟踪 \(branch.upstream)",
                            isCurrent: branch.isCurrent,
                            tint: GlassPalette.violet
                        ) {
                            checkout(branch)
                        }
                    }
                }
            }
        }
    }

    private func checkout(_ branch: Branch) {
        Task {
            await state.checkout(branch)
            dismiss()
        }
    }

    // MARK: 行

    @State private var mergeDirection: MergeDirection?
    @State private var mergeNoFF = false
    /// 待删除的分支（confirmationDialog 用）
    @State private var branchToDelete: String?

    enum MergeDirection: Identifiable {
        case intoCurrent(String)   // 把某分支合进当前
        case currentInto(String)   // 把当前合到某分支
        var id: String {
            switch self {
            case .intoCurrent(let s): return "in-\(s)"
            case .currentInto(let s): return "out-\(s)"
            }
        }
        var otherBranch: String {
            switch self {
            case .intoCurrent(let s), .currentInto(let s): return s
            }
        }
    }

    private func branchRow(name: String, subtitle: String?, isCurrent: Bool, tint: Color,
                           action: @escaping () -> Void) -> some View {
        HStack(spacing: 9) {
            Button(action: action) {
                HStack(spacing: 9) {
                    Circle()
                        .fill(isCurrent ? GlassPalette.mint : tint.opacity(0.7))
                        .frame(width: 6, height: 6)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
                            .lineLimit(1)
                        if let subtitle {
                            Text(subtitle)
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isCurrent ? "当前分支" : "点按切换到此分支")

            // 合并操作区（当前分支自身不显示）
            if !isCurrent {
                mergeMenu(for: name)
            } else {
                StatusBadge(text: "当前", tint: GlassPalette.mint)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            Color.primary.opacity(0.035),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }

    /// 每行右侧的合并菜单：合入当前 / 合并过去 / 删除分支
    private func mergeMenu(for branch: String) -> some View {
        Menu {
            Button {
                mergeDirection = .intoCurrent(branch)
            } label: {
                Label("把 \(branch) 合并进当前分支", systemImage: "arrow.down.right")
            }
            Button {
                mergeDirection = .currentInto(branch)
            } label: {
                Label("把当前分支合并到 \(branch)", systemImage: "arrow.up.right")
            }
            Divider()
            Toggle("保留合并提交（--no-ff）", isOn: $mergeNoFF)
            Divider()
            Button(role: .destructive) {
                branchToDelete = branch
            } label: {
                Label("删除分支 \(branch)…", systemImage: "trash")
            }
        } label: {
            Image(systemName: "arrow.triangle.merge")
                .font(.system(size: 10.5, weight: .medium))
                .frame(width: 24, height: 22)
                .background(Color.primary.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("合并操作：把 \(branch) 合进当前，或把当前合并过去")
        .confirmationDialog(
            mergeConfirmTitle,
            isPresented: Binding(
                get: { mergeDirection != nil },
                set: { if !$0 { mergeDirection = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("合并", role: .destructive) {
                if let dir = mergeDirection {
                    switch dir {
                    case .intoCurrent(let b):
                        Task { await state.mergeIntoCurrent(b, noFF: mergeNoFF) }
                    case .currentInto(let b):
                        Task { await state.mergeCurrentInto(b, noFF: mergeNoFF) }
                    }
                }
                mergeDirection = nil
            }
            Button("取消", role: .cancel) { mergeDirection = nil }
        } message: {
            Text(mergeConfirmMessage)
        }
        .confirmationDialog(
            "删除分支 \(branchToDelete ?? "")？",
            isPresented: Binding(
                get: { branchToDelete != nil },
                set: { if !$0 { branchToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除（已合并才允许）", role: .destructive) {
                if let branch = branchToDelete {
                    Task { await state.deleteBranch(branch, force: false) }
                }
                branchToDelete = nil
            }
            Button("强制删除（未合并也删）", role: .destructive) {
                if let branch = branchToDelete {
                    Task { await state.deleteBranch(branch, force: true) }
                }
                branchToDelete = nil
            }
            Button("取消", role: .cancel) { branchToDelete = nil }
        } message: {
            Text("普通删除只允许已合并的分支（安全）；强制删除会丢弃该分支上未合并的提交，不可恢复。")
        }
    }

    private var mergeConfirmTitle: String {
        guard let dir = mergeDirection else { return "合并" }
        switch dir {
        case .intoCurrent(let b): return "把 \(b) 合并进当前分支？"
        case .currentInto(let b): return "把当前分支合并到 \(b)？"
        }
    }

    private var mergeConfirmMessage: String {
        guard let dir = mergeDirection else { return "" }
        let ff = mergeNoFF ? "将生成一条合并提交（--no-ff）。" : "能快进时直接快进，不产生合并提交。"
        switch dir {
        case .intoCurrent(let b): return "当前分支会加入 \(b) 的改动。\(ff)如有冲突，可到「储藏」页中止。"
        case .currentInto(let b): return "会临时切到 \(b) 完成合并，再切回当前分支。\(ff)如遇冲突会停在 \(b) 上等你解决。"
        }
    }

    // MARK: 底部

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                dismiss()
                showNewBranch = true
            } label: {
                Label("新建分支…", systemImage: "plus")
                    .font(.system(size: 11.5, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(GlassPalette.blue)
            Spacer()
            Text("提示：切远程分支会自动建立本地跟踪")
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
        }
    }

    @State private var showNewBranch = false

    private func emptyHint(_ text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }
}

/// 远程源分组节点：可折叠的树节点（origin ▸ / ▾）。
private struct SourceGroupNode<Content: View>: View {
    let source: String
    let count: Int
    let collapsed: Bool
    let onToggle: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: onToggle) {
                HStack(spacing: 8) {
                    Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                    Image(systemName: "externaldrive.connected.to.line.below")
                        .font(.system(size: 11))
                        .foregroundStyle(GlassPalette.violet)
                    Text(source)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    Text("\(count)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(
                Color.primary.opacity(0.05),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .help(collapsed ? "展开 \(source)" : "折叠 \(source)")

            if !collapsed {
                VStack(alignment: .leading, spacing: 3) {
                    content
                }
                .padding(.leading, 20)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
