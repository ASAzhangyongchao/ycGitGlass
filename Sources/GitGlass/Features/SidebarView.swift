import SwiftUI
import AppKit
import GitCore

struct SidebarView: View {
    @Environment(AppState.self) private var state
    @State private var showCloneSheet = false
    @State private var query = ""
    @State private var showBranchPickerFor: Repository?
    @State private var showAllRepos = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var searchFocused: Bool

    private var searchResults: [(repository: Repository, matchedBranches: [String])] {
        state.sidebarSearch(query)
    }

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if state.repositories.count > 1 || isSearching {
                searchField
                    .padding(.bottom, 10)
            }
            repositoryList
                .layoutPriority(1)   // 剩余高度优先给仓库列表：折叠低频操作省下的空间不该被 Spacer 吞掉
            Divider().padding(.vertical, 10)
            actionButtons
            // 固定 8pt 间隔而不是 Spacer：VStack 里再放一个 flexible 子视图会
            // 跟仓库列表平分剩余高度，折叠低频操作省下的空间就被白白吃掉。
            Color.clear.frame(height: 8)
            // 吉祥物：空闲时慢悠悠起伏，有任务时加速打字
            MascotCow(isBusy: state.isBusy)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 10)
        }
        .padding(.horizontal, 14)
        .padding(.top, 18)
        .sheet(isPresented: $showCloneSheet) {
            CloneSheet { url, folder in
                Task { await state.cloneRepository(from: url, into: folder) }
            }
        }
        .sheet(item: $showBranchPickerFor) { repository in
            BranchPickerSheet()
                .environment(state)
        }
    }

    // MARK: 搜索框

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            TextField("搜仓库或分支名…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5))
                .focused($searchFocused)
            if isSearching {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("清空搜索")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .glassSurface(cornerRadius: 10)
        .help("按仓库名、路径或分支名搜索；命中分支的仓库会列出匹配分支")
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(GlassPalette.accent)
            Text("仓库")
                .font(.system(size: 13, weight: .semibold))
            HelpQuestionButton(tip: Teachings.sidebarPins, arrowEdge: .bottom)
            Spacer()
            Text("\(state.repositories.count)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var repositoryList: some View {
        if state.repositories.isEmpty {
            emptyRepositoryHint
        } else if isSearching && searchResults.isEmpty {
            noSearchResultHint
        } else {
            GeometryReader { proxy in
                repositoryListContent(availableHeight: proxy.size.height)
            }
            .frame(minHeight: 140)
        }
    }

    /// 侧栏列表：常用置顶 → 其余仓库。非常用按可用高度自动折叠，
    /// 折叠永远不会藏掉当前选中的仓库。
    private func repositoryListContent(availableHeight: CGFloat) -> some View {
        let pinned = state.pinnedRepositories
        let others = state.unpinnedRepositories
        let limit = collapsedLimit(for: availableHeight)
        let visibleOthers = visibleUnpinned(others, limit: limit)
        // 一个「常用」都没有时不折叠：保持原来「全量列表 + 滚动」的体验，
        // 只有用户真的开始置顶，才把非常用收起来给常用让位置。
        let collapsible = !state.pinnedRepoIDs.isEmpty && others.count > limit

        return List(selection: Binding(
            get: { state.selectedRepoID },
            set: { newValue in if let newValue { state.selectRepository(newValue) } }
        )) {
            if isSearching {
                ForEach(Array(searchResults.enumerated()), id: \.element.repository.id) { index, result in
                    repositoryRow(result.repository, matchedBranches: result.matchedBranches)
                        .staggered(index)
                }
            } else {
                if !pinned.isEmpty {
                    Section {
                        ForEach(Array(pinned.enumerated()), id: \.element.id) { index, repository in
                            repositoryRow(repository, matchedBranches: [])
                                .staggered(index)
                        }
                    } header: {
                        sectionHeader("常用", icon: "pin.fill", tint: GlassPalette.amber, count: pinned.count)
                    }
                }
                Section {
                    ForEach(Array(visibleOthers.enumerated()), id: \.element.id) { index, repository in
                        repositoryRow(repository, matchedBranches: [])
                            .staggered(index)
                    }
                } header: {
                    // 还没置顶任何常用时不显示分组标题：页面顶部已有「仓库 N」，
                    // 再来一行标题只是重复占高度。
                    if pinned.isEmpty {
                        sectionHeader("仓库", icon: "folder", tint: GlassPalette.blue, count: others.count)
                    } else {
                        sectionHeader("其他仓库", icon: "folder",
                                      tint: GlassPalette.blue, count: others.count,
                                      expandState: collapsible
                                        ? (remaining: max(0, others.count - visibleOthers.count),
                                           expanded: showAllRepos)
                                        : nil)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .animation(Motion.snappy, value: query)
        .animation(Motion.snappy, value: showAllRepos)
        .animation(Motion.snappy, value: state.pinnedRepoIDs)
    }

    private func sectionHeader(_ title: String, icon: String, tint: Color, count: Int,
                               expandState: (remaining: Int, expanded: Bool)? = nil) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 10, weight: .semibold))
            Text("\(count)")
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(.tertiary)
            Spacer(minLength: 4)
            // 展开/收起放在分组标题行：永远可见，不跟内容一起滚到屏幕外
            if let expandState {
                Button {
                    withComfortableAnimation(reduceMotion) { showAllRepos.toggle() }
                } label: {
                    HStack(spacing: 3) {
                        Text(expandState.expanded ? "收起" : "还有 \(expandState.remaining) 个")
                            .font(.system(size: 9.5, weight: .medium))
                        Image(systemName: expandState.expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundStyle(GlassPalette.blue)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(expandState.expanded ? "只显示常用 + 放得下的几个" : "展开其余 \(expandState.remaining) 个非常用仓库")
            }
        }
    }

    /// 按可用高度估算能平铺几个仓库（每行约 44pt，给分组标题留 70pt）。
    private func collapsedLimit(for height: CGFloat) -> Int {
        max(4, Int(max(0, height - 66) / 44))
    }

    /// 折叠时也不能把当前选中的仓库藏起来，否则"选中的东西"会从列表里消失。
    private func visibleUnpinned(_ others: [Repository], limit: Int) -> [Repository] {
        guard !showAllRepos, !state.pinnedRepoIDs.isEmpty else { return others }
        var list = Array(others.prefix(limit))
        if let selected = state.selectedRepoID,
           others.contains(where: { $0.id == selected }),
           !list.contains(where: { $0.id == selected }),
           let repo = others.first(where: { $0.id == selected }) {
            if list.count >= limit, !list.isEmpty { list.removeLast() }
            list.append(repo)
        }
        return list
    }

    private var emptyRepositoryHint: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(GlassPalette.accent.opacity(0.8))
            Text("还没有仓库")
                .font(.system(size: 13, weight: .semibold))
            Text("点下面的「添加仓库」，选择一个本地 Git 文件夹就能开始。")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 170)
        .padding(12)
        .glassSurface(cornerRadius: 16, tint: GlassPalette.blue.opacity(0.08))
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }

    private var noSearchResultHint: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.tertiary)
            Text("没有匹配「\(query)」的仓库或分支")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .padding(12)
    }

    private func repositoryRow(_ repository: Repository, matchedBranches: [String]) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "folder.fill")
                .font(.system(size: 13))
                .foregroundStyle(GlassPalette.blue.opacity(0.85))
            VStack(alignment: .leading, spacing: 2) {
                Text(repository.name)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                if matchedBranches.isEmpty {
                    Text(repository.path)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    // 搜索命中分支：列出匹配的分支 chips，点击直接选仓库并打开分支选择器
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(matchedBranches, id: \.self) { branch in
                            Button {
                                showBranchPickerFor = repository
                                state.selectRepository(repository.id)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.triangle.branch")
                                        .font(.system(size: 8.5))
                                    Text(branch)
                                        .font(.system(size: 10, design: .monospaced))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(GlassPalette.violet)
                            .background(GlassPalette.violet.opacity(0.10), in: Capsule())
                            .help("选中 \(repository.name) 并打开分支选择器")
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            if !isSearching {
                PinToggleButton(pinned: state.isPinned(repository.id)) {
                    withComfortableAnimation(reduceMotion) { state.togglePin(repository.id) }
                }
            }
        }
        .padding(.vertical, 4)
        .tag(repository.id)
        .help(repository.path)
        .contextMenu {
            Button {
                withComfortableAnimation(reduceMotion) { state.togglePin(repository.id) }
            } label: {
                Label(state.isPinned(repository.id) ? "取消常用" : "设为常用（置顶到最上面）",
                      systemImage: state.isPinned(repository.id) ? "pin.slash" : "pin")
            }
            Divider()
            Button("新建分支…") {
                // 右键的仓库可能不是当前选中：先切过去（selectedRepoID 同步生效，
                // currentPath 立即指向新仓库），再弹窗，避免建到别的仓库上。
                state.selectRepository(repository.id)
                state.requestNewBranch()
            }
            Button("在 Finder 中显示") {
                NSWorkspace.shared.selectFile(repository.path, inFileViewerRootedAtPath: "")
            }
            Button("复制仓库路径") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(repository.path, forType: .string)
            }
            Divider()
            Button("从列表移除", role: .destructive) {
                withComfortableAnimation(reduceMotion) { state.removeRepository(repository.id) }
            }
        }
    }

    private var actionButtons: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 高频：日常添加 / 批量导入，永远常显
            sidebarButton("添加仓库…", icon: "plus.circle.fill", prominent: true) {
                if let path = chooseFolder(message: "选择一个本地 Git 仓库文件夹") {
                    Task { await state.addRepository(at: path) }
                }
            }
            sidebarButton("扫描文件夹批量导入", icon: "magnifyingglass.circle") {
                if let path = chooseFolder(message: "选择父文件夹，向下最多扫描 3 层找 .git") {
                    Task { await state.scanFolder(path) }
                }
            }
            // 低频：一次性入库动作，默认折进「更多操作」，把高度让给仓库列表
            moreActionsSection
        }
    }

    /// 「新建仓库 / 克隆远程仓库」只在第一次接入项目时用得到。
    /// 默认收起，展开状态记在本机偏好（AppState），关掉应用再开仍保持。
    private var moreActionsSection: some View {
        VStack(alignment: .leading, spacing: state.sidebarMoreActionsExpanded ? 8 : 0) {
            HStack(spacing: 2) {
                Button {
                    let next = !state.sidebarMoreActionsExpanded
                    withComfortableAnimation(reduceMotion) {
                        state.setSidebarMoreActionsExpanded(next)
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 11.5))
                        Text("更多操作")
                            .font(.system(size: 11.5, weight: .medium))
                        Spacer(minLength: 0)
                        Text(state.sidebarMoreActionsExpanded ? "收起" : "新建 · 克隆")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                        Image(systemName: state.sidebarMoreActionsExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8.5, weight: .bold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("展开后可新建仓库 / 克隆远程仓库（低频操作，默认收起）")

                HelpQuestionButton(tip: Teachings.sidebarMoreActions, arrowEdge: .trailing)
                    .padding(.trailing, 8)
            }
            .background(
                Color.primary.opacity(0.035),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )

            if state.sidebarMoreActionsExpanded {
                Group {
                    sidebarButton("新建仓库", icon: "folder.badge.plus") {
                        if let path = chooseFolder(message: "选择要初始化为 Git 仓库的文件夹", canCreate: true) {
                            Task { await state.createRepository(at: path) }
                        }
                    }
                    sidebarButton("克隆远程仓库", icon: "arrow.down.circle") {
                        showCloneSheet = true
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func sidebarButton(_ title: String, icon: String, prominent: Bool = false,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon).font(.system(size: 12))
                Text(title).font(.system(size: 12, weight: .medium))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .foregroundStyle(prominent ? .primary : .secondary)
        .background(
            (prominent ? GlassPalette.accent.opacity(0.14) : Color.primary.opacity(0.045)),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .help(title)
    }
}

// MARK: - 克隆表单

private struct CloneSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var folder = FileManager.default.homeDirectoryForCurrentUser.path
    let onClone: (String, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("克隆远程仓库").font(.system(size: 17, weight: .semibold))
            VStack(alignment: .leading, spacing: 6) {
                Text("仓库地址").font(.system(size: 11.5)).foregroundStyle(.secondary)
                TextField("git@github.com:user/repo.git", text: $url)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12.5))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("存放位置").font(.system(size: 11.5)).foregroundStyle(.secondary)
                HStack {
                    Text(folder)
                        .font(.system(size: 11.5, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("选择…") {
                        if let chosen = chooseFolder(message: "选择仓库存放的父文件夹") { folder = chosen }
                    }
                    .glassAction()
                }
            }
            InfoHint(text: "建议使用 SSH 地址。若认证失败，到「密钥」页检查对应平台的公钥是否已添加到账号。")
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("克隆") {
                    onClone(url.trimmingCharacters(in: .whitespacesAndNewlines), folder)
                    dismiss()
                }
                .prominentAction()
                .keyboardShortcut(.defaultAction)
                .disabled(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 460)
        .background(GlassBackground())
    }
}

// MARK: - 行尾「常用」开关

/// 悬停才现身的置顶按钮：已置顶时小铜针常显，未置顶时悬停浮出空心针。
private struct PinToggleButton: View {
    let pinned: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: pinned ? "pin.fill" : "pin")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(pinned ? GlassPalette.amber : .secondary)
                .frame(width: 20, height: 18)
                .background(hovering ? Color.primary.opacity(0.09) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
        .opacity(pinned ? 1 : (hovering ? 1 : 0))
        .onHover { hovering = $0 }
        .help(pinned ? "取消常用（不再固定到顶部）" : "设为常用：固定到列表顶部")
    }
}
