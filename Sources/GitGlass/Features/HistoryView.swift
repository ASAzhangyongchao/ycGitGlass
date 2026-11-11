import SwiftUI
import GitCore

/// 历史页：彩色分支轨道 + 即时本地过滤 + 右侧提交详情 Inspector。
/// 输入时零 git 命令；只有点「深度搜索」或选中提交时才访问仓库。
struct HistoryView: View {
    @Environment(AppState.self) private var state
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if state.currentRepository == nil {
            EmptyStateView(title: "还没有仓库", message: "先在左侧添加一个 Git 仓库。", icon: "clock")
        } else {
            VStack(alignment: .leading, spacing: 15) {
                searchBar
                HStack(alignment: .top, spacing: 14) {
                    GlassCard(title: "提交历史", icon: "clock.arrow.circlepath",
                              subtitle: "共 \(state.filteredCommits.count) 条 · 点任意一条在右侧看详情",
                              padding: 14) {
                        historyList
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if state.showDetailPanel {
                        CommitDetailPanel()
                            .frame(maxHeight: .infinity)
                    }

                    // 第三栏：专属 Diff 阅读区（点变更文件后滑入，与列表同高）
                    if state.showDiffViewer {
                        DiffViewerPanel()
                    }
                }
                .animation(reduceMotion ? nil : Motion.snappy, value: state.showDetailPanel)
                .animation(reduceMotion ? nil : Motion.snappy, value: state.showDiffViewer)
            }
            .padding(.vertical, 6)
            .padding(.bottom, 20)
        }
    }

    private var searchBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 第一行：纯搜索（给输入框最大空间）
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("搜索提交说明 / 作者 / hash，支持 author: file: since: 前缀", text: Binding(
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
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .glassSurface(cornerRadius: 12)

            // 第二行：筛选工具条（作者/排序/范围/深搜 + 结果统计）
            HStack(spacing: 7) {
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

                Spacer(minLength: 8)

                Text("\(state.filteredCommits.count) / \(state.commits.count) 条")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .help("筛选后 / 已加载的提交数")

                ActionButton(title: "深度搜索", icon: "sparkle.magnifyingglass") {
                    Task { await state.deepSearch() }
                }
                .disabled(state.isBusy || state.historyQuery.isEmpty)
                .help("扫描完整历史（按文件、日期范围搜索时需要）")
            }
            .padding(.horizontal, 4)

            // 第三行：状态说明（有筛选时才占位，避免空提示常驻）
            HStack(spacing: 8) {
                if let author = state.historyAuthorFilter {
                    HStack(spacing: 5) {
                        StatusBadge(text: "作者：\(author)", tint: GlassPalette.violet)
                        Button("清除") { state.toggleAuthorFilter(author) }
                            .buttonStyle(.plain)
                            .font(.system(size: 10))
                            .foregroundStyle(GlassPalette.violet)
                    }
                }
                if state.needsDeepSearch {
                    Text("按文件 / 日期搜索需点「深度搜索」执行 git 查询")
                        .font(.system(size: 10))
                        .foregroundStyle(GlassPalette.violet.opacity(0.9))
                } else if state.historyQuery.isEmpty && state.historyAuthorFilter == nil {
                    Text("彩色轨道 = 分支 / 合并关系 · 输入即时过滤，零 git 命令")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
                HStack(spacing: 5) {
                    ForEach(GlassPalette.lanes.prefix(4), id: \.self) { color in
                        Circle().fill(color.opacity(0.85)).frame(width: 4.5, height: 4.5)
                    }
                }
                .opacity(state.historyQuery.isEmpty && state.historyAuthorFilter == nil ? 1 : 0)
            }
            .padding(.horizontal, 4)
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
            ScrollView {
                HStack(alignment: .top, spacing: 0) {
                    // 连续轨道背景层：一张 Canvas 画整列，线条跨行贯通
                    CommitGraphColumn(commits: state.filteredCommits,
                                      rowHeight: Self.rowHeight)
                        .padding(.top, 4)
                    // 行内容层：固定行高与轨道对齐
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(state.filteredCommits.enumerated()), id: \.element.id) { index, commit in
                            commitRow(commit)
                                .staggered(index)
                        }
                    }
                    .padding(.vertical, 4)
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
            .background(
                selected ? GlassPalette.accent.opacity(0.10) : Color.clear,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .animation(Motion.snappy, value: selected)
        .help("打开提交详情：元信息、变更文件、遴选 / 还原 / 打标签")
    }

    private func refChips(_ refs: String) -> [String] {
        let parts: [String] = refs.split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return Array(parts.prefix(3))
    }
}
