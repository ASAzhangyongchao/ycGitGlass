import SwiftUI
import GitCore

/// 侧边栏左下角吉祥物：毛毡小牛伏案敲键盘，丝滑无缝循环。
/// - 空闲：缓慢轻轻起伏（呼吸感）
/// - isBusy：加速打字（蹄子交替 + 头部快频点头）
/// - 系统开启「减弱动态效果」时保持静态姿势，不产生任何动画
struct MascotCow: View {
    var isBusy: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bob = false

    // 毛毡质感配色（与 LogoSource 的棕毡小牛一致）
    private let feltBody = Color(red: 0.76, green: 0.58, blue: 0.40)
    private let feltDark = Color(red: 0.55, green: 0.38, blue: 0.24)
    private let feltMuzzle = Color(red: 0.92, green: 0.84, blue: 0.74)
    private let feltHorn = Color(red: 0.93, green: 0.88, blue: 0.76)
    private let deskWood = Color(red: 0.62, green: 0.46, blue: 0.32)
    private let screenGlow = Color(red: 0.55, green: 0.75, blue: 0.95)

    var body: some View {
        if reduceMotion {
            scene(animated: false)
        } else {
            scene(animated: true)
        }
    }

    // MARK: 场景

    private func scene(animated: Bool) -> some View {
        ZStack {
            desk
            laptop
            cow(animated: animated)
        }
        .frame(width: 132, height: 96)
        .onAppear {
            guard animated else { return }
            startAnimation()
        }
        .onChange(of: isBusy) { _, _ in
            guard animated else { return }
            startAnimation()
        }
        .accessibilityLabel(Text(isBusy ? "小牛正在努力干活" : "小牛在工位上休息"))
    }

    private func startAnimation() {
        // 先无动画复位，再用新的节奏重新起循环；切换 busy 时平滑换挡。
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { bob = false }
        withAnimation(loop(base)) { bob = true }
    }

    private var base: TimeInterval { isBusy ? 0.30 : 1.05 }

    private func loop(_ duration: TimeInterval) -> Animation {
        .easeInOut(duration: duration)
            .repeatForever(autoreverses: true)
    }

    // MARK: 打字交替相位（与 bob 同一驱动，天然同步）

    private var hoofLift: CGFloat { bob ? 2.6 : 0 }

    // MARK: 书桌与笔记本

    private var desk: some View {
        VStack(spacing: 0) {
            Spacer()
            RoundedRectangle(cornerRadius: 3)
                .fill(deskWood)
                .frame(width: 126, height: 7)
            RoundedRectangle(cornerRadius: 1.5)
                .fill(deskWood.opacity(0.85))
                .frame(width: 108, height: 4)
                .offset(y: 2)
        }
        .frame(maxWidth: .infinity, alignment: .bottom)
    }

