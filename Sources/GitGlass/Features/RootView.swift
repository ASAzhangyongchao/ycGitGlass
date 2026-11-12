import SwiftUI
import GitCore

struct RootView: View {
    @Environment(AppState.self) private var state
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var newBranchName = ""
    @State private var showNewBranch = false
    @State private var showBranchPicker = false
    @Namespace private var tabIndicator

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 300)
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                // 顶部一行：品牌 + 仓库/分支 + 操作（合并原 actionBar，省一整行）
                HStack(spacing: 10) {
                    BrandHeader()
                    actionBarInline
                }
                .padding(.bottom, 8)
                tabBar
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
        }
        .navigationSplitViewStyle(.balanced)
        .background(GlassBackground())
        .frame(minWidth: 980, minHeight: 640)
        .overlay(alignment: .bottom) {
            NoticeBanner().padding(.bottom, 22)
        }
        .sheet(isPresented: $showNewBranch) {
            TextInputSheet(
                title: "新建分支",
                placeholder: "例如 feature/login",
                confirmTitle: "创建并切换",
                hint: "会从当前分支切出一个新分支，创建后自动刷新一次。",
                text: $newBranchName
            ) {
                Task { await state.createBranch(newBranchName) }
                newBranchName = ""
            }
        }
        .sheet(isPresented: $showBranchPicker) {
            BranchPickerSheet()
        }
        .sheet(isPresented: Binding(
            get: { state.showAbout },
            set: { if !$0 { state.showAbout = false } }
        )) {
            AboutSheet()
        }
        // 启动只刷新一次；更新检查距上次 ≥24h 才静默做一次，同样不轮询。
        .task {
            await state.refresh(reason: .appLaunch)
            await state.autoCheckForUpdatesIfNeeded()
        }
    }

    // MARK: 操作行（仓库/分支信息已并入品牌行，这里只留动作，不再重复两遍）

    /// 顶部操作区（并入品牌行）：分支选择器 + 拉取/推送/刷新紧凑图标
    private var actionBarInline: some View {
        HStack(spacing: 8) {
            if state.isBusy {
                BusyBadge(label: state.busyLabel)
            }

            branchMenu
                .disabled(state.currentRepository == nil || state.isBusy)

            SmallIconButton(icon: "arrow.down", helpText: "拉取（fast-forward，避免多余合并提交）") {
                Task { await state.pull() }
            }
            .disabled(state.currentRepository == nil || state.isBusy)

            SmallIconButton(icon: "arrow.up", helpText: "推送到远程；首次推送自动建立上游") {
                Task { await state.push() }
            }
            .disabled(state.currentRepository == nil || state.isBusy)

            SmallIconButton(icon: "arrow.clockwise", helpText: "手动刷新（⌘R）：状态、分支、历史、远程源与密钥") {
                Task { await state.refresh(reason: .manual) }
            }
            .disabled(state.isBusy)
        }
    }



    private var branchMenu: some View {
        Button {
            showBranchPicker = true
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 11, weight: .semibold))
                Text(state.status.branch.isEmpty ? "选择分支" : state.status.branch)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 180, alignment: .leading)
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassPill(interactive: true)
        }
        .buttonStyle(.plain)
        .help("打开分支选择器：搜索、本地/远程分页、按来源折叠")
    }

    // MARK: 分段控件（玻璃形变过渡）

    @ViewBuilder
    private var tabBar: some View {
        tabButtons
            .padding(.bottom, 14)
    }

    /// 页签栏：单一玻璃轨道 + 等宽六格 + 滑动选中胶囊。
    /// 关键体感修复：高度恒定（不换行不跳变），窄窗口下文字平滑收缩为纯图标，
    /// 选中胶囊用 matchedGeometry 在格间滑动——不再是"整块滑到左边"的换行布局。
    private var tabButtons: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                tabCell(tab)
            }
        }
        .frame(maxWidth: .infinity)
        .glassSurface(cornerRadius: 13)
        .padding(.bottom, 2)
    }

    private func tabCell(_ tab: AppTab) -> some View {
        let selected = state.selectedTab == tab
        return Button {
            withComfortableAnimation(reduceMotion) { state.selectedTab = tab }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(selected ? GlassPalette.blue : .secondary)
                // 窄窗口自动让位：文字用低优先级布局，空间不足时优雅隐藏，留下图标
                Text(tab.rawValue)
                    .font(.system(size: 11.5, weight: selected ? .semibold : .medium))
                    .lineLimit(1)
                    .fixedSize()
                    .layoutPriority(selected ? 1 : 0)
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? .primary : .secondary)
        .background {
            if selected {
                // 选中胶囊：matchedGeometry 在页签间滑动（平滑体感的关键）
                GeometryReader { proxy in
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(colors: [GlassPalette.blue.opacity(0.18), GlassPalette.violet.opacity(0.14)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(GlassPalette.blue.opacity(0.25), lineWidth: 1)
                        )
                        .shadow(color: GlassPalette.blue.opacity(0.15), radius: 6, y: 2)
                        .frame(width: proxy.size.width - 6, height: proxy.size.height - 6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .matchedGeometryEffect(id: "tab-indicator", in: tabIndicator)
                .transition(.opacity)
                .allowsHitTesting(false)
            }
        }
        .animation(reduceMotion ? nil : Motion.spring, value: state.selectedTab)
        .help("\(tab.rawValue)（⌘\(tabIndex(tab))）")
    }

    private func tabIndex(_ tab: AppTab) -> Int {
        guard let index = AppTab.allCases.firstIndex(of: tab) else { return 1 }
        return index + 1
    }

    // MARK: 内容区

    @ViewBuilder
    private var content: some View {
        Group {
            switch state.selectedTab {
            case .dashboard: DashboardView()
            case .commit: CommitView()
            case .history: HistoryView()
            case .stashes: StashView()
            case .remotes: RemoteView()
            case .keys: SSHKeyView()
            }
        }
        // 纯交叉淡化：不用 .id() 强制重建 + move 过渡——
        // 从工作台带详情跳转历史页时，嵌套 move 动画会让布局卡在空态（实测空白卡）。
        .transition(.opacity)
        .animation(reduceMotion ? nil : Motion.snappy, value: state.selectedTab)
    }
}
