import SwiftUI
import AppKit
import GitCore

/// 品牌常量：工程标识仍为 GitGlass，面向用户的产品名是「码牛 MooGit」。
enum Brand {
    static let name = "码牛"
    static let englishName = "MooGit"
    static let fullName = "码牛 MooGit"
    static let tagline = "轻量 Git 工作台 · 看清每一次改动"
    static var version: String { AppConfig.appVersion }
    static var repoSlug: String { AppConfig.repoSlug }
    static var repoURL: URL { AppConfig.repoURL }
    static var releasesURL: URL { AppConfig.releasesURL }

    /// .app bundle 里由 make-brand-assets.swift 生成；swift run 调试时回退到系统符号。
    static var headerImage: NSImage {
        if let url = Bundle.main.url(forResource: "BrandHeader", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSImage(systemSymbolName: "chevron.left.forwardslash.chevron.right",
                       accessibilityDescription: nil) ?? NSImage()
    }

    /// 菜单栏迷你小牛（模板图：自动跟随菜单栏明暗，单色镂空）。
    static var menuCowImage: NSImage {
        if let url = Bundle.main.url(forResource: "MenuCowTemplate", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.isTemplate = true
            return image
        }
        // 兜底：SF Symbol（非 .app 环境运行时）
        return NSImage(systemSymbolName: "chevron.left.forwardslash.chevron.right",
                       accessibilityDescription: nil) ?? NSImage()
    }
}

/// 窗口顶部紧凑品牌行：小 logo + 名称（点开「关于」）+ 当前仓库/分支胶囊 + 更新状态点。
/// 上一版品牌条与顶栏重复显示「仓库名 + 分支」且把内容区压矮，这里收成单行。
struct BrandHeader: View {
    @Environment(AppState.self) private var state

    var body: some View {
        HStack(spacing: 10) {
            Button {
                state.openAbout()
            } label: {
                HStack(spacing: 7) {
                    Image(nsImage: Brand.headerImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 20, height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .stroke(Color.white.opacity(0.55), lineWidth: 0.8)
                        )

                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 5) {
                            Text(Brand.name)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                            Text(Brand.englishName)
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("查看关于、版本与检查更新")

            if state.currentRepository != nil {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill").font(.system(size: 9))
                    Text(state.currentRepository?.name ?? "")
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                    Text("·").foregroundStyle(.tertiary)
                    Image(systemName: "arrow.triangle.branch").font(.system(size: 9))
                    Text(state.status.branch.isEmpty ? "—" : state.status.branch)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                    if state.status.ahead + state.status.behind > 0 {
                        Text("↑\(state.status.ahead) ↓\(state.status.behind)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(GlassPalette.mint)
                    }
                }
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.leading, 14)
                .padding(.trailing, 14)
                .padding(.vertical, 6)
                .glassPill()
            }

            Spacer(minLength: 8)

            updateBadge

            SmallIconButton(icon: "info.circle", helpText: "关于 码牛 MooGit · 版本 · GitHub") {
                state.openAbout()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .glassSurface(cornerRadius: 13, tint: GlassPalette.blue.opacity(0.07))
    }

    /// 更新状态：有新版本时给出醒目入口；平时只留一个安静的刷新点。
    @ViewBuilder
    private var updateBadge: some View {
        switch state.updateState {
        case .available(let info):
            Button {
                state.openAbout()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundStyle(GlassPalette.mint)
                    Text("新版本 \(info.version)")
                        .font(.system(size: 11, weight: .semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
            }
            .buttonStyle(.plain)
            .glassPill(tint: GlassPalette.mint.opacity(0.16), interactive: true)
            .help("有可用更新，点击查看")
            .transition(.scale.combined(with: .opacity))
        case .checking:
            ProgressView()
                .controlSize(.small)
                .help("正在检查更新")
        default:
            EmptyView()
        }
    }
}
