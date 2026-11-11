import SwiftUI
import GitCore

/// 提交页：勾选 → 暂存 → 写一句说明 → 提交，流程线性且每步可回退。
struct CommitView: View {
    @Environment(AppState.self) private var state
    @State private var showDiscardConfirm = false
    @State private var treeMode = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let prefixes = ["feat", "fix", "docs", "refactor", "test", "chore"]

    var body: some View {
        if state.currentRepository == nil {
            EmptyStateView(title: "还没有仓库", message: "先在左侧添加一个 Git 仓库。", icon: "folder")
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(alignment: .top, spacing: 18) {
                            fileList
                            diffPanel
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.bottom, 4)
                }
                // 提交说明卡钉在底部：文件区先滚动，写说明和提交按钮常驻可见
                composer
                    .padding(.top, 2)
                // 底部固定刷新信息条（不再随内容滚动，也给底部留出呼吸空间）
                HStack(spacing: 6) {
                    Image(systemName: "bolt.horizontal.fill").font(.system(size: 9))
                    if let date = state.lastRefreshed {
                        Text("上次刷新 \(date.formatted(.dateTime.hour().minute())) · \(state.lastRefreshReason)")
                    } else {
                        Text("点顶栏「刷新」读取最新状态")
                    }
                    Spacer()
                    Text("暂存/丢弃：悬停文件行右侧按钮")
                        .foregroundStyle(.tertiary)
                }
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.top, 8)
                .padding(.bottom, 14)
            }
            .alert("确定丢弃所选文件的改动？", isPresented: $showDiscardConfirm) {
                Button("取消", role: .cancel) {}
                Button("丢弃改动", role: .destructive) {
                    Task { await state.discardSelected() }
                }
            } message: {
                Text("这会还原到最近一次提交或暂存的状态，无法撤销。未跟踪的新文件不受影响。")
            }
        }
    }

    // MARK: 提交说明

    /// 输入框默认单行高（36），聚焦后撑到多行（110），失焦回落。
    @FocusState private var commitEditorFocused: Bool

    private var composer: some View {
        GlassCard(title: "写一句提交说明", icon: "square.and.pencil",
                  help: "说清「做了什么」即可，例如：修复登录页空白。\n也可先点一个快捷前缀（feat/fix/…），再补一句说明。写完点右下「提交」或「提交并推送」。") {
            VStack(alignment: .leading, spacing: 11) {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: Binding(
                        get: { state.commitMessage },
                        set: { state.commitMessage = $0 }
                    ))
                    .font(.system(size: 13))
                    .focused($commitEditorFocused)
                    .frame(height: commitEditorFocused ? 110 : 36)
                    .padding(6)
                    .scrollContentBackground(.hidden)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(commitEditorFocused
                                    ? GlassPalette.accent.opacity(0.45)
                                    : Color.primary.opacity(0.08),
                                    lineWidth: commitEditorFocused ? 1.5 : 1)
                    )
                    .animation(reduceMotion ? nil : Motion.snappy, value: commitEditorFocused)

                    // 占位提示
                    if state.commitMessage.isEmpty && !commitEditorFocused {
                        Text("一句提交说明，点此处展开…")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 12)
                            .padding(.top, 12)
                            .allowsHitTesting(false)
                    }
                }

                HStack(spacing: 7) {
                    Text("快捷前缀").font(.system(size: 11)).foregroundStyle(.secondary)
                    ForEach(Self.prefixes, id: \.self) { prefix in
                        Button(prefix) { withAnimation(Motion.snappy) { state.appendCommitPrefix(prefix) } }
                            .buttonStyle(.plain)
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .glassPill(interactive: true)
                    }
                    Spacer(minLength: 0)
                }

                // 暂存操作：紧凑图标按钮一行放下，文字提示在悬停 help
                HStack(spacing: 6) {
                    ActionButton(title: "暂存所选 (\(state.selectedFilePaths.count))", icon: "plus.circle",
                                 compact: true) {
                        Task { await state.stageSelected() }
                    }
                    .disabled(state.selectedFilePaths.isEmpty || state.isBusy)
                    .help("暂存所选 (\(state.selectedFilePaths.count))")

                    ActionButton(title: "取消暂存", icon: "minus.circle", compact: true) {
                        Task { await state.unstageSelected() }
                    }
                    .disabled(state.selectedFilePaths.isEmpty || state.isBusy)
                    .help("取消暂存所选")

                    ActionButton(title: "暂存全部", icon: "checkmark.circle", compact: true) {
                        Task { await state.stageAll() }
                    }
                    .disabled(state.status.isClean || state.isBusy)
                    .help("暂存全部改动")

                    ActionButton(title: "储藏当前改动", icon: "archivebox", compact: true) {
                        Task { await state.stashPush() }
                    }
                    .disabled(state.isBusy || state.status.isClean)
                    .help("储藏当前改动，切分支或遴选前很方便")

                    Spacer(minLength: 0)
                }

                // 提交动作行
                HStack(spacing: 6) {
                    if state.status.stagedCount == 0 {
                        Text("先勾选文件暂存，提交按钮才会亮")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 0)

                    ActionButton(title: "提交", icon: "arrow.up.doc", prominent: true,
                                 disabled: !canCommit) {
                        Task { await state.commit() }
                    }
                    .help("把已暂存的文件生成一条提交")

                    ActionButton(title: "提交并推送", icon: "paperplane.fill",
                                 tint: GlassPalette.mint, prominent: true, disabled: !canCommit) {
                        Task { await state.commit(andPush: true) }
                    }
                    .help("提交后自动推送；首次推送会建立上游关联")
                }
            }
        }
    }

    private var canCommit: Bool {
        !state.stagedFiles.isEmpty
            && !state.commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !state.isBusy
    }

    // MARK: 文件列表

    private var fileList: some View {
        GlassCard(title: "代码变更", icon: "doc.on.doc",
                  subtitle: "点击文件名可在右侧查看差异") {
            VStack(alignment: .leading, spacing: 12) {
                if !state.status.isClean {
                    HStack(spacing: 8) {
                        Picker("视图", selection: $treeMode) {
                            Label("列表", systemImage: "list.bullet").tag(false)
                            Label("目录树", systemImage: "folder").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 156)
                        Spacer(minLength: 0)
                        Text("\(state.status.files.count) 个文件")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.tertiary)
                    }
                    .animation(Motion.snappy, value: treeMode)
                }
                if state.status.isClean {
                    VStack(spacing: 10) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 28))
                            .foregroundStyle(GlassPalette.mint)
                        Text("工作区干净，没有待提交的改动")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 150)
                } else {
                    if treeMode {
                        FileTreeView(
                            nodes: state.status.files.map(\.treeNode),
                            selectedPath: state.diffFilePath
                        ) { node in
                            if let file = state.status.files.first(where: { $0.path == node.path }) {
                                Task { await state.loadDiff(for: file) }
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                    } else {
                        if !state.stagedFiles.isEmpty {
                            Text("已暂存 · \(state.stagedFiles.count)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(GlassPalette.mint)
                            ForEach(Array(state.stagedFiles.enumerated()), id: \.element.id) { index, file in
                                fileRow(file).staggered(index)
                            }
                        }
                        if !state.unstagedFiles.isEmpty {
                            Text("未暂存 / 未跟踪 · \(state.unstagedFiles.count)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(GlassPalette.amber)
                                .padding(.top, 2)
                            ForEach(Array(state.unstagedFiles.enumerated()), id: \.element.id) { index, file in
                                fileRow(file).staggered(index)
                            }
                        }
                    }
                    HStack(spacing: 8) {
                        Button("丢弃所选改动") { showDiscardConfirm = true }
                            .buttonStyle(.plain)
                            .font(.system(size: 11))
                            .foregroundStyle(GlassPalette.rose)
                            .disabled(state.selectedFilePaths.isEmpty || state.isBusy)
                            .help("危险操作，会二次确认")
                        Spacer()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 380, maxWidth: .infinity)
    }

    private func fileRow(_ file: FileChange) -> some View {
        let selected = state.selectedFilePaths.contains(file.path)
        return HStack(spacing: 9) {
            Button {
                withAnimation(Motion.snappy) { state.toggleFile(file.path) }
            } label: {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(selected ? GlassPalette.accent : .secondary)
            }
            .buttonStyle(.plain)

            StatusBadge(text: file.badge, tint: badgeColor(file))

            Button {
                Task { await state.loadDiff(for: file) }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.fileName)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    if file.directory != "." && !file.directory.isEmpty {
                        Text(file.directory)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(file.path)

            // GitHub Desktop 式行内悬停操作：悬停浮出，离开隐去
            HoverFileActions(file: file)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            state.diffFilePath == file.path ? GlassPalette.accent.opacity(0.10) : Color.primary.opacity(0.035),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .animation(Motion.snappy, value: selected)
    }

    private func badgeColor(_ file: FileChange) -> Color {
        if file.isConflict { return GlassPalette.rose }
        if file.isUntracked { return GlassPalette.mint }
        if file.badge == "删除" { return GlassPalette.rose }
        if file.isStaged { return GlassPalette.blue }
        return GlassPalette.amber
    }

    // MARK: 差异预览

    private var diffPanel: some View {
        GlassCard(title: "差异预览", icon: "text.alignleft",
                  subtitle: state.diffFilePath.isEmpty ? "点击左侧文件查看" : state.diffFilePath) {
            if let imageDiff = state.imageDiff, let imagePath = state.imageDiffPath, imagePath == state.diffFilePath {
                // 图片变更：并排 / 滑块叠加 / 差异高亮
                ImageDiffView(pair: imageDiff, filePath: imagePath)
            } else if state.isLoadingImageDiff {
                VStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("正在读取图片…")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            } else if state.diffText.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("选中一个文件后，这里显示逐行改动")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    Text("图片文件支持并排与叠加对比")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                DiffTextView(text: state.diffText)
                    .frame(minHeight: 260, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 340, maxWidth: .infinity)
    }
}
