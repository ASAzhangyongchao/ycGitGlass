import SwiftUI
import GitCore

struct RemoteView: View {
    @Environment(AppState.self) private var state
    @State private var form: RemoteForm?
    @State private var pendingDelete: String?

    struct RemoteForm: Identifiable {
        enum Kind { case add, editURL(String), rename(String) }
        let id = UUID()
        let kind: Kind
    }

    var body: some View {
        if state.currentRepository == nil {
            EmptyStateView(title: "还没有仓库", message: "先在左侧添加一个 Git 仓库。", icon: "network")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    toolbar
                    GlassCard(title: "Git 远程源", icon: "network",
                              subtitle: "一个仓库可以同时有多个远程源，例如 origin 与 upstream") {
                        if state.remotes.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "network.slash")
                                    .font(.system(size: 28, weight: .light))
                                    .foregroundStyle(.tertiary)
                                Text("还没有配置远程源")
                                    .font(.system(size: 12.5))
                                Text("本地仓库也可以正常提交；要推送到 GitHub / GitLab 等平台，先添加一个远程源。")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity, minHeight: 150)
                        } else {
                            VStack(alignment: .leading, spacing: 9) {
                                ForEach(Array(state.remotes.enumerated()), id: \.element.id) { index, remote in
                                    remoteRow(remote).staggered(index)
                                }
                            }
                        }
                    }
                    syncCard
                }
                .padding(.vertical, 6)
                .padding(.bottom, 20)
            }
            .sheet(item: $form) { item in
                sheetContent(for: item.kind)
            }
            .alert("删除远程源？", isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            )) {
                Button("取消", role: .cancel) { pendingDelete = nil }
                Button("删除", role: .destructive) {
                    if let name = pendingDelete { Task { await state.removeRemote(name) } }
                    pendingDelete = nil
                }
            } message: {
                Text("只删除本地记录的远程地址，不会删除远程服务器上的仓库。")
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            ActionButton(title: "添加远程源", icon: "plus", prominent: true) {
                form = RemoteForm(kind: .add)
            }
            Spacer()
            Text("\(state.remotes.count) 个远程源")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private func remoteRow(_ remote: Remote) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "network")
                .font(.system(size: 14))
                .foregroundStyle(GlassPalette.blue)
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(remote.name).font(.system(size: 12.5, weight: .semibold))
                    StatusBadge(text: remote.displayHost, tint: GlassPalette.violet)
                    if remote.pushURL.isEmpty || remote.pushURL == remote.fetchURL {
                        StatusBadge(text: "fetch = push", tint: GlassPalette.mint)
                    }
                }
                Text(remote.fetchURL)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                if !remote.pushURL.isEmpty && remote.pushURL != remote.fetchURL {
                    Text("push: " + remote.pushURL)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Menu("操作") {
                Button("编辑地址") { form = RemoteForm(kind: .editURL(remote.name)) }
                Button("重命名") { form = RemoteForm(kind: .rename(remote.name)) }
                Button("复制地址") {
                    copyToPasteboard(remote.fetchURL)
                    state.notice = "已复制 \(remote.name) 的地址"
                }
                Divider()
                Button("删除", role: .destructive) { pendingDelete = remote.name }
            }
            .glassAction()
            .frame(width: 74)
        }
        .padding(12)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var syncCard: some View {
        GlassCard(title: "同步操作", icon: "arrow.triangle.2.circlepath",
                  subtitle: "每次操作完成后会自动刷新一次状态") {
            HStack(spacing: 9) {
                ActionButton(title: "抓取", icon: "arrow.down.to.line") {
                    Task { await state.fetch() }
                }
                .disabled(state.isBusy || state.remotes.isEmpty)
                ActionButton(title: "拉取", icon: "arrow.down") {
                    Task { await state.pull() }
                }
                .disabled(state.isBusy || state.remotes.isEmpty)
                ActionButton(title: "推送", icon: "arrow.up", prominent: true) {
                    Task { await state.push() }
                }
                .disabled(state.isBusy || state.remotes.isEmpty)
                Spacer()
            }
            InfoHint(text: "首次推送到新分支会自动加 -u 建立上游关联；拉取使用 --ff-only，保持历史线性清晰。")
        }
    }

    @ViewBuilder
    private func sheetContent(for kind: RemoteForm.Kind) -> some View {
        switch kind {
        case .add:
            TwoFieldSheet(
                title: "添加远程源",
                firstLabel: "名称", firstPlaceholder: "origin",
                secondLabel: "地址", secondPlaceholder: "git@github.com:user/repo.git",
                confirmTitle: "添加",
                hint: "名称通常用 origin。SSH 地址需要在「密钥」页配置对应平台的公钥。"
            ) { name, url in
                Task { await state.addRemote(name: name, url: url) }
            }
        case .editURL(let name):
            TwoFieldSheet(
                title: "编辑 \(name) 的地址",
                firstLabel: "新地址", firstPlaceholder: "git@github.com:user/repo.git",
                confirmTitle: "保存"
            ) { url, _ in
                Task { await state.setRemoteURL(name: name, url: url) }
            }
        case .rename(let old):
            TwoFieldSheet(
                title: "重命名 \(old)",
                firstLabel: "新名称", firstPlaceholder: "upstream",
                confirmTitle: "重命名"
            ) { new, _ in
                Task { await state.renameRemote(from: old, to: new) }
            }
        }
    }
}
