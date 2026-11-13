import SwiftUI
import GitCore

/// 工作台：一屏看完全天要处理的事，常用动作一步到位。
struct DashboardView: View {
    @Environment(AppState.self) private var state
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                greeting
                    .padding(.top, 10)
                if state.currentRepository == nil {
                    EmptyStateView(
                        title: "先添加一个仓库",
                        message: "在左侧点「添加仓库…」选择本地 Git 文件夹，或用「扫描文件夹」一次导入多个项目。",
                        icon: "folder.badge.gearshape"
                    )
                    .frame(minHeight: 320)
                } else {
                    if let operation = state.inProgressOperation {
                        operationBanner(operation)
                    }
                    HStack(alignment: .top, spacing: 16) {
                        quickActions
                        recentCommits
                    }
                    if !state.onboardingSeen { onboarding }
                }
            }
            .padding(.vertical, 6)
            .padding(.bottom, 20)
        }
        .animation(Motion.spring, value: state.status.files.count)
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(Date.now.formatted(.dateTime.month().day().weekday(.wide)))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
            Text(summary)
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .lineLimit(2)
        }
    }

    /// 问候语只做情绪与状态判断，不复述具体数字（数字由下方统计块唯一呈现）。
    private var summary: String {
        guard let repo = state.currentRepository else { return "开始管理你的 Git 仓库" }
        if state.inProgressOperation != nil {
            return "\(repo.name) 有操作待处理，先解决再继续"
        }
        if state.status.isClean {
            return "\(repo.name) 一切干净，随时可以开始"
        }
        return state.status.stagedCount > 0
            ? "\(repo.name) 已备好一批改动，可以提交了"
            : "\(repo.name) 有新改动，看看要不要暂存"
    }

    private func operationBanner(_ operation: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16))
                .foregroundStyle(GlassPalette.amber)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(operation)操作进行中")
                    .font(.system(size: 12.5, weight: .semibold))
                Text("可能遇到了冲突，先处理再继续提交。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            ActionButton(title: "去处理", icon: "arrow.right", prominent: true) {
                withComfortableAnimation(reduceMotion) { state.selectedTab = .stashes }
            }
        }
        .padding(14)
        .glassSurface(cornerRadius: 16, tint: GlassPalette.amber.opacity(0.14))
        .cardShadow()
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var quickActions: some View {
        GlassCard(title: "今天要做的事", icon: "bolt.fill",
                  help: "按推荐顺序三步走：拉取 → 暂存 → 提交推送。",
                  helpSteps: Teachings.dashboardActions.steps,
                  helpFootnote: Teachings.dashboardActions.footnote) {
            VStack(alignment: .leading, spacing: 11) {
                actionRow(number: "1", title: "拉取远程改动", caption: "先同步，避免推送被拒绝", icon: "arrow.down") {
                    Task { await state.pull() }
                }
                actionRow(number: "2", title: "查看并暂存改动", caption: "勾选文件、写好一句说明", icon: "doc.text.magnifyingglass") {
                    withComfortableAnimation(reduceMotion) { state.selectedTab = .commit }
                }
                actionRow(number: "3", title: "一键提交全部并推送", caption: "自动暂存所有改动并生成简洁说明", icon: "paperplane.fill") {
                    Task { await state.quickCommitAll() }
                }
                .disabled(state.status.isClean)
                // 说明：刷新按钮在顶栏（⌘R）、历史在页签（⌘3），这里不再重复放一份。
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func actionRow(number: String, title: String, caption: String, icon: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Text(number)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(GlassPalette.accent.opacity(0.85), in: Circle())
                Image(systemName: icon).font(.system(size: 12)).foregroundStyle(GlassPalette.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 12.5, weight: .semibold))
                    Text(caption).font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            .padding(10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .disabled(state.isBusy)
    }

    private var recentCommits: some View {
        GlassCard(title: "最近提交", icon: "clock",
                  help: "点任意一条跳到历史页并展开该提交的详情与变更文件。",
                  helpSteps: [
                    .init("clock.arrow.circlepath", "看历史", "最近 5 条提交；点一条直奔历史页详情。"),
                    .init("sidebar.right", "看细节", "详情里有变更文件树、逐文件差异、遴选 / 还原 / 打标签。"),
                  ],
                  helpFootnote: "历史页顶部搜索框可按说明 / 作者 / hash 即时过滤。") {
            if state.commits.isEmpty {
                Text("这个仓库还没有提交记录")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(state.commits.prefix(5).enumerated()), id: \.element.id) { index, commit in
                        Button {
                            withComfortableAnimation(reduceMotion) { state.selectedTab = .history }
                            Task { await state.selectCommit(commit) }
                        } label: {
                            HStack(alignment: .top, spacing: 9) {
                                Circle()
                                    .fill(GlassPalette.accent.opacity(0.65))
                                    .frame(width: 6, height: 6)
                                    .padding(.top, 5)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(commit.subject)
                                        .font(.system(size: 12, weight: .medium))
                                        .lineLimit(1)
                                    Text("\(commit.author) · \(commit.displayDate) · \(commit.shortHash)")
                                        .font(.system(size: 10.5, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 7)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .staggered(index)
                        if index < min(4, state.commits.count - 1) {
                            Divider().opacity(0.5)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var onboarding: some View {
        GlassCard(title: "三步上手", icon: "sparkles", tint: GlassPalette.violet.opacity(0.10)) {
            VStack(alignment: .leading, spacing: 9) {
                onboardingLine("1", "左侧添加或扫描本地仓库")
                onboardingLine("2", "「提交」页勾选文件 → 暂存 → 写一句说明 → 提交")
                onboardingLine("3", "「密钥」页为每个平台生成密钥并复制公钥到平台账号")
                InfoHint(text: "所有 git 数据只在手动刷新、切仓库、切分支或操作完成后更新，不会后台偷偷跑。",
                         tint: GlassPalette.mint)
                HStack {
                    Spacer()
                    ActionButton(title: "知道了", icon: "checkmark", prominent: true) {
                        withComfortableAnimation(reduceMotion) { state.completeOnboarding() }
                    }
                }
            }
        }
    }

    private func onboardingLine(_ number: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Text(number)
                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                .foregroundStyle(GlassPalette.violet)
                .frame(width: 18, height: 18)
                .background(GlassPalette.violet.opacity(0.14), in: Circle())
            Text(text).font(.system(size: 12))
        }
    }
}
