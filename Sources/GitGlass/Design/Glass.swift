import SwiftUI

// MARK: - 动效系统
// 全部为「事件驱动」动画：状态变化才插值，动画结束立刻停止。
// 不使用 repeatForever / TimelineView / Timer / 循环 Timeline，空闲时渲染与 CPU 均为 0。
// 阻尼统一调高（0.86~0.90），减少弹跳带来的晃动，观感更舒适。
enum Motion {
    static var spring: Animation { .spring(response: 0.44, dampingFraction: 0.86) }
    static var snappy: Animation { .spring(response: 0.30, dampingFraction: 0.88) }
    static var soft: Animation { .spring(response: 0.60, dampingFraction: 0.90) }
    static var fade: Animation { .easeInOut(duration: 0.24) }
    static var slide: Animation { .spring(response: 0.50, dampingFraction: 0.90) }
}

/// 统一的状态变更动画入口；系统开启「减弱动态效果」时自动退化为无动画。
@MainActor
func withComfortableAnimation(_ reduceMotion: Bool, _ changes: () -> Void) {
    if reduceMotion {
        changes()
    } else {
        withAnimation(Motion.spring) { changes() }
    }
}

enum GlassPalette {
    static var accent: Color { Color.accentColor }
    static var blue: Color { Color(red: 0.36, green: 0.58, blue: 0.98) }
    static var violet: Color { Color(red: 0.62, green: 0.45, blue: 0.96) }
    static var mint: Color { Color(red: 0.30, green: 0.78, blue: 0.68) }
    static var amber: Color { Color(red: 0.98, green: 0.68, blue: 0.28) }
    static var rose: Color { Color(red: 0.96, green: 0.42, blue: 0.46) }

    /// 提交图轨道按 lane 轮换的颜色
    static let lanes: [Color] = [
        Color(red: 0.36, green: 0.58, blue: 0.98),
        Color(red: 0.62, green: 0.45, blue: 0.96),
        Color(red: 0.30, green: 0.78, blue: 0.68),
        Color(red: 0.98, green: 0.68, blue: 0.28),
        Color(red: 0.96, green: 0.42, blue: 0.46),
        Color(red: 0.36, green: 0.76, blue: 0.90)
    ]
}

/// 静态渐变 + 柔光斑：不产生持续动画，只提供玻璃层的折射底材。
struct GlassBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            (scheme == .dark ? Color(white: 0.10) : Color(white: 0.965))
                .ignoresSafeArea()
            LinearGradient(
                colors: scheme == .dark
                    ? [GlassPalette.blue.opacity(0.16), .clear, GlassPalette.violet.opacity(0.13)]
                    : [GlassPalette.blue.opacity(0.13), .clear, GlassPalette.violet.opacity(0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            RadialGradient(
                colors: [GlassPalette.mint.opacity(scheme == .dark ? 0.14 : 0.20), .clear],
                center: .topTrailing, startRadius: 20, endRadius: 520
            )
            .ignoresSafeArea()
            RadialGradient(
                colors: [GlassPalette.blue.opacity(scheme == .dark ? 0.13 : 0.16), .clear],
                center: .bottomLeading, startRadius: 20, endRadius: 480
            )
            .ignoresSafeArea()
        }
    }
}

// MARK: - 无障碍：降低透明度

private struct GlassTransparencyKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var glassReduceTransparency: Bool {
        get { self[GlassTransparencyKey.self] }
        set { self[GlassTransparencyKey.self] = newValue }
    }
}

/// 原生 Liquid Glass + 顶部高光描边；降低透明度时退化为不透明卡片。
private struct GlassSurfaceModifier: ViewModifier {
    var cornerRadius: CGFloat
    var isCapsule: Bool
    var tint: Color?
    var interactive: Bool

    @Environment(\.glassReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        Group {
            if reduceTransparency {
                content.background(flatColor, in: shape)
            } else if #available(macOS 26.0, *) {
                glassContent(content)
            } else {
                content.background(.regularMaterial, in: shape)
            }
        }
        .overlay { shape.stroke(highlight, lineWidth: 0.9) }
    }

    @ViewBuilder
    private func glassContent(_ content: Content) -> some View {
        if isCapsule {
            if let tint {
                content.glassEffect(.regular.tint(tint).interactive(interactive), in: .capsule)
            } else {
                content.glassEffect(.regular.interactive(interactive), in: .capsule)
            }
        } else {
            if let tint {
                content.glassEffect(.regular.tint(tint).interactive(interactive), in: .rect(cornerRadius: cornerRadius))
            } else {
                content.glassEffect(.regular.interactive(interactive), in: .rect(cornerRadius: cornerRadius))
            }
        }
    }

    private var shape: AnyShape {
        isCapsule
            ? AnyShape(Capsule())
            : AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var flatColor: Color {
        scheme == .dark ? Color(white: 0.17) : Color.white
    }

    private var highlight: LinearGradient {
        LinearGradient(
            colors: [.white.opacity(scheme == .dark ? 0.16 : 0.55), .white.opacity(0.02)],
            startPoint: .top, endPoint: .bottom
        )
    }
}

extension View {
    func glassSurface(cornerRadius: CGFloat = 20, tint: Color? = nil, interactive: Bool = false) -> some View {
        self.modifier(GlassSurfaceModifier(cornerRadius: cornerRadius, isCapsule: false,
                                           tint: tint, interactive: interactive))
    }

    func glassPill(tint: Color? = nil, interactive: Bool = false) -> some View {
        self.modifier(GlassSurfaceModifier(cornerRadius: 0, isCapsule: true,
                                           tint: tint, interactive: interactive))
    }

    @ViewBuilder
    func prominentAction() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    func glassAction() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }

    /// 列表行错峰入场：只对前 12 行加延迟，避免大量动画同时创建。
    @ViewBuilder
    func staggered(_ index: Int, animation: Animation = Motion.soft) -> some View {
        self.transition(.asymmetric(
            insertion: .scale(scale: 0.97).combined(with: .opacity).combined(with: .move(edge: .trailing)),
            removal: .opacity
        ))
        .animation(animation.delay(Double(min(index, 12)) * 0.016), value: index)
    }

    func hoverLift(_ hovering: Bool, scale: CGFloat = 1.02) -> some View {
        self.scaleEffect(hovering ? scale : 1.0)
            .animation(Motion.snappy, value: hovering)
    }

    func cardShadow(elevated: Bool = false) -> some View {
        self.shadow(color: .black.opacity(elevated ? 0.12 : 0.07),
                    radius: elevated ? 26 : 18, x: 0, y: elevated ? 12 : 8)
    }

    /// 给玻璃元素一个身份，同一容器内切换时系统自动做形变过渡。
    @ViewBuilder
    func glassIdentity(_ id: String, in namespace: Namespace.ID) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffectID(id, in: namespace)
        } else {
            self
        }
    }

    /// 面板从右侧自然滑入（配合 withComfortableAnimation 使用）。
    @ViewBuilder
    func panelTransition() -> some View {
        self.transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity).combined(with: .scale(scale: 0.98, anchor: .trailing)),
            removal: .move(edge: .trailing).combined(with: .opacity)
        ))
    }
}
