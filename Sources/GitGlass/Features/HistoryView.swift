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
                }
                .animation(reduceMotion ? nil : Motion.slide, value: state.showDetailPanel)
            }
            .padding(.vertical, 6)
            .padding(.bottom, 20)
        }
    }

    private var searchBar: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索说明 / 作者 / hash，或用 author: message: file: hash: since:", text: Binding(
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
                }

                authorMenu

                sortMenu

                Toggle("全部分支", isOn: Binding(
                    get: { state.historyAllBranches },
                    set: { state.historyAllBranches = $0 }
                ))
                .toggleStyle(.checkbox)
                .font(.system(size: 11.5))
                .onChange(of: state.historyAllBranches) { _, _ in
                    Task { await state.refresh(reason: .manual) }
                }

                ActionButton(title: "深度搜索", icon: "sparkle.magnifyingglass", prominent: true) {
                    Task { await state.deepSearch() }
                }
                .disabled(state.isBusy || state.historyQuery.isEmpty)
            }
            .padding(12)
            .glassSurface(cornerRadius: 14)

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
                    InfoHint(text: "按文件、日期范围搜索需要扫描完整历史，点右侧「深度搜索」才会执行 git 查询。",
                             tint: GlassPalette.violet)
                } else {
                    Text("输入时即时过滤已加载的 \(state.commits.count) 条记录，不产生任何 git 命令。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
                HStack(spacing: 5) {
                    ForEach(GlassPalette.lanes.prefix(4), id: \.self) { color in
                        Circle().fill(color.opacity(0.85)).frame(width: 5, height: 5)
                    }
                    Text("彩色轨道 = 分支 / 合并关系")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
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
