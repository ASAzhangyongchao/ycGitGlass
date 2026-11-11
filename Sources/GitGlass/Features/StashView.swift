import SwiftUI
import GitCore

/// 储藏 + 标签 + 「遴选/还原进行中」的中止入口。
struct StashView: View {
    @Environment(AppState.self) private var state
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stashMessage = ""
    @State private var includeUntracked = true
    @State private var showTagSheet = false
    @State private var pendingStashDrop: StashEntry?
    @State private var pendingTagDelete: String?

    var body: some View {
        if state.currentRepository == nil {
            EmptyStateView(title: "还没有仓库", message: "先在左侧添加一个 Git 仓库。", icon: "archivebox")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let operation = state.inProgressOperation {
                        ConflictPanel(operation: operation)
                    }
                    stashCard
                    tagCard
                }
                .padding(.vertical, 6)
                .padding(.bottom, 22)
            }
            .sheet(isPresented: $showTagSheet) {
                TwoFieldSheet(
                    title: "新建标签",
                    firstLabel: "标签名", firstPlaceholder: "v1.0.0",
                    secondLabel: "附注说明（可选，留空为轻量标签）", secondPlaceholder: "发布说明",
                    confirmTitle: "创建",
                    hint: "默认打在当前 HEAD。要给历史提交打标签，请到「历史」页打开该提交的详情。"
                ) { name, message in
                    Task { await state.addTag(name, message: message) }
                }
            }
            .alert("删除这个储藏？", isPresented: Binding(
                get: { pendingStashDrop != nil },
                set: { if !$0 { pendingStashDrop = nil } }
            )) {
                Button("取消", role: .cancel) { pendingStashDrop = nil }
                Button("删除", role: .destructive) {
                    if let entry = pendingStashDrop { Task { await state.stashDrop(entry) } }
                    pendingStashDrop = nil
                }
            } message: {
                Text("删除后这份储藏的改动无法恢复，请确认已经不需要它。")
            }
            .alert("删除标签？", isPresented: Binding(
                get: { pendingTagDelete != nil },
                set: { if !$0 { pendingTagDelete = nil } }
            )) {
                Button("取消", role: .cancel) { pendingTagDelete = nil }
                Button("删除", role: .destructive) {
                    if let tag = pendingTagDelete { Task { await state.deleteTag(tag) } }
                    pendingTagDelete = nil
                }
            } message: {
                Text("只删除本地标签，不会影响远程服务器的标签。")
            }
        }
    }

    // MARK: 储藏

    private var stashCard: some View {
        GlassCard(title: "储藏改动", icon: "archivebox",
                  subtitle: "临时收起当前改动，切换分支或遴选前特别有用",
                  tint: GlassPalette.violet.opacity(0.06)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 9) {
                    TextField("给这份储藏写句说明（可留空）", text: $stashMessage)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                    Toggle("包含未跟踪文件", isOn: $includeUntracked)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11))
                    ActionButton(title: "储藏当前改动", icon: "tray.and.arrow.down", prominent: true) {
                        Task { await state.stashPush(message: stashMessage, includeUntracked: includeUntracked) }
                        stashMessage = ""
                    }
                    .disabled(state.status.isClean || state.isBusy)
                }

                if state.stashes.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "archivebox")
                            .font(.system(size: 24, weight: .light))
                            .foregroundStyle(.tertiary)
                        Text("还没有储藏记录")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 100)
                } else {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(Array(state.stashes.enumerated()), id: \.element.id) { index, entry in
                            stashRow(entry).staggered(index)
                        }
                    }
                }
                InfoHint(text: "「恢复」保留储藏记录，「恢复并移除」等于 git stash pop。恢复前建议先提交当前改动，避免叠加冲突。")
            }
        }
    }

    private func stashRow(_ entry: StashEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(entry.reflogID)
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(GlassPalette.violet)
                .frame(width: 72, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.displayTitle)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(2)
                HStack(spacing: 8) {
                    if !entry.branch.isEmpty { Label(entry.branch, systemImage: "arrow.triangle.branch") }
                    Text(entry.relativeDate)
                }
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            ActionButton(title: "恢复", icon: "tray.and.arrow.up") {
                Task { await state.stashApply(entry) }
            }
            .disabled(state.isBusy)
            ActionButton(title: "恢复并移除", icon: "arrow.uturn.forward") {
                Task { await state.stashApply(entry, dropAfterApply: true) }
            }
            .disabled(state.isBusy)
            SmallIconButton(icon: "trash", tint: GlassPalette.rose, helpText: "删除这份储藏") {
                pendingStashDrop = entry
            }
        }
        .padding(11)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: 标签

    private var tagCard: some View {
        GlassCard(title: "标签", icon: "tag",
                  subtitle: "给版本发布点做标记，\(state.tags.count) 个本地标签") {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    ActionButton(title: "新建标签", icon: "plus", prominent: true) { showTagSheet = true }
                    Spacer()
                    Text("轻量标签直接指向提交；附注标签可写发布说明")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
                if state.tags.isEmpty {
                    Text("还没有标签。发布版本时可以打一个，例如 v1.0.0。")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 70)
                } else {
                    ForEach(Array(state.tags.enumerated()), id: \.element.id) { index, tag in
                        tagRow(tag).staggered(index)
                    }
                }
            }
        }
    }

    private func tagRow(_ tag: GitTag) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: tag.isAnnotated ? "tag.fill" : "tag")
                .font(.system(size: 12))
                .foregroundStyle(tag.isAnnotated ? GlassPalette.amber : GlassPalette.blue)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(tag.name).font(.system(size: 12, weight: .semibold))
                    StatusBadge(text: tag.isAnnotated ? "附注" : "轻量",
                                tint: tag.isAnnotated ? GlassPalette.amber : GlassPalette.blue)
                }
                HStack(spacing: 8) {
                    Text(tag.target).font(.system(size: 10.5, design: .monospaced))
                    if !tag.message.isEmpty { Text(tag.message).lineLimit(1) }
                }
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            SmallIconButton(icon: "doc.on.doc", helpText: "复制标签名") {
                copyToPasteboard(tag.name)
                state.notice = "已复制标签 \(tag.name)"
            }
            SmallIconButton(icon: "trash", tint: GlassPalette.rose, helpText: "删除本地标签") {
                pendingTagDelete = tag.name
            }
        }
        .padding(11)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
