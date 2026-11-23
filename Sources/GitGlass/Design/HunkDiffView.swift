import SwiftUI
import GitCore

/// 提交页的 diff：按 hunk 分块渲染，每块可直接「暂存 / 取消暂存」。
///
/// SourceTree / GitHub Desktop 的 partial staging：不想整文件提交时，
/// 只把某一处改动放进索引区。这里不做行级（行级要处理新增/删除配对，
/// 收益低且容易出错），只做块级——覆盖日常九成场景。
struct HunkDiffView: View {
    @Environment(AppState.self) private var state
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let text: String
    /// 当前 diff 对应的文件（用来判断方向：已暂存 → 按钮变「取消暂存此块」）
    let file: FileChange?

    private var parsed: UnifiedDiff.Parsed {
        UnifiedDiff.parse(text)
    }

    private var hunks: [DiffHunk] {
        parsed.hunks
    }

    var body: some View {
        // 只做纵向滚动：横向 ScrollView 里 maxWidth/.infinity 会拿到无界宽度，
        // 卡片会被撑到无限宽、视口里什么也看不到（离屏快照实测空白）。
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 8) {
                if parsed.fileHeader.contains(where: { $0.hasPrefix("Binary files") })
                    || parsed.fileHeader.contains(where: { $0.hasPrefix("GIT binary patch") }) {
                    Text("二进制文件不支持按块暂存，请整文件暂存。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(8)
                }
                ForEach(hunks) { hunk in
                    hunkCard(hunk)
                }
                if hunks.isEmpty {
                    DiffTextView(text: text)
                }
            }
            .padding(10)
        }
        .background(.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: 单块

    private func hunkCard(_ hunk: DiffHunk) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(hunk)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(hunk.lines.enumerated()), id: \.offset) { _, line in
                    lineRow(line)
                }
            }
            .padding(.vertical, 2)
        }
        .background(Color.primary.opacity(0.035),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        )
        .contextMenu {
            if let file {
                Button {
                    apply(to: hunk, on: file)
                } label: {
                    Label(file.isStaged ? "取消暂存此块" : "暂存此块",
                          systemImage: file.isStaged ? "minus.circle" : "plus.circle")
                }
                Button {
                    copyToPasteboard(hunk.lines.joined(separator: "\n"))
                } label: {
                    Label("复制这一块", systemImage: "doc.on.doc")
                }
            }
        }
    }

    private func header(_ hunk: DiffHunk) -> some View {
        HStack(spacing: 7) {
            Text(hunk.header)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(GlassPalette.violet)
                .lineLimit(1)
            Text("+\(hunk.added)")
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(GlassPalette.mint)
            Text("−\(hunk.removed)")
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(GlassPalette.rose)
            Spacer(minLength: 12)
            if let file {
                Button {
                    apply(to: hunk, on: file)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: file.isStaged ? "minus.circle" : "plus.circle")
                            .font(.system(size: 9.5, weight: .semibold))
                        Text(file.isStaged ? "取消暂存此块" : "暂存此块")
                            .font(.system(size: 10, weight: .semibold))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(file.isStaged ? GlassPalette.amber : GlassPalette.mint)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    (file.isStaged ? GlassPalette.amber : GlassPalette.mint).opacity(0.12),
                    in: Capsule()
                )
                .help(file.isStaged
                      ? "把这一块从索引区撤回，其他块保持暂存"
                      : "只把这一块放进索引区，其他改动留在工作区")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05))
    }

    private func lineRow(_ line: String) -> some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(barColor(line))
                .frame(width: 2)
            Text(line.isEmpty ? " " : line)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(textColor(line))
                .textSelection(.enabled)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 7)
                .padding(.trailing, 12)
                .padding(.vertical, 0.5)
        }
        .background(bgColor(line))
    }

    private func apply(to hunk: DiffHunk, on file: FileChange) {
        Task {
            if file.isStaged {
                await state.unstageHunk(hunk, file: file)
            } else {
                await state.stageHunk(hunk, file: file)
            }
        }
    }

    // MARK: 配色

    private func barColor(_ line: String) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") { return GlassPalette.mint.opacity(0.75) }
        if line.hasPrefix("-") && !line.hasPrefix("---") { return GlassPalette.rose.opacity(0.75) }
        return .clear
    }

    private func bgColor(_ line: String) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") { return GlassPalette.mint.opacity(0.09) }
        if line.hasPrefix("-") && !line.hasPrefix("---") { return GlassPalette.rose.opacity(0.08) }
        return .clear
    }

    private func textColor(_ line: String) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") { return GlassPalette.mint }
        if line.hasPrefix("-") && !line.hasPrefix("---") { return GlassPalette.rose }
        if line.hasPrefix("\\") { return Color(nsColor: .tertiaryLabelColor) }
        return Color.primary
    }
}
