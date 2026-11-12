import SwiftUI
import AppKit
import GitCore

/// 侧边栏左下角吉祥物：logo 原图 1:1 渲染，做成「活体贴纸」——
/// 不是模仿牛的样子，就是那张图本身在动，像微信/Telegram 动态贴纸。
///
/// - 空闲：整体轻微浮动 + 左右摇摆（贴纸被风吹动的感觉）
/// - 忙碌（执行 git 操作）：快速小幅"敲键抖动" + 头顶冒汗 💧 + 微缩放脉冲
/// - 点击：牛马愤怒 1 秒（泛红 + X 眼 + 「莫挨老子！」气泡），随后消气继续干活
/// - 头顶玻璃气泡：日期 / 星期 / 时间（TimelineView 分钟级刷新）
/// - Reduce Motion：全部静止，仅保留愤怒气泡文字反馈
struct MascotCow: View {
    var isBusy: Bool = false
    /// 快照/自测用：初始即愤怒态（正常交互走点击触发）
    var initiallyAngry: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bob = false
    @State private var angry = false
    @State private var sweatToggle = false
    private let bubbleFormat = MascotBubbleFormat()

    /// 气泡槽位固定高度：时间气泡（两行）与愤怒气泡（一行）都居中放在同一高度里，
    /// 点击切换时整块 MascotCow 的布局高度纹丝不动（体感关键，不许跳）。
    static let bubbleSlotHeight: CGFloat = 48

    init(isBusy: Bool = false, initiallyAngry: Bool = false) {
        self.isBusy = isBusy
        self.initiallyAngry = initiallyAngry
        _angry = State(initialValue: initiallyAngry)
    }

    var body: some View {
        VStack(spacing: 0) {
            // 固定高度槽位：切换愤怒/时间气泡时布局零跳动
            bubble
                .frame(height: Self.bubbleSlotHeight)
                .padding(.bottom, 2)
            sticker
        }
        .contentShape(Rectangle())
        .onTapGesture { triggerAngry() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(isBusy ? "小牛正在努力干活（点它试试）" : "小牛在工位上摸鱼（点它试试）"))
    }

    // MARK: 活体贴纸（logo 原图 + 物理动画）

    private var sticker: some View {
        Image(nsImage: Brand.headerImage)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: 88, height: 88)
            // 无白边：直接圆角裁切 + 轻投影（融入侧边栏，不抢视觉）
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        angry ? Color(red: 0.9, green: 0.3, blue: 0.25).opacity(0.7) : .clear,
                        lineWidth: 2
                    )
            )
            .shadow(color: angry ? Color(red: 0.9, green: 0.3, blue: 0.25).opacity(0.4) : .black.opacity(0.13),
                    radius: angry ? 10 : 5, y: 3)
            .overlay { angryFace }
            .overlay(alignment: .topTrailing) { sweat }
            .hueRotation(.degrees(angry ? -14 : 0))
            .saturation(angry ? 1.3 : 1.0)
            // 贴纸物理动画：
            // 空闲 = 慢速浮动+微倾；忙碌 = 快速敲键抖动（高频小幅 y 弹跳+缩放脉冲）
            .scaleEffect(stickerScale)
            .rotationEffect(.degrees(stickerAngle))
            .offset(y: stickerLift)
            .animation(reduceMotion ? nil : (angry ? Motion.snappy : workAnimation), value: bob)
            .animation(reduceMotion ? nil : Motion.snappy, value: angry)
            .onAppear { startWork() }
            .onChange(of: isBusy) { _, _ in startWork() }
    }

    /// 忙碌时的敲键抖动：小幅度高频弹跳，像整张贴纸被键盘震动带得一起颠
    private var stickerScale: CGFloat {
        if angry { return 1.07 }
        if isBusy { return bob ? 1.0 : 0.97 }        // 快速脉冲
        return bob ? 1.0 : 0.99                      // 慢速呼吸
    }

    private var stickerAngle: Double {
        if angry { return -3 }
        if isBusy { return bob ? 1.2 : -1.2 }         // 快速左右颤
        return bob ? 1.6 : -1.6                       // 慢速摇摆
    }

    private var stickerLift: CGFloat {
        if angry { return -3 }
        if isBusy { return bob ? -1.5 : 1.5 }         // 快速上下颠（敲键感）
        return bob ? -2.5 : 1.5                       // 慢速漂浮
    }

    private var workAnimation: Animation {
        // 空闲呼吸放宽到 3.2s：贴纸"活着"的最低限度动感，渲染压力比 1s 版本降 2/3；
        // 忙碌敲键保持 0.26s 高频（操作期间短暂，可接受）
        .easeInOut(duration: isBusy ? 0.26 : 3.2).repeatForever(autoreverses: true)
    }

    private func startWork() {
        guard !reduceMotion else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { bob = false }
        withAnimation(workAnimation) { bob = true }
    }

    // MARK: 忙碌冒汗 💧（独立节奏，只在 isBusy 出现）

    @ViewBuilder
    private var sweat: some View {
        if isBusy && !angry {
            HStack(spacing: 3) {
                sweatDrop(delay: 0)
                sweatDrop(delay: 0.45)
            }
            .offset(x: 10, y: 6)
            .transition(.opacity)
        }
    }

    private func sweatDrop(delay: Double) -> some View {
        Text("💧")
            .font(.system(size: 11))
            .opacity(sweatToggle ? 1.0 : 0.25)
            .offset(y: sweatToggle ? -3 : 2)
            .animation(
                reduceMotion ? nil :
                    .easeInOut(duration: 0.6).repeatForever(autoreverses: true).delay(delay),
                value: sweatToggle
            )
            .onAppear {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { sweatToggle = false }
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true).delay(delay)) {
                    sweatToggle = true
                }
            }
    }

    // MARK: 愤怒 X 眼 + 斜眉（点击彩蛋）

    private var angryFace: some View {
        Group {
            if angry {
                VStack(spacing: 0) {
                    HStack(spacing: 30) {
                        angryEye
                        angryEye
                    }
                    .padding(.top, 26)
                    Spacer()
                    // 怒气符号：漫画式青筋
                    Text("💢")
                        .font(.system(size: 14))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 10)
                        .padding(.bottom, 10)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private var angryEye: some View {
        ZStack {
            Text("╳")
                .font(.system(size: 16, weight: .black))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
            RoundedRectangle(cornerRadius: 1.5)
                .fill(.white)
                .frame(width: 17, height: 2.8)
                .rotationEffect(.degrees(-24))
                .offset(y: -12)
                .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
        }
    }

    // MARK: 气泡（时钟 / 愤怒）

    @ViewBuilder
    private var bubble: some View {
        ZStack {
            if angry {
                angryBubble
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            } else {
                timeBubble
                    .transition(.opacity)
            }
        }
    }

    private var angryBubble: some View {
        VStack(spacing: 2) {
            Text("莫挨老子！😤")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            LinearGradient(colors: [Color(red: 0.95, green: 0.32, blue: 0.26),
                                    Color(red: 0.80, green: 0.16, blue: 0.15)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.4), lineWidth: 1)
        )
        .shadow(color: Color(red: 0.9, green: 0.25, blue: 0.2).opacity(0.5), radius: 9, y: 3)
        .overlay(alignment: .bottom) {
            Triangle()
                .fill(Color(red: 0.80, green: 0.16, blue: 0.15))
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

    // MARK: 愤怒触发（1 秒消气）

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
