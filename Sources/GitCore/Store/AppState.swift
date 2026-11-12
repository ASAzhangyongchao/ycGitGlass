import Foundation
import Observation

/// 全局状态与「刷新编排」的唯一收口。
///
/// 刷新策略（刻意设计，勿改）：
/// 数据只在这 5 类事件后读取 —— 启动、手动点刷新、切换仓库、切换分支、写操作完成。
/// 本文件没有任何 Timer / Task.sleep 循环 / DispatchSourceTimer / FSEvents / 文件描述符监听，
/// 也不监听应用前后台切换；数据层空闲时 CPU 占用为 0
/// （侧边栏吉祥物的低频呼吸动画是唯一的渲染例外，见 MascotCow）。
@Observable
@MainActor
public final class AppState {
    // MARK: 持久化数据
    public var repositories: [Repository] = []
    public var selectedRepoID: UUID?
    public var platforms: [GitPlatform] = AppConfig.defaultPlatforms
    public var keyPlatformBindings: [String: String] = [:]
    public var onboardingSeen = false

    // MARK: 仓库快照（只在 refresh 时更新）
    public var status: WorktreeStatus = .empty
    public var branches: [Branch] = []
    public var commits: [Commit] = []
    public var remotes: [Remote] = []
    public var keys: [SSHKeyPair] = []
    /// 仓库 id -> 分支名列表（小写缓存）。仅用于侧边栏"按分支搜仓库"，
    /// 在每次 refresh 时顺带从已加载的 branches 数据构建，不产生额外 git 进程。
    public var branchIndex: [UUID: [String]] = [:]
    public var lastRefreshed: Date?
    public var lastRefreshReason: String = ""

    // MARK: 界面状态
    public var selectedTab: AppTab = .dashboard
    public var historyQuery = ""
    public var historyAllBranches = false
    public var deepSearchActive = false
    /// 历史页：作者过滤与排序（纯内存，不触发 git）
    public var historyAuthorFilter: String?
    public var historySort: HistorySort = .newestFirst
    public var commitMessage = ""
    public var selectedFilePaths: Set<String> = []
    public var selectedCommit: Commit?
    public var changedFilesOfSelection: [String] = []
    public var diffText = ""
    public var diffFilePath = ""
    public var stashes: [StashEntry] = []
    public var tags: [GitTag] = []
    public var commitDetail: CommitDetail?
    public var detailDiff = ""
    public var detailDiffFile = ""
    public var inProgressOperation: String?
    public var conflictedFiles: [String] = []
    public var showDetailPanel = false
    /// 历史/提交页的专属 Diff 查看器（第三栏）：点变更文件后打开
    public var showDiffViewer = false
    public var showAbout = false
    /// 刷新历史信息弹窗（标题栏「历史」按钮触发）
    public var showRefreshHistoryPopover = false
    /// 分支选择器弹窗（顶部品牌行的仓库/分支胶囊触发）
    public var showBranchPickerSheet = false
    /// 定位请求：详情面板「在列表中定位」按钮触发，历史列表滚动到该提交并闪烁高亮
    public var locateRequest: LocateRequest?
    public var updateState: UpdateState = .idle
    /// 上次自动检查更新的时间戳（UserDefaults 存储的秒数）。为保持零轮询，只有启动时距上次 ≥24h 才静默检查一次。
    public var lastAutoUpdateCheck: Date?
    /// 图片差异预览：当前加载的图片对与文件路径
    public var imageDiff: ImageDiffService.Pair?
    public var imageDiffPath: String?
    public var isLoadingImageDiff = false

    private static let autoCheckInterval: TimeInterval = 24 * 3600
    private static let lastCheckKey = "lastAutoUpdateCheck"
    public var isBusy = false
    public var busyLabel = ""
    public var errorMessage: String?
    public var errorSuggestion: String?
    public var errorDetail: String?
    public var notice: String?

    private let git = GitService()
    private let ssh = SSHKeyService()
    private let store = RepositoryStore()

    // MARK: 派生数据（纯内存计算，不触发任何 git 命令）

    public var currentRepository: Repository? { repositories.first { $0.id == selectedRepoID } }
    public var currentPath: String? { currentRepository?.path }

    /// 侧边栏搜索：匹配仓库名 / 路径 / 该仓库包含的分支名。
    /// 返回 (仓库, 命中的分支名列表)；分支列表非空表示是分支命中。
    public func sidebarSearch(_ rawQuery: String) -> [(repository: Repository, matchedBranches: [String])] {
        let query = rawQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else {
            return repositories.map { ($0, []) }
        }
        return repositories.compactMap { repository in
            let nameHit = repository.name.lowercased().contains(query)
            let pathHit = repository.path.lowercased().contains(query)
            let branchHits = (branchIndex[repository.id] ?? [])
                .filter { $0.contains(query) }
                .sorted()
            let branchTop = Array(branchHits.prefix(3))
            if nameHit || pathHit || !branchTop.isEmpty {
                return (repository, branchTop)
            }
            return nil
        }
    }
    public var hasUpstream: Bool { !status.upstream.isEmpty }
    public var stagedFiles: [FileChange] { status.files.filter(\.isStaged) }
    public var unstagedFiles: [FileChange] { status.files.filter { !$0.isStaged } }
    public var localBranches: [Branch] { branches.filter { !$0.isRemote } }
    public var remoteBranches: [Branch] { branches.filter(\.isRemote) }
    public var currentBranch: Branch? { branches.first(where: \.isCurrent) }

