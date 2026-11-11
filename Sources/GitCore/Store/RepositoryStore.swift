import Foundation

/// 轻量持久化：一个 JSON 文件即可，不引入 SwiftData / CoreData / SQLite，零常驻开销。
public struct PersistedState: Codable, Sendable, Equatable {
    public var repositories: [Repository]
    public var platforms: [GitPlatform]
    /// 公钥路径 -> 平台 ID 的人工绑定，优先于自动推断
    public var keyPlatformBindings: [String: String]
    public var onboardingSeen: Bool

    public init(repositories: [Repository] = [], platforms: [GitPlatform] = AppConfig.defaultPlatforms,
                keyPlatformBindings: [String: String] = [:], onboardingSeen: Bool = false) {
        self.repositories = repositories
        self.platforms = platforms
        self.keyPlatformBindings = keyPlatformBindings
        self.onboardingSeen = onboardingSeen
    }

    public static let initial = PersistedState()
}

public struct RepositoryStore: Sendable {
    private let fileURL: URL

    public init(fileURL: URL = AppConfig.stateFile) {
        self.fileURL = fileURL
    }

    public func load() -> PersistedState {
        guard let data = try? Data(contentsOf: fileURL) else { return .initial }
        do {
            return try JSONDecoder().decode(PersistedState.self, from: data)
        } catch {
            AppLogger.error(AppLogger.store, "state.decode_failed", detail: ["reason": error.localizedDescription])
            return .initial
        }
    }

    public func save(_ state: PersistedState) throws {
        let fm = FileManager.default
        let directory = fileURL.deletingLastPathComponent()
        if !fm.fileExists(atPath: directory.path) {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: fileURL, options: .atomic)
        AppLogger.info(AppLogger.store, "state.saved", detail: ["repos": "\(state.repositories.count)"])
    }

    /// 添加仓库前做路径归一化与去重，避免同一个仓库重复出现在侧边栏。
    public static func normalized(_ rawPath: String) -> String {
        URL(fileURLWithPath: (rawPath as NSString).expandingTildeInPath).standardizedFileURL.path
    }
}
