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

        // 新建分支弹窗的重名校验需要一份真实分支列表
        state.branches = [
            Branch(name: "main", isCurrent: true),
            Branch(name: "dev"),
            Branch(name: "feature/payment-refactor"),
            Branch(name: "origin/main", isRemote: true)
        ]

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
            case "branchpicker":
                // 分支选择器：验证底部「新建分支」按钮的可视性与展开后的内联输入
                state.showNewBranchSheet = false
                return AnyView(
                    BranchPickerSheet()
                        .environment(state)
                        .padding(16)
                        .background(GlassBackground())
                )
            case "newbranch", "newbranch-error", "newbranch-invalid", "newbranch-from":
                // 新建分支弹窗的三种状态：空 / 重名报错 / 非法字符报错（+ 基于提交）
                let initial: String
                switch page {
                case "newbranch-error": initial = "main"
                case "newbranch-invalid": initial = "feature/bad name"
                default: initial = ""
                }
                let start = page == "newbranch-from" ? "a1b2c3d4e5f6a7b8c9d0" : nil
                return AnyView(
                    NewBranchSheet(startPoint: start, initialName: initial)
                        .environment(state)
                        .padding(20)
                        .background(GlassBackground())
                )
            case "hunkonly":
                // 直渲染 HunkDiffView：验证分块卡片的排版与按钮位置
                state.diffFilePath = "Sources/App.swift"
                let sample = """
                diff --git a/Sources/App.swift b/Sources/App.swift
                index 83db48f..777d10e 100644
                --- a/Sources/App.swift
                +++ b/Sources/App.swift
                @@ -12,6 +12,7 @@ struct App {
                     let store = Store()
                     let cache = Cache()
                -    var legacyFlag = true
                +    var flag = true
                +    var extra = false
                     init() { configure() }
                     func run() { loop() }
                 }
                @@ -40,3 +41,4 @@ extension App {
                     func stop() {}
                     func reset() {}
                +    func ping() {}
                 }
                """
                let fake = FileChange(path: "Sources/App.swift", indexStatus: " ", worktreeStatus: "M")
                return AnyView(
                    HunkDiffView(text: sample, file: fake)
                        .environment(state)
                        .frame(width: 520, height: 620)
                        .padding(20)
                        .background(GlassBackground())
                )
            case "mascotcheck":
                // 布局实测：量正常态与愤怒态的 MascotCow 实际高度，必须相等
                return AnyView(VStack(spacing: 30) {
                    HeightProbe(label: "normal") { MascotCow(isBusy: false) }
                    HeightProbe(label: "angry") { MascotCow(isBusy: false, initiallyAngry: true) }
                }.padding(40))
            case "about":
                // 关于面板：验证卡片内边距（内容不贴玻璃背景边缘）
                return AnyView(
                    AboutSheet()
                        .environment(state)
                        .padding(16)
                        .background(GlassBackground())
                )
            case "teaching":
                // 教学弹层直渲染：验证 TeachingTipView 内容完整性
                return AnyView(HStack(spacing: 20) {
                    TeachingTipView(tip: Teachings.commitFiles)
                    TeachingTipView(tip: Teachings.mascot)
                }.padding(30).environment(state))
            default: return AnyView(HistoryView().environment(state))
            }
        }()
        let host = NSHostingView(rootView: content)
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        // macOS 26 的玻璃 / 材质效果只在真实窗口里绘制：先挂到离屏窗口再截图，
        // 否则 cacheDisplay 得到的是全透明空图。
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        host.layoutSubtreeIfNeeded()

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


