import Foundation
import Darwin

public struct CommandResult: Sendable {
    public var stdout: String
    public var stderr: String
    public var exitCode: Int32
    public var wasTerminated: Bool
}

public struct RawCommandResult: Sendable {
    public var data: Data
    public var stderr: String
    public var exitCode: Int32
    public var wasTerminated: Bool
}

/// 唯一的外部进程出口。
/// 设计要点：
/// 1. 参数以 [String] 传递、绝不拼 shell 字符串，杜绝命令注入；
/// 2. stdout/stderr 走临时文件而非 Pipe，规避大输出时的管道死锁；
/// 3. 整个同步执行放在 detached task，不阻塞主线程与 SwiftUI 渲染；
/// 4. 超时用 pid + SIGTERM，不捕获非 Sendable 的 Process 对象，满足 Swift 6 严格并发。
public struct CommandRunner: Sendable {
    public init() {}

    public func run(
        executable: String,
        arguments: [String],
        workingDirectory: URL? = nil,
        environmentOverrides: [String: String] = [:],
        timeout: TimeInterval = 20
    ) async throws -> CommandResult {
        let directory = workingDirectory?.path
        let overrides = environmentOverrides
        let tool = executable
        let args = arguments
        let limit = timeout
        return try await Task.detached(priority: .userInitiated) {
            try CommandRunner.execute(
                executable: tool,
                arguments: args,
                workingDirectory: directory,
                environmentOverrides: overrides,
                timeout: limit
            )
        }.value
    }

    /// 二进制安全通道：stdout 以原始 Data 返回（用于图片 blob 等二进制内容）。
    public func runRaw(
        executable: String,
        arguments: [String],
        workingDirectory: URL? = nil,
        environmentOverrides: [String: String] = [:],
        timeout: TimeInterval = 20
    ) async throws -> RawCommandResult {
        let directory = workingDirectory?.path
        let overrides = environmentOverrides
        let tool = executable
        let args = arguments
        let limit = timeout
        return try await Task.detached(priority: .userInitiated) {
            try CommandRunner.executeRaw(
                executable: tool,
                arguments: args,
                workingDirectory: directory,
                environmentOverrides: overrides,
                timeout: limit
            )
        }.value
    }

    private static func executeRaw(
        executable: String,
        arguments: [String],
        workingDirectory: String?,
        environmentOverrides: [String: String],
        timeout: TimeInterval
    ) throws -> RawCommandResult {
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw AppError.io("找不到可执行文件：\(executable)")
        }

        let fm = FileManager.default
        let token = UUID().uuidString
        let outURL = fm.temporaryDirectory.appendingPathComponent("gitglass-\(token)-raw-out")
        let errURL = fm.temporaryDirectory.appendingPathComponent("gitglass-\(token)-raw-err")
        defer {
            try? fm.removeItem(at: outURL)
            try? fm.removeItem(at: errURL)
        }
        guard fm.createFile(atPath: outURL.path, contents: nil),
              fm.createFile(atPath: errURL.path, contents: nil) else {
            throw AppError.io("无法创建临时输出文件")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let workingDirectory { process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory, isDirectory: true) }
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["LC_ALL"] = "en_US.UTF-8"
        for (key, value) in environmentOverrides { environment[key] = value }
        process.environment = environment

        let outHandle = try FileHandle(forWritingTo: outURL)
        let errHandle = try FileHandle(forWritingTo: errURL)
        process.standardOutput = outHandle
        process.standardError = errHandle

        do {
            try process.run()
        } catch {
            try? outHandle.close()
            try? errHandle.close()
            throw AppError.io("启动命令失败：\(error.localizedDescription)")
        }

        let pid = process.processIdentifier
        let flag = TimeoutFlag()
        let timeoutItem = DispatchWorkItem {
            guard !flag.isFinished else { return }
            kill(pid, SIGTERM)
        }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout, execute: timeoutItem)
        process.waitUntilExit()
        flag.markFinished()
        timeoutItem.cancel()
        try? outHandle.close()
        try? errHandle.close()

        let outData = (try? Data(contentsOf: outURL)) ?? Data()
        let errData = (try? Data(contentsOf: errURL)) ?? Data()
        return RawCommandResult(
            data: outData,
            stderr: String(decoding: errData, as: UTF8.self),
            exitCode: process.terminationStatus,
            wasTerminated: process.terminationReason == .uncaughtSignal
        )
    }

    private static func execute(
        executable: String,
        arguments: [String],
        workingDirectory: String?,
        environmentOverrides: [String: String],
        timeout: TimeInterval
    ) throws -> CommandResult {
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw AppError.io("找不到可执行文件：\(executable)")
        }

        let fm = FileManager.default
        let token = UUID().uuidString
        let outURL = fm.temporaryDirectory.appendingPathComponent("gitglass-\(token)-out")
        let errURL = fm.temporaryDirectory.appendingPathComponent("gitglass-\(token)-err")
        defer {
            try? fm.removeItem(at: outURL)
            try? fm.removeItem(at: errURL)
        }
        guard fm.createFile(atPath: outURL.path, contents: nil),
              fm.createFile(atPath: errURL.path, contents: nil) else {
            throw AppError.io("无法创建临时输出文件")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let workingDirectory { process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory, isDirectory: true) }

        var environment = ProcessInfo.processInfo.environment
        // 禁止任何交互式提示（凭据框、编辑器、分页器），保证无人值守时不会卡死。
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_PAGER"] = "cat"
        environment["GIT_EDITOR"] = "true"
        environment["GIT_ASKPASS"] = "/bin/echo"
        environment["LC_ALL"] = "en_US.UTF-8"
        for (key, value) in environmentOverrides { environment[key] = value }
        process.environment = environment

        let outHandle = try FileHandle(forWritingTo: outURL)
        let errHandle = try FileHandle(forWritingTo: errURL)
        process.standardOutput = outHandle
        process.standardError = errHandle

        do {
            try process.run()
        } catch {
            try? outHandle.close()
            try? errHandle.close()
            throw AppError.io("启动命令失败：\(error.localizedDescription)")
        }

        let pid = process.processIdentifier
        let flag = TimeoutFlag()
        let timeoutItem = DispatchWorkItem {
            // 进程已正常退出时绝不再 kill，避免 pid 被系统复用后误伤别的进程。
            guard !flag.isFinished else { return }
            kill(pid, SIGTERM)
        }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout, execute: timeoutItem)
        process.waitUntilExit()
        flag.markFinished()
        timeoutItem.cancel()
        try? outHandle.close()
        try? errHandle.close()

        let outData = (try? Data(contentsOf: outURL)) ?? Data()
        let errData = (try? Data(contentsOf: errURL)) ?? Data()
        return CommandResult(
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errData, as: UTF8.self),
            exitCode: process.terminationStatus,
            wasTerminated: process.terminationReason == .uncaughtSignal
        )
    }
}

/// 一次性超时保护用的线程安全标志（非轮询、非常驻）。
private final class TimeoutFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false

    func markFinished() {
        lock.lock()
        finished = true
        lock.unlock()
    }

    var isFinished: Bool {
        lock.lock()
        defer { lock.unlock() }
        return finished
    }
}
