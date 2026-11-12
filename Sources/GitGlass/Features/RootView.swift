import SwiftUI
import GitCore

struct RootView: View {
    @Environment(AppState.self) private var state
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var newBranchName = ""
    @State private var showNewBranch = false
    @Namespace private var tabIndicator

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 300)
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                // 顶部一行：品牌 + 仓库/分支 + 操作（单一玻璃条，避免嵌套 HStack 宽度歧义）
                BrandHeader()
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
                // 选中胶囊：matchedGeometry 在页签间滑动。
                // 不用 GeometryReader——条件插入的背景 GeometryReader 在
                // macOS 26 会向 AutoLayout 输出歧义约束（切页时崩溃根源）。
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
                    .padding(3)
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
