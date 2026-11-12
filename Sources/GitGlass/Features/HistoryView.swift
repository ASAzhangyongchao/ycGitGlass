import SwiftUI
import GitCore

/// 历史页：彩色分支轨道 + 即时本地过滤 + 右侧提交详情 Inspector。
/// 输入时零 git 命令；只有点「深度搜索」或选中提交时才访问仓库。
struct HistoryView: View {
    @Environment(AppState.self) private var state
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 定位闪烁状态：locateRequest 到来时滚动并高亮闪烁
    @State private var flashHash: String?
    @State private var flashOn = false
    /// 内容区可用宽度（隐形探测器测量，驱动三栏/两栏策略）
    @State private var viewportWidth: CGFloat = 1400

    var body: some View {
        if state.currentRepository == nil {
            EmptyStateView(title: "还没有仓库", message: "先在左侧添加一个 Git 仓库。", icon: "clock")
        } else {
            // macOS 26 .glassEffect 在约束更新时有系统级崩溃问题（NSViewUpdateConstraints）。
            // 历史页强制走平面卡片路径（纯色+描边，视觉相近），换取绝对稳定。
            content
                .environment(\.glassReduceTransparency, true)
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 15) {
            searchBar
            // 宽度感知三栏策略（探测式）：隐形探测器读取可用宽度，
            // 不用 GeometryReader 包整棵树（避免约束歧义）。
            ZStack(alignment: .topLeading) {
                GeometryReader { geo in
                    Color.clear
                        .onAppear { viewportWidth = geo.size.width }
                        .onChange(of: geo.size.width) { _, w in viewportWidth = w }
                }
                .frame(height: 0)
                .allowsHitTesting(false)

                let wide = viewportWidth >= 1240
                HStack(alignment: .top, spacing: 14) {
                    GlassCard(title: "提交历史", icon: "clock.arrow.circlepath",
                              help: "彩色轨道 = 分支 / 合并关系；点提交看详情，详情里可定位 / 遴选 / 还原 / 打标签。",
                              padding: 14) {
                        historyList
                    }
                    .frame(minWidth: wide ? 360 : 300,
                           idealWidth: 480,
                           maxWidth: .infinity, maxHeight: .infinity)

                    ZStack(alignment: .topTrailing) {
                        if state.showDetailPanel {
                            CommitDetailPanel()
                                .frame(maxHeight: .infinity)
                        }
                        // 窄窗口：Diff 覆盖在详情上（带关闭按钮），列表保持可读宽度
                        if state.showDiffViewer && !wide {
                            DiffViewerPanel()
                        }
                    }

                    // 宽窗口：第三栏并排
                    if state.showDiffViewer && wide {
                        DiffViewerPanel()
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.bottom, 20)
    }

    private var searchBar: some View {
        // 单行统一工具条：搜索 + 筛选 + 统计都在一条玻璃条里。
        // ViewThatFits：窗口窄时自动降级为紧凑版（作者/排序收进「筛选」菜单），
        // 永不溢出换行。
        ViewThatFits(in: .horizontal) {
            toolbar(compact: false)
            toolbar(compact: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassSurface(cornerRadius: 12)
    }

    private func toolbar(compact: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField("搜索说明 / 作者 / hash…", text: Binding(
                get: { state.historyQuery },
                set: { state.historyQuery = $0 }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 12.5))
            .onChange(of: state.historyQuery) { _, _ in state.historyQueryChanged() }

            if !state.historyQuery.isEmpty {
                Button {
                    withComfortableAnimation(reduceMotion) { state.historyQuery = "" }
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("清空搜索")
            }

            Divider().frame(height: 14).opacity(0.5)

            if compact {
                Menu {
                    Section("作者") {
                        ForEach(state.availableAuthors.prefix(20), id: \.name) { entry in
                            Button("\(entry.name) (\(entry.count))") { state.toggleAuthorFilter(entry.name) }
                        }
                    }
                    Section("排序") {
                        ForEach(HistorySort.allCases, id: \.self) { sort in
                            Button(sort.rawValue) { state.historySort = sort }
                        }
                    }
                    Divider()
                    Toggle("全部分支", isOn: Binding(
                        get: { state.historyAllBranches },
                        set: { state.historyAllBranches = $0 }
                    ))
                } label: {
                    Label("筛选", systemImage: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 11, weight: .medium))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("作者 / 排序 / 全部分支（窗口较窄时的紧凑模式）")
            } else {
                authorMenu
                sortMenu

                Toggle("全部分支", isOn: Binding(
                    get: { state.historyAllBranches },
                    set: { state.historyAllBranches = $0 }
                ))
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
                .onChange(of: state.historyAllBranches) { _, _ in
                    Task { await state.refresh(reason: .manual) }
                }
            }

            Spacer(minLength: 8)

            if state.historyAuthorFilter != nil {
                Button {
                    if let author = state.historyAuthorFilter { state.toggleAuthorFilter(author) }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "person.fill")
                        Text("清除作者筛选")
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(GlassPalette.violet)
                }
                .buttonStyle(.plain)
                .help("取消作者筛选")
            }

            Text("\(state.filteredCommits.count)/\(state.commits.count)")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(.tertiary)
                .help("筛选后 / 已加载的提交数")

            if state.needsDeepSearch {
                ActionButton(title: "深度搜索", icon: "sparkle.magnifyingglass", prominent: true) {
                    Task { await state.deepSearch() }
                }
                .disabled(state.isBusy || state.historyQuery.isEmpty)
                .help("扫描完整历史（按文件、日期范围搜索时需要）")
            }
        }
    }

    /// 行高与轨道列共用，保证节点与行内容严格对齐。
    static let rowHeight: CGFloat = 52

    // MARK: 作者筛选菜单（从已加载提交提取，纯内存）

    private var authorMenu: some View {
        Menu {
            ForEach(state.availableAuthors, id: \.name) { author in
                Button {
                    withComfortableAnimation(reduceMotion) {
                        state.toggleAuthorFilter(author.name)
                    }
                } label: {
                    HStack {
                        Text(author.name)
                        Text("\(author.count)").foregroundStyle(.secondary)
                        if state.historyAuthorFilter == author.name {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 10.5, weight: .semibold))
                Text(state.historyAuthorFilter ?? "作者")
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                    .frame(maxWidth: 90, alignment: .leading)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .glassPill(tint: state.historyAuthorFilter != nil ? GlassPalette.violet.opacity(0.16) : nil, interactive: true)
        .help("按提交人筛选（从已加载的提交中提取）")
    }

    // MARK: 排序菜单

    private var sortMenu: some View {
        Menu {
            ForEach(HistorySort.allCases) { sort in
                Button {
                    withComfortableAnimation(reduceMotion) { state.historySort = sort }
                } label: {
                    HStack {
                        Image(systemName: sort.symbol)
                        Text(sort.rawValue)
                        if state.historySort == sort {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 10.5, weight: .semibold))
                Text(state.historySort.rawValue)
                    .font(.system(size: 11.5, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .glassPill(interactive: true)
        .help("排序方式（纯内存排序，立即生效）")
    }

    @ViewBuilder
    private var historyList: some View {
        if state.filteredCommits.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.tertiary)
                Text(state.historyQuery.isEmpty ? "还没有提交记录" : "没有匹配的提交")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                if !state.historyQuery.isEmpty {
                    Text("试试更短的关键词，或点「深度搜索」扫描完整历史。")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 180)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    HStack(alignment: .top, spacing: 0) {
                        // 连续轨道背景层：一张 Canvas 画整列，线条跨行贯通
                        CommitGraphColumn(commits: state.filteredCommits,
                                          rowHeight: Self.rowHeight)
                            .padding(.top, 4)
                        // 行内容层：固定行高与轨道对齐
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(state.filteredCommits) { commit in
                                commitRow(commit)
                                    .id(commit.hash)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .onChange(of: state.locateRequest) { _, request in
                    guard let request else { return }
                    proxy.scrollTo(request.hash, anchor: .center)
                    flashHash = request.hash
                    flashOn = true
                    // 闪烁两轮后熄灭（事件驱动，无 Timer）
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(240)); flashOn = false
                        try? await Task.sleep(for: .milliseconds(240)); flashOn = true
                        try? await Task.sleep(for: .milliseconds(240)); flashOn = false
                        try? await Task.sleep(for: .milliseconds(240)); flashOn = true
                        try? await Task.sleep(for: .milliseconds(300)); flashOn = false
                        flashHash = nil
                    }
                }
            }
        }
    }

    private func commitRow(_ commit: Commit) -> some View {
        let selected = state.showDetailPanel && state.selectedCommit?.id == commit.hash
        return Button {
            Task { await state.openDetail(for: commit) }
        } label: {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(commit.subject)
                            .font(.system(size: 12.5, weight: selected ? .bold : .semibold))
                            .lineLimit(2)
                        ForEach(refChips(commit.refs), id: \.self) { chip in
                            StatusBadge(text: chip,
                                        tint: chip.hasPrefix("tag") ? GlassPalette.amber : GlassPalette.blue)
                        }
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: 8) {
                        Label(commit.author, systemImage: "person")
                        Text(commit.displayDate)
                        Text(commit.shortHash)
                            .font(.system(size: 10.5, design: .monospaced))
                    }
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(selected ? GlassPalette.accent : Color.secondary.opacity(0.5))
            }
            .padding(.horizontal, 8)
            .frame(minHeight: Self.rowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background {
                let flashing = flashHash == commit.hash && flashOn
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(flashing
                          ? GlassPalette.accent.opacity(0.30)
                          : (selected ? GlassPalette.accent.opacity(0.10) : Color.clear))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(GlassPalette.accent.opacity(flashing ? 0.75 : 0),
                                          lineWidth: 1.5)
                    )
            }
        }
        .buttonStyle(.plain)
        .help("打开提交详情：元信息、变更文件、遴选 / 还原 / 打标签")
    }

    private func refChips(_ refs: String) -> [String] {
        let parts: [String] = refs.split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return Array(parts.prefix(3))
    }
}
