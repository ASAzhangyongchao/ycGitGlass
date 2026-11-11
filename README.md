# GitGlass · 轻 Git

一个 macOS 26 原生 Git 桌面客户端：提交简洁、历史清晰、远程源与多平台 SSH 密钥集中维护。
用系统 SwiftUI 的 Liquid Glass 构建，**零第三方依赖、零 WebView、零后台轮询**。

---

## 1. 分发包里有什么

| 内容 | 路径 | 说明 |
|---|---|---|
| 可直接运行的应用 | `GitGlass.app` | arm64 原生、ad-hoc 签名，约 3.5 MB |
| 完整源码 | `Sources/` | Swift 6.2，20+ 个文件，按功能分层 |
| 工程清单 | `Package.swift` | SwiftPM，可在任意 Mac 上重建 |
| 应用配置 | `Resources/Info.plist` | 版本 1.1.0，最低 macOS 26.0 |
| 脚本 | `scripts/` | `build-app.sh` 打包应用、`package.sh` 生成分发 zip |
| 文档 | `README.md`、`docs/` | 本文件 + 完整操作手册（Markdown / HTML） |

## 2. 系统要求

| 项目 | 要求 |
|---|---|
| 操作系统 | **macOS 26.0 及以上**（界面使用系统 Liquid Glass API） |
| 现成 `.app` 架构 | **arm64 / Apple Silicon**；Intel Mac 请用源码重建（见 3.B） |
| 外部命令 | 系统自带 `git`（建议 2.30+）、`ssh-keygen`、`ssh`、`open` |
| 编译环境 | 仅从源码构建时需要：Xcode 26 或 Command Line Tools（`xcode-select --install`） |
| 权限 | 需要读写本地仓库目录与 `~/.ssh`；应用未启用沙箱，属于本机开发工具 |

> 通用二进制（arm64 + x86_64）在只装 Command Line Tools 的机器上无法构建（缺 XCBuild.framework），所以提供「现成 arm64 应用 + 全源码任意架构重建」两条路径。

## 3. 安装

### A. Apple Silicon Mac（最快）

```bash
# 1. 解压后把应用拖进「应用程序」，也可以停留在任意目录
cp -R GitGlass.app /Applications/

# 2. 如果系统提示「无法验证开发者」，去掉隔离属性（ad-hoc 签名的正常现象）
xattr -cr /Applications/GitGlass.app

# 3. 启动
open /Applications/GitGlass.app
```

也可以在 Finder 里右键应用 → 「打开」→ 确认一次。

### B. 在另一台 Mac 上从源码重建（Intel / 不同 macOS / 想自己编译）

```bash
# 1. 把整个解压目录拷过去（必须包含 Sources/ 和 Package.swift）
cd GitGlass-1.1.0-macOS26

# 2. 准备编译工具（若已有 Xcode 26 可跳过）
xcode-select --install

# 3. 一键构建出当前机器架构的 .app
chmod +x scripts/build-app.sh
./scripts/build-app.sh

# 4. 启动
open dist/GitGlass.app
```

脚本里的 `--disable-sandbox` 是为受管环境准备的（SwiftPM 默认会再套一层 sandbox-exec）；普通 Xcode 环境保留也无害。构建产物在 `dist/GitGlass.app`，日志会打印目标架构。

### C. 验证安装

```bash
swift run --disable-sandbox GitGlassSelfTest   # 服务层深度自检，应输出 129 通过 / 0 失败
```

## 4. 三步上手

1. 左侧点「添加仓库…」选一个本地 Git 文件夹；或「扫描文件夹批量导入」一次导入多个项目。
2. 「提交」页勾选文件 → 暂存 → 写一句说明 → 提交（或「提交并推送」）。
3. 「密钥」页为 GitHub / GitLab / Gitee 等生成密钥，复制公钥粘贴到平台账号，点「测试连接」确认。

## 5. 换机时的数据迁移

| 数据 | 位置 | 说明 |
|---|---|---|
| 仓库列表、自定义平台、密钥归类 | `~/Library/Application Support/GitGlass/state.json` | 想保留列表就拷到新机器同路径 |
| SSH 私钥 / 公钥 | `~/.ssh/` | **应用不会打包也不会上传**；按需自行安全迁移，或在新机器重新生成 |
| SSH Host 配置 | `~/.ssh/config` | 应用只改 `# >>> GitGlass managed >>>` 标记块；首次写入备份为 `config.gitglass.bak` |
| 仓库本身 | 各自目录 | 用 git 自己管理，与应用无关 |

