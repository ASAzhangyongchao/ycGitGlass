# 贡献与维护指南

欢迎在 GitHub 上继续迭代 GitGlass。这份文档说明开发环境、代码约定和发布流程。

## 1. 环境

| 项目 | 要求 |
|---|---|
| macOS | 26.0+（用到系统 Liquid Glass API） |
| 工具链 | Swift 6.2+ / Xcode 26 或 Command Line Tools |
| 依赖 | 无第三方依赖；`swift package resolve` 应当 instantly 完成 |
| 外部命令 | 系统 `git`、`ssh-keygen`、`ssh`、`iconutil` |

```bash
git clone <仓库地址>
cd GitGlass
swift build
swift run GitGlassSelfTest
```

若本地环境不允许 SwiftPM 嵌套沙箱（报 `sandbox-exec: Operation not permitted`），给命令加 `--disable-sandbox`，打包脚本已内置该参数。

## 2. 分支与提交

- `main` 为受保护主分支，只通过 PR 合入；CI 通过才允许合并。
- 功能分支命名：`feature/xxx`、`fix/xxx`、`docs/xxx`。
- 提交信息用 Conventional Commits：`feat:` / `fix:` / `docs:` / `refactor:` / `test:` / `chore:`，一句话说清做了什么。
- 一个 PR 只做一件事；改了行为就同步改自检与文档。

## 3. 代码约定

**分层（不要越层）**

```
Views（SwiftUI，不写业务逻辑）
  → AppState（@Observable @MainActor，刷新编排）
  → GitService / SSHKeyService（领域服务，不依赖 UI 类型）
  → CommandRunner（唯一的外部进程出口）
```

**必须遵守**

| 约定 | 原因 |
|---|---|
| 所有外部命令走 `CommandRunner`，参数用 `[String]` + `--` 分隔路径 | 防止命令注入与路径以 `-` 开头被当选项 |
| 不读取私钥内容、不把 token / 密钥写进日志 | 安全边界 |
| 错误统一为 `AppError`，提供中文 `friendlyMessage` 与 `recoverySuggestion` | 新手友好，UI 不展示堆栈 |
| 配置集中在 `AppConfig`，启动时校验 | 快速失败 |
| 数据库/文件写入通过 `RepositoryStore`，多步命令考虑事务等价性 | 可回滚 |
| **禁止 Timer / FSEvents / 前后台监听 / 定时轮询** | 刷新只由 6 类事件触发，空闲 CPU 为 0 |
| 动画必须事件驱动，不用 `repeatForever` | 空闲不渲染 |
| 新增 UI 元素检查 Reduce Motion / Reduce Transparency 回退 | 无障碍 |
| 新的 git 能力先在 `GitService` 落地，再包 `AppState.mutate` | 写操作完成后自动刷新一次 |

## 4. 自检要求（合并前必过）

```bash
swift build                                   # 0 error / 0 warning
swift run GitGlassSelfTest                    # 输出「N 通过，0 失败」
./scripts/build-app.sh                        # 能组装出 .app
./scripts/package.sh                          # 能生成完整分发包（需先有 .app）
```

新增任何服务层能力，都要在 `Sources/GitGlassSelfTest/main.swift` 里补真实仓库断言。自检使用临时 Git 仓库和临时 SSH 目录，**不得读写用户真实 `~/.ssh`**。

CI（`.github/workflows/ci.yml`）在 `macos-26` runner 上跑同样的编译、自检与打包，并把 `.app` 上传为 artifact。

## 5. PR 检查清单

- [ ] `swift build` 无 error / warning
- [ ] 自检 0 失败，且新增功能有对应断言
- [ ] `CHANGELOG.md` 的 Unreleased 段已更新
- [ ] 用户可见行为变化时同步更新 `docs/操作手册.md` 与 `docs/操作手册.html`
- [ ] 没有引入 Timer / 轮询 / 后台常驻任务
- [ ] 没有硬编码密钥、令牌、绝对路径
- [ ] 危险操作有二次确认，错误有中文恢复建议

## 6. 发布流程

1. 更新 `CHANGELOG.md`（把 Unreleased 归入新版本）、`Resources/Info.plist` 的 `CFBundleShortVersionString` / `CFBundleVersion`、`scripts/package.sh` 的 `VERSION`。
2. 提交并合入 `main`。
3. 运行：

   ```bash
   ./scripts/release.sh v1.2.0
   ```

   脚本会校验工作区与版本号格式、本地跑一遍自检，然后创建并推送 tag。
4. `release.yml` 收到 `v*` tag 后自动：编译 → 自检 → 生成 `.app` → 打包 zip → 创建 / 更新 GitHub Release 并附上分发包。
5. 在 Release 页面补充发布说明。

## 7. 报告问题

请用仓库的 Issue 模板，附上 macOS 版本、芯片架构、Git 版本、复现步骤，以及错误提示条里「查看原始信息」的内容（**注意先把私钥、令牌等敏感信息删掉**）。
