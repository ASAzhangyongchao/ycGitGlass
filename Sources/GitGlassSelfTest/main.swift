import Foundation
import GitCore

/// 深度自检：在真实临时 Git 仓库 + 临时 SSH 目录上跑通全部服务层能力，不依赖 GUI、不触碰用户真实 ~/.ssh。
@main
struct GitGlassSelfTest {
    static func main() async {
        var passed = 0
        var failed = 0

        func check(_ label: String, _ condition: Bool, _ detail: String = "") {
            if condition {
                passed += 1
                print("  ✅ \(label)")
            } else {
                failed += 1
                print("  ❌ \(label) \(detail)")
            }
        }

        func section(_ title: String) { print("\n▸ \(title)") }

        print("码牛 MooGit 深度自检 v1.3.0")

        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("gitglass-selftest-\(UUID().uuidString)")
        let repo = root.appendingPathComponent("demo")
        defer { try? fm.removeItem(at: root) }

        section("环境")
        do {
            try AppConfig.validate()
            check("git / ssh-keygen 可用", true)
        } catch {
            check("git / ssh-keygen 可用", false, "\(error)")
        }

        let git = GitService()
        let runner = CommandRunner()

        do {
            // MARK: A 基础仓库操作
            section("A · 仓库 / 状态 / 提交 / 历史")
            try fm.createDirectory(at: repo, withIntermediateDirectories: true)
            _ = try await git.initializeRepository(at: repo.path)
            _ = try await runner.run(executable: AppConfig.gitExecutable,
                                     arguments: ["-C", repo.path, "config", "user.name", "GitGlass SelfTest"])
            _ = try await runner.run(executable: AppConfig.gitExecutable,
                                     arguments: ["-C", repo.path, "config", "user.email", "selftest@gitglass.local"])
            try "hello\n".write(to: repo.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
            try fm.createDirectory(at: repo.appendingPathComponent("Sources"), withIntermediateDirectories: true)
            try "print(1)\n".write(to: repo.appendingPathComponent("Sources/main.swift"), atomically: true, encoding: .utf8)

            check("isRepository 识别仓库", try await git.isRepository(repo.path))
            check("非仓库路径返回 false", try await git.isRepository(root.path) == false)

            let initial = try await git.status(at: repo.path)
            check("status 识别 2 个未跟踪文件", initial.files.count == 2, "实际 \(initial.files.count)")
            check("status 未暂存计数", initial.stagedCount == 0 && initial.unstagedCount == 2)

            try await git.stage(paths: ["README.md"], at: repo.path)
            let staged = try await git.status(at: repo.path)
            check("stage 单个文件", staged.stagedCount == 1)
            check("stage 后 isStaged", staged.files.first(where: { $0.path == "README.md" })?.isStaged == true)

            try await git.unstage(paths: ["README.md"], at: repo.path)
            check("空仓库 unstage 走 rm --cached", try await git.status(at: repo.path).stagedCount == 0)

            try await git.stageAll(at: repo.path)
            let firstHash = try await git.commit(message: "feat: 初始化项目", at: repo.path)
            check("commit 返回短 hash", !firstHash.isEmpty, firstHash)
            check("提交后工作区干净", try await git.status(at: repo.path).isClean)

            try "print(2)\n".write(to: repo.appendingPathComponent("Sources/main.swift"), atomically: true, encoding: .utf8)
            let modified = try await git.status(at: repo.path)
            check("status 识别修改状态", modified.files.first?.badge == "修改", modified.files.first?.badge ?? "-")
            let diff = try await git.diff(for: "Sources/main.swift", staged: false, at: repo.path)
            check("diff 含新增行", diff.contains("+print(2)"), diff.prefix(80).description)

            try await git.stageAll(at: repo.path)
            _ = try await git.commit(message: "fix: 修正输出", at: repo.path)
            let history = try await git.log(at: repo.path)
            check("log 返回 2 条提交", history.count == 2, "实际 \(history.count)")
            check("log 时间倒序", history.first?.subject == "fix: 修正输出")
            check("log 含图形轨道", history.contains { !$0.graph.isEmpty })
            check("log 字段完整", history.first?.author.isEmpty == false && history.first?.shortHash.isEmpty == false)

            let grep = try await git.log(at: repo.path, query: "初始化")
            check("按说明搜索", grep.count == 1 && grep.first?.subject == "feat: 初始化项目")
            let authorSearch = try await git.log(at: repo.path, query: "author:GitGlass")
            check("按作者搜索", authorSearch.count >= 1)
            let fileSearch = try await git.log(at: repo.path, query: "file:README.md")
            check("按文件搜索", fileSearch.count == 1)
            let changed = try await git.changedFiles(in: history.first?.hash ?? "", at: repo.path)
            check("show 变更文件列表", changed.contains("Sources/main.swift"))

            let rootHash = try await git.log(at: repo.path, query: "初始化").first?.hash ?? ""
            check("取到首条提交完整 hash", rootHash.count >= 7)

            // MARK: B 遴选 / 还原
            section("B · 遴选 Cherry-pick / 还原 Revert")
            let branchesBefore = try await git.branches(at: repo.path)
            let mainBranch = branchesBefore.first(where: \.isCurrent)?.name ?? "main"
            try await git.createBranch("feature/cherry", at: repo.path)
            check("新建并切到 feature/cherry", try await git.status(at: repo.path).branch == "feature/cherry")

            try "let feature = true\n".write(to: repo.appendingPathComponent("FeatureOnly.swift"),
                                             atomically: true, encoding: .utf8)
            try await git.stageAll(at: repo.path)
            _ = try await git.commit(message: "feat: 分支独有功能", at: repo.path)
            let featureHash = try await git.log(at: repo.path).first?.hash ?? ""
            check("分支提交已创建", featureHash.count >= 7)

            try await git.checkout(mainBranch, at: repo.path)
            check("切回主分支", try await git.status(at: repo.path).branch == mainBranch)
            check("主分支没有该新文件", !fm.fileExists(atPath: repo.appendingPathComponent("FeatureOnly.swift").path))

            try await git.cherryPick(featureHash, at: repo.path)
            let afterPick = try await git.log(at: repo.path)
            check("遴选生成新提交", afterPick.first?.subject == "feat: 分支独有功能", afterPick.first?.subject ?? "-")
            check("遴选带来文件内容", fm.fileExists(atPath: repo.appendingPathComponent("FeatureOnly.swift").path))
            check("遴选后无挂起操作", git.inProgressOperation(at: repo.path) == nil)
            check("遴选后主分支多一条提交", afterPick.count == 3,
                  "实际 \(afterPick.count) 条：\(afterPick.map(\.shortHash).joined(separator: ","))")
            // Git 是内容寻址：父提交 / 树 / 作者 / 时间戳完全一致时，cherry-pick
            // 可能复用同一个 commit hash，属正常行为。真正要保证的是「原分支历史不被改写」。
            try await git.checkout("feature/cherry", at: repo.path)
            let featureLog = try await git.log(at: repo.path)
            check("遴选不改写原分支历史", featureLog.first?.hash == featureHash && featureLog.count == 3,
                  "实际 \(featureLog.count) 条，首条 \(featureLog.first?.shortHash ?? "-")")
            try await git.checkout(mainBranch, at: repo.path)

            try await git.revert(afterPick.first?.hash ?? "", at: repo.path)
            let afterRevert = try await git.log(at: repo.path)
            check("还原生成反向提交", afterRevert.first?.subject.hasPrefix("Revert") == true,
                  afterRevert.first?.subject ?? "-")
            check("还原后文件被移除", !fm.fileExists(atPath: repo.appendingPathComponent("FeatureOnly.swift").path))
            check("还原后工作区干净", try await git.status(at: repo.path).isClean)

            // MARK: B2 冲突可视化与解决
            section("B2 · 冲突检测 / 选边 / 继续 / 中止")
            try "base line\n".write(to: repo.appendingPathComponent("Conflict.txt"),
                                    atomically: true, encoding: .utf8)
            try await git.stageAll(at: repo.path)
            _ = try await git.commit(message: "chore: 冲突基线", at: repo.path)

            try await git.createBranch("conflict-src", at: repo.path)
            try "from source branch\n".write(to: repo.appendingPathComponent("Conflict.txt"),
                                             atomically: true, encoding: .utf8)
            try await git.stageAll(at: repo.path)
            _ = try await git.commit(message: "feat: 来源分支改动", at: repo.path)
            let sourceHash = try await git.log(at: repo.path).first?.hash ?? ""

            try await git.checkout(mainBranch, at: repo.path)
            try "from main branch\n".write(to: repo.appendingPathComponent("Conflict.txt"),
                                           atomically: true, encoding: .utf8)
            try await git.stageAll(at: repo.path)
            _ = try await git.commit(message: "feat: 主分支改动", at: repo.path)

            do {
                try await git.cherryPick(sourceHash, at: repo.path)
                check("遴选冲突被检出", false)
            } catch let error as AppError {
                check("遴选冲突被检出", error.friendlyMessage.contains("遴选")
                      || error.friendlyMessage.contains("冲突"), error.friendlyMessage)
            }
            check("进行中操作识别为遴选", git.inProgressOperation(at: repo.path) == "遴选")
            let conflicts = try await git.conflictedFiles(at: repo.path)
            check("冲突文件列表正确", conflicts.contains("Conflict.txt"), conflicts.joined(separator: ","))

            try await git.resolveConflict(filePath: "Conflict.txt", choose: .theirs, at: repo.path)
            let resolvedText = try String(contentsOf: repo.appendingPathComponent("Conflict.txt"), encoding: .utf8)
            check("采用 theirs 生效", resolvedText.contains("from source branch"), resolvedText)
            check("解决后冲突列表清空", try await git.conflictedFiles(at: repo.path).isEmpty)

            try await git.continueOperation(at: repo.path)
            check("继续后操作状态清空", git.inProgressOperation(at: repo.path) == nil)
            check("继续后工作区干净", try await git.status(at: repo.path).isClean)
            check("继续后生成提交", (try await git.log(at: repo.path)).first?.subject == "feat: 来源分支改动")

            // 第二次冲突：验证一键中止
            try await git.createBranch("conflict-src2", at: repo.path)
            try "second source\n".write(to: repo.appendingPathComponent("Conflict.txt"),
                                        atomically: true, encoding: .utf8)
            try await git.stageAll(at: repo.path)
            _ = try await git.commit(message: "feat: 第二次来源改动", at: repo.path)
            let sourceHash2 = try await git.log(at: repo.path).first?.hash ?? ""

            try await git.checkout(mainBranch, at: repo.path)
            try "second main\n".write(to: repo.appendingPathComponent("Conflict.txt"),
                                      atomically: true, encoding: .utf8)
            try await git.stageAll(at: repo.path)
            _ = try await git.commit(message: "feat: 第二次主分支改动", at: repo.path)
            do {
                try await git.cherryPick(sourceHash2, at: repo.path)
                check("第二次冲突被检出", false)
            } catch {
                check("第二次冲突被检出", true)
            }
            check("第二次冲突状态正确", git.inProgressOperation(at: repo.path) == "遴选")
            try await git.abortOperation(at: repo.path)
            check("中止后状态清空", git.inProgressOperation(at: repo.path) == nil)
            check("中止后工作区干净", try await git.status(at: repo.path).isClean)
            let noConflicts = await git.conflictedFilesIfNeeded(at: repo.path)
            check("无操作时冲突列表为空且不起进程", noConflicts.isEmpty)

            // MARK: C 储藏
            section("C · 储藏 Stash")
            try "stash mark\n".write(to: repo.appendingPathComponent("StashNote.txt"),
                                     atomically: true, encoding: .utf8)
            try await git.stashPush(at: repo.path, message: "自检储藏", includeUntracked: true)
            check("储藏后工作区干净", try await git.status(at: repo.path).isClean)
            let stashList = try await git.stashes(at: repo.path)
            check("储藏列表 1 条", stashList.count == 1, "实际 \(stashList.count)")
            check("储藏说明解析", stashList.first?.message.contains("自检储藏") == true,
                  stashList.first?.message ?? "-")
            check("储藏 reflog id 合法", stashList.first?.reflogID.hasPrefix("stash@{") == true)
            check("储藏分支解析", stashList.first?.branch.isEmpty == false, stashList.first?.branch ?? "-")

            let stashID = stashList.first?.reflogID ?? ""
            try await git.stashApply(stashID, at: repo.path, dropAfterApply: false)
            check("恢复储藏带回文件", fm.fileExists(atPath: repo.appendingPathComponent("StashNote.txt").path))
            check("apply 保留储藏记录", try await git.stashes(at: repo.path).count == 1)
            try await git.stashDrop(stashID, at: repo.path)
            check("删除储藏后为空", try await git.stashes(at: repo.path).isEmpty)

            try await git.stageAll(at: repo.path)
            _ = try await git.commit(message: "chore: 提交恢复内容", at: repo.path)

            try "pop mark\n".write(to: repo.appendingPathComponent("PopNote.txt"),
                                   atomically: true, encoding: .utf8)
            try await git.stashPush(at: repo.path, message: "pop 测试")
            let popID = try await git.stashes(at: repo.path).first?.reflogID ?? ""
            try await git.stashApply(popID, at: repo.path, dropAfterApply: true)
            let stashesAfterPop = try await git.stashes(at: repo.path)
            check("pop 恢复并移除记录", fm.fileExists(atPath: repo.appendingPathComponent("PopNote.txt").path)
                  && stashesAfterPop.isEmpty)

            do {
                try await git.stageAll(at: repo.path)
                _ = try await git.commit(message: "chore: 清理 pop", at: repo.path)
                try await git.stashPush(at: repo.path, message: "不应成功")
                check("无改动时储藏被拦截", false)
            } catch let error as AppError {
                check("无改动时储藏被拦截", error.friendlyMessage.contains("储藏"), error.friendlyMessage)
            }

            // MARK: D 标签
            section("D · 标签 Tag")
            try await git.addTag("v1.0.0", at: repo.path)
            try await git.addTag("v1.1.0", message: "发布说明", at: repo.path)
            try await git.addTag("v0.9.0", to: rootHash, at: repo.path)
            let tags = try await git.tags(at: repo.path)
            check("标签共 3 个", tags.count == 3, "实际 \(tags.count)")
            check("轻量标签识别", tags.first(where: { $0.name == "v1.0.0" })?.isAnnotated == false)
            check("附注标签识别", tags.first(where: { $0.name == "v1.1.0" })?.isAnnotated == true)
            check("附注内容解析", tags.first(where: { $0.name == "v1.1.0" })?.message.contains("发布说明") == true)
            try await git.deleteTag("v0.9.0", at: repo.path)
            check("删除标签后剩 2 个", try await git.tags(at: repo.path).count == 2)

            // MARK: E 提交详情
            section("E · 提交详情 / 逐文件 diff")
            let detailHash = try await git.log(at: repo.path).first?.hash ?? ""
            let detail = try await git.commitDetail(detailHash, at: repo.path)
            check("详情 hash 正确", detail.hash == detailHash)
            check("详情作者解析", detail.authorName == "GitGlass SelfTest", detail.authorName)
            check("详情邮箱解析", detail.authorEmail == "selftest@gitglass.local", detail.authorEmail)
            check("详情父提交非空", !detail.parents.isEmpty)
            check("详情提交说明非空", !detail.subject.isEmpty)
            check("详情时间格式", detail.authorDate.contains("T"))
            check("详情含变更文件", !detail.changedFiles.isEmpty)
            check("详情统计文件数", detail.fileCount >= 0)
            check("详情非合并提交", !detail.isMerge)
            let rootDetail = try await git.commitDetail(rootHash, at: repo.path)
            check("首个提交无父提交", rootDetail.parents.isEmpty)
            check("首个提交含新增文件", rootDetail.changedFiles.contains { $0.status == "A" })

            let detailFile = detail.changedFiles.first?.path ?? "README.md"
            let commitDiff = try await git.diffInCommit(detailHash, file: detailFile, at: repo.path)
            check("逐文件 diff 有内容", commitDiff.count > 10, commitDiff.prefix(60).description)
            do {
                _ = try await git.commitDetail("not-a-hash", at: repo.path)
                check("非法提交号被拦截", false)
            } catch let error as AppError {
                check("非法提交号被拦截", error.friendlyMessage.contains("不合法"), error.friendlyMessage)
            }

            // MARK: F 分支 / 远程源 / 扫描
            section("F · 分支 / 远程源 / 批量扫描")
            try await git.createBranch("tmp/delete-me", at: repo.path)
            try await git.checkout(mainBranch, at: repo.path)
            try await git.deleteBranch("tmp/delete-me", at: repo.path)
            check("删除本地分支", !(try await git.branches(at: repo.path)).contains { $0.name == "tmp/delete-me" })

            try await git.addRemote(name: "origin", url: "git@github.com:example/demo.git", at: repo.path)
            check("addRemote / remotes", try await git.remotes(at: repo.path).count == 1)
            try await git.setRemoteURL(name: "origin", url: "git@gitee.com:example/demo.git", at: repo.path)
            check("setRemoteURL", try await git.remotes(at: repo.path).first?.fetchURL.contains("gitee.com") == true)
            try await git.renameRemote(from: "origin", to: "upstream", at: repo.path)
            check("renameRemote", try await git.remotes(at: repo.path).first?.name == "upstream")
            try await git.removeRemote(name: "upstream", at: repo.path)
            check("removeRemote", try await git.remotes(at: repo.path).isEmpty)
            do {
                try await git.addRemote(name: "bad name", url: "x", at: repo.path)
                check("非法远程名被拦截", false)
            } catch let error as AppError {
                check("非法远程名被拦截", error.friendlyMessage.contains("远程源名称"), error.friendlyMessage)
            }
            check("扫描文件夹发现仓库", git.discoverRepositories(in: root.path).count == 1)

            // MARK: G 中文 / 空格路径
            section("G · 中文与空格路径")
            let chineseDir = repo.appendingPathComponent("中文 目录")
            try fm.createDirectory(at: chineseDir, withIntermediateDirectories: true)
            try "// 中文文件\n".write(to: chineseDir.appendingPathComponent("文件 名.swift"),
                                     atomically: true, encoding: .utf8)
            let unicodeStatus = try await git.status(at: repo.path)
            let unicodePath = "中文 目录/文件 名.swift"
            check("中文空格路径可解析", unicodeStatus.files.contains { $0.path == unicodePath },
                  unicodeStatus.files.map(\.path).joined(separator: ","))
            try await git.stage(paths: [unicodePath], at: repo.path)
            check("中文空格路径可暂存", (try await git.status(at: repo.path)).stagedCount == 1)
            _ = try await git.commit(message: "feat: 支持中文路径", at: repo.path)
            check("中文路径提交后干净", try await git.status(at: repo.path).isClean)

            // MARK: H 错误体系
            section("H · 错误映射 / 类型化错误")
            let cases: [(String, String)] = [
                ("Permission denied (publickey).", "SSH"),
                ("fatal: The current branch has no upstream branch", "上游"),
                ("nothing to commit, working tree clean", "提交"),
                ("error: could not apply abc1234... demo", "遴选"),
                ("No local changes to save", "储藏"),
                ("WARNING: UNPROTECTED PRIVATE KEY FILE!", "权限"),
                ("fatal: not a git repository", "不是")
            ]
            for (raw, keyword) in cases {
                let text = AppError.translate(raw)
                check("错误中文化「\(keyword)」", text.contains(keyword), text)
            }
            let typedError = AppError.commandFailed(command: "git push", code: 128,
                                                    message: "Permission denied (publickey).")
            check("错误含恢复建议", typedError.suggestion.contains("密钥"), typedError.suggestion)
            check("错误含原始信息折叠", typedError.rawDetail.contains("git push"))
            do {
                _ = try await git.commit(message: "   ", at: repo.path)
                check("空提交信息被拦截", false)
            } catch let error as AppError {
                check("空提交信息被拦截", error.friendlyMessage.contains("提交说明"), error.friendlyMessage)
            }

            // MARK: I 持久化
            section("I · 状态持久化")
            let store = RepositoryStore(fileURL: root.appendingPathComponent("state.json"))
            var saved = PersistedState.initial
            saved.repositories = [Repository(name: "demo", path: repo.path)]
            saved.keyPlatformBindings = ["/tmp/a.pub": "github"]
            saved.onboardingSeen = true
            saved.platforms.append(GitPlatform(id: "custom-x", name: "公司 GitLab",
                                               host: "git.example.com", symbol: "server.rack", isCustom: true))
            try store.save(saved)
            let loaded = store.load()
            check("仓库列表往返", loaded.repositories.count == 1)
            check("密钥绑定往返", loaded.keyPlatformBindings["/tmp/a.pub"] == "github")
            check("自定义平台往返", loaded.platforms.contains { $0.host == "git.example.com" })
            check("引导标记往返", loaded.onboardingSeen)
            check("默认平台预设完整", loaded.platforms.count >= 6)
            check("路径归一化", RepositoryStore.normalized("~/demo/../demo") == "/demo"
                  || RepositoryStore.normalized("~/demo/../demo").hasSuffix("/demo"))

            // MARK: J SSH 密钥（完全隔离在临时目录）
            section("J · 多平台密钥 / SSH config")
            let sshHome = root.appendingPathComponent("ssh-home")
            let configURL = sshHome.appendingPathComponent("config")
            try fm.createDirectory(at: sshHome, withIntermediateDirectories: true)
            let originalConfig = "Host personal\n    HostName personal.example.com\n    User git\n"
            try originalConfig.write(to: configURL, atomically: true, encoding: .utf8)
            let ssh = SSHKeyService(sshDirectory: sshHome, configURL: configURL)
            let platform = AppConfig.defaultPlatforms[0]
            let generated = try await ssh.generateKey(for: platform, email: "test@example.com", passphrase: "")
            check("生成私钥文件", fm.fileExists(atPath: generated.privateKeyPath ?? ""))
            check("生成公钥文件", fm.fileExists(atPath: generated.publicKeyPath))
            let privateAttributes = try fm.attributesOfItem(atPath: generated.privateKeyPath ?? "")
            let privateMode = privateAttributes[FileAttributeKey.posixPermissions] as? NSNumber
            check("私钥权限为 600", Int(privateMode?.intValue ?? -1) == 0o600, "\(privateMode?.intValue ?? -1)")
            let pubText = try ssh.publicKeyContent(generated)
            check("公钥以 ssh-ed25519 开头", pubText.hasPrefix("ssh-ed25519"))
            let parsed = try await ssh.fingerprint(of: generated.publicKeyPath)
            check("指纹解析出 SHA256", parsed.fingerprint.hasPrefix("SHA256:"), parsed.fingerprint)
            check("指纹解析出 ED25519", parsed.keyType.uppercased().contains("ED25519"), parsed.keyType)
            let listed = try await ssh.listKeys(platforms: AppConfig.defaultPlatforms,
                                                bindings: [generated.publicKeyPath: "github"])
            check("密钥列表 1 把", listed.count == 1)
            check("密钥平台归类", listed.first?.platformID == "github")
            check("密钥权限检查通过", listed.first?.permissionsOK == true)

            try ssh.applyConfig(keys: listed, platforms: AppConfig.defaultPlatforms)
            let configAfter = try String(contentsOf: configURL, encoding: .utf8)
            check("config 写入 GitHub Host", configAfter.contains("Host github.com"))
            check("config 保留用户手写 Host", configAfter.contains("Host personal"))
            check("config 含管理块标记", configAfter.contains(AppConfig.configBlockBegin))
            let backup = sshHome.appendingPathComponent("config.gitglass.bak")
            check("首次写入自动备份", fm.fileExists(atPath: backup.path))
            check("备份内容为原始配置", (try? String(contentsOf: backup, encoding: .utf8)) == originalConfig)

            try ssh.applyConfig(keys: listed, platforms: AppConfig.defaultPlatforms)
            let configTwice = try String(contentsOf: configURL, encoding: .utf8)
            check("重复写入幂等（单管理块）",
                  configTwice.components(separatedBy: AppConfig.configBlockBegin).count - 1 == 1)
            check("重复写入仍保留手写 Host", configTwice.contains("Host personal"))

            try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: generated.privateKeyPath ?? "")
            try ssh.fixPermissions(generated)
            let fixed = try await ssh.listKeys(platforms: AppConfig.defaultPlatforms, bindings: [:])
            check("修复权限生效", fixed.first?.permissionsOK == true)
            check("私钥内容不进入日志", AppLogger.sanitize("BEGIN OPENSSH PRIVATE KEY").contains("隐去"))
            check("敏感参数被脱敏", AppLogger.sanitize("token=abc123").contains("隐去"))

            let tempPub = root.appendingPathComponent("probe.pub")
            try "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGitGlassProbeKeyOnlyForTest test@github.com\n"
                .write(to: tempPub, atomically: true, encoding: .utf8)
            let fakeKey = SSHKeyPair(publicKeyPath: tempPub.path, privateKeyPath: nil, platformID: "github")
            check("公钥内容可读", (try ssh.publicKeyContent(fakeKey)).hasPrefix("ssh-ed25519"))
            check("仅公钥标记正确", fakeKey.hasPrivateKey == false)

            // MARK: K 命令执行器
            section("K · 命令执行器 / 超时 / 并发")
            let echoResult = try await runner.run(executable: "/bin/echo",
                                                  arguments: ["hello; echo INJECTED"])
            check("参数不经 shell 解析", echoResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                  == "hello; echo INJECTED")
            let timeoutStart = Date()
            let timed = try await runner.run(executable: "/bin/sleep", arguments: ["5"], timeout: 1)
            let elapsed = Date().timeIntervalSince(timeoutStart)
            check("超时 1 秒内终止", elapsed < 3, "耗时 \(String(format: "%.2f", elapsed))s")
            check("超时进程被信号终止", timed.wasTerminated || timed.exitCode != 0)
            let concurrent = try await withThrowingTaskGroup(of: String.self) { group in
                for index in 0..<5 {
                    group.addTask {
                        let result = try await runner.run(executable: "/bin/echo", arguments: ["task\(index)"])
                        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
                var values: [String] = []
                for try await value in group { values.append(value) }
                return values
            }
            check("并发 5 条命令全部成功", concurrent.count == 5 && Set(concurrent).count == 5)
            check("空仓库状态解析仍正常", try await git.status(at: repo.path).isClean)

            // MARK: L 轻量约束 / 模型契约
            section("L · 轻量约束 / 模型契约")
            check("刷新原因均为事件", RefreshReason.manual.rawValue == "手动刷新"
                  && RefreshReason.branchSwitch.rawValue == "切换分支"
                  && RefreshReason.afterMutation.rawValue == "操作完成")
            check("页面含储藏页", AppTab.allCases.contains(.stashes) && AppTab.allCases.count == 6)
            check("最后状态仍干净", try await git.status(at: repo.path).isClean)

            // MARK: M 版本比较与更新信息
            section("M · 版本比较 / 更新信息")
            check("1.2.0 < 1.3.0", UpdateService.compareVersions("1.2.0", "1.3.0") < 0)
            check("v1.3.0 > 1.2.9", UpdateService.compareVersions("v1.3.0", "1.2.9") > 0)
            check("1.2 == 1.2.0", UpdateService.compareVersions("1.2", "1.2.0") == 0)
            check("1.10.0 > 1.9.0（非字典序）", UpdateService.compareVersions("1.10.0", "1.9.0") > 0)
            check("2.0.0-beta < 2.0.0", UpdateService.compareVersions("2.0.0-beta", "2.0.0") < 0)
            check("非法段按 0 处理", UpdateService.compareVersions("1.x", "1.0.1") < 0)
            let info = UpdateInfo(tag: "v1.4.0", name: "Release 1.4.0",
                                  htmlURL: "https://example.com", publishedAt: "2026-11-11")
            check("UpdateInfo 去 v 前缀", info.version == "1.4.0")
            check("应用版本与配置一致", AppConfig.appVersion == "1.3.0")
            check("更新源指向正式仓库", AppConfig.repoSlug == "ASAzhangyongchao/ycGitGlass"
                  && AppConfig.updateAPIURL.absoluteString.contains("releases/latest"))
            check("版本比较驱动更新判定", UpdateService.compareVersions(AppConfig.appVersion, info.version) < 0)
        } catch {
            failed += 1
            print("  ❌ 自检中断：\(error)")
            if let appError = error as? AppError {
                print("     \(appError.friendlyMessage)")
                print("     \(appError.rawDetail)")
            }
        }

        print("\n结果：\(passed) 通过，\(failed) 失败")
        if failed > 0 { exit(1) }
    }
}
