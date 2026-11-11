import SwiftUI
import AppKit
import GitCore

struct SidebarView: View {
    @Environment(AppState.self) private var state
    @State private var showCloneSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            repositoryList
            Divider().padding(.vertical, 10)
            actionButtons
            Spacer(minLength: 12)
            // 吉祥物：空闲时慢悠悠起伏，有任务时加速打字
            MascotCow(isBusy: state.isBusy)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 10)
        }
        .padding(.horizontal, 14)
        .padding(.top, 18)
        .sheet(isPresented: $showCloneSheet) {
            CloneSheet { url, folder in
                Task { await state.cloneRepository(from: url, into: folder) }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(GlassPalette.accent)
            Text("仓库")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Text("\(state.repositories.count)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var repositoryList: some View {
        if state.repositories.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(GlassPalette.accent.opacity(0.8))
                Text("还没有仓库")
                    .font(.system(size: 13, weight: .semibold))
                Text("点下面的「添加仓库」，选择一个本地 Git 文件夹就能开始。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 170)
            .padding(12)
            .glassSurface(cornerRadius: 16, tint: GlassPalette.blue.opacity(0.08))
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
        } else {
            List(selection: Binding(
                get: { state.selectedRepoID },
                set: { newValue in if let newValue { state.selectRepository(newValue) } }
            )) {
                ForEach(Array(state.repositories.enumerated()), id: \.element.id) { index, repository in
                    repositoryRow(repository)
                        .staggered(index)
                        .contextMenu {
                            Button("在 Finder 中显示") {
                                NSWorkspace.shared.selectFile(repository.path, inFileViewerRootedAtPath: "")
                            }
                            Divider()
                            Button("从列表移除", role: .destructive) {
                                withAnimation(Motion.spring) { state.removeRepository(repository.id) }
                            }
                        }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 140)
        }
    }

    private func repositoryRow(_ repository: Repository) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "folder.fill")
                .font(.system(size: 13))
                .foregroundStyle(GlassPalette.blue.opacity(0.85))
            VStack(alignment: .leading, spacing: 2) {
                Text(repository.name)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                Text(repository.path)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .tag(repository.id)
        .help(repository.path)
    }

    private var actionButtons: some View {
        VStack(alignment: .leading, spacing: 8) {
            sidebarButton("添加仓库…", icon: "plus.circle.fill", prominent: true) {
                if let path = chooseFolder(message: "选择一个本地 Git 仓库文件夹") {
                    Task { await state.addRepository(at: path) }
                }
            }
            sidebarButton("扫描文件夹批量导入", icon: "magnifyingglass.circle") {
                if let path = chooseFolder(message: "选择父文件夹，向下最多扫描 3 层找 .git") {
                    Task { await state.scanFolder(path) }
                }
            }
            sidebarButton("新建仓库", icon: "folder.badge.plus") {
                if let path = chooseFolder(message: "选择要初始化为 Git 仓库的文件夹", canCreate: true) {
                    Task { await state.createRepository(at: path) }
                }
            }
            sidebarButton("克隆远程仓库", icon: "arrow.down.circle") {
                showCloneSheet = true
            }
        }
    }

    private func sidebarButton(_ title: String, icon: String, prominent: Bool = false,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon).font(.system(size: 12))
                Text(title).font(.system(size: 12, weight: .medium))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .foregroundStyle(prominent ? .primary : .secondary)
        .background(
            (prominent ? GlassPalette.accent.opacity(0.14) : Color.primary.opacity(0.045)),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .help(title)
    }
}

// MARK: - 克隆表单

private struct CloneSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var folder = FileManager.default.homeDirectoryForCurrentUser.path
    let onClone: (String, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("克隆远程仓库").font(.system(size: 17, weight: .semibold))
            VStack(alignment: .leading, spacing: 6) {
                Text("仓库地址").font(.system(size: 11.5)).foregroundStyle(.secondary)
                TextField("git@github.com:user/repo.git", text: $url)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12.5))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("存放位置").font(.system(size: 11.5)).foregroundStyle(.secondary)
                HStack {
                    Text(folder)
                        .font(.system(size: 11.5, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("选择…") {
                        if let chosen = chooseFolder(message: "选择仓库存放的父文件夹") { folder = chosen }
                    }
                    .glassAction()
                }
            }
            InfoHint(text: "建议使用 SSH 地址。若认证失败，到「密钥」页检查对应平台的公钥是否已添加到账号。")
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("克隆") {
                    onClone(url.trimmingCharacters(in: .whitespacesAndNewlines), folder)
                    dismiss()
                }
                .prominentAction()
                .keyboardShortcut(.defaultAction)
                .disabled(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 460)
        .background(GlassBackground())
    }
}
