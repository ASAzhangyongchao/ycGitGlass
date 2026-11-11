import SwiftUI
import AppKit
import GitCore

/// 多平台密钥：每个平台一张卡，生成 / 复制公钥 / 测试连接 / 归类 / 写 SSH 配置。
struct SSHKeyView: View {
    @Environment(AppState.self) private var state
    @State private var generatingPlatform: GitPlatform?
    @State private var showAddPlatform = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                header
                InfoHint(
                    text: "只读取公钥，绝不读取、展示或复制私钥内容。~/.ssh/config 只改应用自己带标记的管理块，其余手写配置原样保留。",
                    tint: GlassPalette.mint,
                    icon: "lock.shield.fill"
                )
                ForEach(Array(state.platforms.enumerated()), id: \.element.id) { index, platform in
                    platformCard(platform).staggered(index)
                }
                configCard
            }
            .padding(.vertical, 6)
            .padding(.bottom, 22)
        }
        .sheet(item: $generatingPlatform) { platform in
            GenerateKeySheet(platform: platform)
        }
        .sheet(isPresented: $showAddPlatform) {
            TwoFieldSheet(
                title: "添加自建平台",
                firstLabel: "平台名称", firstPlaceholder: "公司 GitLab",
                secondLabel: "服务器域名", secondPlaceholder: "git.example.com",
                confirmTitle: "添加",
                hint: "域名用于生成 SSH Host 配置与测试连接，不要带 https:// 前缀。"
            ) { name, host in
                state.addCustomPlatform(name: name, host: host)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("SSH 密钥").font(.system(size: 17, weight: .semibold, design: .rounded))
                Text("已发现 \(state.keys.count) 把公钥 · \(state.platforms.count) 个平台")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ActionButton(title: "添加自建平台", icon: "plus") {
                showAddPlatform = true
            }
            ActionButton(title: "刷新", icon: "arrow.clockwise") {
                Task { await state.refresh(reason: .manual) }
            }
            .disabled(state.isBusy)
        }
    }

    private func platformCard(_ platform: GitPlatform) -> some View {
        let keys = state.keys(for: platform.id)
        return GlassCard(
            title: platform.name,
            icon: platform.symbol,
            subtitle: platform.host.isEmpty ? "自定义平台，需填写域名" : platform.host,
            tint: keys.isEmpty ? nil : GlassPalette.mint.opacity(0.08)
        ) {
            VStack(alignment: .leading, spacing: 10) {
                if keys.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "key.slash")
                            .font(.system(size: 17))
                            .foregroundStyle(.tertiary)
                        Text("还没有这个平台的密钥")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Spacer()
                        ActionButton(title: "生成密钥", icon: "key.fill", prominent: true) {
                            generatingPlatform = platform
                        }
                    }
                } else {
                    ForEach(keys, id: \.id) { key in
                        keyRow(key, platform: platform)
                    }
                    HStack {
                        Spacer()
                        Button("再生成一把") { generatingPlatform = platform }
                            .buttonStyle(.plain)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .help("同名密钥已存在时会提示，不会覆盖旧密钥")
                    }
                }
            }
        }
    }

    private func keyRow(_ key: SSHKeyPair, platform: GitPlatform) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "key.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(GlassPalette.mint)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(key.name).font(.system(size: 12, weight: .semibold))
                        StatusBadge(text: key.keyType.isEmpty ? "SSH" : key.keyType, tint: GlassPalette.blue)
                        if !key.permissionsOK {
                            StatusBadge(text: "权限过宽", tint: GlassPalette.rose)
                        }
                        if !key.hasPrivateKey {
                            StatusBadge(text: "仅公钥", tint: GlassPalette.amber)
                        }
                    }
                    if !key.fingerprint.isEmpty {
                        Text(key.fingerprint)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                    Text(key.comment.isEmpty ? key.publicKeyPath : key.comment)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 6)
            }

            HStack(spacing: 7) {
                ActionButton(title: "复制公钥", icon: "doc.on.doc", prominent: true) {
                    let content = state.publicKeyContent(key)
                    guard !content.isEmpty else { return }
                    copyToPasteboard(content)
                    state.notice = "已复制 \(platform.name) 的公钥，去平台账号里粘贴即可"
                }
                ActionButton(title: "测试连接", icon: "network") {
                    Task { await state.testConnection(platform: platform, key: key) }
                }
                .disabled(!key.hasPrivateKey || platform.host.isEmpty || state.isBusy)

                if !key.permissionsOK {
                    ActionButton(title: "修复权限", icon: "lock.rotation", tint: GlassPalette.rose) {
                        Task { await state.fixKeyPermissions(key) }
                    }
                }

                Menu("归类") {
                    ForEach(state.platforms) { target in
                        Button(target.name) { state.bindKey(key, to: target.id) }
                    }
                }
                .glassAction()
                .help("自动归类不准时，手动指定平台")

                Spacer(minLength: 0)
                SmallIconButton(icon: "folder", helpText: "复制公钥文件路径") {
                    copyToPasteboard(key.publicKeyPath)
                    state.notice = "已复制公钥路径"
                }
            }
            .disabled(state.isBusy)
        }
        .padding(12)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var configCard: some View {
        GlassCard(title: "写入 SSH 配置", icon: "terminal",
                  subtitle: "让不同平台自动选用对应密钥，避免多账号串号") {
            VStack(alignment: .leading, spacing: 11) {
                InfoHint(
                    text: "会为每个「已有私钥 + 已填域名」的平台生成 Host 配置（IdentitiesOnly yes）。首次写入自动备份原文件为 config.gitglass.bak。",
                    tint: GlassPalette.violet
                )
                HStack(spacing: 9) {
                    ActionButton(title: "写入 ~/.ssh/config", icon: "square.and.arrow.down",
                                 prominent: true) {
                        Task { await state.applySSHConfig() }
                    }
                    .disabled(state.isBusy)
                    ActionButton(title: "打开 ~/.ssh 文件夹", icon: "folder") {
                        NSWorkspace.shared.open(AppConfig.sshDirectory)
                    }
                    Spacer()
                }
                Text("复制公钥到平台后，回到对应卡片点「测试连接」确认认证是否通过；失败时错误提示会给出具体修复建议。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - 生成密钥表单

private struct GenerateKeySheet: View {
    let platform: GitPlatform
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var usePassphrase = false
    @State private var passphrase = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("为 \(platform.name) 生成密钥")
                .font(.system(size: 17, weight: .semibold))
            Text("将生成 ED25519 密钥：~/.ssh/id_ed25519_\(platform.id)")
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("邮箱（仅写入公钥注释，可留空）")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                TextField("you@example.com", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12.5))
            }

            Toggle("设置密码短语（更安全，但每次使用需解锁）", isOn: $usePassphrase)
                .font(.system(size: 11.5))
                .toggleStyle(.checkbox)

            if usePassphrase {
                SecureField("密码短语", text: $passphrase)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12.5))
            }

            InfoHint(
                text: "生成后请点「复制公钥」并粘贴到 \(platform.name) 账号的 SSH Keys 页面。密码短语不会被保存或写入日志。",
                tint: GlassPalette.amber
            )

            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("生成") {
                    Task {
                        await state.generateKey(for: platform, email: email,
                                               passphrase: usePassphrase ? passphrase : "")
                    }
                    dismiss()
                }
                .prominentAction()
                .keyboardShortcut(.defaultAction)
                .disabled(usePassphrase && passphrase.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 460)
        .background(GlassBackground())
    }
}
