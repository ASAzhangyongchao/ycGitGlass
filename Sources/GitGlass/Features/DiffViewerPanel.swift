import SwiftUI
import GitCore

/// 历史/提交页的专属 Diff 阅读区（第三栏）：
/// 点提交详情里的变更文件后滑入，与列表同高、占满可用宽度，
/// 替代此前详情面板里 210pt 高的内嵌小框。
struct DiffViewerPanel: View {
    @Environment(AppState.self) private var state
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 数据源：.history 读详情字段（detailDiff），.commit 读工作区字段（diffText）。
    /// 两页写入路径不同，此前只读详情字段导致提交页 diff 恒空态（已修）。
    var source: DiffSource = .history

    enum DiffSource {
        case history, commit

        var title: String { self == .history ? "变更内容" : "工作区变更" }
        var emptyHint: String { self == .history ? "在详情里点一个变更文件" : "在左侧点一个文件" }
        var emptySub: String {
            self == .history ? "这里会以完整高度显示逐行差异或图片对比"
                             : "这里会以完整高度显示这个文件的逐行差异或图片对比"
        }
    }

    private var activeFile: String {
        source == .history ? state.detailDiffFile : state.diffFilePath
    }

    private var activeText: String {
        source == .history ? state.detailDiff : state.diffText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.5)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 300, idealWidth: 460, maxWidth: .infinity)
        .frame(maxHeight: .infinity)
        .glassSurface(cornerRadius: 18, tint: GlassPalette.blue.opacity(0.05))
        .cardShadow(elevated: true)
        .panelTransition()
    }

    // MARK: 头部

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.justify.leading")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(GlassPalette.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(source.title)
                    .font(.system(size: 12.5, weight: .bold))
                Text(activeFile.isEmpty ? "未选择文件" : (activeFile as NSString).lastPathComponent)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if source == .history, let detail = state.commitDetail {
                StatusBadge(text: detail.shortHash, tint: GlassPalette.blue)
            }
            Spacer(minLength: 8)
            SmallIconButton(icon: "xmark", helpText: "关闭变更视图") {
                withComfortableAnimation(reduceMotion) { state.closeDiffViewer() }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    // MARK: 内容

    @ViewBuilder
    private var content: some View {
        if let imageDiff = state.imageDiff, let imagePath = state.imageDiffPath,
           imagePath == activeFile {
            ScrollView([.vertical]) {
                ImageDiffView(pair: imageDiff, filePath: imagePath)
                    .padding(14)
            }
        } else if state.isLoadingImageDiff {
            VStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("正在读取图片…")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if activeText.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(.tertiary)
                Text(source.emptyHint)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text(source.emptySub)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(20)
        } else {
            // 文本 diff：铺满整个面板
            DiffTextView(text: activeText)
                .padding(10)
        }
    }
}
