import SwiftUI

/// 简易换行流式布局：一行放不下自动折到下一行，用于页签在窄窗口下不被硬挤压。
/// 只在尺寸变化时重排，无任何持续渲染。
struct FlowLayout<Data: RandomAccessCollection, ItemContent: View>: View
where Data.Element: Hashable {
    var spacing: CGFloat = 8
    let items: Data
    @ViewBuilder let content: (Data.Element) -> ItemContent

    init(spacing: CGFloat = 8, data: Data,
         @ViewBuilder content: @escaping (Data.Element) -> ItemContent) {
        self.spacing = spacing
        self.items = data
        self.content = content
    }

    var body: some View {
        // Layout 协议类型可以直接参与 ViewBuilder 组合（SwiftUI 对 Layout 有特殊支持）。
        FlowWrapLayout(spacing: spacing) {
            ForEach(Array(items), id: \.self) { item in
                content(item)
            }
        }
    }
}

/// 原生 Layout：按提议宽度换行摆放子视图。
/// 约定：content 由 Layout 的 callAsFunction 闭包直接传入，避免存储非 Sendable 视图。
struct FlowWrapLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : x, height: max(y + rowHeight, 0))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
