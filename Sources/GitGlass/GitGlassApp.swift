import SwiftUI
import AppKit
import GitCore

@main
struct GitGlassApp: App {
    @State private var state = AppState()

    var body: some Scene {
        WindowGroup(Brand.fullName) {
            RootView()
                .environment(state)
                // 系统「降低透明度」开启时，玻璃自动退化为不透明卡片。
                .environment(\.glassReduceTransparency,
                             NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1180, height: 810)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("关于 码牛 MooGit") {
                    state.openAbout()
                }
            }
            CommandMenu("Git") {
                Button("手动刷新") { Task { await state.refresh(reason: .manual) } }
                    .keyboardShortcut("r", modifiers: [.command])
                Button("检查更新…") { Task { await state.checkForUpdates() } }
                    .keyboardShortcut("u", modifiers: [.command])
                Button("拉取") { Task { await state.pull() } }
                    .keyboardShortcut("l", modifiers: [.command])
                Button("推送") { Task { await state.push() } }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Button("储藏当前改动") { Task { await state.stashPush() } }
                    .keyboardShortcut("s", modifiers: [.command, .option])
                Divider()
                Button("工作台") { withAnimation(Motion.spring) { state.selectedTab = .dashboard } }
                    .keyboardShortcut("1", modifiers: [.command])
                Button("提交") { withAnimation(Motion.spring) { state.selectedTab = .commit } }
                    .keyboardShortcut("2", modifiers: [.command])
                Button("历史") { withAnimation(Motion.spring) { state.selectedTab = .history } }
                    .keyboardShortcut("3", modifiers: [.command])
                Button("储藏 / 标签") { withAnimation(Motion.spring) { state.selectedTab = .stashes } }
                    .keyboardShortcut("4", modifiers: [.command])
                Button("远程源") { withAnimation(Motion.spring) { state.selectedTab = .remotes } }
                    .keyboardShortcut("5", modifiers: [.command])
                Button("密钥") { withAnimation(Motion.spring) { state.selectedTab = .keys } }
                    .keyboardShortcut("6", modifiers: [.command])
            }
        }

        // 屏幕顶部菜单栏常驻入口：关掉主窗口也能快速刷新 / 同步。
        // label 用模板小牛图（自动跟随菜单栏明暗），title 留给无障碍朗读。
        MenuBarExtra {
            menuBarContent
        } label: {
            Image(nsImage: Brand.menuCowImage)
        }
        .menuBarExtraStyle(.menu)
    }

    @ViewBuilder
    private var menuBarContent: some View {
        Text(state.currentRepository?.name ?? "未选择仓库")
        Text("\(state.status.files.count) 个改动 · \(state.status.branch.isEmpty ? "—" : state.status.branch)")
        Divider()
        Button("打开主窗口") {
            if let window = NSApp.windows.first(where: { $0.title.contains(Brand.name) }) {
                window.makeKeyAndOrderFront(nil)
            }
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("手动刷新") { Task { await state.refresh(reason: .manual) } }
            .disabled(state.currentRepository == nil)
        Button("拉取") { Task { await state.pull() } }
            .disabled(state.currentRepository == nil)
        Button("推送") { Task { await state.push() } }
            .disabled(state.currentRepository == nil)
        Divider()
        Button("关于 / 检查更新") { state.openAbout() }
        Divider()
        Button("退出 码牛") { NSApp.terminate(nil) }
    }
}