    /// 历史列表的即时过滤完全在内存完成，输入时零外部进程、零 CPU 尖峰。
    public var filteredCommits: [Commit] {
        var result = baseFiltered
        // 作者筛选（作者菜单选择）
        if let author = historyAuthorFilter, !author.isEmpty {
            result = result.filter { $0.author == author }
        }
        // 排序
        switch historySort {
        case .newestFirst:
            break // git log 默认已是时间倒序，保持轨道图语义
        case .oldestFirst:
            result = result.reversed()
        case .authorAZ:
            result.sort { $0.author.localizedCaseInsensitiveCompare($1.author) == .orderedAscending }
        case .authorZA:
            result.sort { $0.author.localizedCaseInsensitiveCompare($1.author) == .orderedDescending }
        }
        return result
    }

    private var baseFiltered: [Commit] {
        let query = historyQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if deepSearchActive || query.isEmpty { return commits }
        let (key, value) = Self.parseLocalQuery(query)
        let needle = value.lowercased()
        guard !needle.isEmpty else { return commits }
        switch key {
        case "author":
            return commits.filter { $0.author.lowercased().contains(needle) || $0.email.lowercased().contains(needle) }
        case "message":
            return commits.filter { $0.subject.lowercased().contains(needle) || $0.body.lowercased().contains(needle) }
        case "hash":
            return commits.filter { $0.hash.lowercased().contains(needle) || $0.shortHash.lowercased().contains(needle) }
        case "file", "since", "until":
            // 这些需要走 git 层；输入时先不删行，提示用户点「深度搜索」。
            return commits
        default:
            return commits.filter { $0.searchableText.lowercased().contains(needle) }
        }
    }

    /// 已加载提交中的作者列表（去重，按提交数降序），供作者筛选菜单。
    public var availableAuthors: [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for commit in commits where !commit.author.isEmpty {
            counts[commit.author, default: 0] += 1
        }
        return counts
            .map { (name: $0.key, count: $0.value) }
            .sorted { $0.count == $1.count
                ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                : $0.count > $1.count }
    }

    public func toggleAuthorFilter(_ name: String) {
        historyAuthorFilter = historyAuthorFilter == name ? nil : name
    }

    public var needsDeepSearch: Bool {
        let (key, _) = Self.parseLocalQuery(historyQuery)
        return ["file", "path", "since", "until"].contains(key)
    }

