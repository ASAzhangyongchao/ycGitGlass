import SwiftUI
import GitCore

/// 整列连续渲染的提交轨道图（GitKraken / Fork 风格）。
/// 关键：所有行的 graph 拼成一张大 Canvas 一次绘制，行高统一，
/// 竖线/斜线跨行连续不断——而不是此前每行各画一小段造成的“断裂小树”。
struct CommitGraphColumn: View {
    let commits: [Commit]
    var rowHeight: CGFloat = 52
    var laneStep: CGFloat = 11

    @Environment(\.colorScheme) private var scheme

    private var maxColumns: Int {
        commits.map(\.graph.count).max() ?? 1
    }

    var width: CGFloat {
        max(18, CGFloat(maxColumns) * laneStep + 10)
    }

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            let rowCount = commits.count
            guard rowCount > 0 else { return }

            for (row, commit) in commits.enumerated() {
                let centerY = CGFloat(row) * rowHeight + rowHeight / 2
                let characters = Array(commit.graph)

                // 第一遍：连线（画满整行高度，跨行连续）
                for (index, character) in characters.enumerated() {
                    let x = CGFloat(index) * laneStep + laneStep / 2 + 2
                    let lane = index / 2
                    let color = laneColor(lane)

                    switch character {
                    case "|", ":":
                        stroke(context, from: CGPoint(x: x, y: centerY - rowHeight / 2),
                               to: CGPoint(x: x, y: centerY + rowHeight / 2),
                               color: color, width: 2.4)
                    case "/":
                        // 左下 → 右上，画满行高，与上下行的斜线衔接
                        stroke(context, from: CGPoint(x: x - laneStep * 0.5, y: centerY + rowHeight / 2),
                               to: CGPoint(x: x + laneStep * 0.5, y: centerY - rowHeight / 2),
                               color: color, width: 2.0)
                    case "\\":
                        stroke(context, from: CGPoint(x: x - laneStep * 0.5, y: centerY - rowHeight / 2),
                               to: CGPoint(x: x + laneStep * 0.5, y: centerY + rowHeight / 2),
                               color: color, width: 2.0)
                    case "-", "_":
                        stroke(context, from: CGPoint(x: x - laneStep * 0.55, y: centerY),
                               to: CGPoint(x: x + laneStep * 0.55, y: centerY),
                               color: color, width: 2.4)
                    default:
                        break
                    }
                }

                // 第二遍：节点（叠在线上方）
                for (index, character) in characters.enumerated() {
                    guard character == "*" || character == "o" || character == "@" else { continue }
                    let x = CGFloat(index) * laneStep + laneStep / 2 + 2
                    let lane = index / 2
                    let color = laneColor(lane)

                    // HEAD / 分支头：外圈光环 + 实心大点
                    let isHead = row == 0
                    let dotRadius: CGFloat = isHead ? 5.6 : 4.6

                    if isHead {
                        let halo = CGRect(x: x - 9, y: centerY - 9, width: 18, height: 18)
                        context.fill(Path(ellipseIn: halo), with: .color(color.opacity(0.20)))
                        let ring = CGRect(x: x - 7, y: centerY - 7, width: 14, height: 14)
                        context.stroke(Path(ellipseIn: ring), with: .color(color), lineWidth: 1.6)
                    } else {
                        let outer = CGRect(x: x - dotRadius, y: centerY - dotRadius,
                                           width: dotRadius * 2, height: dotRadius * 2)
                        context.fill(Path(ellipseIn: outer), with: .color(color.opacity(0.22)))
                    }
                    let inner = CGRect(x: x - dotRadius + 1.6, y: centerY - dotRadius + 1.6,
                                       width: (dotRadius - 1.6) * 2, height: (dotRadius - 1.6) * 2)
                    context.fill(Path(ellipseIn: inner), with: .color(color))
                }
            }
        }
        .frame(width: width, height: CGFloat(commits.count) * rowHeight)
        .accessibilityLabel(Text("分支轨道图"))
    }

    private func laneColor(_ lane: Int) -> Color {
        let color = GlassPalette.lanes[lane % GlassPalette.lanes.count]
        return color.opacity(scheme == .dark ? 0.95 : 0.88)
    }

    private func stroke(_ context: GraphicsContext, from: CGPoint, to: CGPoint,
                        color: Color, width: CGFloat) {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
    }
}
