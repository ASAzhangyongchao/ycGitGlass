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
    @State private var showRefreshHistory = false
    @State private var isHovering = false

    /// 操作行：品牌与仓库/分支已上移系统标题栏，这里只留高频操作。
    /// 图标+文字标签（可读优先），悬停浮起提示可点。
    var body: some View {
        HStack(spacing: 8) {
            if state.isBusy {
                BusyBadge(label: state.busyLabel)
            }

            Spacer(minLength: 8)

            labeledIconButton(icon: "arrow.down", label: "拉取",
                              help: "拉取远程改动（fast-forward，避免多余合并提交）") {
                Task { await state.pull() }
            }
            .disabled(state.currentRepository == nil || state.isBusy)

            labeledIconButton(icon: "arrow.up", label: "推送",
                              help: "推送到远程；首次推送自动建立上游关联") {
                Task { await state.push() }
            }
            .disabled(state.currentRepository == nil || state.isBusy)

            labeledIconButton(icon: "arrow.clockwise", label: "刷新",
                              help: "手动刷新（⌘R）：状态、分支、历史、远程源与密钥") {
                Task { await state.refresh(reason: .manual) }
            }
            .disabled(state.isBusy)

            updateBadge

            labeledIconButton(icon: "clock.arrow.circlepath", label: "历史",
                              help: "查看刷新历史") {
                showRefreshHistory.toggle()
            }
            .popover(isPresented: $showRefreshHistory, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    if let date = state.lastRefreshed {
                        Text("上次刷新")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                        Text("\(date.formatted(.dateTime.month().day().hour().minute())) · \(state.lastRefreshReason)")
                            .font(.system(size: 11.5, design: .monospaced))
                    } else {
                        Text("还没有刷新记录")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                    Divider().opacity(0.5)
                    Text("空闲零后台任务 · 数据只在手动刷新、切仓库 / 分支、操作完成后更新")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .padding(12)
                .frame(width: 250, alignment: .leading)
            }

            labeledIconButton(icon: "info.circle", label: "关于",
                              help: "关于 码牛 MooGit · 版本 · GitHub · 检查更新") {
                state.openAbout()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .glassSurface(cornerRadius: 13, tint: GlassPalette.blue.opacity(0.07))
    }

    /// 紧凑图标按钮（悬停浮出文字说明）
    private func labeledIconButton(icon: String, label: String, help: String,
                                    action: @escaping () -> Void) -> some View {
        HoverHintButton(icon: icon, hint: label, help: help, action: action)
    }
}

/// 紧凑图标按钮：默认只显示图标；悬停时按钮下方浮出文字标签。
private struct HoverHintButton: View {
    let icon: String
    let hint: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10.5, weight: .medium))
                .frame(width: 24, height: 20)
                .background(hovering ? Color.primary.opacity(0.10) : Color.primary.opacity(0.05),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(alignment: .bottom) { hoverLabel }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .onHover { hovering = $0 }
        .help(help)
    }

    @ViewBuilder
    private var hoverLabel: some View {
        if hovering {
            Text(hint)
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.98),
                            in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
                .fixedSize()
                .offset(y: 26)
                .zIndex(10)
        }
    }
}

extension BrandHeader {
    /// 更新状态：有新版本时给出醒目入口；平时安静。
    @ViewBuilder
    var updateBadge: some View {
        switch state.updateState {
        case .available(let info):
            Button {
                state.openAbout()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundStyle(GlassPalette.mint)
                    Text("新版本 \(info.version)")
                        .font(.system(size: 10.5, weight: .semibold))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(GlassPalette.mint.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
            .help("发现新版本 \(info.version)，点击查看")
        default:
            EmptyView()
        }
    }
}
