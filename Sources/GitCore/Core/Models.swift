import Foundation

// MARK: - 仓库

public struct Repository: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var path: String
    public var addedAt: Date

    public init(id: UUID = UUID(), name: String, path: String, addedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.path = path
        self.addedAt = addedAt
    }
}

public struct Branch: Identifiable, Codable, Hashable, Sendable {
    public var name: String
    public var isCurrent: Bool
    public var isRemote: Bool
    public var upstream: String

    public var id: String { (isRemote ? "r/" : "l/") + name }

    public init(name: String, isCurrent: Bool = false, isRemote: Bool = false, upstream: String = "") {
        self.name = name
        self.isCurrent = isCurrent
        self.isRemote = isRemote
        self.upstream = upstream
    }

    /// 远程分支保留 `origin/main` 前缀，用户更容易看出来自哪个远程源。
    public var displayName: String { name }
}

// MARK: - 工作区变更

public struct FileChange: Identifiable, Codable, Hashable, Sendable {
    public var path: String
    public var oldPath: String?
    /// porcelain v1 的 X（索引区）状态码，空格表示无变化
    public var indexStatus: String
    /// porcelain v1 的 Y（工作区）状态码
    public var worktreeStatus: String

    public init(path: String, oldPath: String? = nil, indexStatus: String, worktreeStatus: String) {
        self.path = path
        self.oldPath = oldPath
        self.indexStatus = indexStatus
        self.worktreeStatus = worktreeStatus
    }

    public var id: String { path }
    public var isStaged: Bool { indexStatus != " " && indexStatus != "?" && !indexStatus.isEmpty }
    public var isUntracked: Bool { indexStatus == "?" && worktreeStatus == "?" }
    public var isConflict: Bool { indexStatus == "U" || worktreeStatus == "U" || indexStatus == "A" && worktreeStatus == "A" }
    public var isRename: Bool { indexStatus == "R" || worktreeStatus == "R" }

    /// 用于提交列表左侧的状态徽标
    public var badge: String {
        if isConflict { return "冲突" }
        if isUntracked { return "新增" }
        if isRename { return "重命名" }
        if indexStatus == "A" { return "已加" }
        if indexStatus == "D" || worktreeStatus == "D" { return "删除" }
        if indexStatus == "M" || worktreeStatus == "M" { return "修改" }
        return "变更"
    }

    public var fileName: String { (path as NSString).lastPathComponent }
    public var directory: String { (path as NSString).deletingLastPathComponent }
}

public struct WorktreeStatus: Codable, Hashable, Sendable {
    public var branch: String
    public var upstream: String
    public var ahead: Int
    public var behind: Int
    public var files: [FileChange]

    public init(branch: String = "", upstream: String = "", ahead: Int = 0, behind: Int = 0, files: [FileChange] = []) {
        self.branch = branch
        self.upstream = upstream
        self.ahead = ahead
        self.behind = behind
        self.files = files
    }

    public var isClean: Bool { files.isEmpty }
    public var stagedCount: Int { files.filter(\.isStaged).count }
    public var unstagedCount: Int { files.filter { !$0.isStaged }.count }
    public var untrackedCount: Int { files.filter(\.isUntracked).count }
    public static let empty = WorktreeStatus()
}

// MARK: - 历史

public struct Commit: Identifiable, Codable, Hashable, Sendable {
    public var hash: String
    public var shortHash: String
    public var author: String
    public var email: String
    /// ISO8601 字符串，避免 DateFormatter 在列表渲染时反复创建
    public var date: String
    public var subject: String
    public var body: String
    public var refs: String
    /// `git log --graph` 生成的 ASCII 轨道，等宽字体渲染
    public var graph: String

    public init(hash: String, shortHash: String, author: String, email: String, date: String,
                subject: String, body: String, refs: String, graph: String) {
        self.hash = hash
        self.shortHash = shortHash
        self.author = author
        self.email = email
        self.date = date
        self.subject = subject
        self.body = body
        self.refs = refs
        self.graph = graph
    }

    public var id: String { hash }
    public var searchableText: String { "\(hash) \(shortHash) \(author) \(email) \(subject) \(body) \(refs)" }
    public var displayDate: String {
        // 2026-11-11T09:30:00+08:00 -> 11-11 09:30
        guard date.count >= 16 else { return date }
        let start = date.index(date.startIndex, offsetBy: 5)
        let end = date.index(date.startIndex, offsetBy: 16)
        return String(date[start..<end]).replacingOccurrences(of: "T", with: " ")
    }
}

// MARK: - 远程源

public struct Remote: Identifiable, Codable, Hashable, Sendable {
    public var name: String
    public var fetchURL: String
    public var pushURL: String

    public var id: String { name }
    public var displayHost: String {
        guard let at = fetchURL.lastIndex(of: "@") else { return fetchURL }
        let rest = fetchURL[fetchURL.index(after: at)...]
        return String(rest.split(separator: ":").first ?? Substring(rest))
    }

    public init(name: String, fetchURL: String, pushURL: String = "") {
        self.name = name
        self.fetchURL = fetchURL
        self.pushURL = pushURL
    }
}

// MARK: - 平台与密钥

public struct GitPlatform: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var host: String
    public var symbol: String
    public var isCustom: Bool

    public init(id: String, name: String, host: String, symbol: String, isCustom: Bool = false) {
        self.id = id
        self.name = name
        self.host = host
        self.symbol = symbol
        self.isCustom = isCustom
    }
}

