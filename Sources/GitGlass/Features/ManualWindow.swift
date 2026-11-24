import SwiftUI
import AppKit
import WebKit
import GitCore

// MARK: - 资源定位
//
// 唯一真源：docs/操作手册.html
//   · 打包后的 .app：Contents/Resources/Manual.html（scripts/build-app.sh 复制）
//   · swift run / 离屏快照 / 自检：从 bundleURL 或本源文件位置向上找到 docs/操作手册.html
// 任何情况下都不要在这里维护第二份内容；找不到时显示可操作的错误页，绝不白屏。

enum ManualResource {
    static let bundledName = "Manual"

    static func url() -> URL? {
        if let bundled = Bundle.main.url(forResource: bundledName, withExtension: "html"),
           FileManager.default.fileExists(atPath: bundled.path) {
            return bundled
        }
        var dirs: [URL] = [Bundle.main.bundleURL]
        dirs.append(URL(fileURLWithPath: #filePath))
        for start in dirs {
            var dir = start
            for _ in 0..<7 {
                let candidate = dir.appendingPathComponent("docs/操作手册.html")
                if FileManager.default.fileExists(atPath: candidate.path) {
                    return candidate
                }
                let parent = dir.deletingLastPathComponent()
                if parent.path == dir.path { break }
                dir = parent
            }
        }
        return nil
    }

    /// 资源缺失时的兜底页：说清怎么修，而不是给一块空白。
    static var fallbackHTML: String {
        """
        <!DOCTYPE html><html lang="zh-CN"><head><meta charset="UTF-8">
        <style>
          body{font-family:-apple-system,"PingFang SC",sans-serif;padding:48px;
               color:#e8edf7;background:#11161f;line-height:1.8}
          h1{font-size:22px;margin:0 0 12px}
          code{background:rgba(126,162,255,.18);padding:2px 6px;border-radius:6px}
          p{color:#a4b1c5;font-size:13px}
        </style></head><body>
        <h1>手册资源未找到</h1>
        <p>应用内手册来自 <code>docs/操作手册.html</code>，打包时由
        <code>scripts/build-app.sh</code> 复制为 <code>Contents/Resources/Manual.html</code>。</p>
        <p>请重新执行 <code>./scripts/build-app.sh</code> 打包，或从源码目录启动应用。
        也可以直接用浏览器打开项目里的 <code>docs/操作手册.html</code>。</p>
        </body></html>
        """
    }
}

// MARK: - 章节目录（窗口顶部「跳转」菜单，与 HTML 左侧目录同源）

enum ManualChapters {
    static let all: [(id: String, title: String)] = [
        ("install", "01 安装与迁移"),
        ("ui", "02 认识界面"),
        ("dashboard", "03 工作台"),
        ("commit", "04 提交代码"),
        ("history", "05 历史 / 遴选 / 冲突"),
        ("stash", "06 储藏与标签"),
        ("remote", "07 远程源"),
        ("keys", "08 SSH 密钥"),
        ("perf", "09 刷新与性能"),
        ("shortcuts", "10 快捷键"),
        ("faq", "11 故障排查"),
        ("privacy", "12 隐私与安全"),
        ("dev", "13 开发者说明")
    ]
}

// MARK: - WebView 桥接：搜索 / 缩放 / 目录跳转 / 外链拦截

@MainActor
final class ManualBrowser: NSObject, WKNavigationDelegate, ObservableObject {
    weak var webView: WKWebView?

    @Published var matchFound: Bool?
    @Published var magnification: CGFloat = 1.0
    @Published var loadFailed = false

    func find(_ query: String) {
        guard let webView, !query.isEmpty else {
            clearSelection()
            matchFound = nil
            return
        }
        let config = WKFindConfiguration()
        config.backwards = false
        config.wraps = true
        config.caseSensitive = false
        webView.find(query, configuration: config) { [weak self] result in
            Task { @MainActor in
                self?.matchFound = result.matchFound
            }
        }
    }

    func clearSelection() {
        webView?.evaluateJavaScript("window.getSelection().removeAllRanges()") { _, _ in }
    }

    func zoom(_ delta: CGFloat) {
        guard let webView else { return }
        let next = min(max(magnification + delta, 0.75), 2.0)
        magnification = next
        webView.allowsMagnification = true
        webView.magnification = next
    }

    func resetZoom() {
        magnification = 1.0
        webView?.magnification = 1.0
    }

    func jump(to id: String) {
        // id 全部来自 ManualChapters 常量，不拼接用户输入，无注入风险。
        let script = "document.getElementById('\(id)')?.scrollIntoView({behavior:'smooth',block:'start'})"
        webView?.evaluateJavaScript(script) { _, _ in }
    }

    func print() {
        guard let webView else { return }
        let operation = NSPrintOperation(view: webView)
        operation.canSpawnSeparateThread = true
        operation.run()
    }

    // 手册里的外链交给系统浏览器，手册窗口不会变成浏览器；本地锚点照常跳转。
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        let url = navigationAction.request.url
        let scheme = url?.scheme?.lowercased() ?? ""
        if scheme == "http" || scheme == "https" {
            if let url { NSWorkspace.shared.open(url) }
            decisionHandler(.cancel)
        } else {
            decisionHandler(.allow)
        }
    }

    func webView(_ webView: WKWebView,
                 didFail navigation: WKNavigation!,
                 withError error: Error) {
        loadFailed = true
    }
}

// MARK: - NSViewRepresentable

struct ManualWebView: NSViewRepresentable {
    let browser: ManualBrowser
    let url: URL?
    /// 由父视图的 colorScheme 驱动，系统切换明暗时 SwiftUI 重绘 → 这里更新 webView 外观，
    /// 从而让手册里的 prefers-color-scheme 跟着翻。
    let scheme: ColorScheme

