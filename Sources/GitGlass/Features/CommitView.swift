import SwiftUI
import GitCore

/// 提交页：勾选 → 暂存 → 写一句说明 → 提交，流程线性且每步可回退。
struct CommitView: View {
    @Environment(AppState.self) private var state
    @State private var showDiscardConfirm = false
    @State private var showDiscardAllConfirm = false
    @State private var treeMode = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let prefixes = ["feat", "fix", "docs", "refactor", "test", "chore"]

    var body: some View {
        if state.currentRepository == nil {
            EmptyStateView(title: "还没有仓库", message: "先在左侧添加一个 Git 仓库。", icon: "folder")
        } else {
            VStack(alignment: .leading, spacing: 0) {
                if state.diffFilePath.isEmpty {
                    // 普通模式：文件列表独占（原右侧 diff 栏取消，列表全宽）
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            fileList
                        }
                        .padding(.vertical, 6)
                        .padding(.bottom, 4)
                    }
                    .onTapGesture { commitEditorFocused = false }
                } else {
                    // 沉浸模式：点击文件后全宽大画面查看变更，返回回列表。
                    // layoutPriority(1)：diff 面板优先占高度，绝不被底部
                    // 提交栏（TextEditor 撑高时）挤压成 0 高空白。
                    immersiveDiff
                        .layoutPriority(1)
                    Spacer(minLength: 0)
                }
                // 提交说明卡钉在底部：文件区先滚动，写说明和提交按钮常驻可见
                composer
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
                    .padding(.bottom, 6)
            }
            .alert("确定丢弃所选文件的改动？", isPresented: $showDiscardConfirm) {
                Button("取消", role: .cancel) {}
                Button("丢弃改动", role: .destructive) {
                    Task { await state.discardSelected() }
                }
            } message: {
                Text("这会还原到最近一次提交或暂存的状态，无法撤销。未跟踪的新文件不受影响。")
            }
            .alert("确定丢弃全部改动？", isPresented: $showDiscardAllConfirm) {
                Button("取消", role: .cancel) {}
                Button("全部丢弃", role: .destructive) {
                    Task { await state.discardAllChanges() }
                }
            } message: {
                Text("工作区所有改动（含已暂存与未暂存）都会被还原，无法撤销。这是不可恢复的操作。")
            }
        }
    }

    // MARK: 提交说明

    /// 输入框默认单行高（36），聚焦后撑到多行（110），失焦回落。
    @FocusState private var commitEditorFocused: Bool

    /// 底部提交栏 v4（极简一行）：
    /// [前缀][⋯次要操作] [输入框——————] [提交并推送] [提交]
    /// 次要操作全部收进菜单，主操作只留两个小按钮；中间内容最大化。
    private var composer: some View {
        HStack(alignment: .center, spacing: 8) {
            // 左：前缀下拉
            Menu {
                ForEach(Self.prefixes, id: \.self) { prefix in
                    Button(prefix) { state.appendCommitPrefix(prefix) }
                }
            } label: {
                Image(systemName: "text.prepend")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .frame(width: 26, height: 26)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("插入快捷前缀：feat / fix / docs …")

            // 中：输入框（默认矮，聚焦撑高）
            ZStack(alignment: .topLeading) {
                TextEditor(text: Binding(
                    get: { state.commitMessage },
                    set: { state.commitMessage = $0 }
                ))
                .font(.system(size: 12.5))
                .focused($commitEditorFocused)
                .frame(height: commitEditorFocused ? 88 : 30, alignment: .top)
                .padding(.horizontal, 8)
                .padding(.top, 7)
                .padding(.bottom, 3)
                .scrollContentBackground(.hidden)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(commitEditorFocused
                                ? GlassPalette.accent.opacity(0.45)
                                : Color.primary.opacity(0.08),
                                lineWidth: commitEditorFocused ? 1.5 : 1)
                )
                .animation(reduceMotion ? nil : Motion.snappy, value: commitEditorFocused)

                if state.commitMessage.isEmpty && !commitEditorFocused {
                    HStack(spacing: 6) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 10))
                        Text("一句提交说明，点此展开…（⌘⏎ 提交并推送）")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity)

            // 右：两个主按钮（小号，带文字）
            Button {
                Task { await state.commit(andPush: true) }
            } label: {
                Label("提交并推送", systemImage: "paperplane.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(GlassPalette.mint)
            .disabled(!canCommit)
            .keyboardShortcut(.return, modifiers: .command)
            .help("提交后自动推送；首次推送会建立上游关联（⌘⏎）")

            Button {
                Task { await state.commit() }
            } label: {
                Text("提交")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .disabled(!canCommit)
            .help("只提交不推送")
        }
        .padding(.horizontal, 2)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }



    /// 次要操作小按钮：图标 + 文字，视觉轻但可读（区别于主按钮）。
    private func secondaryButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 10.5, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .contentShape(Rectangle())
        .glassPill(interactive: true)
    }

    private var canCommit: Bool {
        !state.stagedFiles.isEmpty
            && !state.commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !state.isBusy
    }

    // MARK: 文件列表

    private var fileList: some View {
        GlassCard(title: "代码变更", icon: "doc.on.doc",
                  help: "勾选 → 暂存 → 写说明 → 提交。点文件名全屏看差异；悬停文件行快速暂存 / 丢弃。",
                  helpSteps: Teachings.commitFiles.steps,
                  helpFootnote: Teachings.commitFiles.footnote) {
            VStack(alignment: .leading, spacing: 12) {
                if !state.status.isClean {
                    HStack(spacing: 8) {
                        Picker("视图", selection: $treeMode) {
                            Label("列表", systemImage: "list.bullet").tag(false)
                            Label("目录树", systemImage: "folder").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 140)
                        Spacer(minLength: 0)
                        Text("\(state.status.files.count) 个文件")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.tertiary)

                        // 变更操作统一入口：暂存 / 储藏 / 丢弃都在这
                        Menu {
                            Section("暂存") {
                                Button("暂存所选 (\(state.selectedFilePaths.count))") {
                                    Task { await state.stageSelected() }
                                }
                                .disabled(state.selectedFilePaths.isEmpty || state.isBusy)
                                Button("暂存全部改动") { Task { await state.stageAll() } }
                                    .disabled(state.isBusy)
                                Button("取消暂存所选") { Task { await state.unstageSelected() } }
                                    .disabled(state.selectedFilePaths.isEmpty || state.isBusy)
                            }
                            Section("储藏") {
                                Button("储藏当前改动") { Task { await state.stashPush() } }
                                    .disabled(state.isBusy)
                            }
                            Section("丢弃（危险，二次确认）") {
                                Button("丢弃所选改动") { showDiscardConfirm = true }
                                    .disabled(state.selectedFilePaths.isEmpty || state.isBusy)
                                Button("丢弃全部改动") { showDiscardAllConfirm = true }
                                    .disabled(state.isBusy)
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 12, weight: .semibold))
                                .frame(width: 24, height: 24)
                                .contentShape(Rectangle())
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .help("暂存 / 储藏 / 丢弃：变更操作统一入口")
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
                        // Sourcetree 式强对比分组：色条 + 标题 + 计数 + 底色区分
                        if !state.stagedFiles.isEmpty {
                            sectionHeader(title: "已暂存", count: state.stagedFiles.count,
                                          tint: GlassPalette.mint,
                                          caption: "将进入下次提交")
                            VStack(spacing: 2) {
                                ForEach(Array(state.stagedFiles.enumerated()), id: \.element.id) { index, file in
                                    fileRow(file).staggered(index)
                                }
                            }
                            .padding(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(GlassPalette.mint.opacity(0.06),
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        if !state.unstagedFiles.isEmpty {
                            sectionHeader(title: "未暂存改动", count: state.unstagedFiles.count,
                                          tint: GlassPalette.amber,
                                          caption: "勾选后点 + 暂存")
                            .padding(.top, state.stagedFiles.isEmpty ? 0 : 10)
                            VStack(spacing: 2) {
                                ForEach(Array(state.unstagedFiles.enumerated()), id: \.element.id) { index, file in
                                    fileRow(file).staggered(index)
                                }
                            }
                            .padding(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(GlassPalette.amber.opacity(0.05),
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 380, maxWidth: .infinity)
    }

    /// Sourcetree 式分组头：色条 + 标题 + 计数徽标 + 用途说明
    private func sectionHeader(title: String, count: Int, tint: Color, caption: String) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(tint)
                .frame(width: 4, height: 14)
            Text(title)
                .font(.system(size: 12, weight: .bold))
            Text("\(count)")
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(tint.opacity(0.14), in: Capsule())
            Text(caption)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
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

    /// 全宽沉浸式 diff 视图：文件名 + 返回 + 内容铺满
    private var immersiveDiff: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                Button {
                    state.diffFilePath = ""
                    state.diffText = ""
                    state.imageDiff = nil
                    state.imageDiffPath = nil
                } label: {
                    Label("返回列表", systemImage: "chevron.left")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.primary.opacity(0.06),
                                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
                .help("回到文件列表（⎋）")

                Text((state.diffFilePath as NSString).lastPathComponent)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(state.diffFilePath)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HelpQuestionButton(tip: Teachings.commitDiff, arrowEdge: .bottom)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
            .padding(.top, 6)
            .padding(.bottom, 8)

            DiffViewerPanel(source: .commit)
                .frame(maxHeight: .infinity)
        }
    }


}