    public init() {
        let persisted = store.load()
        repositories = persisted.repositories
        platforms = persisted.platforms.isEmpty ? AppConfig.defaultPlatforms : persisted.platforms
        keyPlatformBindings = persisted.keyPlatformBindings
        onboardingSeen = persisted.onboardingSeen
        selectedRepoID = persisted.repositories.first?.id
        // 启动时集中校验外部工具，缺失时立刻给出可读提示，而不是等到第一次点按钮。
        do {
            try AppConfig.validate()
        } catch let error as AppError {
            errorMessage = error.friendlyMessage
            errorSuggestion = error.suggestion
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - 统一执行包装

    /// 等待中的工作用 continuation 挂起，绝不轮询；每个工作结束都唤醒等待者。
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []

    private func waitForIdle() async {
        while isBusy {
            await withCheckedContinuation { continuation in
                idleWaiters.append(continuation)
            }
        }
    }

    private func signalIdle() {
        let waiters = idleWaiters
        idleWaiters = []
        for waiter in waiters { waiter.resume() }
    }

    private func perform(_ label: String, refreshOnFailure: Bool = false,
                         _ operation: @MainActor @escaping () async throws -> Void) async {
        // 快速切换仓库时，后一次刷新会在这里排队等待，而不是被静默丢弃。
        await waitForIdle()
        guard !isBusy else { return }
        isBusy = true
        busyLabel = label
        errorMessage = nil
        errorSuggestion = nil
        errorDetail = nil
        defer {
            isBusy = false
            busyLabel = ""
            signalIdle()
        }
        do {
            try await operation()
        } catch let error as AppError {
            errorMessage = error.friendlyMessage
            errorSuggestion = error.suggestion
            errorDetail = error.rawDetail
            AppLogger.error(AppLogger.ui, "operation.failed", detail: ["label": label, "reason": error.friendlyMessage])
            // 遴选 / 还原冲突会留下 CHERRY_PICK_HEAD，失败后也要刷新，让横幅及时出现。
            if refreshOnFailure, let path = currentPath {
                try? await loadAll(at: path, reason: .afterMutation)
            }
        } catch {
            errorMessage = error.localizedDescription
            AppLogger.error(AppLogger.ui, "operation.failed", detail: ["label": label, "reason": error.localizedDescription])
            if refreshOnFailure, let path = currentPath {
                try? await loadAll(at: path, reason: .afterMutation)
            }
        }
    }

    /// 单次刷新并行拉取 5 类数据，避免串行 N 次进程等待。
    /// 核心数据（status/branches/remotes/log/conflict）失败即整体失败；
    /// 辅助数据（密钥/储藏/标签）失败降级为空——例如 ~/.ssh 权限异常
    /// 不应导致整个仓库的 status 都看不到。
    private func loadAll(at path: String, reason: RefreshReason) async throws {
        let allBranches = historyAllBranches
        let bindings = keyPlatformBindings
        let platformList = platforms
        async let statusTask = git.status(at: path)
        async let branchTask = git.branches(at: path)
        async let remoteTask = git.remotes(at: path)
        async let logTask = git.log(at: path, allBranches: allBranches)
        async let keyTask = ssh.listKeys(platforms: platformList, bindings: bindings)
        async let stashTask = git.stashes(at: path)
        async let tagTask = git.tags(at: path)
        // 没有进行中的操作时，这个方法内部直接返回空，不产生额外进程。
        async let conflictTask = git.conflictedFilesIfNeeded(at: path)
        let (newStatus, newBranches, newRemotes, newCommits, newConflicts) =
            try await (statusTask, branchTask, remoteTask, logTask, conflictTask)

        status = newStatus
        branches = newBranches
        remotes = newRemotes
        commits = newCommits
        conflictedFiles = newConflicts

        // 辅助数据降级：失败不影响核心视图
        keys = (try? await keyTask) ?? []
        stashes = (try? await stashTask) ?? []
        tags = (try? await tagTask) ?? []

        // 分支名缓存：供侧边栏"按分支搜仓库"，纯内存构建零额外进程
        if let repoID = selectedRepoID {
            branchIndex[repoID] = newBranches.map { $0.name.lowercased() }
        }
        // 纯文件检查，不产生额外进程
        inProgressOperation = git.inProgressOperation(at: path)
        lastRefreshed = Date()
        lastRefreshReason = reason.rawValue
        deepSearchActive = false
        AppLogger.info(AppLogger.ui, "refreshed", detail: ["reason": reason.rawValue])
    }

    /// 唯一的刷新入口；调用方只有 5 类事件（见文件头注释）。
    public func refresh(reason: RefreshReason) async {
        guard let path = currentPath else {
            status = .empty
            branches = []
            commits = []
            remotes = []
            return
        }
        // 记录发起时的仓库：排队等待期间用户可能又切了仓库，
        // 醒来后仓库已变则跳过（最新一次刷新会带上新仓库的数据）
        let expectedRepo = selectedRepoID
        await perform("正在读取仓库") {
            guard self.selectedRepoID == expectedRepo else { return }
            try await self.loadAll(at: path, reason: reason)
        }
    }

    /// 写操作：执行成功后自动刷新一次（.afterMutation / .branchSwitch），不引入后台轮询。
    private func mutate(_ label: String, reason: RefreshReason = .afterMutation,
                        refreshOnFailure: Bool = false,
                        _ operation: @MainActor @escaping () async throws -> String) async {
        await perform(label, refreshOnFailure: refreshOnFailure) {
            let message = try await operation()
            if let path = self.currentPath {
                try await self.loadAll(at: path, reason: reason)
            }
            if !message.isEmpty { self.notice = message }
        }
    }

    // MARK: - 仓库维护

    public func selectRepository(_ id: UUID) {
        guard selectedRepoID != id else { return }
        selectedRepoID = id
        resetSelections()
        save()
        Task { await refresh(reason: .repositorySwitch) }
    }

    public func addRepository(at rawPath: String) async {
        let path = RepositoryStore.normalized(rawPath)
        guard !repositories.contains(where: { $0.path == path }) else {
            notice = "这个仓库已经在侧边栏了"
            return
        }
        guard (try? await git.isRepository(path)) == true else {
            presentError(.notARepository(path))
            return
        }
        let repository = Repository(name: URL(fileURLWithPath: path).lastPathComponent, path: path)
        repositories.append(repository)
        selectedRepoID = repository.id
        resetSelections()
        save()
        await refresh(reason: .repositorySwitch)
    }

    /// 批量导入：用户点「扫描文件夹」时才遍历磁盘，最多 3 层 / 40 个仓库。
    public func scanFolder(_ rawPath: String) async {
        let path = RepositoryStore.normalized(rawPath)
        let found = git.discoverRepositories(in: path)
        guard !found.isEmpty else {
            notice = "这个文件夹下没找到 Git 仓库（最多向下找 3 层）"
            return
        }
        var added = 0
        for var repository in found {
            repository.path = RepositoryStore.normalized(repository.path)
            guard !repositories.contains(where: { $0.path == repository.path }) else { continue }
            repositories.append(repository)
            added += 1
        }
        if selectedRepoID == nil { selectedRepoID = repositories.first?.id }
        save()
        notice = "找到 \(found.count) 个仓库，新增 \(added) 个"
        await refresh(reason: .repositorySwitch)
    }

    public func removeRepository(_ id: UUID) {
        repositories.removeAll { $0.id == id }
        if selectedRepoID == id {
            selectedRepoID = repositories.first?.id
            resetSelections()
        }
        save()
        Task { await refresh(reason: .repositorySwitch) }
    }

    public func createRepository(at rawPath: String) async {
        let path = RepositoryStore.normalized(rawPath)
        await perform("正在新建仓库") {
            try await self.git.initializeRepository(at: path)
        }
        await addRepository(at: path)
    }

    public func cloneRepository(from url: String, into folder: String) async {
        let name = Self.repositoryName(from: url)
        let destination = RepositoryStore.normalized((folder as NSString).appendingPathComponent(name))
        await perform("正在克隆仓库") {
            try await self.git.clone(from: url, to: destination)
        }
        guard errorMessage == nil else { return }
        await addRepository(at: destination)
    }

    // MARK: - 分支

    public func checkout(_ branch: Branch) async {
        guard let path = currentPath, !branch.isCurrent else { return }
        await mutate("正在切换分支", reason: .branchSwitch) {
            try await self.git.checkout(branch.name, at: path)
            return "已切换到 \(branch.displayName)"
        }
    }

    public func createBranch(_ name: String) async {
        guard let path = currentPath else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            presentError(.invalidInput("请填写分支名"))
            return
        }
        await mutate("正在新建分支", reason: .branchSwitch) {
            try await self.git.createBranch(trimmed, at: path)
            return "已创建并切换到 \(trimmed)"
        }
    }

    // MARK: - 暂存 / 提交

    public func toggleFile(_ path: String) {
        if selectedFilePaths.contains(path) { selectedFilePaths.remove(path) }
        else { selectedFilePaths.insert(path) }
    }

    public func stageSelected() async {
        guard let path = currentPath, !selectedFilePaths.isEmpty else { return }
        let paths = Array(selectedFilePaths)
        await mutate("正在暂存") {
            try await self.git.stage(paths: paths, at: path)
            self.selectedFilePaths = []
            await self.reloadDiffAfterMutation()
            return "已暂存 \(paths.count) 个文件"
        }
    }

    public func unstageSelected() async {
        guard let path = currentPath, !selectedFilePaths.isEmpty else { return }
        let paths = selectedFilePaths.compactMap { selected in
            status.files.first(where: { $0.path == selected && $0.isStaged })?.path
        }
        guard !paths.isEmpty else {
            presentError(.invalidInput("未跟踪文件没有暂存记录，无需取消暂存"))
            return
        }
        await mutate("正在取消暂存") {
            try await self.git.unstage(paths: paths, at: path)
            self.selectedFilePaths = []
            await self.reloadDiffAfterMutation()
            return "已取消暂存 \(paths.count) 个文件"
        }
    }

    public func stageAll() async {
        guard let path = currentPath else { return }
        await mutate("正在暂存全部") {
            try await self.git.stageAll(at: path)
            self.selectedFilePaths = []
            await self.reloadDiffAfterMutation()
            return "已暂存全部改动"
        }
    }

    public func unstageAll() async {
        guard let path = currentPath else { return }
        await mutate("正在取消全部暂存") {
            try await self.git.unstageAll(at: path)
            await self.reloadDiffAfterMutation()
            return "已取消全部暂存"
        }
    }

    /// 暂存/取消暂存等改变文件状态的写操作后：若 diff 面板正显示着受影响的文件，
    /// 立即按新状态重新加载，避免面板残留旧 diff（截图反馈的"没同步变"）。
    private func reloadDiffAfterMutation() async {
        guard let path = currentPath, !diffFilePath.isEmpty else { return }
        guard let updated = status.files.first(where: { $0.path == diffFilePath }) else {
            diffText = ""
            return
        }
        do {
            diffText = try await git.diff(for: updated.path, staged: updated.isStaged, at: path)
        } catch {
            diffText = ""
        }
    }

    /// 单文件行内操作（悬停按钮）。
    public func stageFile(_ file: FileChange) async {
        guard let path = currentPath else { return }
        await mutate("正在暂存 \(file.fileName)") {
            try await self.git.stage(paths: [file.path], at: path)
            await self.reloadDiffAfterMutation()
            return ""
        }
    }

    public func unstageFile(_ file: FileChange) async {
        guard let path = currentPath, file.isStaged, !file.isUntracked else { return }
        await mutate("正在取消暂存 \(file.fileName)") {
            try await self.git.unstage(paths: [file.path], at: path)
            await self.reloadDiffAfterMutation()
            return ""
        }
    }

    public func discardFile(_ file: FileChange) async {
        guard let path = currentPath else { return }
        await mutate("正在丢弃 \(file.fileName)") {
            try await self.git.discard(paths: [file.path], at: path)
            if self.diffFilePath == file.path { self.diffText = "" }
            return "已丢弃 \(file.fileName)"
        }
    }

    public func discardSelected() async {
        guard let path = currentPath, !selectedFilePaths.isEmpty else { return }
        let paths = Array(selectedFilePaths)
        await mutate("正在丢弃改动") {
            try await self.git.discard(paths: paths, at: path)
            self.selectedFilePaths = []
            return "已丢弃 \(paths.count) 个文件的改动"
        }
    }

    /// 丢弃全部改动（已暂存 + 未暂存 + 未跟踪），UI 二次确认后调用。
    public func discardAllChanges() async {
        guard let path = currentPath else { return }
        await mutate("正在丢弃全部改动") {
            try await self.git.discardAll(at: path)
            self.selectedFilePaths = []
            return "已丢弃全部改动，工作区回到最近一次提交"
        }
    }

    public func commit(andPush: Bool = false) async {
        guard let path = currentPath else { return }
        let message = commitMessage
        let branch = status.branch
        let upstream = hasUpstream
        // 无远程源时推送步骤跳过：提交本身已成功，不该被 push 失败整体报错
        let remote = remotes.first?.name
        await mutate(andPush ? "正在提交并推送" : "正在提交") {
            let hash = try await self.git.commit(message: message, at: path)
            if andPush, let remote {
                try await self.git.push(at: path, branch: branch, remote: remote, hasUpstream: upstream)
                return "提交 \(hash) 已推送到 \(remote)"
            }
            self.commitMessage = ""
            self.selectedFilePaths = []
            return andPush && remote == nil
                ? "提交成功 \(hash)（未配置远程源，跳过推送）"
                : "提交成功 \(hash)"
        }
    }

    /// 工作台的「一键提交全部并推送」：无提交说明时自动生成一句简洁描述。
    public func quickCommitAll() async {
        guard let path = currentPath else { return }
        if commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            commitMessage = "chore: 更新 \(status.files.count) 个文件"
        }
        let message = commitMessage
        let branch = status.branch
        let upstream = hasUpstream
        let remote = remotes.first?.name
        await mutate("正在一键提交") {
            try await self.git.stageAll(at: path)
            let hash = try await self.git.commit(message: message, at: path)
            if let remote {
                try await self.git.push(at: path, branch: branch, remote: remote, hasUpstream: upstream)
                self.commitMessage = ""
                self.selectedFilePaths = []
                return "已提交 \(hash) 并推送到 \(remote)"
            }
            self.commitMessage = ""
            self.selectedFilePaths = []
            return "已提交 \(hash)（未配置远程源，跳过推送）"
        }
    }