    func makeCoordinator() -> ManualBrowser { browser }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsMagnification = true
        webView.allowsBackForwardNavigationGestures = true
        applyAppearance(to: webView)
        context.coordinator.webView = webView
        load(into: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        applyAppearance(to: webView)
        if context.coordinator.webView !== webView {
            context.coordinator.webView = webView
        }
    }

    private func applyAppearance(to webView: WKWebView) {
        webView.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
    }

    private func load(into webView: WKWebView) {
        if let url {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            webView.loadHTMLString(ManualResource.fallbackHTML, baseURL: nil)
        }
    }
}

// MARK: - 手册窗口内容

struct ManualWindowView: View {
    @StateObject private var browser = ManualBrowser()
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @Environment(\.colorScheme) private var scheme

    private let resourceURL = ManualResource.url()

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().opacity(0.6)
            if resourceURL == nil {
                missingBanner
            }
            ManualWebView(browser: browser, url: resourceURL, scheme: scheme)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            statusBar
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 760, minHeight: 480)
    }

    // MARK: 顶部工具条

    private var toolbar: some View {
        HStack(spacing: 10) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(GlassPalette.blue)
            VStack(alignment: .leading, spacing: 1) {
                Text("操作手册")
                    .font(.system(size: 13, weight: .bold))
                Text("v\(AppConfig.appVersion) · 离线内置")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 12)

            // 搜索：⌘F 聚焦，回车找下一个
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("搜索手册内容", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5))
                    .focused($searchFocused)
                    .onSubmit { browser.find(query) }
                    .frame(minWidth: 120, idealWidth: 168, maxWidth: 200)
                if !query.isEmpty {
                    Button {
                        query = ""
                        browser.clearSelection()
                        browser.matchFound = nil
                        searchFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    searchFocused = true
                    browser.find(query)
                } label: {
                    Image(systemName: "return")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help("查找下一个（回车）")
                .keyboardShortcut("f", modifiers: [.command])
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.055),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            if let found = browser.matchFound, !query.isEmpty {
                Text(found ? "已找到" : "无结果")
                    .font(.system(size: 9.5))
                    .foregroundStyle(found ? GlassPalette.mint : GlassPalette.rose)
                    .fixedSize()
            }

            Menu {
                ForEach(ManualChapters.all, id: \.id) { chapter in
                    Button(chapter.title) { browser.jump(to: chapter.id) }
                }
            } label: {
                Label("目录", systemImage: "list.bullet")
                    .font(.system(size: 11.5))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("跳转到指定章节")

            HStack(spacing: 4) {
                Button { browser.zoom(-0.15) } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                Button { browser.resetZoom() } label: {
                    Text("\(Int(browser.magnification * 100))%")
                        .font(.system(size: 9.5))
                        .frame(width: 32, height: 20)
                        .contentShape(Rectangle())
                }
                Button { browser.zoom(0.15) } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .background(Color.primary.opacity(0.045),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .help("缩放页面（75% ~ 200%，点百分比复位）")

            Divider().frame(height: 18)

            Button {
                if let url = resourceURL { NSWorkspace.shared.open(url) }
            } label: {
                Image(systemName: "safari").font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .help("在默认浏览器中打开（可打印 / 存为 PDF）")
            .disabled(resourceURL == nil)

            Button {
                browser.print()
            } label: {
                Image(systemName: "printer").font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .help("打印 / 存为 PDF")

            Button("完成") { ManualWindowController.shared.close() }
                .keyboardShortcut(.defaultAction)
                .prominentAction()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 11)
    }

    private var missingBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(GlassPalette.amber)
            Text("未找到内置手册资源，已显示诊断页。请重新运行 scripts/build-app.sh 打包。")
                .font(.system(size: 11))
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(GlassPalette.amber.opacity(0.12))
    }

    private var statusBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "internaldrive")
                .font(.system(size: 9))
            Text("内置离线文档 · 不联网、不上传任何内容")
                .font(.system(size: 9.5))
            Spacer()
            if browser.loadFailed {
                Text("加载失败").foregroundStyle(GlassPalette.rose)
            }
            Text("帮助 ▸ 操作手册　⌘?")
                .font(.system(size: 9.5))
        }
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.03))
    }
}

// MARK: - 单例窗口控制器
//
// 用 AppKit 管理而不是 SwiftUI WindowGroup：菜单栏常驻入口在主窗口关闭后
// 仍要能打开手册；也不与 RootView 的唯一 sheet presenter 抢窗口模态。

@MainActor
final class ManualWindowController {
    static let shared = ManualWindowController()
    private init() {}

    private var window: NSWindow?
    private let autosaveName = "GitGlassManualWindow"

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1060, height: 740),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "码牛 MooGit 操作手册"
        window.minSize = NSSize(width: 760, height: 480)
        window.isReleasedWhenClosed = false
        let hadSavedFrame = UserDefaults.standard.string(forKey: "NSWindow Frame \(autosaveName)") != nil
        window.setFrameAutosaveName(autosaveName)
        if !hadSavedFrame { window.center() }
        window.contentView = NSHostingView(rootView: ManualWindowView())
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.close()
    }

    func openInBrowser() {
        guard let url = ManualResource.url() else { return }
        NSWorkspace.shared.open(url)
    }
}
