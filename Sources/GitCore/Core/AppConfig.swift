import Foundation

/// 集中配置：所有外部依赖路径与平台预设在此一处定义，启动时统一校验、快速失败。
public enum AppConfig {
    /// 面向用户的产品名；工程 / bundle 标识仍保持 GitGlass 以兼容已有配置目录。
    public static let appName = "码牛 MooGit"
    public static let bundleIdentifier = "com.gitglass.app"
    public static let logSubsystem = "com.gitglass.app"
    public static let configBlockBegin = "# >>> GitGlass managed >>>"
    public static let configBlockEnd = "# <<< GitGlass managed <<<"

    /// 允许通过环境变量覆盖 git 路径（Homebrew / 多版本并存场景）。
    public static var gitExecutable: String {
        if let override = ProcessInfo.processInfo.environment["GITGLASS_GIT"], !override.isEmpty {
            return override
        }
        for candidate in ["/usr/bin/git", "/opt/homebrew/bin/git", "/usr/local/bin/git"] {
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return "/usr/bin/git"
    }

    public static var sshKeygenExecutable: String { firstExecutable(["/usr/bin/ssh-keygen", "/opt/homebrew/bin/ssh-keygen"]) }
    public static var sshExecutable: String { firstExecutable(["/usr/bin/ssh", "/opt/homebrew/bin/ssh"]) }

    public static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    public static var sshDirectory: URL { home.appendingPathComponent(".ssh") }
    public static var sshConfigURL: URL { sshDirectory.appendingPathComponent("config") }
    public static var supportDirectory: URL {
        home.appendingPathComponent("Library/Application Support/GitGlass", isDirectory: true)
    }
    public static var stateFile: URL { supportDirectory.appendingPathComponent("state.json") }

    public static let defaultPlatforms: [GitPlatform] = [
        GitPlatform(id: "github", name: "GitHub", host: "github.com", symbol: "chevron.left.forwardslash.chevron.right"),
        GitPlatform(id: "gitlab", name: "GitLab", host: "gitlab.com", symbol: "fox.fill"),
        GitPlatform(id: "gitee", name: "Gitee", host: "gitee.com", symbol: "g.circle.fill"),
        GitPlatform(id: "bitbucket", name: "Bitbucket", host: "bitbucket.org", symbol: "b.circle.fill"),
        GitPlatform(id: "coding", name: "CODING", host: "e.coding.net", symbol: "c.circle.fill"),
        GitPlatform(id: "custom", name: "其他 / 自建", host: "", symbol: "server.rack")
    ]

    /// 启动时调用；缺关键工具直接报错，避免运行时才失败。
    public static func validate() throws {
        guard FileManager.default.isExecutableFile(atPath: gitExecutable) else {
            throw AppError.gitNotFound
        }
        guard FileManager.default.isExecutableFile(atPath: sshKeygenExecutable) else {
            throw AppError.ssh("找不到 ssh-keygen，请确认已安装系统命令行工具")
        }
    }

    private static func firstExecutable(_ candidates: [String]) -> String {
        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
        return candidates[0]
    }
}
