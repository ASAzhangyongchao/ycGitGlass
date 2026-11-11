import SwiftUI
import AppKit
import GitCore

/// 遴选 / 还原冲突的可视化处理面板：列出冲突文件，选一侧或标记已解决，再继续操作。
struct ConflictPanel: View {
    @Environment(AppState.self) private var state
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let operation: String

    private var hasConflicts: Bool { !state.conflictedFiles.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if hasConflicts {
                Text("待解决的冲突文件 · \(state.conflictedFiles.count)")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(state.conflictedFiles.enumerated()), id: \.element) { index, file in
                        conflictRow(file).staggered(index)
                    }
                }
                InfoHint(
                    text: "「采用当前分支」保留你这边的内容（ours），「采用对方」用被遴选提交的内容（theirs）。也可以自己在编辑器里改完冲突标记后点「已手动解决」。",
                    tint: GlassPalette.blue
                )
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(GlassPalette.mint)
                    Text("没有未解决的冲突，可以继续完成\(operation)。")
                        .font(.system(size: 12))
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background(GlassPalette.mint.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            HStack(spacing: 9) {
                ActionButton(title: "继续\(operation)", icon: "arrow.right", prominent: true) {
                    Task { await state.continueOperation() }
                }
                .disabled(hasConflicts || state.isBusy)
                .help(hasConflicts ? "先把上面的冲突文件全部处理完" : "用已有提交信息完成这次\(operation)")

                ActionButton(title: "中止当前操作", icon: "xmark.circle", tint: GlassPalette.rose) {
                    Task { await state.abortOperation() }
                }
                .disabled(state.isBusy)

                Spacer(minLength: 0)
                SmallIconButton(icon: "folder", helpText: "在 Finder 中打开仓库目录") {
                    if let path = state.currentPath {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
                    }
                }
            }
        }
        .padding(16)
        .glassSurface(cornerRadius: 18, tint: GlassPalette.amber.opacity(0.12))
        .cardShadow()
        .panelTransition()
        .animation(reduceMotion ? nil : Motion.spring, value: state.conflictedFiles.count)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 17))
                .foregroundStyle(GlassPalette.amber)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(operation)操作进行中\(hasConflicts ? " · 有冲突" : "")")
                    .font(.system(size: 13, weight: .semibold))
                Text("冲突解决后会自动刷新，全部处理完即可继续；也可以直接中止回到操作前。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
        }
    }

    private func conflictRow(_ file: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 11))
                .foregroundStyle(GlassPalette.rose)
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 2) {
                Text((file as NSString).lastPathComponent)
                    .font(.system(size: 12, weight: .medium))
                Text(file)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            ActionButton(title: "采用当前分支", icon: "arrow.left") {
                Task { await state.resolveConflict(file, choose: .ours) }
            }
            .disabled(state.isBusy)
            ActionButton(title: "采用对方", icon: "arrow.right") {
                Task { await state.resolveConflict(file, choose: .theirs) }
            }
            .disabled(state.isBusy)
            ActionButton(title: "已手动解决", icon: "checkmark") {
                Task { await state.markConflictResolved(file) }
            }
            .disabled(state.isBusy)
        }
        .padding(11)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}
