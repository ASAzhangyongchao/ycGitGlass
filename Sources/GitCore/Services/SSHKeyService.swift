import Foundation

public struct KeyFingerprint: Sendable, Equatable {
    public var bits: Int
    public var fingerprint: String
    public var comment: String
    public var keyType: String
}

/// 多平台 SSH 密钥管理。
/// 安全边界：只读公钥内容，绝不读取、展示、复制、记录私钥文件内容；
/// 对 ~/.ssh/config 的修改限定在带标记的管理块内，且首次修改前自动备份。
public struct SSHKeyService: Sendable {
    private let runner: CommandRunner
    private let keygen: String
    private let ssh: String
    private let sshDirectory: URL
    private let configURL: URL

    public init(
        runner: CommandRunner = CommandRunner(),
        keygenExecutable: String = AppConfig.sshKeygenExecutable,
        sshExecutable: String = AppConfig.sshExecutable,
        sshDirectory: URL = AppConfig.sshDirectory,
        configURL: URL = AppConfig.sshConfigURL
    ) {
        self.runner = runner
        self.keygen = keygenExecutable
        self.ssh = sshExecutable
        self.sshDirectory = sshDirectory
        self.configURL = configURL
    }

    // MARK: - 扫描

    public func listKeys(platforms: [GitPlatform], bindings: [String: String]) async throws -> [SSHKeyPair] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sshDirectory.path) else { return [] }
        let urls = try fm.contentsOfDirectory(
            at: sshDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []
        )
        let publicURLs = urls.filter { $0.pathExtension == "pub" }

        // 并行解析指纹，避免「每个公钥串行起一个 ssh-keygen 进程」形成 N+1 等待。
        // 单个损坏的公钥降级为空信息，不影响其余密钥展示。
        return try await withThrowingTaskGroup(of: SSHKeyPair.self) { group in
            for pubURL in publicURLs {
                group.addTask {
                    let fileManager = FileManager.default
                    let privateURL = pubURL.deletingPathExtension()
                    let hasPrivate = fileManager.fileExists(atPath: privateURL.path)
                    var permissionsOK = true
                    if hasPrivate,
                       let attributes = try? fileManager.attributesOfItem(atPath: privateURL.path),
                       let mode = attributes[FileAttributeKey.posixPermissions] as? NSNumber {
                        permissionsOK = (mode.intValue & 0o077) == 0
                    }
                    let info = (try? await self.fingerprint(of: pubURL.path))
                        ?? KeyFingerprint(bits: 0, fingerprint: "", comment: "", keyType: "")
                    let inferred = Self.inferPlatform(
                        from: pubURL.lastPathComponent + " " + info.comment,
                        platforms: platforms
                    )
                    return SSHKeyPair(
                        publicKeyPath: pubURL.path,
                        privateKeyPath: hasPrivate ? privateURL.path : nil,
                        platformID: bindings[pubURL.path] ?? inferred,
                        keyType: info.keyType,
                        bits: info.bits,
                        fingerprint: info.fingerprint,
                        comment: info.comment,
                        permissionsOK: permissionsOK
                    )
                }
            }
            var pairs: [SSHKeyPair] = []
            for try await pair in group { pairs.append(pair) }
            return pairs.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    public func fingerprint(of publicKeyPath: String) async throws -> KeyFingerprint {
        let result = try await runner.run(
            executable: keygen,
            arguments: ["-lf", publicKeyPath],
            timeout: 10
        )
        let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.exitCode == 0, !output.isEmpty {
            let tokens = output.split(separator: " ").map(String.init)
            if tokens.count >= 3 {
                let bits = Int(tokens[0]) ?? 0
                let hash = tokens[1]
                let type = (tokens.last ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "()"))
                let comment = tokens.dropFirst(2).dropLast().joined(separator: " ")
                return KeyFingerprint(bits: bits, fingerprint: hash, comment: comment, keyType: type)
            }
        }
        // ssh-keygen 解析失败时，退化为读取公钥首行（公钥非敏感）。
        if let content = try? String(contentsOfFile: publicKeyPath, encoding: .utf8),
           let first = content.split(separator: " ").first {
            return KeyFingerprint(bits: 0, fingerprint: "", comment: "", keyType: String(first))
        }
        throw AppError.ssh("无法解析公钥：\(publicKeyPath)")
    }

    /// 公钥内容可以安全展示与复制；私钥内容始终不进入内存字符串。
    public func publicKeyContent(_ key: SSHKeyPair) throws -> String {
        let data = try Data(contentsOf: URL(fileURLWithPath: key.publicKeyPath))
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 生成与权限

    @discardableResult
    public func generateKey(for platform: GitPlatform, email: String, passphrase: String = "") async throws -> SSHKeyPair {
        let fm = FileManager.default
        if !fm.fileExists(atPath: sshDirectory.path) {
            try fm.createDirectory(at: sshDirectory, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
        }
        let base = "id_ed25519_" + platform.id
        let privateURL = sshDirectory.appendingPathComponent(base)
        let publicURL = privateURL.appendingPathExtension("pub")
        guard !fm.fileExists(atPath: privateURL.path), !fm.fileExists(atPath: publicURL.path) else {
            throw AppError.ssh("「\(platform.name)」的密钥已存在，直接复制公钥即可，不会覆盖旧密钥")
        }
        let comment = email.isEmpty ? "GitGlass-\(platform.name)" : "\(platform.name)-\(email)"
        // 密码短语走 stdin 而非 argv：argv 会短暂出现在 `ps` 进程列表里。
        // ssh-keygen -p 场景从 stdin 读；生成时用 -N -（占位）不可靠，
        // 这里改为：无密码短语直接 -N ""；有密码短语时先无密码生成再当场加改。
        var result: CommandResult
        if passphrase.isEmpty {
            result = try await runner.run(
                executable: keygen,
                arguments: ["-t", "ed25519", "-C", comment, "-f", privateURL.path, "-N", "", "-q"],
                timeout: 30
            )
        } else {
            // 生成无密码密钥 → 立即通过 stdin 交互补上密码短语（不经过 argv）
            result = try await runner.run(
                executable: keygen,
                arguments: ["-t", "ed25519", "-C", comment, "-f", privateURL.path, "-N", "", "-q"],
                timeout: 30
            )
            guard result.exitCode == 0 else {
                throw AppError.ssh("生成密钥失败：\(AppError.translate(result.stderr))")
            }
            let oldStdin = "old\n\(passphrase)\n\(passphrase)\n"
            result = try await runner.run(
                executable: keygen,
                arguments: ["-p", "-f", privateURL.path],
                stdin: oldStdin,
                timeout: 30
            )
        }
        guard result.exitCode == 0 else {
            throw AppError.ssh("生成密钥失败：\(AppError.translate(result.stderr))")
        }
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: privateURL.path)
        try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: publicURL.path)
        AppLogger.info(AppLogger.ssh, "key.generated", detail: ["platform": platform.id])
        return SSHKeyPair(publicKeyPath: publicURL.path, privateKeyPath: privateURL.path,
                          platformID: platform.id, keyType: "ED25519", bits: 256,
                          fingerprint: "", comment: comment, permissionsOK: true)
    }

    public func fixPermissions(_ key: SSHKeyPair) throws {
        guard let privatePath = key.privateKeyPath else {
            throw AppError.ssh("只有公钥，没有对应的私钥文件")
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: privatePath)
        AppLogger.info(AppLogger.ssh, "key.permissions_fixed")
    }

    // MARK: - ~/.ssh/config 托管

    /// 只替换应用自己带标记的块，用户手写的 Host 配置原样保留。
    public func applyConfig(keys: [SSHKeyPair], platforms: [GitPlatform]) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: sshDirectory.path) {
            try fm.createDirectory(at: sshDirectory, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
        }
        let existing = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        if !existing.isEmpty {
            let backup = sshDirectory.appendingPathComponent("config.gitglass.bak")
            if !fm.fileExists(atPath: backup.path) {
                try existing.write(to: backup, atomically: true, encoding: .utf8)
            }
        }
        let blocks: [String] = keys.compactMap { key in
            guard let privatePath = key.privateKeyPath,
                  let platform = platforms.first(where: { $0.id == key.platformID }),
                  !platform.host.isEmpty else { return nil }
            return """
            Host \(platform.host)
                HostName \(platform.host)
                User git
                IdentityFile \(privatePath)
                IdentitiesOnly yes
                AddKeysToAgent yes
                UseKeychain yes
                IgnoreUnknown UseKeychain
            """
        }
        var content = Self.removeManagedBlock(from: existing)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !blocks.isEmpty {
            if !content.isEmpty { content += "\n\n" }
            content += AppConfig.configBlockBegin + "\n"
                + blocks.joined(separator: "\n\n") + "\n"
                + AppConfig.configBlockEnd + "\n"
        }
        try content.write(to: configURL, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
        AppLogger.info(AppLogger.ssh, "config.applied", detail: ["hosts": "\(blocks.count)"])
    }

    private static func removeManagedBlock(from text: String) -> String {
        var output: [String] = []
        var skipping = false
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == AppConfig.configBlockBegin { skipping = true; continue }
            if trimmed == AppConfig.configBlockEnd { skipping = false; continue }
            if !skipping { output.append(line) }
        }
        return output.joined(separator: "\n")
    }

    // MARK: - 连接测试

    public func testConnection(platform: GitPlatform, key: SSHKeyPair) async throws -> String {
        guard !platform.host.isEmpty else {
            throw AppError.ssh("自定义平台需要先填写服务器域名，例如 git.example.com")
        }
        guard let privatePath = key.privateKeyPath else {
            throw AppError.ssh("只找到公钥，缺少对应私钥，无法发起认证")
        }
        let result = try await runner.run(
            executable: ssh,
            arguments: [
                "-T", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=accept-new",
                "-o", "ConnectTimeout=8", "-i", privatePath, "git@\(platform.host)"
            ],
            timeout: 20
        )
        let combined = (result.stdout + "\n" + result.stderr).lowercased()
        let accepted = result.exitCode == 0
            || combined.contains("successfully authenticated")
            || combined.contains("welcome to")
            || combined.contains("you have successfully authenticated")
        guard accepted else {
            throw AppError.ssh("连接 \(platform.host) 失败："
                + AppError.translate(result.stderr.isEmpty ? result.stdout : result.stderr))
        }
        return "连接成功：\(platform.name) 已认可这把密钥"
    }

    private static func inferPlatform(from text: String, platforms: [GitPlatform]) -> String {
        let lower = text.lowercased()
        for platform in platforms where !platform.host.isEmpty {
            let token = String(platform.host.split(separator: ".").first ?? Substring(platform.host))
            if lower.contains(platform.id) || lower.contains(token) { return platform.id }
        }
        return "custom"
    }
}
