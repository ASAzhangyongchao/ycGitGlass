import Foundation

/// 图片差异预览：提取指定提交里图片文件的旧版/新版内容（原始 Data，UI 层负责解码）。
/// 二进制图片不走文本 diff，专门用 blob 提取。
public struct ImageDiffService: Sendable {
    private let runner: CommandRunner
    private let git: String

    public init(gitExecutable: String = AppConfig.gitExecutable, runner: CommandRunner = CommandRunner()) {
        self.git = gitExecutable
        self.runner = runner
    }

    public struct Pair: Sendable {
        public var beforeData: Data?
        public var afterData: Data?
        public var beforeBytes: Int
        public var afterBytes: Int
        public var isBinaryChange: Bool { beforeData != nil || afterData != nil }

        public init(beforeData: Data?, afterData: Data?, beforeBytes: Int, afterBytes: Int) {
            self.beforeData = beforeData
            self.afterData = afterData
            self.beforeBytes = beforeBytes
            self.afterBytes = afterBytes
        }
    }

    public static let supportedExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "tiff", "tif", "bmp", "heic", "svg", "ico", "pdf"
    ]

    public static func isImagePath(_ path: String) -> Bool {
        supportedExtensions.contains((path as NSString).pathExtension.lowercased())
    }

    /// 提取某提交中 file 的新版内容，以及它的父提交里的旧版内容。
    /// 旧版不存在（新增文件）或新版不存在（删除文件）时对应侧为 nil。
    public func images(inCommit hash: String, file: String, at repoPath: String) async throws -> Pair {
        let newBlob = try await blob(hash: hash, path: file, at: repoPath)
        let oldBlob = try await blob(hash: "\(hash)^", path: file, at: repoPath)
        return Pair(
            beforeData: oldBlob,
            afterData: newBlob,
            beforeBytes: oldBlob?.count ?? 0,
            afterBytes: newBlob?.count ?? 0
        )
    }

    /// 工作区未暂存图片：新版直接读磁盘，旧版读 HEAD。
    public func worktreeImages(file: String, at repoPath: String) async throws -> Pair {
        let diskURL = URL(fileURLWithPath: repoPath).appendingPathComponent(file)
        var afterData: Data?
        if let data = try? Data(contentsOf: diskURL) {
            afterData = data
        }
        let headBlob = try await blob(hash: "HEAD", path: file, at: repoPath)
        return Pair(
            beforeData: headBlob,
            afterData: afterData,
            beforeBytes: headBlob?.count ?? 0,
            afterBytes: afterData?.count ?? 0
        )
    }

    private func blob(hash: String, path file: String, at repoPath: String) async -> Data? {
        guard !file.isEmpty else { return nil }
        // 存在性探测：cat-file -e 不存在时退出码非 0，视为该侧缺失（新增/删除），不算错误
        guard let exists = try? await runner.run(
            executable: git,
            arguments: ["-C", repoPath, "cat-file", "-e", "\(hash):\(file)"],
            timeout: 10
        ), exists.exitCode == 0 else { return nil }
        // 二进制安全通道取原始字节
        guard let raw = try? await runner.runRaw(
            executable: git,
            arguments: ["-C", repoPath, "cat-file", "-p", "\(hash):\(file)"],
            timeout: 15
        ), raw.exitCode == 0 else { return nil }
        return raw.data
    }
}
