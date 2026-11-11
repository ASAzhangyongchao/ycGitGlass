import Foundation

/// 版本发布信息（来自 GitHub Releases）。
public struct UpdateInfo: Codable, Sendable, Equatable {
    public var tag: String
    public var name: String
    public var htmlURL: String
    public var publishedAt: String

    public init(tag: String, name: String = "", htmlURL: String = "", publishedAt: String = "") {
        self.tag = tag
        self.name = name
        self.htmlURL = htmlURL
        self.publishedAt = publishedAt
    }

    /// "v1.3.0" -> "1.3.0"
    public var version: String { tag.hasPrefix("v") ? String(tag.dropFirst()) : tag }
}

/// 更新检查状态。
public enum UpdateState: Equatable, Sendable {
    case idle
    case checking
    case upToDate
    case available(UpdateInfo)
    case noReleasesYet
    case failed(String)
}

/// GitHub Releases 更新检查。
/// 与应用「零后台轮询」约定一致：只在启动满 24 小时或用户手动点击时调用一次，绝不定时轮询。
///
/// 网络策略：优先用系统代理（很多用户开着 Clash/Surge 等），
/// 代理下超时则降级为"忽略代理直连"再试一次——两个世界都能通。
public struct UpdateService: Sendable {
    public init() {}

    /// 会话：遵循系统代理（默认行为）。
    private static let proxiedSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 15
        return URLSession(configuration: config)
    }()

    /// 会话：忽略系统代理直连（代理异常时的兜底）。
    private static let directSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 15
        config.connectionProxyDictionary = [:]
        return URLSession(configuration: config)
    }()

    public enum UpdateError: LocalizedError {
        case network(String)
        case http(Int)

        public var errorDescription: String? {
            switch self {
            case .network(let detail):
                return "网络不可用（\(detail)）。若你开着代理/VPN，请确认其放行 api.github.com，或暂时关闭代理后重试。"
            case .http(let code):
                return "GitHub 返回 HTTP \(code)，请稍后再试。"
            }
        }
    }

    /// 拉取最新 Release；仓库还没有任何 Release 时返回 nil（不算错误）。
    public func latest() async throws -> UpdateInfo? {
        do {
            return try await fetch(session: Self.proxiedSession)
        } catch let error as UpdateError {
            // 代理路径失败 → 直连兜底（代理软件偶尔拦 api.github.com）
            if case .network = error {
                return try await fetch(session: Self.directSession)
            }
            throw error
        } catch {
            throw error
        }
    }

    private func fetch(session: URLSession) async throws -> UpdateInfo? {
        var request = URLRequest(url: AppConfig.updateAPIURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("MooGit/\(AppConfig.appVersion) update-check", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw UpdateError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw UpdateError.network("响应异常")
        }
        if http.statusCode == 404 { return nil }
        guard (200..<300).contains(http.statusCode) else {
            throw UpdateError.http(http.statusCode)
        }

        struct Payload: Codable {
            let tag_name: String?
            let name: String?
            let html_url: String?
            let published_at: String?
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard let tag = payload.tag_name, !tag.isEmpty else { return nil }
        return UpdateInfo(
            tag: tag,
            name: payload.name ?? tag,
            htmlURL: payload.html_url ?? AppConfig.releasesURL.absoluteString,
            publishedAt: payload.published_at ?? ""
        )
    }

    /// 语义化版本比较：a<b 返回 -1，a>b 返回 1，相等返回 0。
    /// 容忍 "v" 前缀、位数不等的版本号（1.2 vs 1.2.0）、非数字段（按 0 处理）；
    /// 预发布后缀（如 2.0.0-beta）视为低于同号正式版。
    public static func compareVersions(_ a: String, _ b: String) -> Int {
        func parse(_ raw: String) -> ([Int], Bool) {
            var text = raw.trimmingCharacters(in: .whitespaces)
            if text.hasPrefix("v") || text.hasPrefix("V") { text.removeFirst() }
            var isPreRelease = false
            if let dash = text.firstIndex(of: "-") {
                text = String(text[..<dash])
                isPreRelease = true
            }
            let numbers = text.split(separator: ".").map { Int($0) ?? 0 }
            return (numbers, isPreRelease)
        }
        let (leftNumbers, leftPre) = parse(a)
        let (rightNumbers, rightPre) = parse(b)
        let count = max(leftNumbers.count, rightNumbers.count)
        for index in 0..<count {
            let x = index < leftNumbers.count ? leftNumbers[index] : 0
            let y = index < rightNumbers.count ? rightNumbers[index] : 0
            if x != y { return x < y ? -1 : 1 }
        }
        // 数字段全部相同：正式版 > 预发布版
        if leftPre != rightPre { return leftPre ? -1 : 1 }
        return 0
    }
}
