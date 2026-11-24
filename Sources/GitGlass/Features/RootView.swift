import SwiftUI
import GitCore

/// 窗口级弹窗的唯一槽位。
///
/// macOS 上同一视图链挂多个 `.sheet` 时，呈现请求会互相竞争（系统只维护
/// 一个 window-modal presenter），实测容易出现「状态改了、面板不弹」。
/// 所有窗口级弹窗因此收口成一个 `.sheet(item:)`，谁来都只走这一扇门。
private enum RootSheet: Identifiable {
    case branchPicker
    case about
    case newBranch(startPoint: String?)

    var id: String {
        switch self {
        case .branchPicker: return "branchPicker"
        case .about: return "about"
        case .newBranch(let start): return "newBranch-\(start ?? "HEAD")"
        }
    }
}

struct RootView: View {
    @Environment(AppState.self) private var state
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var activeSheet: RootSheet?
    @State private var hoveringCapsule = false
    @Namespace private var tabIndicator

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 300)
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                tabBar
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 20)
            // 页签条别贴住系统标题栏：detail 区从 toolbar 下沿直接起，
            // 少了这一层会让六格玻璃轨道和上面的仓库/分支胶囊挤成一条。
            .padding(.top, 16)
            .padding(.bottom, 14)
        }
        .navigationSplitViewStyle(.balanced)
        .background(GlassBackground())
        .frame(minWidth: 980, minHeight: 640)
        // 系统标题栏：左侧品牌 + 仓库/分支胶囊（点击开分支选择器）
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                // 胶囊 + 工具按钮收进同一个 toolbar item 的 HStack 里。
                // macOS 会按自己的规则给 group 内 item 排序（实测把自定义视图
                // 甩到最右、贴住窗口边缘，左右内边距一起消失），合成一个 item
                // 之后顺序、项间距、与窗口右缘的距离全部由这里控制。
                HStack(spacing: 8) {
                    branchCapsule

                    if state.isBusy {
                        BusyBadge(label: state.busyLabel)
                    }
                    ToolbarIconButton(icon: "arrow.down", label: "拉取",
                                      help: "拉取远程改动（fast-forward）") {
                        Task { await state.pull() }
                    }
                    .disabled(state.currentRepository == nil || state.isBusy)

                    ToolbarIconButton(icon: "arrow.up", label: "推送",
                                      help: "推送到远程；首次自动建立上游") {
                        Task { await state.push() }
                    }
                    .disabled(state.currentRepository == nil || state.isBusy)

                    ToolbarIconButton(icon: "arrow.clockwise", label: "刷新",
                                      help: "手动刷新（⌘R）") {
                        Task { await state.refresh(reason: .manual) }
                    }
                    .disabled(state.isBusy)

                    ToolbarIconButton(icon: "clock.arrow.circlepath", label: "历史",
                                      help: "查看刷新历史") {
                        state.showRefreshHistoryPopoverNow()
                    }

                    ToolbarIconButton(icon: "book.closed", label: "手册",
                                      help: "打开操作手册（⌘?）") {
                        ManualWindowController.shared.show()
                    }

                    ToolbarIconButton(icon: "info.circle", label: "关于",
                                      help: "关于 码牛 MooGit · 版本 · 检查更新") {
                        state.openAbout()
                    }
                }
                .padding(.trailing, 16)
            }
            // macOS 26 会给同一 ToolbarItem 内的内容套一层共享圆角底色，
            // 这层容器右边界被系统钉在窗口右缘内侧约 3px 处——外面再加多少
            // padding 都会被它吞掉（实测 6 / 12 / 40 三个值，容器位置一动不动）。
            // 关掉共享背景，胶囊与图标按自己的布局落位，右侧留白才真正可控。
            .sharedBackgroundVisibility(.hidden)
        }
        .overlay(alignment: .bottom) {
            NoticeBanner().padding(.bottom, 22)
        }
        // 唯一弹窗出口：分支选择器 / 关于 都从这里出，避免多个 sheet
        // 抢同一个 window-modal presenter。
        .sheet(item: $activeSheet) { which in
            switch which {
            case .branchPicker:
                BranchPickerSheet()
                    .environment(state)
            case .about:
                AboutSheet()
            case .newBranch(let startPoint):
                NewBranchSheet(startPoint: startPoint)
                    .environment(state)
            }
        }
        // AppState 里的两个「请求打开」信号当作一次性事件：
        // 收到即置回 false，并转成本地 activeSheet。
        // 按钮 / 菜单 / 自动更新提示因此共用同一条呈现链路。
        .onChange(of: state.showBranchPickerSheet) { _, open in
            guard open else { return }
            state.showBranchPickerSheet = false
            openBranchPicker()
        }
        .onChange(of: state.showAbout) { _, open in
            guard open else { return }
            state.showAbout = false
            activeSheet = .about
        }
        .onChange(of: state.showNewBranchSheet) { _, open in
            guard open else { return }
            state.showNewBranchSheet = false
            activeSheet = .newBranch(startPoint: state.newBranchStartPoint)
        }
        .alert("刷新历史", isPresented: Binding(
            get: { state.showRefreshHistoryPopover },
            set: { state.showRefreshHistoryPopover = $0 }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            if let date = state.lastRefreshed {
                Text("\(date.formatted(.dateTime.month().day().hour().minute())) · \(state.lastRefreshReason)\n空闲零后台任务，数据只在手动刷新、切仓库 / 分支、操作完成后更新")
            } else {
                Text("还没有刷新记录。数据只在手动刷新、切仓库 / 分支、操作完成后更新")
            }
        }
        // 启动只刷新一次；更新检查距上次 ≥24h 才静默做一次，同样不轮询。
        .task {
            await state.refresh(reason: .appLaunch)
            await state.autoCheckForUpdatesIfNeeded()
        }
    }

    /// 顶栏「仓库 · 分支」胶囊：点击打开分支选择器。
    private var branchCapsule: some View {
        Button {
            openBranchPicker()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "folder.fill").font(.system(size: 9))
                Text(state.currentRepository?.name ?? "")
                    .font(.system(size: 11, weight: .medium))
                Text("·").font(.system(size: 10)).foregroundStyle(.tertiary)
                Image(systemName: "arrow.triangle.branch").font(.system(size: 9))
                Text(state.status.branch.isEmpty ? "—" : state.status.branch)
                    .font(.system(size: 11, design: .monospaced))
                if state.status.ahead + state.status.behind > 0 {
                    Text("↑\(state.status.ahead) ↓\(state.status.behind)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(GlassPalette.mint)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            // 左右各 14pt：胶囊底色在深色玻璃上很淡，内边距给足才看得出
            // "字在胶囊里"而不是"字直接浮着、跟旁边的图标贴一起"。
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(hoveringCapsule ? 0.16 : 0.09), in: Capsule())
            .overlay {
                // 一层极细描边把胶囊轮廓勾出来，纯填充在深底上边界会糊掉
                Capsule().strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.8)
            }
            // 显式命中形状：胶囊内边距也算点击热区，避免点在文字空隙无反应
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hoveringCapsule = $0 }
        .disabled(state.currentRepository == nil)
        .opacity(state.currentRepository == nil ? 0 : 1)
        .help("点击打开分支选择器（⌘⇧B）；右键可新建分支（⌘⌥N）")
        .contextMenu {
            Button("切换分支…") { openBranchPicker() }
            Button("新建分支…") { state.requestNewBranch() }
            Divider()
            Button("复制当前分支名") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(state.status.branch, forType: .string)
            }
            .disabled(state.status.branch.isEmpty)
        }
    }

    /// 打开分支选择器的唯一入口：顶栏胶囊、⌘⇧B、以及外部信号都走这里。
    private func openBranchPicker() {
        guard state.currentRepository != nil else { return }
        activeSheet = .branchPicker
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