    public func loadDiff(for file: FileChange) async {
        guard let path = currentPath else { return }
        diffFilePath = file.path
        imageDiff = nil
        imageDiffPath = nil
        if ImageDiffService.isImagePath(file.path) {
            await loadImageDiff(path: file.path) { service in
                try await service.worktreeImages(file: file.path, at: path)
            }
            return
        }
        await perform("正在读取差异") {
            self.diffText = try await self.git.diff(for: file.path, staged: file.isStaged, at: path)
        }
    }

    private func loadImageDiff(path filePath: String,
                               _ fetch: @MainActor @escaping (ImageDiffService) async throws -> ImageDiffService.Pair) async {
        isLoadingImageDiff = true
        await perform("正在读取图片") {
            let service = ImageDiffService()
            let pair = try await fetch(service)
            self.imageDiff = pair
            self.imageDiffPath = filePath
        }
        isLoadingImageDiff = false
    }

    // MARK: - 同步

    public func pull() async {
        guard let path = currentPath else { return }
        await mutate("正在拉取") {
            try await self.git.pull(at: path)
            return "拉取完成"
        }
    }

    public func fetch() async {
        guard let path = currentPath else { return }
        await mutate("正在抓取") {
            try await self.git.fetch(at: path)
            return "抓取完成"
        }
    }

