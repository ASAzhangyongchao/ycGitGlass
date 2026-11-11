import SwiftUI
import GitCore

/// 提交详情 Inspector：完整元信息 + 统计 + 操作 + 变更文件树 + 逐文件 diff。
struct CommitDetailPanel: View {
    @Environment(AppState.self) private var state
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showCherryPickConfirm = false
    @State private var showRevertConfirm = false
    @State private var showTagSheet = false
    @State private var tagName = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if let detail = state.commitDetail {
                    metadata(detail)
                    statistics(detail)
                    actions
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
        .frame(minWidth: 350, idealWidth: 380, maxWidth: 400)
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
            Text("对这条提交做什么")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 7) {
                ActionButton(title: "遴选", icon: "arrow.triangle.merge", prominent: true) {
                    showCherryPickConfirm = true
                }
                .help("Sourcetree 的 Cherry-pick：把这条提交复制到当前分支")
                ActionButton(title: "还原", icon: "arrow.uturn.backward", tint: GlassPalette.rose) {
                    showRevertConfirm = true
                }
                .help("生成一条反向提交，撤销这条提交的改动")
            }
            HStack(spacing: 7) {
                ActionButton(title: "定位", icon: "target") {
                    state.locateSelectedInList()
                }
                .help("在左侧列表中定位这条提交：滚动过去并高亮闪烁")
                ActionButton(title: "打标签", icon: "tag") { showTagSheet = true }
                ActionButton(title: "复制 hash", icon: "doc.on.doc") {
                    if let hash = state.selectedCommit?.hash {
                        copyToPasteboard(hash)
                        state.notice = "已复制完整提交号"
                    }
                }
            }
        }
        .disabled(state.isBusy)
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
