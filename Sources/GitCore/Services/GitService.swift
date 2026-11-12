import Foundation

/// Git 领域服务：所有 git 能力的唯一出口。
/// 纯 Swift 值类型、不依赖任何 UI 框架；所有操作异步执行，视图层不感知 Process。
public struct GitService: Sendable {
    private let runner: CommandRunner
    private let git: String

    public init(gitExecutable: String = AppConfig.gitExecutable, runner: CommandRunner = CommandRunner()) {
        self.git = gitExecutable
        self.runner = runner
    }

    // MARK: - 基础执行

    private func run(_ path: String, _ args: [String], timeout: TimeInterval = 20,
                     unchecked: Bool = false) async throws -> CommandResult {
        let full = ["-C", path] + args
        AppLogger.info(AppLogger.git, "git.run", detail: ["subcommand": args.first ?? ""])
        let result = try await runner.run(executable: git, arguments: full, timeout: timeout)
        if !unchecked && result.exitCode != 0 {
            if result.wasTerminated { throw AppError.timeout("git " + args.joined(separator: " ")) }
            let message = result.stderr.isEmpty ? result.stdout : result.stderr
            throw AppError.commandFailed(
                command: "git " + full.joined(separator: " "),
                code: result.exitCode,
                message: message
            )
        }
        return result
    }

    private func rawRun(_ args: [String], timeout: TimeInterval = 30) async throws -> CommandResult {
        let result = try await runner.run(executable: git, arguments: args, timeout: timeout)
        if result.exitCode != 0 {
            if result.wasTerminated { throw AppError.timeout("git " + args.joined(separator: " ")) }
            throw AppError.commandFailed(command: "git " + args.joined(separator: " "),
                                         code: result.exitCode,
                                         message: result.stderr.isEmpty ? result.stdout : result.stderr)
        }
        return result
    }

    private static let recordSeparator = "\u{1e}"
    private static let fieldSeparator = "\u{1f}"
    private static let marker = "\u{1}"

    // MARK: - 仓库

    public func isRepository(_ path: String) async throws -> Bool {
        let result = try await run(path, ["rev-parse", "--is-inside-work-tree"], unchecked: true)
        return result.exitCode == 0 && result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
    }

    public func initializeRepository(at path: String) async throws {
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        _ = try await rawRun(["init", "-b", "main", path])
    }

