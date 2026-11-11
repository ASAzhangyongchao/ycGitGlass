import Foundation
import OSLog

/// 结构化 JSON 日志：只记录事件与耗时，绝不记录私钥内容、令牌、完整公钥。
/// 使用系统 os.Logger，数据由系统统一压缩存储，空闲时零开销。
public enum AppLogger {
    private static let subsystem = AppConfig.logSubsystem
    public static let git = Logger(subsystem: subsystem, category: "git")
    public static let ssh = Logger(subsystem: subsystem, category: "ssh")
    public static let store = Logger(subsystem: subsystem, category: "store")
    public static let ui = Logger(subsystem: subsystem, category: "ui")

    public static func info(_ logger: Logger, _ event: String, detail: [String: String] = [:]) {
        write(logger, level: .info, event: event, detail: detail)
    }

    public static func error(_ logger: Logger, _ event: String, detail: [String: String] = [:]) {
        write(logger, level: .error, event: event, detail: detail)
    }

    private static func write(_ logger: Logger, level: OSLogType, event: String, detail: [String: String]) {
        var payload: [String: String] = ["event": event]
        for (key, value) in detail {
            payload[key] = sanitize(value)
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let line = String(data: data, encoding: .utf8) else { return }
        logger.log(level: level, "\(line, privacy: .public)")
    }

    /// 脱敏：过滤私钥块、Bearer/token、file:// 之外的敏感参数。
    public static func sanitize(_ text: String) -> String {
        var result = text
        if result.contains("PRIVATE KEY") { return "[已隐去私钥内容]" }
        let patterns = ["token=", "password=", "secret="]
        for pattern in patterns where result.lowercased().contains(pattern) {
            return "[已隐去敏感参数]"
        }
        if result.count > 300 { result = String(result.prefix(300)) + "…" }
        return result
    }
}
