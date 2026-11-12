import SwiftUI
import AppKit
import GitCore

struct SidebarView: View {
    @Environment(AppState.self) private var state
    @State private var showCloneSheet = false
    @State private var query = ""
    @State private var showBranchPickerFor: Repository?
    @FocusState private var searchFocused: Bool

    private var searchResults: [(repository: Repository, matchedBranches: [String])] {
        state.sidebarSearch(query)
    }

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if state.repositories.count > 1 || isSearching {
                searchField
                    .padding(.bottom, 10)
            }
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
        .sheet(item: $showBranchPickerFor) { repository in
            BranchPickerSheet()
                .environment(state)
        }
    }

    // MARK: 搜索框

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            TextField("搜仓库或分支名…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5))
                .focused($searchFocused)
            if isSearching {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("清空搜索")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .glassSurface(cornerRadius: 10)
        .help("按仓库名、路径或分支名搜索；命中分支的仓库会列出匹配分支")
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
        } else if isSearching && searchResults.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("没有匹配「\(query)」的仓库或分支")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 120)
            .padding(12)
        } else {
            List(selection: Binding(
                get: { state.selectedRepoID },
                set: { newValue in if let newValue { state.selectRepository(newValue) } }
            )) {
                ForEach(Array(searchResults.enumerated()), id: \.element.repository.id) { index, result in
                    repositoryRow(result.repository, matchedBranches: result.matchedBranches)
                        .staggered(index)
                        .contextMenu {
                            Button("在 Finder 中显示") {
                                NSWorkspace.shared.selectFile(result.repository.path, inFileViewerRootedAtPath: "")
                            }
                            Divider()
                            Button("从列表移除", role: .destructive) {
                                withAnimation(Motion.spring) { state.removeRepository(result.repository.id) }
                            }
                        }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 140)
            .animation(Motion.snappy, value: query)
        }
    }

    private func repositoryRow(_ repository: Repository, matchedBranches: [String]) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "folder.fill")
                .font(.system(size: 13))
                .foregroundStyle(GlassPalette.blue.opacity(0.85))
            VStack(alignment: .leading, spacing: 2) {
                Text(repository.name)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                if matchedBranches.isEmpty {
                    Text(repository.path)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    // 搜索命中分支：列出匹配的分支 chips，点击直接选仓库并打开分支选择器
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(matchedBranches, id: \.self) { branch in
                            Button {
                                // 先弹分支选择器再选仓库：sheet 挂在当前视图树，
                                // 避免此前 0.15s 魔法延迟期间用户点到别处打开过期仓库的弹窗
                                showBranchPickerFor = repository
                                state.selectRepository(repository.id)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.triangle.branch")
                                        .font(.system(size: 8.5))
                                    Text(branch)
                                        .font(.system(size: 10, design: .monospaced))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(GlassPalette.violet)
                            .background(GlassPalette.violet.opacity(0.10), in: Capsule())
                            .help("选中 \(repository.name) 并打开分支选择器")
                        }
                    }
                }
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
