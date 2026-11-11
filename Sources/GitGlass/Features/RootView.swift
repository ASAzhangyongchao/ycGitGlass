import SwiftUI
import GitCore

struct RootView: View {
    @Environment(AppState.self) private var state
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var glassNamespace
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var newBranchName = ""
    @State private var showNewBranch = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 300)
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                BrandHeader()
                    .padding(.bottom, 12)
                topBar
                tabBar
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
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
        // 启动只刷新一次；之后仅由手动按钮 / 切仓库 / 切分支 / 写操作触发。
        .task {
            await state.refresh(reason: .appLaunch)
        }
    }

    // MARK: 顶栏

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(state.currentRepository?.name ?? "还没有仓库")
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .lineLimit(1)
                    HStack(spacing: 7) {
                        Image(systemName: "arrow.triangle.branch").font(.system(size: 10))
                        Text(state.status.branch.isEmpty ? "未选择分支" : state.status.branch)
                            .font(.system(size: 11.5, weight: .medium))
                        if state.status.ahead > 0 {
                            StatusBadge(text: "领先 \(state.status.ahead)", tint: GlassPalette.mint)
                        }
                        if state.status.behind > 0 {
                            StatusBadge(text: "落后 \(state.status.behind)", tint: GlassPalette.amber)
                        }
                    }
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                if state.isBusy {
                    BusyBadge(label: state.busyLabel)
                }

                branchMenu
                    .disabled(state.currentRepository == nil || state.isBusy)

                ActionButton(title: "拉取", icon: "arrow.down") {
                    Task { await state.pull() }
                }
                .disabled(state.currentRepository == nil || state.isBusy)
                .help("用 fast-forward 拉取远程改动，避免多余合并提交")

                ActionButton(title: "推送", icon: "arrow.up", prominent: true) {
                    Task { await state.push() }
                }
                .disabled(state.currentRepository == nil || state.isBusy)

                ActionButton(title: "刷新", icon: "arrow.clockwise") {
                    Task { await state.refresh(reason: .manual) }
                }
                .disabled(state.isBusy)
                .help("手动重新读取状态、分支、历史、远程源与密钥（⌘R）")
            }

            HStack(spacing: 6) {
                Image(systemName: "bolt.horizontal.fill").font(.system(size: 9))
                if let date = state.lastRefreshed {
                    Text("上次刷新 \(date.formatted(.dateTime.hour().minute())) · \(state.lastRefreshReason)")
                } else {
                    Text("数据不会自动轮询，仅在你点刷新、切仓库、切分支或完成操作时更新")
                }
                Spacer()
                Text("空闲零后台任务")
                    .foregroundStyle(.tertiary)
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
        }
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    private var branchMenu: some View {
        Menu {
            Section("本地分支") {
                ForEach(state.localBranches) { branch in
                    Button {
                        Task { await state.checkout(branch) }
                    } label: {
                        HStack {
                            Text(branch.displayName)
                            if branch.isCurrent { Image(systemName: "checkmark") }
                        }
                    }
                }
            }
            if !state.remoteBranches.isEmpty {
                Section("远程分支") {
                    ForEach(state.remoteBranches) { branch in
                        Button(branch.displayName) {
                            Task { await state.checkout(branch) }
                        }
                    }
                }
            }
            Divider()
            Button("新建分支…") { showNewBranch = true }
        } label: {
            Label(state.status.branch.isEmpty ? "选择分支" : state.status.branch,
                  systemImage: "chevron.up.chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .glassPill(interactive: true)
        }
        .menuStyle(.borderlessButton)
        .help("切换分支会自动刷新一次")
    }

    // MARK: 分段控件（玻璃形变过渡）

    @ViewBuilder
    private var tabBar: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 16) {
                tabButtons
            }
            .padding(.bottom, 14)
        } else {
            tabButtons.padding(.bottom, 14)
        }
    }

    private var tabButtons: some View {
        HStack(spacing: 7) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                let selected = state.selectedTab == tab
                Button {
                    withComfortableAnimation(reduceMotion) { state.selectedTab = tab }
                } label: {
                    Label(tab.rawValue, systemImage: tab.symbol)
                        .font(.system(size: 12, weight: selected ? .semibold : .medium))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(selected ? .primary : .secondary)
                .glassPill(tint: selected ? GlassPalette.blue.opacity(0.20) : nil, interactive: true)
                .glassIdentity(tab.rawValue, in: glassNamespace)
            }
            Spacer(minLength: 0)
        }
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
        .id(state.selectedTab)
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .move(edge: .trailing)).combined(with: .scale(scale: 0.99)),
            removal: .opacity
        ))
        .animation(reduceMotion ? nil : Motion.spring, value: state.selectedTab)
    }
}
