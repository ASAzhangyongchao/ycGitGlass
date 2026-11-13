import SwiftUI
import GitCore

/// 提交详情 Inspector：完整元信息 + 统计 + 操作 + 变更文件树 + 逐文件 diff。
struct CommitDetailPanel: View {
    @Environment(AppState.self) private var state
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showCherryPickConfirm = false
    @State private var showRevertConfirm = false
    @State private var showTagSheet = false
    @State private var showGraphPopover = false
    @State private var tagName = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if let detail = state.commitDetail {
                    metadata(detail)
                    statistics(detail)
                    actions
                    graphSection
                    if !detail.body.isEmpty {
                        bodySection(detail.body)
                    }
                    filesSection(detail)
                    // diff 已移至独立的 DiffViewerPanel（历史页第三栏），
                    // 这里不再内嵌 210pt 小框——阅读体验交给全高面板。
                } else {
                    loading
                }
            }
            .padding(16)
        }
        .frame(minWidth: 300, idealWidth: 360, maxWidth: 380)
        .glassSurface(cornerRadius: 20, tint: GlassPalette.blue.opacity(0.06))
        .cardShadow(elevated: true)
        .panelTransition()
        .alert("遴选到当前分支？", isPresented: $showCherryPickConfirm) {
            Button("取消", role: .cancel) {}
            Button("遴选") {
                if let commit = state.selectedCommit { Task { await state.cherryPick(commit) } }
            }
        } message: {
            Text("会把这条提交的改动复制成一条新提交，原提交保持不变。若内容冲突，可到「储藏」页一键中止。")
        }
        .alert("生成反向提交？", isPresented: $showRevertConfirm) {
            Button("取消", role: .cancel) {}
            Button("还原", role: .destructive) {
                if let commit = state.selectedCommit { Task { await state.revert(commit) } }
            }
        } message: {
            Text("会新增一条撤销该提交改动的提交，不改写已有历史，适合已经推送出去的提交。")
        }
        .sheet(isPresented: $showTagSheet) {
            TextInputSheet(
                title: "给这条提交打标签",
                placeholder: "例如 v1.2.0",
                confirmTitle: "创建标签",
                hint: "标签会打在选中的这条提交上，创建后可到「储藏」页查看和管理。",
                text: $tagName
            ) {
                if let hash = state.selectedCommit?.hash {
                    Task { await state.addTag(tagName, to: hash) }
                }
                tagName = ""
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text("提交详情")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(state.selectedCommit?.subject ?? "—")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 7) {
                    StatusBadge(text: state.selectedCommit?.shortHash ?? "—", tint: GlassPalette.blue)
                    if state.commitDetail?.isMerge == true {
                        StatusBadge(text: "合并提交", tint: GlassPalette.violet)
                    }
                    if let ref = state.commitDetail?.refs, !ref.isEmpty {
                        Text(ref)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 6)
            SmallIconButton(icon: "xmark", helpText: "关闭详情") {
                withComfortableAnimation(reduceMotion) { state.closeDetail() }
            }
        }
    }

    private func metadata(_ detail: CommitDetail) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            detailRow("提交号", detail.shortHash, mono: true) {
                copyToPasteboard(detail.hash)
                state.notice = "已复制完整提交号"
            }
            detailRow("作者", "\(detail.authorName) <\(detail.authorEmail)>")
            detailRow("提交时间", Self.formatDate(detail.authorDate))
            if detail.committerName != detail.authorName || detail.committerEmail != detail.authorEmail {
                detailRow("提交者", "\(detail.committerName) <\(detail.committerEmail)>")
            }
            detailRow("父提交", detail.parents.isEmpty ? "无（仓库的第一次提交）" : detail.parents.map { String($0.prefix(8)) }.joined(separator: ", "), mono: true)
        }
        .padding(12)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func detailRow(_ label: String, _ value: String, mono: Bool = false,
                           copy: (() -> Void)? = nil) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .frame(width: 54, alignment: .leading)
            Text(value)
                .font(.system(size: 10.5, design: mono ? .monospaced : .default))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            if let copy {
                SmallIconButton(icon: "doc.on.doc", helpText: "复制") { copy() }
            }
        }
    }

    private func statistics(_ detail: CommitDetail) -> some View {
        HStack(spacing: 8) {
            statChip("\(detail.fileCount)", "文件", GlassPalette.blue)
            statChip("+\(detail.insertions)", "新增行", GlassPalette.mint)
            statChip("-\(detail.deletions)", "删除行", GlassPalette.rose)
        }
    }

    private func statChip(_ value: String, _ label: String, _ tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .contentTransition(.numericText())
            Text(label).font(.system(size: 9.5)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("对这条提交做什么")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                HelpQuestionButton(tip: Teachings.cherryRevert, arrowEdge: .bottom)
            }
            HStack(spacing: 5) {
                smallActionButton("遴选", icon: "arrow.triangle.merge", tint: GlassPalette.accent) {
                    showCherryPickConfirm = true
                }
                .help("Cherry-pick：把这条提交的改动复制到当前分支")

                smallActionButton("还原", icon: "arrow.uturn.backward", tint: GlassPalette.rose) {
                    showRevertConfirm = true
                }
                .help("生成一条反向提交，撤销这条提交的改动")

                smallActionButton("定位", icon: "target", tint: nil) {
                    state.locateSelectedInList()
                }
                .help("在左侧列表中定位这条提交：滚动过去并高亮闪烁")

                smallActionButton("打标签", icon: "tag", tint: nil) { showTagSheet = true }

                smallActionButton("复制hash", icon: "doc.on.doc", tint: nil) {
                    if let hash = state.selectedCommit?.hash {
                        copyToPasteboard(hash)
                        state.notice = "已复制完整提交号"
                    }
                }
            }
        }
        .disabled(state.isBusy)
    }

    /// 小号操作按钮：一行五个放得下
    private func smallActionButton(_ title: String, icon: String, tint: Color?,
                                    action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                Text(title)
                    .font(.system(size: 9, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background((tint ?? Color.primary).opacity(tint == nil ? 0.05 : 0.10),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint ?? .primary)
    }

    // MARK: 分支图弹层（轨道列折叠后的对应关系出口）

    /// 该提交在提交序列中的位置（用于截取局部上下文）
    private var graphContext: [Commit] {
        guard let hash = state.selectedCommit?.hash else { return [] }
        let all = state.commits
        guard let index = all.firstIndex(where: { $0.hash == hash }) else { return [] }
        let lower = max(0, index - 8)
        let upper = min(all.count, index + 9)
        return Array(all[lower..<upper])
    }

    private var graphSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("分支关系")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 8) {
                    HelpQuestionButton(tip: Teachings.branchPopover, arrowEdge: .bottom)
                    SmallIconButton(icon: "point.3.connected.trianglepath.dotted",
                                    helpText: "在弹层中查看这条提交前后的分支轨道") {
                        showGraphPopover = true
                    }
                }
            }
            if state.selectedCommit?.graph.contains("*") == true
                || state.selectedCommit?.graph.contains("|") == true {
                // 迷你静态示意：单行轨道字符（等宽渲染）
                let graphText = state.selectedCommit?.graph.trimmingCharacters(in: .whitespaces) ?? ""
                HStack(spacing: 4) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(GlassPalette.accent)
                    Text(graphText)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .padding(.vertical, 2)
            }
            if graphContext.isEmpty {
                Text("列表里找不到这条提交（可能在全部分支视图之外）")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .popover(isPresented: $showGraphPopover, arrowEdge: .leading) {
            CommitGraphPopover(commits: graphContext,
                               highlightHash: state.selectedCommit?.hash)
        }
    }

    private func bodySection(_ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("提交说明正文").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.secondary)
            Text(body)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private func filesSection(_ detail: CommitDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("变更文件 · \(detail.changedFiles.count)")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("点文件在右侧看差异")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
            }
            if detail.changedFiles.isEmpty {
                Text("这条提交没有文件变更")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            } else {
                FileTreeView(
                    nodes: detail.changedFiles.map(\.treeNode),
                    selectedPath: state.detailDiffFile,
                    compact: true
                ) { node in
                    Task { await state.loadDetailDiff(file: node.path) }
                }
            }
        }
    }

    private var loading: some View {
        VStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("正在读取提交详情…")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }

    private static func formatDate(_ raw: String) -> String {
        guard raw.count >= 19 else { return raw }
        let end = raw.index(raw.startIndex, offsetBy: 19)
        return String(raw[..<end]).replacingOccurrences(of: "T", with: " ")
    }
}

