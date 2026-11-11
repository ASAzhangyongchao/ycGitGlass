import SwiftUI
import AppKit
import GitCore

/// 图片差异预览：并排 / 滑块叠加 / 感知差异 三种模式，玻璃风格。
struct ImageDiffView: View {
    let pair: ImageDiffService.Pair
    let filePath: String

    enum Mode: String, CaseIterable {
        case side = "并排"
        case slider = "叠加对比"
        case difference = "差异高亮"
    }

    @State private var mode: Mode = .side
    @State private var slider: Double = 50
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var beforeImage: NSImage? {
        pair.beforeData.flatMap { NSImage(data: $0) }
    }

    private var afterImage: NSImage? {
        pair.afterData.flatMap { NSImage(data: $0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            switch mode {
            case .side: sideBySide
            case .slider: sliderCompare
            case .difference: differenceCompare
            }

            footer
        }
        .animation(reduceMotion ? nil : Motion.snappy, value: mode)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Picker("模式", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 220)
            Spacer(minLength: 0)
            StatusBadge(text: (filePath as NSString).lastPathComponent, tint: GlassPalette.violet)
        }
    }

    // MARK: 并排

    private var sideBySide: some View {
        HStack(alignment: .top, spacing: 12) {
            pane(image: beforeImage, label: "旧版本", bytes: pair.beforeBytes,
                 tint: .secondary, placeholder: "旧版本不存在（新增文件）")
            Image(systemName: "arrow.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 60)
            pane(image: afterImage, label: "新版本", bytes: pair.afterBytes,
                 tint: GlassPalette.mint, placeholder: "新版本不存在（文件已删除）")
        }
    }

    private func pane(image: NSImage?, label: String, bytes: Int, tint: Color, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(label).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(tint)
                Text(Self.formatBytes(bytes))
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(.system(size: 18))
                        Text(placeholder)
                            .font(.system(size: 10))
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.tertiary)
                    .padding(10)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 190)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 滑块叠加

    private var sliderCompare: some View {
        VStack(spacing: 8) {
            ZStack {
                if let beforeImage {
                    Image(nsImage: beforeImage)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 190)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    emptyOverlay("旧版本不存在")
                }
                if let afterImage {
                    Image(nsImage: afterImage)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 190)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .mask(
                            GeometryReader { proxy in
                                HStack(spacing: 0) {
                                    Rectangle().frame(width: proxy.size.width * slider / 100)
                                    Color.clear
                                }
                            }
                        )
                }
                // 分割线手柄
                GeometryReader { proxy in
                    let x = proxy.size.width * slider / 100
                    ZStack {
                        Rectangle()
                            .fill(.white)
                            .frame(width: 1.6)
                            .shadow(color: .black.opacity(0.4), radius: 2)
                            .position(x: x, y: proxy.size.height / 2)
                        Circle()
                            .fill(.white)
                            .frame(width: 18, height: 18)
                            .shadow(color: .black.opacity(0.3), radius: 3)
                            .overlay(
                                Image(systemName: "arrow.left.and.right")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(Color(white: 0.25))
                            )
                            .position(x: x, y: proxy.size.height / 2)
                    }
                }
                .allowsHitTesting(false)
            }
            .frame(height: 190)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Slider(value: $slider, in: 0...100) {
                Text("对比位置")
            }
            .labelsHidden()
            HStack {
                Text("旧").font(.system(size: 9.5)).foregroundStyle(.tertiary)
                Spacer()
                Text("新").font(.system(size: 9.5)).foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: 差异高亮（新图叠差分混合）

    private var differenceCompare: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(0.75))
                if let afterImage {
                    Image(nsImage: afterImage)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 190)
                        .clipped()
                        .blendMode(.difference)
                    if let beforeImage {
                        Image(nsImage: beforeImage)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 190)
                            .clipped()
                            .blendMode(.difference)
                    }
                    // 黑色 = 完全一致；亮色 = 像素有差异
                    Image(nsImage: afterImage)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 190)
                        .clipped()
                        .blendMode(.overlay)
                        .opacity(0.15)
                } else {
                    emptyOverlay("没有新版本")
                }
            }
            .frame(height: 190)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text("黑色区域 = 内容一致；发亮区域 = 像素发生变化")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    private func emptyOverlay(_ text: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "photo")
                .font(.system(size: 18))
                .foregroundStyle(.white.opacity(0.5))
            Text(text)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(height: 190)
        .frame(maxWidth: .infinity)
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