卸载：删除 `GitGlass.app` 即可；想连配置一起清掉，再删除上面那个 `state.json`。

## 6. 命令速查

| 命令 | 用途 |
|---|---|
| `./scripts/build-app.sh` | Release 编译并组装 `.app` |
| `./scripts/package.sh` | 生成含源码 + 应用 + 文档的分发 zip |
| `swift scripts/make-icon.swift` | 重新生成本地玻璃风格应用图标（`Resources/AppIcon.icns`） |
| `./scripts/release.sh v1.2.0` | 校验版本与自检后打 tag，触发 CI 自动发布 Release |
| `swift build --disable-sandbox` | Debug 编译（0 error / 0 warning） |
| `swift run --disable-sandbox GitGlassSelfTest` | 真实临时仓库上的 129 项自检 |
| `open dist/GitGlass.app` | 启动应用 |

## 7. 源码结构

```
Sources/
├── GitCore/                  领域层，不依赖 SwiftUI
│   ├── Core/                 配置、类型化错误、脱敏日志、模型、命令执行器
│   ├── Services/             GitService、SSHKeyService
│   └── Store/                AppState（刷新编排）、RepositoryStore（JSON 持久化）
├── GitGlass/                 表现层
│   ├── Design/               Liquid Glass 设计系统、彩色提交图 Canvas、文件树
│   └── Features/             工作台 / 提交 / 历史 / 储藏 / 冲突处理 / 远程源 / 密钥
└── GitGlassSelfTest/         服务层深度自检

.github/                      CI、自动 Release、Issue / PR 模板
docs/                         Markdown + HTML 操作手册（含 ASCII 文件名副本）
scripts/                      打包、图标、发布脚本
CHANGELOG.md / CONTRIBUTING.md / LICENSE
```

数据流向：视图 → `AppState`（@Observable）→ `GitService` / `SSHKeyService` → `CommandRunner`（Process）。

## 8. 设计约束

- **刷新只由事件触发**：启动、手动刷新按钮、切仓库、切分支、写操作完成、深度搜索。没有 Timer、文件监听、前后台触发，空闲时零后台任务。
- **动画全部事件驱动**：弹簧过渡只在状态变化时插值，结束即停；支持系统「减弱动态效果」与「降低透明度」。
- **安全**：命令参数按数组传递并用 `--` 分隔路径，不拼 shell；私钥内容从不读取/展示/记录；日志脱敏。
- **可读性优先**：中文错误提示 + 修复建议，危险操作二次确认，每个按钮都有帮助说明。

## 9. 文档

- `docs/操作手册.md`：完整操作手册（安装迁移、六个页面、搜索语法、遴选、冲突处理、故障排查、快捷键）
- `docs/操作手册.html`：排版版手册，浏览器打开即可，也可打印为 PDF
- `docs/UserGuide.md` / `docs/UserGuide.html`：同一份手册的 ASCII 文件名副本，跨系统解压时备用
- `CHANGELOG.md`：版本变更记录；`CONTRIBUTING.md`：开发与发布规范；`LICENSE`：MIT

## 10. 在 GitHub 上维护

仓库采用 `main` 受保护分支 + PR 流程，贡献前先读 `CONTRIBUTING.md`。

| 机制 | 文件 | 作用 |
|---|---|---|
| CI | `.github/workflows/ci.yml` | 在 `macos-26` runner 上编译、跑 129 项自检、静态检查无轮询、组装 `.app` 并上传 artifact |
| 自动发布 | `.github/workflows/release.yml` | 推送 `v*` tag 后自动构建分发 zip 并发布到 GitHub Releases |
| 本地发版 | `scripts/release.sh` | 校验版本号 / 工作区 / 自检，创建并推送 tag |
| 问题反馈 | `.github/ISSUE_TEMPLATE/` | 结构化 Bug / 功能建议模板 |
| PR 检查 | `.github/pull_request_template.md` | 自检、文档、安全、无障碍清单 |

发版节奏：更新 `CHANGELOG.md` + `Resources/Info.plist` + `scripts/package.sh` 的版本号 → 合入 main → `./scripts/release.sh vX.Y.Z` → CI 自动出 Release。

### Roadmap

| 优先级 | 计划 |
|---|---|
| 高 | 合并 / 变基冲突的逐行三方编辑视图、stash 分支图 |
| 中 | 提交图上的分支名标签、按作者 / 日期聚合、快捷键自定义 |
| 中 | Apple 开发者签名与公证（去掉 `xattr` 步骤）、通用二进制 |
| 低 | 硬件密钥（sk-ssh-ed25519）、ssh-agent 状态、多窗口多仓库并排 |