/// 分支图弹层：展示目标提交前后的局部轨道（±8 条），
/// 轨道列被折叠（并行分支过多）时，这里是分支对应关系的主要出口。
struct CommitGraphPopover: View {
    let commits: [Commit]
    var highlightHash: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(GlassPalette.accent)
                Text("分支轨道 · 上下文")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text("高亮 = 当前提交")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            if commits.isEmpty {
                Text("没有可展示的轨道上下文")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(16)
            } else {
                ScrollView {
                    HStack(alignment: .top, spacing: 0) {
                        CommitGraphColumn(commits: commits,
                                          rowHeight: 44,
                                          laneStep: 11,
                                          maxCharacters: 30,
                                          highlightHash: highlightHash)
                            .padding(.top, 2)
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(commits) { commit in
                                HStack(spacing: 6) {
                                    Text(commit.shortHash)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(commit.hash == highlightHash
                                                         ? GlassPalette.accent : .secondary)
                                    Text(commit.subject)
                                        .font(.system(size: 11,
                                                      weight: commit.hash == highlightHash ? .semibold : .regular))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                .frame(minHeight: 44, alignment: .leading)
                                .padding(.horizontal, 4)
                                .background(commit.hash == highlightHash
                                            ? GlassPalette.accent.opacity(0.10)
                                            : Color.clear)
                                .cornerRadius(7)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                }
                .frame(minWidth: 460, minHeight: 240)
                .frame(maxHeight: 380)
            }
        }
        .frame(width: 520, alignment: .leading)
        .padding(.bottom, 8)
    }
}