    public func push() async {
        guard let path = currentPath else { return }
        let branch = status.branch
        let upstream = hasUpstream
        let remote = remotes.first?.name ?? "origin"
        await mutate("正在推送") {
            try await self.git.push(at: path, branch: branch, remote: remote, hasUpstream: upstream)
            return upstream ? "已推送到 \(remote)" : "已推送并建立 \(remote)/\(branch) 关联"
        }
    }

    // MARK: - 历史

    public func deepSearch() async {
        guard let path = currentPath else { return }
        await perform("正在搜索历史") {
            self.commits = try await self.git.log(
                at: path, query: self.historyQuery,
                allBranches: self.historyAllBranches, limit: 500
            )
            self.deepSearchActive = true
            self.lastRefreshReason = RefreshReason.deepSearch.rawValue
        }
    }

    public func selectCommit(_ commit: Commit) async {
        await openDetail(for: commit)
    }

    public func historyQueryChanged() {
        deepSearchActive = false
    }

    // MARK: - 遴选 / 还原 / 冲突中止

    public func cherryPick(_ commit: Commit) async {
        guard let path = currentPath else { return }
        await mutate("正在遴选提交", refreshOnFailure: true) {
            try await self.git.cherryPick(commit.hash, at: path)
            return "已把 \(commit.shortHash)「\(commit.subject)」遴选到当前分支"
        }
    }