public struct SSHKeyPair: Identifiable, Codable, Hashable, Sendable {
    public var publicKeyPath: String
    public var privateKeyPath: String?
    public var platformID: String
    public var keyType: String
    public var bits: Int
    public var fingerprint: String
    public var comment: String
    public var permissionsOK: Bool

    public var id: String { publicKeyPath }
    public var name: String { (publicKeyPath as NSString).lastPathComponent }
    public var hasPrivateKey: Bool { privateKeyPath != nil }

    public init(publicKeyPath: String, privateKeyPath: String? = nil, platformID: String = "custom",
                keyType: String = "", bits: Int = 0, fingerprint: String = "", comment: String = "",
                permissionsOK: Bool = true) {
        self.publicKeyPath = publicKeyPath
        self.privateKeyPath = privateKeyPath
        self.platformID = platformID
        self.keyType = keyType
        self.bits = bits
        self.fingerprint = fingerprint
        self.comment = comment
        self.permissionsOK = permissionsOK
    }
}

// MARK: - 提交详情 / 储藏 / 标签

public struct ChangedFile: Identifiable, Codable, Hashable, Sendable {
    /// A 新增 / M 修改 / D 删除 / R 重命名 / C 复制
    public var status: String
    public var path: String
    public var oldPath: String?

    public var id: String { status + ":" + path }
    public var displayStatus: String {
        switch status {
        case "A": return "新增"
        case "M": return "修改"
        case "D": return "删除"
        case "R": return "重命名"
        case "C": return "复制"
        default: return status
        }
    }
    public var fileName: String { (path as NSString).lastPathComponent }
    public var directory: String { (path as NSString).deletingLastPathComponent }

    public init(status: String, path: String, oldPath: String? = nil) {
        self.status = status
        self.path = path
        self.oldPath = oldPath
    }
}

public struct CommitDetail: Codable, Hashable, Sendable {
    public var hash: String
    public var authorName: String
    public var authorEmail: String
    public var authorDate: String
    public var committerName: String
    public var committerEmail: String
    public var committerDate: String
    public var parents: [String]
    public var subject: String
    public var body: String
    public var refs: String
    public var changedFiles: [ChangedFile]
    public var insertions: Int
    public var deletions: Int
    public var fileCount: Int

    public init(hash: String = "", authorName: String = "", authorEmail: String = "",
                authorDate: String = "", committerName: String = "", committerEmail: String = "",
                committerDate: String = "", parents: [String] = [], subject: String = "",
                body: String = "", refs: String = "", changedFiles: [ChangedFile] = [],
                insertions: Int = 0, deletions: Int = 0, fileCount: Int = 0) {
        self.hash = hash
        self.authorName = authorName
        self.authorEmail = authorEmail
        self.authorDate = authorDate
        self.committerName = committerName
        self.committerEmail = committerEmail
        self.committerDate = committerDate
        self.parents = parents
        self.subject = subject
        self.body = body
        self.refs = refs
        self.changedFiles = changedFiles
        self.insertions = insertions
        self.deletions = deletions
        self.fileCount = fileCount
    }

    public var isMerge: Bool { parents.count > 1 }
    public var shortHash: String { String(hash.prefix(8)) }
}

public struct StashEntry: Identifiable, Codable, Hashable, Sendable {
    public var index: Int
    public var reflogID: String
    public var message: String
    public var branch: String
    public var relativeDate: String

    public var id: String { reflogID }
    public var displayTitle: String { message.isEmpty ? "（无说明）" : message }

    public init(index: Int, reflogID: String, message: String = "", branch: String = "",
                relativeDate: String = "") {
        self.index = index
        self.reflogID = reflogID
        self.message = message
        self.branch = branch
        self.relativeDate = relativeDate
    }
}

public struct GitTag: Identifiable, Codable, Hashable, Sendable {
    public var name: String
    public var target: String
    public var isAnnotated: Bool
    public var message: String

    public var id: String { name }

    public init(name: String, target: String = "", isAnnotated: Bool = false, message: String = "") {
        self.name = name
        self.target = target
        self.isAnnotated = isAnnotated
        self.message = message
    }
}

// MARK: - UI 状态枚举（纯数据，不依赖 SwiftUI）

public enum AppTab: String, Codable, CaseIterable, Sendable {
    case dashboard = "工作台"
    case commit = "提交"
    case history = "历史"
    case stashes = "储藏"
    case remotes = "远程源"
    case keys = "密钥"

    public var symbol: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .commit: return "arrow.up.doc"
        case .history: return "clock.arrow.circlepath"
        case .stashes: return "archivebox"
        case .remotes: return "network"
        case .keys: return "key.fill"
        }
    }
}

/// 唯一允许的刷新触发来源。刻意不包含 timer / 文件监听 / 应用前后台切换。
public enum RefreshReason: String, Sendable {
    case appLaunch = "启动"
    case manual = "手动刷新"
    case repositorySwitch = "切换仓库"
    case branchSwitch = "切换分支"
    case afterMutation = "操作完成"
    case deepSearch = "深度搜索"
}

/// 历史页排序方式（纯内存排序，不触发 git）。
public enum HistorySort: String, CaseIterable, Sendable, Identifiable {
    case newestFirst = "时间 新→旧"
    case oldestFirst = "时间 旧→新"
    case authorAZ = "作者 A→Z"
    case authorZA = "作者 Z→A"

    public var id: String { rawValue }

    public var symbol: String {
        switch self {
        case .newestFirst: return "arrow.down"
        case .oldestFirst: return "arrow.up"
        case .authorAZ: return "textformat.abc"
        case .authorZA: return "textformat.abc.dottedunderline"
        }
    }
}
