import SwiftUI
import GitCore

/// 关于面板：品牌、版本、GitHub 链接、检查更新与状态反馈。
struct AboutSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                Image(nsImage: Brand.headerImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 92, height: 92)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.white.opacity(0.6), lineWidth: 1.5)
                    )
                    .shadow(color: .black.opacity(0.18), radius: 14, x: 0, y: 6)

                VStack(spacing: 5) {
                    HStack(spacing: 8) {
                        Text(Brand.name)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                        Text(Brand.englishName)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Text(Brand.tagline)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 28)
            .padding(.bottom, 18)

            infoCard

            updateCard
                .padding(.top, 12)

            HStack(spacing: 10) {
                linkButton("GitHub 仓库", icon: "chevron.left.forwardslash.chevron.right") {
                    state.openRepositoryPage()
                }
                linkButton("问题反馈", icon: "exclamationmark.bubble") {
                    state.openIssuesPage()
                }
                linkButton("发布历史", icon: "clock.arrow.circlepath") {
                    state.openReleasesPage()
                }
            }
            .padding(.top, 14)

            Spacer(minLength: 12)

            HStack {
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .prominentAction()
            }
            .padding(.bottom, 22)
        }
        .frame(width: 430, height: 560)
        .background(GlassBackground())
    }

    // MARK: 版本信息

    private var infoCard: some View {
        VStack(spacing: 0) {
            row("版本", "v\(AppConfig.appVersion)（\(AppConfig.appBuild)）")
            Divider().opacity(0.5)
            row("系统要求", "macOS 26.0 及以上 · Apple Silicon / Intel 源码重建")
            Divider().opacity(0.5)
            row("开源协议", "MIT License")
            Divider().opacity(0.5)
            row("仓库", AppConfig.repoSlug)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 16)
        .glassSurface(cornerRadius: 14)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .frame(width: 66, alignment: .leading)
            Text(value)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }

    // MARK: 检查更新

    private var updateCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("软件更新")
                    .font(.system(size: 12, weight: .semibold))
                updateStatusText
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)

            if case .available(let info) = state.updateState {
                ActionButton(title: "前往下载", icon: "arrow.down.circle.fill",
                             tint: GlassPalette.mint, prominent: true) {
                    state.openReleasesPage()
                }
                .help(info.htmlURL)
            }

            ActionButton(title: updateButtonTitle, icon: "arrow.triangle.2.circlepath") {
                Task { await state.checkForUpdates() }
            }
            .disabled(isChecking)
        }
        .padding(14)
        .glassSurface(cornerRadius: 14, tint: updateTint)
        .animation(reduceMotion ? nil : Motion.snappy, value: state.updateState)
    }

    private var updateButtonTitle: String {
        if case .available = state.updateState { return "重新检查" }
        return isChecking ? "检查中…" : "检查更新"
    }

    private var isChecking: Bool {
        if case .checking = state.updateState { return true }
        return false
    }

    private var updateTint: Color? {
        switch state.updateState {
        case .available: return GlassPalette.mint.opacity(0.12)
        case .failed: return GlassPalette.rose.opacity(0.10)
        default: return nil
        }
    }

    @ViewBuilder
    private var updateStatusText: some View {
        switch state.updateState {
        case .idle:
            Text("启动时每天最多自动检查一次；也可随时手动检查")
        case .checking:
            Text("正在连接 GitHub…")
        case .upToDate:
            Text("已是最新版本 v\(AppConfig.appVersion)")
        case .available(let info):
            Text("发现新版本 \(info.version)，点击「前往下载」打开发布页")
        case .noReleasesYet:
            Text("仓库还没有发布过版本，可先从源码构建")
        case .failed(let reason):
            Text(reason)
        }
    }

    // MARK: 链接按钮

    private func linkButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 11.5, weight: .medium))
                .fixedSize()
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .foregroundStyle(GlassPalette.blue)
        .glassPill(interactive: true)
        .hoverLift(false)
        .onHover { _ in }
    }
}