    public func revert(_ commit: Commit) async {
        guard let path = currentPath else { return }
        await mutate("正在还原提交", refreshOnFailure: true) {
            try await self.git.revert(commit.hash, at: path)
            return "已生成一条反向提交，撤销 \(commit.shortHash) 的改动"
        }
    }

    public func abortOperation() async {
        guard let path = currentPath else { return }
        await mutate("正在中止操作") {
            try await self.git.abortOperation(at: path)
            return "已中止，工作区回到操作前"
        }
    }

    public func resolveConflict(_ file: String, choose: GitService.ConflictResolution) async {
        guard let path = currentPath else { return }
        await mutate("正在解决冲突") {
            try await self.git.resolveConflict(filePath: file, choose: choose, at: path)
            return "已采用\(choose == .ours ? "当前分支" : "对方提交")的版本并暂存：\(file)"
        }
    }

    public func markConflictResolved(_ file: String) async {
        guard let path = currentPath else { return }
        await mutate("正在标记冲突已解决") {
            try await self.git.markConflictResolved(filePath: file, at: path)
            return "已标记为解决：\(file)"
        }
    }

    public func continueOperation() async {
        guard let path = currentPath else { return }
        await mutate("正在继续操作", refreshOnFailure: true) {
            try await self.git.continueOperation(at: path)
            return "冲突处理完成，操作已继续"
        }
    }

    // MARK: - 储藏

    public func stashPush(message: String = "", includeUntracked: Bool = true) async {
        guard let path = currentPath else { return }
        await mutate("正在储藏改动") {
            try await self.git.stashPush(at: path, message: message, includeUntracked: includeUntracked)
            return "改动已储藏，工作区已恢复干净"
        }
    }

    public func stashApply(_ entry: StashEntry, dropAfterApply: Bool = false) async {
        guard let path = currentPath else { return }
        await mutate("正在恢复储藏") {
            try await self.git.stashApply(entry.reflogID, at: path, dropAfterApply: dropAfterApply)
            return dropAfterApply ? "已恢复并移除该储藏" : "已恢复改动（储藏记录仍保留）"
        }
    }

    public func stashDrop(_ entry: StashEntry) async {
        guard let path = currentPath else { return }
        await mutate("正在删除储藏") {
            try await self.git.stashDrop(entry.reflogID, at: path)
            return "已删除 \(entry.reflogID)"
        }
    }

    // MARK: - 标签与分支

    public func addTag(_ name: String, to hash: String = "", message: String = "") async {
        guard let path = currentPath else { return }
        await mutate("正在打标签") {
            try await self.git.addTag(name, to: hash, message: message, at: path)
            return "已创建标签 \(name)"
        }
    }

    public func deleteTag(_ name: String) async {
        guard let path = currentPath else { return }
        await mutate("正在删除标签") {
            try await self.git.deleteTag(name, at: path)
            return "已删除标签 \(name)（仅本地）"
        }
    }

    public func deleteBranch(_ name: String, force: Bool = false) async {
        guard let path = currentPath else { return }
        await mutate("正在删除分支", reason: .branchSwitch) {
            try await self.git.deleteBranch(name, at: path, force: force)
            return "已删除分支 \(name)"
        }
    }

    // MARK: - 提交详情

    public func openDetail(for commit: Commit) async {
        selectedCommit = commit
        showDetailPanel = true
        showDiffViewer = false
        commitDetail = nil
        detailDiff = ""
        detailDiffFile = ""
        changedFilesOfSelection = []
        guard let path = currentPath else { return }
        await perform("正在读取提交详情") {
            let detail = try await self.git.commitDetail(commit.hash, at: path)
            self.commitDetail = detail
            self.changedFilesOfSelection = detail.changedFiles.map(\.path)
        }
    }

    /// 方向一：把指定分支的改动合并进当前分支（git merge source）
    public func mergeIntoCurrent(_ source: String, noFF: Bool = false) async {
        guard let path = currentPath else { return }
        let branch = status.branch
        await mutate("正在把 \(source) 合并进 \(branch)", refreshOnFailure: true) {
            try await self.git.merge(source, at: path, noFF: noFF)
            if noFF {
                return "已合并 \(source) → \(branch)（保留合并提交）"
            }
            return "已合并 \(source) → \(branch)"
        }
    }

