import Foundation

/// unified diff 里的一个 hunk（`@@ -12,3 +14,5 @@` 开头的块）。
///
/// 用途：按块暂存 / 按块取消暂存（SourceTree、GitHub Desktop 的 partial staging）。
/// 只做纯解析，不碰 git——真正的 apply 在 GitService 里。
public struct DiffHunk: Identifiable, Hashable, Sendable {
    /// header 在同一个文件里可能重复（相邻同起点块），拼序号保证唯一。
    public var id: String
    /// 原始 `@@ … @@` 行，apply 时必须原样写回。
    public var header: String
    /// 块内每一行，保留 `+` / `-` / 空格前缀和 `\ No newline at end of file`
    public var lines: [String]
    public var oldStart: Int
    public var newStart: Int
    public var added: Int
    public var removed: Int

    public init(id: String, header: String, lines: [String],
                oldStart: Int, newStart: Int, added: Int, removed: Int) {
        self.id = id
        self.header = header
        self.lines = lines
        self.oldStart = oldStart
        self.newStart = newStart
        self.added = added
        self.removed = removed
    }
}

/// unified diff 解析 / 回写为 patch。
public enum UnifiedDiff {
    /// 切分结果：文件头（`diff --git`、`index`、`---`、`+++` 等）+ 各 hunk。
    public struct Parsed: Sendable {
        public var fileHeader: [String]
        public var hunks: [DiffHunk]
    }

    public static func parse(_ text: String) -> Parsed {
        var header: [String] = []
        var hunks: [DiffHunk] = []
        var currentHeader = ""
        var currentLines: [String] = []
        var oldStart = 0
        var newStart = 0
        var added = 0
        var removed = 0

        func flush() {
            guard !currentHeader.isEmpty else { return }
            // 去掉块尾空行：git apply 对多出来的空行会报 "corrupt patch"
            while let last = currentLines.last, last.isEmpty {
                currentLines.removeLast()
            }
            hunks.append(DiffHunk(id: "\(currentHeader)#\(hunks.count)",
                                  header: currentHeader,
                                  lines: currentLines,
                                  oldStart: oldStart,
                                  newStart: newStart,
                                  added: added,
                                  removed: removed))
            currentLines = []
            added = 0
            removed = 0
        }

        for line in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.hasPrefix("@@") {
                flush()
                currentHeader = line
                let ranges = parseRanges(line)
                oldStart = ranges.0
                newStart = ranges.1
                continue
            }
            if currentHeader.isEmpty {
                if !line.isEmpty { header.append(line) }
            } else {
                currentLines.append(line)
                if line.hasPrefix("+") { added += 1 }
                if line.hasPrefix("-") { removed += 1 }
            }
        }
        flush()
        return Parsed(fileHeader: header, hunks: hunks)
    }

    /// 用原文件头 + 单个 hunk 拼出可 `git apply` 的补丁。
    public static func patch(fileHeader: [String], hunk: DiffHunk) -> String {
        var out = ""
        if !fileHeader.isEmpty {
            out += fileHeader.joined(separator: "\n") + "\n"
        }
        out += hunk.header + "\n"
        out += hunk.lines.joined(separator: "\n") + "\n"
        return out
    }

    /// `@@ -12,3 +14,5 @@ xxx` → (12, 14)
    private static func parseRanges(_ header: String) -> (Int, Int) {
        var old = 0
        var new = 0
        for part in header.split(separator: " ") {
            if part.hasPrefix("-") {
                let value = part.dropFirst().split(separator: ",").first ?? ""
                old = Int(value) ?? 0
            } else if part.hasPrefix("+") {
                let value = part.dropFirst().split(separator: ",").first ?? ""
                new = Int(value) ?? 0
            }
        }
        return (old, new)
    }
}
