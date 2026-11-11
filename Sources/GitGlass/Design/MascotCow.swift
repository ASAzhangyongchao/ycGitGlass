import SwiftUI
import AppKit
import GitCore

/// 侧边栏左下角吉祥物：直接使用品牌 logo（毛毡小牛真身，不再手绘仿品）。
/// - 干活动画：logo 轻微起伏 + 微倾（敲代码的节奏感），忙碌时加快
/// - 点击彩蛋：进入「牛马愤怒」1 秒——变红 + 生气 X 眼斜眉 + 气泡「莫挨老子！」，然后弹回干活
/// - 头顶玻璃气泡显示 日期 / 星期 / 时间（TimelineView 分钟级，非 Timer）
/// - Reduce Motion 下全部静止（点击仍显示愤怒气泡，无抖动）
struct MascotCow: View {
    var isBusy: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bob = false
    @State private var angry = false
    private let bubbleFormat = MascotBubbleFormat()

    var body: some View {
        VStack(spacing: 0) {
            bubble
                .padding(.bottom, 4)
            cowView
        }
        .contentShape(Rectangle())
        .onTapGesture { triggerAngry() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(isBusy ? "小牛正在努力干活" : "小牛在工位上休息（点它试试）"))
    }

    // MARK: 牛（logo 真身）

    private var cowView: some View {
        Image(nsImage: Brand.headerImage)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: 108, height: 108)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(
                        angry ? Color(red: 0.9, green: 0.3, blue: 0.25).opacity(0.65) : Color.white.opacity(0.55),
                        lineWidth: angry ? 2 : 1
                    )
            )
            .shadow(color: angry ? Color(red: 0.9, green: 0.3, blue: 0.25).opacity(0.45) : .black.opacity(0.15),
                    radius: angry ? 12 : 6, y: 3)
            .overlay { angryFace }
            .saturation(angry ? 1.25 : 1.0)
            .hueRotation(.degrees(angry ? -12 : 0)) // 泛红的怒气滤镜
            .scaleEffect(angry ? 1.06 : (bob ? 1.0 : 0.985))
            .rotationEffect(.degrees(angry ? -3 : (bob ? 1.5 : -1.5)))
            .animation(reduceMotion ? nil : (angry ? Motion.snappy : workAnimation), value: bob)
            .animation(reduceMotion ? nil : Motion.snappy, value: angry)
            .onAppear { startWork() }
            .onChange(of: isBusy) { _, _ in startWork() }
    }

    private var workAnimation: Animation {
        .easeInOut(duration: isBusy ? 0.32 : 0.95).repeatForever(autoreverses: true)
    }

    private func startWork() {
        guard !reduceMotion else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { bob = false }
        withAnimation(workAnimation) { bob = true }
    }

    /// 愤怒眉眼贴纸（叠在 logo 上）
    private var angryFace: some View {
        Group {
            if angry {
                HStack(spacing: 26) {
                    angryEye
                    angryEye
                }
                .padding(.top, 34)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .allowsHitTesting(false)
    }

    private var angryEye: some View {
        ZStack {
            Text("╳")
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.55), radius: 2, y: 1)
            RoundedRectangle(cornerRadius: 1.5)
                .fill(.white)
                .frame(width: 16, height: 2.6)
                .rotationEffect(.degrees(-24))
                .offset(y: -11)
                .shadow(color: .black.opacity(0.55), radius: 2, y: 1)
        }
    }

    // MARK: 气泡（时钟 / 愤怒）

    @ViewBuilder
    private var bubble: some View {
        if angry {
            angryBubble
                .transition(.scale(scale: 0.6).combined(with: .opacity))
        } else {
            timeBubble
                .transition(.opacity)
        }
    }

    private var angryBubble: some View {
        VStack(spacing: 2) {
            Text("莫挨老子！😤")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
            Text("牛马愤怒")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 7)
        .background(
            LinearGradient(colors: [Color(red: 0.95, green: 0.32, blue: 0.26),
                                    Color(red: 0.82, green: 0.18, blue: 0.16)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: Color(red: 0.9, green: 0.25, blue: 0.2).opacity(0.5), radius: 8, y: 3)
        .overlay(alignment: .bottom) {
            Triangle()
                .fill(Color(red: 0.82, green: 0.18, blue: 0.16))
                .frame(width: 10, height: 6)
                .offset(y: 6)
        }
    }

    private var timeBubble: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let date = timeline.date
            VStack(spacing: 2) {
                Text(bubbleFormat.weekdayAndDate(date))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(bubbleFormat.time(date))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .glassSurface(cornerRadius: 12, tint: GlassPalette.blue.opacity(0.08))
            .overlay(alignment: .bottom) {
                Triangle()
                    .fill(Color.primary.opacity(0.05))
                    .frame(width: 10, height: 6)
                    .offset(y: 6)
            }
            .shadow(color: .black.opacity(0.06), radius: 6, y: 3)
            .help(bubbleFormat.full(date))
        }
    }

    // MARK: 愤怒触发（1 秒后自动消气）

    private func triggerAngry() {
        guard !angry else { return }
        angry = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.0))
            angry = false
            startWork()
        }
    }
}

// MARK: - 气泡文案格式

/// 时钟气泡的日期时间格式化（缓存 formatter，避免每分钟重建）。
private struct MascotBubbleFormat {
    private let weekdayAndDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter
    }()

    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private let fullFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日 EEEE HH:mm"
        return formatter
    }()

    func weekdayAndDate(_ date: Date) -> String { weekdayAndDateFormatter.string(from: date) }
    func time(_ date: Date) -> String { timeFormatter.string(from: date) }
    func full(_ date: Date) -> String { fullFormatter.string(from: date) }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