    /// 方向二：把当前分支合并到目标分支（自动 checkout 目标 → merge 当前 → 切回）
    public func mergeCurrentInto(_ target: String, noFF: Bool = false) async {
        guard let path = currentPath else { return }
        let current = status.branch
        guard !current.isEmpty, current != target else {
            presentError(.invalidInput("目标分支不能是当前分支"))
            return
        }
        await mutate("正在把 \(current) 合并到 \(target)", refreshOnFailure: true) {
            try await self.git.checkout(target, at: path)
            do {
                try await self.git.merge(current, at: path, noFF: noFF)
            } catch {
                // 合并冲突时停在 target 上（用户解决），不自动切回
                throw error
            }
            try await self.git.checkout(current, at: path)
            return "已把 \(current) 合并到 \(target)，并切回 \(current)"
        }
    }

    /// 在左侧列表中定位当前选中的提交（滚动 + 高亮闪烁）
    public func locateSelectedInList() {
        guard let commit = selectedCommit else { return }
        locateRequest = LocateRequest(hash: commit.hash)
    }

    public func closeDetail() {
        showDetailPanel = false
        showDiffViewer = false
    }

    public func closeDiffViewer() {
        showDiffViewer = false
    }

    public func loadDetailDiff(file: String) async {
        guard let path = currentPath, let hash = selectedCommit?.hash else { return }
        detailDiffFile = file
        imageDiff = nil
        imageDiffPath = nil
        showDiffViewer = true
        if ImageDiffService.isImagePath(file) {
            await loadImageDiff(path: file) { service in
                try await service.images(inCommit: hash, file: file, at: path)
            }
            return
        }
        await perform("正在读取文件差异") {
            self.detailDiff = try await self.git.diffInCommit(hash, file: file, at: path)
        }
    }

    // MARK: - 远程源

    public func addRemote(name: String, url: String) async {
        guard let path = currentPath else { return }
        await mutate("正在添加远程源") {
            try await self.git.addRemote(name: name, url: url, at: path)
            return "已添加远程源 \(name)"
        }
    }

    public func setRemoteURL(name: String, url: String) async {
        guard let path = currentPath else { return }
        await mutate("正在更新地址") {
            try await self.git.setRemoteURL(name: name, url: url, at: path)
            return "已更新 \(name) 的地址"
        }
    }

    public func renameRemote(from old: String, to new: String) async {
        guard let path = currentPath else { return }
        await mutate("正在重命名") {
            try await self.git.renameRemote(from: old, to: new, at: path)
            return "已重命名为 \(new)"
        }
    }

    public func removeRemote(_ name: String) async {
        guard let path = currentPath else { return }
        await mutate("正在删除远程源") {
            try await self.git.removeRemote(name: name, at: path)
            return "已删除远程源 \(name)"
        }
    }

    // MARK: - 密钥

    public func generateKey(for platform: GitPlatform, email: String, passphrase: String) async {
        await perform("正在生成密钥") {
            let key = try await self.ssh.generateKey(for: platform, email: email, passphrase: passphrase)
            self.keyPlatformBindings[key.publicKeyPath] = platform.id
            self.save()
            self.keys = try await self.ssh.listKeys(
                platforms: self.platforms, bindings: self.keyPlatformBindings
            )
            self.notice = "已为 \(platform.name) 生成 ED25519 密钥，请复制公钥到平台"
        }
    }

    public func bindKey(_ key: SSHKeyPair, to platformID: String) {
        keyPlatformBindings[key.publicKeyPath] = platformID
        save()
        if let index = keys.firstIndex(where: { $0.id == key.id }) {
            keys[index].platformID = platformID
        }
        notice = "已归类到 \(platformName(platformID))"
    }

    public func publicKeyContent(_ key: SSHKeyPair) -> String {
        (try? ssh.publicKeyContent(key)) ?? ""
    }

    public func testConnection(platform: GitPlatform, key: SSHKeyPair) async {
        await perform("正在测试连接") {
            self.notice = try await self.ssh.testConnection(platform: platform, key: key)
        }
    }

    public func applySSHConfig() async {
        await perform("正在写入 SSH 配置") {
            try self.ssh.applyConfig(keys: self.keys, platforms: self.platforms)
            self.notice = "已写入 ~/.ssh/config（原文件已备份为 config.gitglass.bak）"
        }
    }

    public func fixKeyPermissions(_ key: SSHKeyPair) async {
        await perform("正在修复权限") {
            try self.ssh.fixPermissions(key)
            self.keys = try await self.ssh.listKeys(
                platforms: self.platforms, bindings: self.keyPlatformBindings
            )
            self.notice = "私钥权限已改为 600"
        }
    }

