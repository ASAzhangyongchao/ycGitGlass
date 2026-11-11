import SwiftUI
import AppKit
import GitCore

@main
struct GitGlassApp: App {
    @State private var state = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(state)
                // 系统「降低透明度」开启时，玻璃自动退化为不透明卡片。
                .environment(\.glassReduceTransparency,
                             NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1180, height: 780)
        .commands {
            CommandMenu("Git") {
                Button("手动刷新") { Task { await state.refresh(reason: .manual) } }
                    .keyboardShortcut("r", modifiers: [.command])
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
    }
}
