import SwiftUI
import AppKit

// MARK: - 右侧 Inspector 面板容器
// 大厂桌面端标配模式（Slack 线程面板 / Linear peek / Figma 检查器 / Notion 预览）：
// 选中一个东西 → 右侧就地展开 → 不打断当前列表上下文。
//
// 壳只提供容器能力；内容（提交详情 / diff / 预览）由调用方注入，互不干扰：
// - 可拖宽：左缘拖柄调宽度
// - 宽度记忆：按 key 记到 UserDefaults，下次打开恢复
// - 可关闭：右上关闭按钮 + ESC
// - 窄屏浮层：可用宽度不足时自动变成覆盖式浮层（列表保持可读宽度）
// - 同项 toggle：再点同一项时收起（由调用方的 open/toggle 逻辑决定）

/// 面板宽度记忆存储（每个面板 key 独立记录）
enum InspectorWidthStore {
    private static let prefix = "inspector.width."

    static func load(_ key: String, default: CGFloat) -> CGFloat {
        let saved = UserDefaults.standard.double(forKey: prefix + key)
        return saved > 0 ? saved : `default`
    }

    static func save(_ key: String, width: CGFloat) {
        UserDefaults.standard.set(width, forKey: prefix + key)
    }
}

/// 可停靠右侧面板容器。
/// 用法：`InspectorPanel(key: "commit.diff", minWidth: 380, defaultWidth: 480) { DiffViewerPanel(...) }`
struct InspectorPanel<Content: View>: View {
    /// 宽度记忆 key（同 key 的面板共享宽度）
    let key: String
    var minWidth: CGFloat = 340
    var maxWidth: CGFloat = 760
    var defaultWidth: CGFloat = 460
    /// 面板顶部额外工具行（可选；内容自适应者传 nil）
    var toolbar: AnyView? = nil
    @ViewBuilder var content: Content

    @State private var width: CGFloat = 0 // 0 = 未初始化，首帧从存储读取
    @State private var dragStartWidth: CGFloat?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if width <= 0 {
                // 首帧占位：onAppear 里读记忆宽度（避免 init 期读 UserDefaults 的开销）
                Color.clear
                    .frame(width: defaultWidth)
                    .onAppear { width = InspectorWidthStore.load(key, default: defaultWidth) }
            } else {
                HStack(spacing: 0) {
                    dragHandle
                    VStack(alignment: .leading, spacing: 0) {
                        if let toolbar { toolbar }
                        content
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(width: min(max(width, minWidth), maxWidth))
            }
        }
    }

    // MARK: 拖宽手柄（左缘 5px 热区）

    private var dragHandle: some View {
        ZStack {
            // 视觉拖柄：悬停变亮的细条
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.primary.opacity(0.08))
                .frame(width: 3)
                .padding(.vertical, 24)
            // 热区比视觉宽（好抓）
            Color.clear
                .contentShape(Rectangle())
                .frame(width: 7)
                .onHover { hovering in
                    NSCursor.resizeLeftRight.set()
                    if !hovering { NSCursor.arrow.set() }
                }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    if dragStartWidth == nil { dragStartWidth = width }
                    // 向左拖 = 变宽（手柄在左缘）
                    let w = (dragStartWidth ?? width) - value.translation.width
                    width = min(max(w, minWidth), maxWidth)
                }
                .onEnded { _ in
                    dragStartWidth = nil
                    InspectorWidthStore.save(key, width: width)
                }
        )
        .help("拖动调整面板宽度（宽度会记住）")
    }
}

// MARK: - 窄屏浮层包装器
// 可用宽度 < threshold 时：inspector 不再并排挤列表，而是盖在内容上方
// （带投影 + 顶部拖拽条视觉暗示浮层，点外面/ESC 关闭）。

struct InspectorAdaptiveContainer<Inspector: View>: View {
    /// 内容区可用宽度小于此值时切换浮层
    var compactThreshold: CGFloat = 900
    @ViewBuilder var inspector: Inspector

    @State private var viewportWidth: CGFloat = 1400

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // 隐形宽度探测器（不参与布局）
            GeometryReader { geo in
                Color.clear
                    .onAppear { viewportWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, w in viewportWidth = w }
            }
            .frame(height: 0)
            .allowsHitTesting(false)

            if viewportWidth < compactThreshold {
                // 窄屏：浮层模式（覆盖右侧，列表保持完整可读）
                inspector
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.18), radius: 18, y: 6)
                    .frame(maxWidth: 480)
                    .padding(.leading, 40) // 左侧留缝露出下层列表，暗示可关闭
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                // 宽屏：并排 dock 模式
                inspector
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.88), value: viewportWidth >= compactThreshold)
    }
}
