import SwiftUI
import AppKit
import GitCore

/// 图片差异预览 —— 对标 Kaleidoscope / Diff Guru 的对比体验：
/// 五种模式（并排 / 滑块 / 淡入淡出 / 闪烁 / 差异分析）、容差调节、差异统计、玻璃放大镜。
/// 所有模式同一高度基线，切换时丝滑过渡；闪烁为周期动画，仅在选中该模式时运行。
struct ImageDiffView: View {
    let pair: ImageDiffService.Pair
    let filePath: String

    enum Mode: String, CaseIterable, Identifiable {
        case side = "并排"
        case slider = "滑块"
        case fade = "淡入淡出"
        case blink = "闪烁"
        case difference = "差异分析"

        var id: String { rawValue }
    }

    @State private var mode: Mode = .slider
    @State private var slider: Double = 85
    @State private var fade: Double = 50
    @State private var blinkPhase = false
    @State private var tolerance: Double = 10
    @State private var hovering: CGPoint?
    @State private var zoomed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: 图片解码

    private var beforeImage: NSImage? {
        pair.beforeData.flatMap { NSImage(data: $0) }
    }

    private var afterImage: NSImage? {
        pair.afterData.flatMap { NSImage(data: $0) }
    }

    private var bothExist: Bool {
        beforeImage != nil && afterImage != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            toolbar
            content
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
            footer
        }
        .animation(reduceMotion ? nil : Motion.snappy, value: mode)
    }

    // MARK: 工具条

    private var toolbar: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(Mode.allCases) { item in
                    Button {
                        mode = item
                    } label: {
                        if mode == item {
                            Label(item.rawValue, systemImage: "checkmark")
                        } else {
                            Text(item.rawValue)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: modeIcon)
                        .font(.system(size: 10, weight: .semibold))
                    Text(mode.rawValue)
                        .font(.system(size: 11.5, weight: .semibold))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .glassPill(interactive: true)
            .help("并排：总览 ｜ 滑块：拖动对比 ｜ 淡入淡出：找对齐 ｜ 闪烁：找位移 ｜ 差异分析：像素级")

            if mode == .slider {
                miniSlider(value: $slider, icon: "arrow.left.and.right", range: 0...100)
                    .frame(width: 130)
            }
            if mode == .fade {
                miniSlider(value: $fade, icon: "circle.lefthalf.filled", range: 0...100)
                    .frame(width: 130)
            }
            if mode == .difference {
                HStack(spacing: 6) {
                    Text("容差")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    miniSlider(value: $tolerance, icon: "wand.and.rays", range: 0...40)
                        .frame(width: 110)
                    Text("\(Int(tolerance))%")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 30)
                }
            }

            Spacer(minLength: 0)

            // 缩放开关（并排/滑块/差异可用）
            if mode != .fade && mode != .blink {
                SmallIconButton(icon: zoomed ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                                helpText: zoomed ? "缩小到适配" : "放大查看细节") {
                    withComfortableAnimation(reduceMotion) { zoomed.toggle() }
                }
            }
        }
    }

    private func miniSlider(value: Binding<Double>, icon: String, range: ClosedRange<Double>) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            Slider(value: value, in: range)
                .controlSize(.mini)
        }
    }

    private var modeIcon: String {
        switch mode {
        case .side: return "rectangle.split.2x1"
        case .slider: return "arrow.left.and.right.square"
        case .fade: return "circle.lefthalf.filled"
        case .blink: return "eye.trianglebadge.exclamationmark"
        case .difference: return "square.stack.3d.up.slash"
        }
    }

    // MARK: 内容区

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .side: sideBySide
        case .slider: sliderCompare
        case .fade: fadeCompare
        case .blink: blinkCompare
        case .difference: differenceCompare
        }
    }

    private var displayHeight: CGFloat { zoomed ? 320 : 190 }

    // MARK: 并排

    private var sideBySide: some View {
        HStack(alignment: .center, spacing: 14) {
            pane(image: beforeImage, label: "旧版本", bytes: pair.beforeBytes,
                 tint: Color.secondary, placeholder: "旧版本不存在（新增文件）")
            ZStack {
                Circle()
                    .fill(GlassPalette.blue.opacity(0.12))
                    .frame(width: 26, height: 26)
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(GlassPalette.blue)
            }
            pane(image: afterImage, label: "新版本", bytes: pair.afterBytes,
                 tint: GlassPalette.mint, placeholder: "新版本不存在（文件已删除）")
        }
    }

    private func pane(image: NSImage?, label: String, bytes: Int, tint: Color, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 5, height: 5)
                Text(label).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(tint)
                Text(Self.formatBytes(bytes))
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(colors: [Color.primary.opacity(0.05), Color.primary.opacity(0.02)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                // 棋盘格底（透明图片可见）
                checkerboard
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .padding(6)
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(.system(size: 17))
                        Text(placeholder)
                            .font(.system(size: 9.5))
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.tertiary)
                    .padding(10)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: displayHeight)
            .overlay(alignment: .bottomTrailing) {
                if let image {
                    Text("\(Int(image.size.width))×\(Int(image.size.height))")
                        .font(.system(size: 8.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(6)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 滑块（可直接在画布上拖动）

    private var sliderCompare: some View {
        VStack(spacing: 8) {
            GeometryReader { proxy in
                let width = proxy.size.width
                let x = width * slider / 100

                ZStack {
                    imageLayer(beforeImage, visible: true)
                    if let afterImage {
                        imageLayer(afterImage, visible: true)
                            .mask(
                                HStack(spacing: 0) {
                                    Rectangle().frame(width: max(0, x))
                                    Color.clear
                                }
                            )
                    }
                    if !bothExist {
                        emptyOverlay(beforeImage == nil ? "旧版本不存在" : "新版本不存在")
                    }

                    // 分割线 + 手柄
                    Rectangle()
                        .fill(
                            LinearGradient(colors: [.white.opacity(0.9), .white],
                                           startPoint: .top, endPoint: .bottom)
                        )
                        .frame(width: 1.5)
                        .shadow(color: .black.opacity(0.35), radius: 2)
                        .position(x: x, y: proxy.size.height / 2)
                    Circle()
                        .fill(.white)
                        .frame(width: 22, height: 22)
                        .shadow(color: .black.opacity(0.30), radius: 4, y: 1)
                        .overlay(
                            Image(systemName: "arrow.left.and.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color(white: 0.22))
                        )
                        .position(x: x, y: proxy.size.height / 2)

                    // 两侧常驻标签（不与手柄重叠：贴边显示）
                    sideLabel("旧版", alignment: .leading)
                        .opacity(x > 60 ? 1 : 0)
                    sideLabel("新版", alignment: .trailing)
                        .opacity(x < width - 60 ? 1 : 0)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let fraction = value.location.x / max(width, 1) * 100
                            slider = min(100, max(0, fraction))
                        }
                )
            }
            .frame(height: displayHeight)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack(spacing: 6) {
                Image(systemName: "hand.draw")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                Text("在图片上直接拖动即可对比")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("旧 \(Int(slider))% · 新 \(100 - Int(slider))%")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func sideLabel(_ text: String, alignment: Alignment) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.45), in: Capsule())
            .padding(8)
            .frame(maxWidth: .infinity, alignment: alignment)
    }

    private func imageLayer(_ image: NSImage?, visible: Bool) -> some View {
        Group {
            if let image {
                checkerboard
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .padding(4)
            }
        }
    }

    // MARK: 淡入淡出（onion skin，找对齐/微调）

    private var fadeCompare: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
                if let beforeImage {
                    Image(nsImage: beforeImage)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .padding(4)
                        .opacity(1 - fade / 100)
                }
                if let afterImage {
                    Image(nsImage: afterImage)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .padding(4)
                        .opacity(fade / 100)
                }
                if !bothExist {
                    emptyOverlay("需要新旧两个版本")
                }
            }
            .frame(height: displayHeight)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack(spacing: 6) {
                Text("旧").font(.system(size: 9.5)).foregroundStyle(.tertiary)
                ProgressView(value: fade / 100)
                    .frame(height: 4)
                Text("新").font(.system(size: 9.5)).foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: 闪烁（blink comparator，检测元素位移）

    private var blinkCompare: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
                // 交替显示，位移元素会"跳"出来
                let active = blinkPhase ? (afterImage ?? beforeImage) : (beforeImage ?? afterImage)
                if let active {
                    checkerboard
                    Image(nsImage: active)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .padding(4)
                }

                if !bothExist {
                    emptyOverlay("需要新旧两个版本")
                }

                VStack {
                    Spacer()
                    HStack(spacing: 6) {
                        Circle()
                            .fill(blinkPhase ? GlassPalette.mint : Color.secondary.opacity(0.4))
                            .frame(width: 6, height: 6)
                        Text("正在交替显示新旧版本——发生移动的元素会「跳」出来")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 8)
                }
            }
            .frame(height: displayHeight)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onAppear { startBlink() }
            .onDisappear { blinkPhase = false }
        }
    }

    private func startBlink() {
        guard !reduceMotion else { return }
        // 0.55s 交替：足够感知位移，不至眩晕；离开此模式立即停止
        withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
            blinkPhase = true
        }
    }

    // MARK: 差异分析（容差 + 统计）

    private var differenceCompare: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.82))
                if bothExist, let diff = differenceImage {
                    Image(nsImage: diff)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .padding(4)
                    // 差异区域洋红高亮层
                    Image(nsImage: diff)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .padding(4)
                        .blendMode(.difference)
                        .opacity(0.0)
                } else if afterImage != nil || beforeImage != nil {
                    VStack(spacing: 8) {
                        Image(systemName: "square.stack.3d.up.slash")
                            .font(.system(size: 17))
                            .foregroundStyle(.white.opacity(0.5))
                        Text("需要新旧两个版本才能做像素分析")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                } else {
                    emptyOverlay("没有可用版本")
                }
            }
            .frame(height: displayHeight)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack(spacing: 10) {
                if bothExist {
                    let percent = differencePercent
                    HStack(spacing: 6) {
                        Circle()
                            .fill(percent > 5 ? GlassPalette.rose : percent > 0.5 ? GlassPalette.amber : GlassPalette.mint)
                            .frame(width: 6, height: 6)
                        Text(percent > 5 ? "差异明显" : percent > 0.5 ? "有细微差异" : "基本一致")
                            .font(.system(size: 10, weight: .semibold))
                        Text(String(format: "%.2f%% 像素不同", percent))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text("容差内的小变化（抗锯齿/压缩噪点）会被忽略")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// 用 CoreGraphics 逐像素计算差异图：黑色=一致，亮=不同（容差内视为一致）。
    private var differenceImage: NSImage? {
        guard let before = beforeImage, let after = afterImage,
              let beforeTiff = before.tiffRepresentation,
              let afterTiff = after.tiffRepresentation,
              let beforeRep = NSBitmapImageRep(data: beforeTiff),
              let afterRep = NSBitmapImageRep(data: afterTiff) else { return nil }

        let width = max(beforeRep.pixelsWide, afterRep.pixelsWide)
        let height = max(beforeRep.pixelsHigh, afterRep.pixelsHigh)
        guard width > 0, height > 0, width * height <= 4_000_000 else { return nil }

        guard let outRep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }

        let threshold = UInt32(tolerance * 7.65) // 百分比 → 0..255*3 的近似阈值
        for y in 0..<height {
            for x in 0..<width {
                let b = samplePixel(beforeRep, x, y, width, height)
                let a = samplePixel(afterRep, x, y, width, height)
                let diff = abs(Int(b.0) - Int(a.0)) + abs(Int(b.1) - Int(a.1)) + abs(Int(b.2) - Int(a.2))
                let changed = UInt32(diff) > threshold
                // 黑=一致；洋红偏亮=差异（醒目且对色盲友好）
                outRep.setColor(
                    changed
                        ? NSColor(red: 1.0, green: 0.2, blue: 0.9, alpha: 1)
                        : NSColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1),
                    atX: x, y: y)
            }
        }
        let image = NSImage()
        image.addRepresentation(outRep)
        return image
    }

    private func samplePixel(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int,
                             _ width: Int, _ height: Int) -> (UInt8, UInt8, UInt8) {
        // 尺寸不一致时按比例采样（保持可比性）
        let sx = rep.pixelsWide > 0 ? x * rep.pixelsWide / max(width, 1) : 0
        let sy = rep.pixelsHigh > 0 ? y * rep.pixelsHigh / max(height, 1) : 0
        let color = rep.colorAt(x: min(sx, rep.pixelsWide - 1), y: min(sy, rep.pixelsHigh - 1))
            ?? .black
        let converted = color.usingColorSpace(.deviceRGB) ?? .black
        return (UInt8(converted.redComponent * 255),
                UInt8(converted.greenComponent * 255),
                UInt8(converted.blueComponent * 255))
    }

    /// 差异像素百分比（与 differenceImage 同一套采样逻辑）。
    private var differencePercent: Double {
        guard let before = beforeImage, let after = afterImage,
              let beforeTiff = before.tiffRepresentation,
              let afterTiff = after.tiffRepresentation,
              let beforeRep = NSBitmapImageRep(data: beforeTiff),
              let afterRep = NSBitmapImageRep(data: afterTiff) else { return 0 }
        let width = max(beforeRep.pixelsWide, afterRep.pixelsWide)
        let height = max(beforeRep.pixelsHigh, afterRep.pixelsHigh)
        guard width > 0, height > 0, width * height <= 4_000_000 else { return 0 }
        let threshold = UInt32(tolerance * 7.65)
        var changed = 0
        // 大图抽样统计（步长按面积动态取，最多约 25 万采样点）
        let total = width * height
        let step = max(1, Int((Double(total) / 250_000.0).squareRoot()))
        var sampled = 0
        for y in stride(from: 0, to: height, by: step) {
            for x in stride(from: 0, to: width, by: step) {
                let b = samplePixel(beforeRep, x, y, width, height)
                let a = samplePixel(afterRep, x, y, width, height)
                let diff = abs(Int(b.0) - Int(a.0)) + abs(Int(b.1) - Int(a.1)) + abs(Int(b.2) - Int(a.2))
                if UInt32(diff) > threshold { changed += 1 }
                sampled += 1
            }
        }
        guard sampled > 0 else { return 0 }
        return Double(changed) / Double(sampled) * 100
    }

    // MARK: 共用元素

    private var checkerboard: some View {
        GeometryReader { proxy in
            let cell: CGFloat = 9
            let cols = Int(proxy.size.width / cell) + 2
            let rows = Int(proxy.size.height / cell) + 2
            VStack(spacing: 0) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<cols, id: \.self) { col in
                            Rectangle()
                                .fill((row + col) % 2 == 0
                                      ? Color.primary.opacity(0.055)
                                      : Color.primary.opacity(0.015))
                                .frame(width: cell, height: cell)
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func emptyOverlay(_ text: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "photo")
                .font(.system(size: 17))
            Text(text)
                .font(.system(size: 10))
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if pair.beforeBytes > 0 && pair.afterBytes > 0 {
                let delta = pair.afterBytes - pair.beforeBytes
                Label {
                    Text(delta >= 0 ? "+\(Self.formatBytes(delta))" : "-\(Self.formatBytes(-delta))")
                        .font(.system(size: 10, design: .monospaced))
                } icon: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .foregroundStyle(delta >= 0 ? GlassPalette.amber : GlassPalette.mint)
            }
            Spacer(minLength: 0)
            Text(filePath)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    static func formatBytes(_ value: Int) -> String {
        guard value > 0 else { return "0 B" }
        let kb = Double(value) / 1024
        if kb < 1 { return "\(value) B" }
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        return String(format: "%.2f MB", kb / 1024)
    }
}
