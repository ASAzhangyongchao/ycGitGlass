import SwiftUI
import AppKit
import GitCore

/// 品牌常量：工程标识仍为 GitGlass，面向用户的产品名是「码牛 MooGit」。
enum Brand {
    static let name = "码牛"
    static let englishName = "MooGit"
    static let fullName = "码牛 MooGit"
    static let tagline = "轻量 Git 工作台 · 看清每一次改动"
    static let version = "1.2.0"

    /// .app bundle 里由 make-brand-assets.swift 生成；swift run 调试时回退到系统符号。
    static var headerImage: NSImage {
        if let url = Bundle.main.url(forResource: "BrandHeader", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSImage(systemSymbolName: "chevron.left.forwardslash.chevron.right",
                       accessibilityDescription: nil) ?? NSImage()
    }
}

/// 窗口页头的玻璃品牌条：应用图标 + 名称 + 版本 + 当前仓库/分支。
struct BrandHeader: View {
    @Environment(AppState.self) private var state

    var body: some View {
        HStack(spacing: 11) {
            Image(nsImage: Brand.headerImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.55), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.16), radius: 7, x: 0, y: 3)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text(Brand.name)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    Text(Brand.englishName)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    StatusBadge(text: "v\(Brand.version)", tint: GlassPalette.blue)
                }
                Text(Brand.tagline)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            if let repository = state.currentRepository {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill").font(.system(size: 9))
                    Text(repository.name)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                    Text("·").foregroundStyle(.tertiary)
                    Image(systemName: "arrow.triangle.branch").font(.system(size: 9))
                    Text(state.status.branch.isEmpty ? "—" : state.status.branch)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .glassPill()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .glassSurface(cornerRadius: 16, tint: GlassPalette.blue.opacity(0.07))
        .cardShadow()
    }
}