    private var laptop: some View {
        ZStack {
            // 屏幕
            RoundedRectangle(cornerRadius: 3.5)
                .fill(Color(white: 0.22))
                .frame(width: 34, height: 22)
                .overlay(
                    VStack(alignment: .leading, spacing: 2.5) {
                        codeLine(width: 18, delay: 0)
                        codeLine(width: 24, delay: 0.15)
                        codeLine(width: 12, delay: 0.30)
                        codeLine(width: 21, delay: 0.45)
                    }
                    .padding(4),
                    alignment: .topLeading
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 3.5)
                        .strokeBorder(screenGlow.opacity(0.5), lineWidth: 1)
                )
                .shadow(color: screenGlow.opacity(0.35), radius: 4, y: 1)
            // 键盘底座（微俯视梯形感）
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(white: 0.30))
                .frame(width: 42, height: 5)
                .offset(y: 13)
        }
        .rotationEffect(.degrees(-6))
        .position(x: 66, y: 58)
    }

    private func codeLine(width: CGFloat, delay: Double) -> some View {
        Capsule()
            .fill(screenGlow.opacity(bob ? 0.95 : 0.45))
            .frame(width: width, height: 2.2)
            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true).delay(delay),
                       value: bob)
    }

    // MARK: 毛毡小牛

    private func cow(animated: Bool) -> some View {
        let bodyY: CGFloat = bob ? -1.8 : 1.2
        let headTilt: Double = bob ? -2.4 : 2.2
        let tailSwing: Double = bob ? 9 : -7

        return ZStack {
            // 尾巴
            tail
                .rotationEffect(.degrees(animated ? tailSwing : 4), anchor: .bottom)
                .offset(x: -20, y: -16)

            // 身体（伏案的前倾躯干）
            Ellipse()
                .fill(feltBody)
                .frame(width: 46, height: 34)
                .overlay(
                    Ellipse().fill(feltDark)
                        .frame(width: 13, height: 10)
                        .offset(x: -8, y: -6)
                )
                .overlay(
                    Ellipse().fill(feltDark)
                        .frame(width: 10, height: 8)
                        .offset(x: 10, y: 4)
                )

            // 蹄子搭在键盘上
            hoof(left: true)
                .offset(x: -9, y: 24 - (animated && bob ? hoofLift : 0))
            hoof(left: false)
                .offset(x: 9, y: 24 - (animated && !bob ? hoofLift : 0))

            // 头
            head(tilt: animated ? headTilt : 0)
                .offset(x: 0, y: -22)
        }
        .frame(width: 80, height: 70)
        .offset(y: bodyY)
        .position(x: 62, y: 42)
    }

    private func hoof(left: Bool) -> some View {
        Capsule()
            .fill(feltDark)
            .frame(width: 9, height: 13)
            .overlay(
                Capsule()
                    .fill(feltMuzzle)
                    .frame(width: 9, height: 4)
                    .offset(y: 4)
            )
    }

    private var tail: some View {
        ZStack {
            Capsule()
                .fill(feltBody)
                .frame(width: 4, height: 18)
            Circle()
                .fill(feltDark)
                    .frame(width: 7, height: 7)
                    .offset(y: -10)
        }
    }

    private func head(tilt: Double) -> some View {
        ZStack {
            // 耳朵
            ear.flip(false).offset(x: -19, y: -2)
            ear.flip(true).offset(x: 19, y: -2)
            // 牛角
            horn.mirror(false).offset(x: -11, y: -16)
            horn.mirror(true).offset(x: 11, y: -16)
            // 脸
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(feltBody)
                .frame(width: 40, height: 34)
                .overlay(
                    Ellipse().fill(feltDark)
                        .frame(width: 9, height: 7)
                        .offset(x: 12, y: -9)
                )
            // 口鼻
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(feltMuzzle)
                .frame(width: 24, height: 15)
                .offset(y: 8)
                .overlay(
                    HStack(spacing: 6) {
                        Circle().fill(feltDark).frame(width: 3.4, height: 3.4)
                        Circle().fill(feltDark).frame(width: 3.4, height: 3.4)
                    }
                    .offset(y: 8)
                )
            // 眼睛（专注盯着屏幕）
            HStack(spacing: 12) {
                eye
                eye
            }
            .offset(y: -2)
        }
        .rotationEffect(.degrees(tilt), anchor: .bottom)
    }

    private var eye: some View {
        ZStack {
            Capsule().fill(Color(white: 0.12)).frame(width: 4.4, height: 5.4)
            Circle().fill(.white).frame(width: 1.6, height: 1.6).offset(x: 0.8, y: -1)
        }
    }

    private var ear: some View {
        Ellipse()
            .fill(feltBody)
            .frame(width: 13, height: 9)
            .overlay(
                Ellipse().fill(feltMuzzle.opacity(0.7))
                    .frame(width: 8, height: 5)
            )
    }

    private var horn: some View {
        Capsule()
            .fill(feltHorn)
            .frame(width: 4.5, height: 10)
            .rotationEffect(.degrees(-18))
    }
}

private extension View {
    /// 左右镜像小工具：牛角/耳朵两侧对称。
    func flip(_ flag: Bool) -> some View {
        scaleEffect(x: flag ? -1 : 1, y: 1, anchor: .center)
    }

    func mirror(_ flag: Bool) -> some View {
        flip(flag)
    }
}
