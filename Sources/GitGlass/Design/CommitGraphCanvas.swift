import SwiftUI

/// 把 `git log --graph` 的 ASCII 轨道重绘成彩色分支线。
/// 使用单个 Canvas 一次性绘制，无子视图、无动画、无持续渲染。
struct CommitGraphCanvas: View {
    let graph: String
    var compact = false
    @Environment(\.colorScheme) private var scheme

    private var step: CGFloat { compact ? 8 : 10 }
    private var height: CGFloat { compact ? 18 : 22 }

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            let characters = Array(graph)
            let middle = size.height / 2
            for (index, character) in characters.enumerated() {
                let x = CGFloat(index) * step + step / 2
                let lane = index / 2
                let color = GlassPalette.lanes[lane % GlassPalette.lanes.count]
                    .opacity(scheme == .dark ? 0.95 : 0.85)

                switch character {
                case "*", "o", "@":
                    let outer = CGRect(x: x - 4.6, y: middle - 4.6, width: 9.2, height: 9.2)
                    let inner = CGRect(x: x - 2.6, y: middle - 2.6, width: 5.2, height: 5.2)
                    context.fill(Path(ellipseIn: outer), with: .color(color.opacity(0.22)))
                    context.fill(Path(ellipseIn: inner), with: .color(color))
                case "|":
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(path, with: .color(color.opacity(0.8)), lineWidth: 2.2)
                case "/":
                    var path = Path()
                    path.move(to: CGPoint(x: x - step * 0.45, y: size.height))
                    path.addLine(to: CGPoint(x: x + step * 0.45, y: 0))
                    context.stroke(path, with: .color(color.opacity(0.8)), lineWidth: 1.8)
                case "\\":
                    var path = Path()
                    path.move(to: CGPoint(x: x - step * 0.45, y: 0))
                    path.addLine(to: CGPoint(x: x + step * 0.45, y: size.height))
                    context.stroke(path, with: .color(color.opacity(0.8)), lineWidth: 1.8)
                case "-", "_":
                    var path = Path()
                    path.move(to: CGPoint(x: x - step * 0.5, y: middle))
                    path.addLine(to: CGPoint(x: x + step * 0.5, y: middle))
                    context.stroke(path, with: .color(color.opacity(0.8)), lineWidth: 2.2)
                case "+", "x", ".", ":":
                    let rect = CGRect(x: x - 2.4, y: middle - 2.4, width: 4.8, height: 4.8)
                    context.fill(Path(roundedRect: rect, cornerRadius: 1.2), with: .color(color))
                default:
                    break
                }
            }
        }
        .frame(width: max(16, CGFloat(graph.count) * step + 8), height: height)
        .accessibilityLabel(Text("分支轨道"))
        .help(graph.isEmpty ? "主分支" : graph)
    }
}
