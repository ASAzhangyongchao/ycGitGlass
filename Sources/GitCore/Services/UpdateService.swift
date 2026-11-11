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
public struct UpdateService: Sendable {
    public init() {}

    /// 拉取最新 Release；仓库还没有任何 Release 时返回 nil（不算错误）。
    public func latest() async throws -> UpdateInfo? {
        var request = URLRequest(url: AppConfig.updateAPIURL, timeoutInterval: 12)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("GitGlass/\(AppConfig.appVersion) update-check", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppError.io("更新服务响应异常")
        }
        if http.statusCode == 404 { return nil }
        guard (200..<300).contains(http.statusCode) else {
            throw AppError.io("更新服务返回 HTTP \(http.statusCode)")
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