    public func addCustomPlatform(name: String, host: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedHost.isEmpty else {
            presentError(.invalidInput("平台名称和服务器域名都要填写"))
            return
        }
        let id = "custom-" + UUID().uuidString.prefix(8)
        platforms.append(GitPlatform(id: id, name: trimmedName, host: trimmedHost,
                                     symbol: "server.rack", isCustom: true))
        save()
        notice = "已添加平台 \(trimmedName)"
    }

    public func keys(for platformID: String) -> [SSHKeyPair] {
        keys.filter { $0.platformID == platformID }
    }

    public func platformName(_ id: String) -> String {
        platforms.first(where: { $0.id == id })?.name ?? "其他 / 自建"
    }

    // MARK: - 提示与引导

    public func dismissError() {
        errorMessage = nil
        errorSuggestion = nil
        errorDetail = nil
    }

    public func dismissNotice() { notice = nil }

    public func completeOnboarding() {
        onboardingSeen = true
        save()
    }

    // MARK: - 关于与更新

    public func showRefreshHistoryPopoverNow() {
        showRefreshHistoryPopover = true
    }

    public func openAbout() {
        showAbout = true
    }

    /// 手动检查更新（About 面板按钮触发）。
    public func checkForUpdates() async {
        updateState = .checking
        await checkForUpdatesInternal(manual: true)
    }

    /// 启动时的静默检查：距上次自动检查不足 24 小时则直接跳过，绝不轮询。
    public func autoCheckForUpdatesIfNeeded() async {
        let last = UserDefaults.standard.double(forKey: Self.lastCheckKey)
        let lastDate = last > 0 ? Date(timeIntervalSince1970: last) : nil
        lastAutoUpdateCheck = lastDate
        if let lastDate, Date().timeIntervalSince(lastDate) < Self.autoCheckInterval {
            return
        }
        await checkForUpdatesInternal(manual: false)
    }

    private func checkForUpdatesInternal(manual: Bool) async {
        let service = UpdateService()
        do {
            let info = try await service.latest()
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastCheckKey)
            if let info {
                let result = UpdateService.compareVersions(AppConfig.appVersion, info.version)
                if result < 0 {
                    updateState = .available(info)
                    if manual { showAbout = true }
                } else {
                    updateState = .upToDate
                }
            } else {
                updateState = .noReleasesYet
            }
        } catch {
            // 静默检查失败不打扰用户；手动检查给出可读错误。
            updateState = manual ? .failed("检查更新失败：网络不可用或 GitHub 无法访问")
                                 : .idle
        }
    }

    public func openReleasesPage() {
        NSWorkspaceOpenURL(AppConfig.releasesURL)
    }

    public func openRepositoryPage() {
        NSWorkspaceOpenURL(AppConfig.repoURL)
    }

    public func openIssuesPage() {
        NSWorkspaceOpenURL(AppConfig.issuesURL)
    }

    public func appendCommitPrefix(_ prefix: String) {
        let trimmed = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            commitMessage = prefix + ": "
        } else if !trimmed.hasPrefix(prefix + ":") {
            commitMessage = prefix + ": " + trimmed
        }
    }

    // MARK: - 内部

    private func resetSelections() {
        selectedFilePaths = []
        selectedCommit = nil
        changedFilesOfSelection = []
        diffText = ""
        diffFilePath = ""
        stashes = []
        tags = []
        commitDetail = nil
        detailDiff = ""
        detailDiffFile = ""
        inProgressOperation = nil
        conflictedFiles = []
        showDetailPanel = false
        showDiffViewer = false
        historyQuery = ""
        deepSearchActive = false
        status = .empty
        commits = []
        branches = []
        remotes = []
        branchIndex = [:]
    }

    private func save() {
        do {
            try store.save(PersistedState(
                repositories: repositories,
                platforms: platforms,
                keyPlatformBindings: keyPlatformBindings,
                onboardingSeen: onboardingSeen
            ))
        } catch {
            AppLogger.error(AppLogger.store, "state.save_failed", detail: ["reason": error.localizedDescription])
        }
    }

    private func presentError(_ error: AppError) {
        errorMessage = error.friendlyMessage
        errorSuggestion = error.suggestion
        errorDetail = error.rawDetail
    }

    private static func parseLocalQuery(_ query: String) -> (String, String) {
        for key in ["author", "message", "file", "path", "hash", "since", "until"] {
            let prefix = key + ":"
            if query.lowercased().hasPrefix(prefix) {
                return (key, String(query.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces))
            }
        }
        return ("text", query)
    }

    private static func repositoryName(from url: String) -> String {
        let last = url.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .split(separator: "/").last ?? "repository"
        let cleaned = String(last).replacingOccurrences(of: ".git", with: "")
        return cleaned.isEmpty ? "repository" : cleaned
    }
}

/// Core 层不依赖 AppKit 的前提下打开外部链接：通过 Foundation 的 Process 调 open。
private func NSWorkspaceOpenURL(_ url: URL) {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    task.arguments = [url.absoluteString]
    try? task.run()
}