    public func clone(from url: String, to destination: String) async throws {
        guard !url.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw AppError.invalidInput("请填写远程仓库地址")
        }
        _ = try await rawRun(["clone", url, destination], timeout: 180)
    }

    /// 用户主动点击「扫描文件夹」时才执行，绝非常驻监听。
    public func discoverRepositories(in root: String, maxDepth: Int = 3) -> [Repository] {
        let fm = FileManager.default
        let rootURL = URL(fileURLWithPath: root).standardizedFileURL
        guard let enumerator = fm.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsPackageDescendants]
        ) else { return [] }

        var found: [Repository] = []
        for case let url as URL in enumerator {
            let depth = url.standardizedFileURL.pathComponents.count - rootURL.pathComponents.count
            if depth > maxDepth {
                enumerator.skipDescendants()
                continue
            }
            if url.lastPathComponent == ".git" {
                let parent = url.deletingLastPathComponent()
                found.append(Repository(name: parent.lastPathComponent, path: parent.path))
                enumerator.skipDescendants()
                if found.count >= 40 { break }
            }
        }
        return found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - 状态与分支

    public func status(at path: String) async throws -> WorktreeStatus {
        let result = try await run(path, ["-c", "core.quotePath=false", "status", "--porcelain=v1", "-uall", "-b"])
        var branch = ""
        var upstream = ""
        var ahead = 0
        var behind = 0
        var files: [FileChange] = []

        for rawLine in result.stdout.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.hasPrefix("## ") {
                let header = String(line.dropFirst(3))
                if header.hasPrefix("No commits yet on ") {
                    branch = String(header.dropFirst("No commits yet on ".count))
                } else {
                    let parts = header.components(separatedBy: "...")
                    branch = parts[0].components(separatedBy: " ").first ?? header
                    if parts.count > 1 {
                        upstream = parts[1].components(separatedBy: " ").first ?? ""
                    }
                }
                ahead = Self.numberAfter("ahead", in: header)
                behind = Self.numberAfter("behind", in: header)
                continue
            }
            guard line.count >= 4 else { continue }
            let chars = Array(line)
            let x = String(chars[0])
            let y = String(chars[1])
            var rest = String(chars[3...])
            if rest.hasPrefix("\"") && rest.hasSuffix("\"") {
                rest = String(rest.dropFirst().dropLast())
            }
            var oldPath: String?
            if ["R", "C"].contains(x) || ["R", "C"].contains(y), let arrow = rest.range(of: " -> ") {
                oldPath = String(rest[..<arrow.lowerBound])
                rest = String(rest[arrow.upperBound...])
            }
            files.append(FileChange(path: rest, oldPath: oldPath, indexStatus: x, worktreeStatus: y))
        }
        return WorktreeStatus(branch: branch, upstream: upstream, ahead: ahead, behind: behind, files: files)
    }

    /// 一次 for-each-ref 拿齐本地 + 远程分支，避免逐分支查询（N+1）。
    public func branches(at path: String) async throws -> [Branch] {
        let format = "%(refname)|%(refname:short)|%(HEAD)|%(upstream:short)"
        let result = try await run(path, ["for-each-ref", "--format=\(format)", "refs/heads", "refs/remotes"])
        var items: [Branch] = []
        for line in result.stdout.split(separator: "\n") where !line.isEmpty {
            let fields = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 4 else { continue }
            items.append(Branch(name: fields[1],
                                isCurrent: fields[2] == "*",
                                isRemote: fields[0].hasPrefix("refs/remotes/"),
                                upstream: fields[3]))
        }
        return items.sorted { lhs, rhs in
            if lhs.isCurrent != rhs.isCurrent { return lhs.isCurrent }
            if lhs.isRemote != rhs.isRemote { return !lhs.isRemote }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    public func checkout(_ branch: String, at path: String, create: Bool = false) async throws {
        guard Self.isValidRefName(branch) else { throw AppError.invalidInput("分支名不合法") }
        var args = ["checkout"]
        if create {
            args += ["-b", branch]
        } else if branch.contains("/") {
            let existing = try await self.branches(at: path).filter { !$0.isRemote }.map(\.name)
            if let local = existing.first(where: { branch.hasSuffix("/" + $0) }) {
                args.append(local)
            } else {
                args += ["--track", branch]
            }
        } else {
            args.append(branch)
        }
        _ = try await run(path, args)
    }

    public func createBranch(_ name: String, at path: String) async throws {
        try await checkout(name, at: path, create: true)
    }

    // MARK: - 暂存与提交

    public func stage(paths: [String], at path: String) async throws {
        guard !paths.isEmpty else { return }
        _ = try await run(path, ["add", "--"] + paths)
    }

    /// 只对已暂存文件调用。空仓库（首次提交前）没有 HEAD，
    /// `git restore --staged` 会报 "could not resolve HEAD"，需改用 `git rm --cached`。
    public func unstage(paths: [String], at path: String) async throws {
        let valid = paths.filter { !$0.isEmpty }
        guard !valid.isEmpty else { return }
        if try await hasHEAD(at: path) {
            _ = try await run(path, ["restore", "--staged", "--"] + valid)
        } else {
            _ = try await run(path, ["rm", "--cached", "--"] + valid)
        }
    }

    public func stageAll(at path: String) async throws {
        _ = try await run(path, ["add", "-A"])
    }

    public func unstageAll(at path: String) async throws {
        if try await hasHEAD(at: path) {
            _ = try await run(path, ["reset"])
        } else {
            _ = try await run(path, ["rm", "--cached", "-r", "."], unchecked: true)
        }
    }

    private func hasHEAD(at path: String) async throws -> Bool {
        let result = try await run(path, ["rev-parse", "--verify", "HEAD"], unchecked: true)
        return result.exitCode == 0
    }

    @discardableResult
    public func commit(message: String, at path: String) async throws -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AppError.invalidInput("请先写一句提交说明，例如「修复登录页空白」") }
        _ = try await run(path, ["commit", "-m", trimmed], timeout: 60)
        let result = try await run(path, ["rev-parse", "--short", "HEAD"])
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 丢弃某个未暂存文件的改动（危险操作，UI 必须二次确认）。
    public func discard(paths: [String], at path: String) async throws {
        guard !paths.isEmpty else { return }
        _ = try await run(path, ["restore", "--"] + paths)
    }

    /// 丢弃全部改动（已暂存 + 未暂存 + 未跟踪）。危险操作，UI 必须二次确认。
    public func discardAll(at path: String) async throws {
        // 重置已暂存 + 还原已跟踪文件的修改
        _ = try await run(path, ["reset", "--hard", "HEAD"])
        // 清掉未跟踪文件与目录（不动 .gitignore 忽略的内容）
        _ = try await run(path, ["clean", "-fd"])
    }

    // MARK: - 同步

    public func push(at path: String, branch: String, remote: String = "origin", hasUpstream: Bool = true) async throws {
        var args = ["push"]
        if !hasUpstream { args += ["-u", remote, branch] }
        _ = try await run(path, args, timeout: 90)
    }

    /// 只用 fast-forward，避免产生无意义的 merge commit，保持历史线性清晰。
    public func pull(at path: String) async throws {
        _ = try await run(path, ["pull", "--ff-only"], timeout: 90)
    }

    public func fetch(at path: String, remote: String = "") async throws {
        var args = ["fetch", "--prune"]
        if !remote.isEmpty { args.append(remote) }
        _ = try await run(path, args, timeout: 90)
    }

    // MARK: - 历史与搜索

    /// 支持前缀语法：author: / message: / file: / hash: / since: / until:，普通文本按提交说明搜索。
    public func log(at path: String, query: String = "", allBranches: Bool = false,
                    limit: Int = 200) async throws -> [Commit] {
        let fields = ["%H", "%h", "%an", "%ae", "%aI", "%s", "%b", "%D"]
        let format = Self.marker + fields.joined(separator: Self.fieldSeparator) + Self.recordSeparator
        var args = [
            "-c", "core.quotePath=false", "log", "--graph", "--decorate=short",
            "--date=iso-strict", "--pretty=format:\(format)",
            "--max-count=\(max(1, min(limit, 1000)))", "--regexp-ignore-case"
        ]
        if allBranches { args.append("--all") }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var trailing: [String] = []
        if !trimmed.isEmpty {
            let (key, value) = Self.parseQuery(trimmed)
            switch key {
            case "author": args.append("--author=\(value)")
            case "message": args.append("--grep=\(value)")
            case "hash": args.append(value)
            case "since": args.append("--since=\(value)")
            case "until": args.append("--until=\(value)")
            case "file", "path": trailing = ["--", value]
            default: args.append("--grep=\(value)")
            }
        }
        args += trailing
        let result = try await run(path, args, timeout: 30)
        return Self.parseLog(result.stdout)
    }

    public func changedFiles(in hash: String, at path: String) async throws -> [String] {
        guard hash.count >= 7, hash.count <= 40, hash.allSatisfy(\.isHexDigit) else {
            throw AppError.invalidInput("提交号不合法")
        }
        let result = try await run(path, ["-c", "core.quotePath=false", "show", "--pretty=format:", "--name-only", hash])
        return result.stdout.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    /// 未跟踪文件没有 diff，回退为读取文本内容（限制 256KB，二进制跳过）。
    public func diff(for filePath: String, staged: Bool, at path: String) async throws -> String {
        var args = ["-c", "core.quotePath=false", "diff", "--no-color"]
        if staged { args.append("--cached") }
        args += ["--", filePath]
        let result = try await run(path, args)
        if !result.stdout.isEmpty { return result.stdout }

        let url = URL(fileURLWithPath: path).appendingPathComponent(filePath)
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber, size.intValue <= 256 * 1024,
              let data = try? Data(contentsOf: url) else {
            return "（文件较大或不可读，已跳过内容预览）"
        }
        if data.contains(0) { return "（二进制文件，无法以文本预览）" }
        let text = String(decoding: data, as: UTF8.self)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .prefix(400)
            .map { "+ " + $0 }
            .joined(separator: "\n")
    }

    // MARK: - 冲突处理

    /// 采用哪一侧的版本。遴选场景下 ours = 当前分支，theirs = 被遴选的提交。
    public enum ConflictResolution: String, Codable, Sendable {
        case ours
        case theirs
    }

    public func conflictedFiles(at path: String) async throws -> [String] {
        let result = try await run(
            path,
            ["-c", "core.quotePath=false", "diff", "--name-only", "--diff-filter=U"],
            unchecked: true
        )
        return result.stdout.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    /// 无进行中操作时直接返回空，不启动任何进程（保持刷新轻量）。
    public func conflictedFilesIfNeeded(at path: String) async -> [String] {
        guard inProgressOperation(at: path) != nil else { return [] }
        return (try? await conflictedFiles(at: path)) ?? []
    }

    public func resolveConflict(filePath: String, choose: ConflictResolution,
                                at repoPath: String) async throws {
        guard !filePath.isEmpty else { throw AppError.invalidInput("文件路径不能为空") }
        let flag = choose == .ours ? "--ours" : "--theirs"
        _ = try await run(repoPath, ["checkout", flag, "--", filePath])
        _ = try await run(repoPath, ["add", "--", filePath])
    }

    /// 用户已手动编辑完冲突标记，只需标记为已解决。
    public func markConflictResolved(filePath: String, at repoPath: String) async throws {
        guard !filePath.isEmpty else { throw AppError.invalidInput("文件路径不能为空") }
        _ = try await run(repoPath, ["add", "--", filePath])
    }

    /// 全部冲突解决后继续；GIT_EDITOR=true 已由 CommandRunner 设置，不会弹出编辑器。
    public func continueOperation(at path: String) async throws {
        guard let operation = inProgressOperation(at: path) else {
            throw AppError.invalidInput("当前没有可继续的操作")
        }
        switch operation {
        case "遴选": _ = try await run(path, ["cherry-pick", "--continue"], timeout: 60)
        case "还原": _ = try await run(path, ["revert", "--continue"], timeout: 60)
        case "变基": _ = try await run(path, ["rebase", "--continue"], timeout: 60)
        default:
            throw AppError.invalidInput("合并冲突请在命令行手动提交，或点「中止当前操作」回到操作前")
        }
    }

    // MARK: - 遴选 / 还原（借鉴 Sourcetree 的 Cherry-pick / Reverse commit）

    /// 纯文件检查，不启动进程；用于刷新时显示「遴选进行中」横幅。
    public func inProgressOperation(at path: String) -> String? {
        let fm = FileManager.default
        let gitDir = URL(fileURLWithPath: path).appendingPathComponent(".git", isDirectory: true)
        let markers: [(String, String)] = [
            ("CHERRY_PICK_HEAD", "遴选"),
            ("REVERT_HEAD", "还原"),
            ("MERGE_HEAD", "合并"),
            ("rebase-merge", "变基"),
            ("rebase-apply", "变基")
        ]
        for (file, label) in markers where fm.fileExists(atPath: gitDir.appendingPathComponent(file).path) {
            return label
        }
        return nil
    }

    /// 把某一条别的分支上的提交「复制」到当前分支，生成一条新提交。
    public func cherryPick(_ hash: String, at path: String) async throws {
        guard Self.isValidHash(hash) else { throw AppError.invalidInput("提交号不合法") }
        _ = try await run(path, ["cherry-pick", hash], timeout: 60)
    }

    /// 生成一条反向提交来撤销历史改动，不改写已有历史。
    public func revert(_ hash: String, at path: String) async throws {
        guard Self.isValidHash(hash) else { throw AppError.invalidInput("提交号不合法") }
        _ = try await run(path, ["revert", "--no-edit", hash], timeout: 60)
    }

    public func abortOperation(at path: String) async throws {
        guard let operation = inProgressOperation(at: path) else {
            throw AppError.invalidInput("当前没有进行中的遴选、还原或合并操作")
        }
        switch operation {
        case "遴选": _ = try await run(path, ["cherry-pick", "--abort"])
        case "还原": _ = try await run(path, ["revert", "--abort"])
        case "合并": _ = try await run(path, ["merge", "--abort"])
        default: _ = try await run(path, ["rebase", "--abort"])
        }
    }

    // MARK: - 储藏（Stash）

    public func stashes(at path: String) async throws -> [StashEntry] {
        let format = "%gd\u{1f}%gs\u{1f}%cr\u{1e}"
        let result = try await run(path, ["stash", "list", "--pretty=format:\(format)"], unchecked: true)
        var entries: [StashEntry] = []
        for raw in result.stdout.components(separatedBy: "\u{1e}") {
            let line = raw.trimmingCharacters(in: .newlines)
            guard !line.isEmpty else { continue }
            let fields = line.components(separatedBy: "\u{1f}")
            guard fields.count >= 3 else { continue }
            let reflogID = fields[0].trimmingCharacters(in: .whitespaces)
            let indexToken = reflogID.split(separator: "@").last?
                .trimmingCharacters(in: CharacterSet(charactersIn: "{}")) ?? ""
            let index = Int(indexToken) ?? entries.count
            var message = fields[1]
            var branch = ""
            let lower = message.lowercased()
            if lower.hasPrefix("on ") || lower.hasPrefix("wip on "),
               let colon = message.firstIndex(of: ":") {
                let head = String(message[..<colon])
                branch = head.split(separator: " ").last.map(String.init) ?? ""
                message = String(message[message.index(after: colon)...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            entries.append(StashEntry(index: index, reflogID: reflogID,
                                      message: message, branch: branch,
                                      relativeDate: fields[2]))
        }
        return entries
    }

    public func stashPush(at path: String, message: String = "", includeUntracked: Bool = true) async throws {
        var args = ["stash", "push"]
        if includeUntracked { args.append("--include-untracked") }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { args += ["-m", trimmed] }
        let result = try await run(path, args)
        // git stash push 在干净工作区会以退出码 0 结束，只打印 "No local changes to save"。
        // 必须显式识别，否则 UI 会误报「储藏成功」却什么都没发生。
        let output = (result.stdout + "\n" + result.stderr).lowercased()
        if output.contains("no local changes to save") {
            throw AppError.commandFailed(command: "git stash push", code: 0,
                                         message: "No local changes to save")
        }
    }

    public func stashApply(_ id: String, at path: String, dropAfterApply: Bool = false) async throws {
        guard Self.isValidStashID(id) else { throw AppError.invalidInput("储藏编号不合法") }
        _ = try await run(path, ["stash", dropAfterApply ? "pop" : "apply", id])
    }

    public func stashDrop(_ id: String, at path: String) async throws {
        guard Self.isValidStashID(id) else { throw AppError.invalidInput("储藏编号不合法") }
        _ = try await run(path, ["stash", "drop", id])
    }

    // MARK: - 标签

    public func tags(at path: String) async throws -> [GitTag] {
        let format = "%(refname:short)\u{1f}%(objectname:short)\u{1f}%(objecttype)\u{1f}%(contents:subject)"
        let result = try await run(path, ["tag", "--list", "--format=\(format)"], unchecked: true)
        var items: [GitTag] = []
        for line in result.stdout.split(separator: "\n") where !line.isEmpty {
            let fields = line.split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 4 else { continue }
            items.append(GitTag(name: fields[0], target: fields[1],
                                isAnnotated: fields[2] == "tag", message: fields[3]))
        }
        return items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func addTag(_ name: String, to hash: String = "", message: String = "", at path: String) async throws {
        guard Self.isValidRefName(name) else { throw AppError.invalidInput("标签名不合法") }
        let annotatedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        var args = ["tag"]
        if !annotatedMessage.isEmpty { args += ["-a", name, "-m", annotatedMessage] }
        else { args.append(name) }
        if !hash.isEmpty {
            guard Self.isValidHash(hash) else { throw AppError.invalidInput("提交号不合法") }
            args.append(hash)
        }
        _ = try await run(path, args)
    }

    public func deleteTag(_ name: String, at path: String) async throws {
        guard Self.isValidRefName(name) else { throw AppError.invalidInput("标签名不合法") }
        _ = try await run(path, ["tag", "-d", name])
    }

    public func deleteBranch(_ name: String, at path: String, force: Bool = false) async throws {
        guard Self.isValidRefName(name) else { throw AppError.invalidInput("分支名不合法") }
        _ = try await run(path, ["branch", force ? "-D" : "-d", name])
    }

    // MARK: - 提交详情（三个只读命令并行，点击时才执行）

    public func commitDetail(_ hash: String, at path: String) async throws -> CommitDetail {
        guard Self.isValidHash(hash) else { throw AppError.invalidInput("提交号不合法") }
        let metaFormat = "%H\u{1f}%an\u{1f}%ae\u{1f}%aI\u{1f}%cn\u{1f}%ce\u{1f}%cI\u{1f}%P\u{1f}%s\u{1f}%b\u{1f}%D"
        async let metaTask = run(path, ["show", "--no-patch", "--pretty=format:\(metaFormat)", hash])
        async let statusTask = run(path, ["-c", "core.quotePath=false", "show",
                                          "--pretty=format:", "--name-status", "--find-renames", hash])
        async let statTask = run(path, ["diff-tree", "--no-commit-id", "-r", "--root", "--shortstat", hash],
                                 unchecked: true)
        let (meta, status, stat) = try await (metaTask, statusTask, statTask)

        let fields = meta.stdout.trimmingCharacters(in: .newlines).components(separatedBy: "\u{1f}")
        let changed = Self.parseNameStatus(status.stdout)
        return CommitDetail(
            hash: fields.count > 0 ? fields[0] : hash,
            authorName: fields.count > 1 ? fields[1] : "",
            authorEmail: fields.count > 2 ? fields[2] : "",
            authorDate: fields.count > 3 ? fields[3] : "",
            committerName: fields.count > 4 ? fields[4] : "",
            committerEmail: fields.count > 5 ? fields[5] : "",
            committerDate: fields.count > 6 ? fields[6] : "",
            parents: fields.count > 7 ? fields[7].split(separator: " ").map(String.init).filter { !$0.isEmpty } : [],
            subject: fields.count > 8 ? fields[8] : "",
            body: fields.count > 9 ? fields[9].trimmingCharacters(in: .whitespacesAndNewlines) : "",
            refs: fields.count > 10 ? fields[10].trimmingCharacters(in: .whitespacesAndNewlines) : "",
            changedFiles: changed,
            insertions: Self.count(of: "insertions?", in: stat.stdout),
            deletions: Self.count(of: "deletions?", in: stat.stdout),
            fileCount: Self.count(of: "files? changed", in: stat.stdout)
        )
    }

    public func diffInCommit(_ hash: String, file: String, at path: String) async throws -> String {
        guard Self.isValidHash(hash), !file.isEmpty else { throw AppError.invalidInput("参数不合法") }
        let result = try await run(path, ["-c", "core.quotePath=false", "show",
                                          "--no-color", "--format=", hash, "--", file])
        return result.stdout.isEmpty ? "（这条提交里该文件没有可显示的文本差异）" : result.stdout
    }

    // MARK: - 远程源

    public func remotes(at path: String) async throws -> [Remote] {
        let result = try await run(path, ["remote", "-v"])
        var byName: [String: Remote] = [:]
        for line in result.stdout.split(separator: "\n") where !line.isEmpty {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard parts.count >= 3 else { continue }
            var remote = byName[parts[0]] ?? Remote(name: parts[0], fetchURL: "", pushURL: "")
            if parts[2].contains("fetch") { remote.fetchURL = parts[1] }
            if parts[2].contains("push") { remote.pushURL = parts[1] }
            byName[remote.name] = remote
        }
        return byName.values.sorted { $0.name < $1.name }
    }

    public func addRemote(name: String, url: String, at path: String) async throws {
        guard Self.isValidRemoteName(name) else { throw AppError.invalidInput("远程源名称只能包含字母、数字、点、下划线和连字符") }
        guard !url.trimmingCharacters(in: .whitespaces).isEmpty else { throw AppError.invalidInput("请填写远程源地址") }
        _ = try await run(path, ["remote", "add", name, url])
    }

    public func removeRemote(name: String, at path: String) async throws {
        guard Self.isValidRemoteName(name) else { throw AppError.invalidInput("远程源名称不合法") }
        _ = try await run(path, ["remote", "remove", name])
    }

    public func setRemoteURL(name: String, url: String, at path: String) async throws {
        guard Self.isValidRemoteName(name) else { throw AppError.invalidInput("远程源名称不合法") }
        guard !url.trimmingCharacters(in: .whitespaces).isEmpty else { throw AppError.invalidInput("请填写远程源地址") }
        _ = try await run(path, ["remote", "set-url", name, url])
    }

    public func renameRemote(from old: String, to new: String, at path: String) async throws {
        guard Self.isValidRemoteName(old), Self.isValidRemoteName(new) else {
            throw AppError.invalidInput("远程源名称不合法")
        }
        _ = try await run(path, ["remote", "rename", old, new])
    }

    // MARK: - 解析工具

    private static func isValidHash(_ hash: String) -> Bool {
        guard hash.count >= 7, hash.count <= 40 else { return false }
        return hash.allSatisfy(\.isHexDigit)
    }

    private static func isValidStashID(_ id: String) -> Bool {
        id.hasPrefix("stash@{") && id.hasSuffix("}") && id.count <= 24
    }

    private static func parseNameStatus(_ output: String) -> [ChangedFile] {
        var files: [ChangedFile] = []
        for raw in output.split(separator: "\n") where !raw.isEmpty {
            let parts = raw.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 2 else { continue }
            let state = String(parts[0].prefix(1))
            if (state == "R" || state == "C") && parts.count >= 3 {
                files.append(ChangedFile(status: state, path: parts[2], oldPath: parts[1]))
            } else {
                files.append(ChangedFile(status: state, path: parts[1]))
            }
        }
        return files
    }

    private static func count(of label: String, in text: String) -> Int {
        guard let range = text.range(of: "\\d+ " + label, options: .regularExpression),
              let token = text[range].split(separator: " ").first else { return 0 }
        return Int(token) ?? 0
    }

    private static func parseQuery(_ query: String) -> (String, String) {
        for key in ["author", "message", "file", "path", "hash", "since", "until"] {
            let prefix = key + ":"
            if query.lowercased().hasPrefix(prefix) {
                return (key, String(query.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces))
            }
        }
        return ("text", query)
    }

    private static func parseLog(_ output: String) -> [Commit] {
        var commits: [Commit] = []
        for raw in output.split(separator: Character(recordSeparator), omittingEmptySubsequences: true) {
            let segment = String(raw).trimmingCharacters(in: .newlines)
            guard let markerRange = segment.range(of: marker) else { continue }
            let graph = String(segment[..<markerRange.lowerBound])
            let fields = String(segment[markerRange.upperBound...]).components(separatedBy: fieldSeparator)
            guard fields.count >= 8 else { continue }
            commits.append(Commit(
                hash: fields[0], shortHash: fields[1], author: fields[2], email: fields[3],
                date: fields[4], subject: fields[5], body: fields[6].trimmingCharacters(in: .whitespacesAndNewlines),
                refs: fields[7], graph: graph
            ))
        }
        return commits
    }

    private static func numberAfter(_ label: String, in text: String) -> Int {
        guard let range = text.range(of: label + " \\d+", options: .regularExpression) else { return 0 }
        return Int(text[range].split(separator: " ").last ?? "0") ?? 0
    }

    private static func isValidRemoteName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 64, !name.hasPrefix("-") else { return false }
        return name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-" }
    }

    private static func isValidRefName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 128, !name.hasPrefix("-"), !name.contains(" ") else { return false }
        return true
    }
}
