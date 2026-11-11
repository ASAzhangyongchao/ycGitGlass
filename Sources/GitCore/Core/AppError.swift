import Foundation

/// 类型化错误：UI 只消费 friendlyMessage / recoverySuggestion，绝不展示原始堆栈。
public enum AppError: Error, LocalizedError, Equatable, Sendable {
    case gitNotFound
    case notARepository(String)
    case commandFailed(command: String, code: Int32, message: String)
    case timeout(String)
    case invalidInput(String)
    case io(String)
    case ssh(String)

    public var errorDescription: String? { friendlyMessage }
    public var recoverySuggestion: String? { suggestion }

    public var friendlyMessage: String {
        switch self {
        case .gitNotFound:
            return "找不到 git 命令"
        case .notARepository(let path):
            return "「\(path)」不是一个 Git 仓库"
        case .commandFailed(_, _, let message):
            return Self.translate(message)
        case .timeout(let command):
            return "命令执行超时：\(command)"
        case .invalidInput(let reason):
            return reason
        case .io(let reason):
            return reason
        case .ssh(let reason):
            return reason
        }
    }

    public var suggestion: String {
        switch self {
        case .gitNotFound:
            return "安装 Xcode 命令行工具（xcode-select --install），或设置环境变量 GITGLASS_GIT 指向 git。"
        case .notARepository:
            return "在侧边栏移除它，重新添加一个包含 .git 目录的文件夹；也可以用「新建仓库」初始化。"
        case .commandFailed(_, _, let message):
            return Self.translateSuggestion(message)
        case .timeout:
            return "网络可能不通或仓库过大。检查网络后点右上角刷新重试，或先只做本地提交。"
        case .invalidInput:
            return "请检查输入内容后重试。"
        case .io:
            return "检查磁盘权限与剩余空间。"
        case .ssh:
            return "到「密钥」页检查密钥与平台配置。"
        }
    }

    /// 把 git / ssh 的原始 stderr 翻译为新手能看懂的中文。
    public static func translate(_ raw: String) -> String {
        let s = raw.lowercased()
        if s.contains("permission denied (publickey)") || s.contains("authentication failed") {
            return "SSH 认证失败：远程平台没认出你的密钥"
        }
        if s.contains("not a git repository") { return "这个文件夹不是 Git 仓库" }
        if s.contains("no upstream branch") || s.contains("has no upstream branch") {
            return "当前分支还没有关联远程分支（上游）"
        }
        if s.contains("nothing to commit") || s.contains("no changes added to commit") {
            return "没有需要提交的内容：请先勾选文件并暂存"
        }
        if s.contains("could not apply") { return "遴选 / 还原遇到冲突：这份改动与当前分支冲突了" }
        if s.contains("no local changes to save") { return "当前没有可储藏的改动" }
        if s.contains("conflict") || s.contains("unmerged") { return "存在合并冲突，需要先解决冲突再提交" }
        if s.contains("could not resolve host") || s.contains("could not read from remote repository") {
            return "连不上远程仓库：检查网络与远程源地址"
        }
        if s.contains("remote .* already exists") || s.contains("already exists") { return "同名远程源已存在" }
        if s.contains("pathspec") { return "文件已不在工作区，点刷新重新读取状态" }
        if s.contains("unprotected private key file") || s.contains("permissions 0") {
            return "私钥文件权限太开放，需要改为 600"
        }
        if s.contains("non-fast-forward") || s.contains("rejected") {
            return "推送被拒绝：远程有别人的新提交，先「拉取」再推送"
        }
        if s.contains("no such remote") { return "找不到这个远程源" }
        if s.contains("would be overwritten by checkout") || s.contains("local changes") {
            return "有未提交的改动会切丢，请先提交或暂存"
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Git 命令执行失败" : String(trimmed.prefix(240))
    }

    private static func translateSuggestion(_ raw: String) -> String {
        let s = raw.lowercased()
        if s.contains("permission denied (publickey)") || s.contains("authentication failed") {
            return "到「密钥」页确认该平台已生成密钥、公钥已复制到平台账号，并点「测试连接」。"
        }
        if s.contains("no upstream branch") { return "点「提交」页的「提交并推送」，会自动建立上游关联。" }
        if s.contains("nothing to commit") { return "回到「提交」页勾选文件，点「暂存所选」。未跟踪文件也要先暂存。" }
        if s.contains("could not apply") || s.contains("conflict") {
            return "如果是遴选 / 还原造成的，到「储藏」页点「中止当前操作」即可回到操作前；也可手动解决 <<<<<<< 冲突后暂存并提交。"
        }
        if s.contains("no local changes to save") { return "工作区是干净的，不需要储藏。" }
        if s.contains("could not resolve host") { return "检查网络，或到「远程源」页确认地址是否写错。" }
        if s.contains("non-fast-forward") || s.contains("rejected") { return "先点「拉取」，合并远程改动后再推送。" }
        if s.contains("unprotected private key") { return "在「密钥」页点「修复权限」即可。" }
        if s.contains("would be overwritten") { return "先提交当前改动，再切换分支。" }
        return "可在右上角点刷新重新读取状态；如果反复失败，复制下方原始信息排查。"
    }

    /// 给 UI 折叠区展示的原始信息（可能为空）。
    public var rawDetail: String {
        if case .commandFailed(let command, let code, let message) = self {
            return "$ \(command)\nexit=\(code)\n\(message.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
        return ""
    }
}
