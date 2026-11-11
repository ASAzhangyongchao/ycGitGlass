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
            VStack(alignment: .leading, spacing: 13) {
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
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(state.filteredCommits.enumerated()), id: \.element.id) { index, commit in
                        commitRow(commit)
                            .staggered(index)
                        if index < state.filteredCommits.count - 1 {
                            Divider().opacity(0.45)
                        }
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
            HStack(alignment: .center, spacing: 9) {
                CommitGraphCanvas(graph: commit.graph, compact: true)

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
            .padding(.vertical, 8)
            .padding(.horizontal, 7)
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
