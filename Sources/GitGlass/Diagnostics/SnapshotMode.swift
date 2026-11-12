import SwiftUI
import AppKit
import GitCore

/// 调试用：离屏渲染 HistoryView 快照（模拟工作台点击最近提交后的状态）。
/// 用 `GitGlass --snap out.png [w h]` 触发，正常启动不执行。
@MainActor
enum SnapshotMode {
    static func run() -> Bool {
        let args = CommandLine.arguments
        guard args.contains("--snap"), let index = args.firstIndex(of: "--snap"),
              args.count > index + 1 else { return false }
        setbuf(stdout, nil)
        let out = args[index + 1]
        let width: CGFloat = args.count > index + 3 ? CGFloat(Int(args[index + 2]) ?? 1100) : 1100
        let height: CGFloat = args.count > index + 3 ? CGFloat(Int(args[index + 3]) ?? 700) : 700
        let page = args.count > index + 4 ? args[index + 4] : "history"

        let state = AppState()
        let repo = Repository(id: UUID(), name: "GitGlass", path: "/tmp/xx")
        state.repositories = [repo]
        state.selectedRepoID = repo.id
        var status = WorktreeStatus.empty
        status.branch = "main"
        state.status = status
        var status2 = state.status
        status2.files = [
            FileChange(path: "Sources/App.swift", indexStatus: "M", worktreeStatus: " "),
            FileChange(path: "docs/说明.md", indexStatus: "?", worktreeStatus: "?")
        ]
        state.status = status2
        var commits: [Commit] = []
        for index in 0..<30 {
            // 模拟宽轨道（多分支并行）：偶数行多几条竖线，验证折叠策略
            let graph: String
            if page == "widegraph" {
                // 20 字符 ≈ 10 条并行分支 → 必须触发自动折叠
                graph = "* | | | | | | | | | |"
            } else {
                switch index % 3 {
                case 0: graph = "* | | |\\"
                case 1: graph = "* | | | |"
                default: graph = "* | | |/ "
                }
            }
            commits.append(Commit(
                hash: "hash\(index)", shortHash: "s\(index)abc",
                author: "张三", email: "z@x.c",
                date: "2026-11-11T09:\(String(format: "%02d", index % 60)):00+08:00",
                subject: "提交主题 \(index) 修复某某问题",
                body: "", refs: index == 0 ? "HEAD -> main" : "",
                graph: graph
            ))
        }
        state.commits = commits
        state.selectedCommit = commits[0]
        state.showDetailPanel = true
        if page == "diff" { state.showDiffViewer = true }
        if page == "history" { state.showDetailPanel = true }
        state.commitDetail = CommitDetail(
            hash: "hash0", authorName: "张三", authorEmail: "z@x.c",
            authorDate: "2026-11-11 09:00",
            committerName: "张三", committerEmail: "z@x.c",
            committerDate: "2026-11-11 09:00",
            parents: [], subject: "提交主题 0", body: "", refs: "HEAD -> main",
            changedFiles: [], insertions: 10, deletions: 2, fileCount: 0)

        _ = NSApplication.shared
        let content: AnyView = {
            switch page {
            case "dashboard": return AnyView(DashboardView().environment(state))
            case "commit": return AnyView(CommitView().environment(state))
            case "diff": return AnyView(HistoryView().environment(state))
            case "root": return AnyView(RootView().environment(state))
            case "commitdiff":
                // 复现提交页沉浸式 diff：模拟 loadDiff 完成后的状态
                state.diffFilePath = "Sources/App.swift"
                state.diffText = """
                diff --git a/Sources/App.swift b/Sources/App.swift
                index 83db48f..777d10e 100644
                --- a/Sources/App.swift
                +++ b/Sources/App.swift
                @@ -1,3 +1,4 @@
                 line1
                -line2
                +line2 CHANGED
                 line3
                +line4 NEW
                """
                print("SNAP diffFilePath=[\(state.diffFilePath)] diffText.len=\(state.diffText.count)")
                return AnyView(CommitView().environment(state))
            case "mascotcheck":
                // 布局实测：量正常态与愤怒态的 MascotCow 实际高度，必须相等
                return AnyView(VStack(spacing: 30) {
                    HeightProbe(label: "normal") { MascotCow(isBusy: false) }
                    HeightProbe(label: "angry") { MascotCow(isBusy: false, initiallyAngry: true) }
                }.padding(40))
            default: return AnyView(HistoryView().environment(state))
            }
        }()
        let host = NSHostingView(rootView: content)
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        host.layoutSubtreeIfNeeded()
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))

        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return true }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        if let tiff = bitmap.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: out))
            print("saved: \(out)")
        }
        exit(0)
    }
}

/// 布局探针：渲染 content 并输出实际占用高度（stdout 供脚本断言）。
private struct HeightProbe<Content: View>: View {
    let label: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 4) {
            content()
            GeometryReader { geo in
                Color.clear
                    .onAppear { print("HEIGHT[\(label)]=\(geo.size.height)") }
            }
            .frame(height: 0)
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { print("TOTAL[\(label)]=\(geo.size.height)") }
            }
        )
    }
}


