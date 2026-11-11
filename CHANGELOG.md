# 变更日志

本项目遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 风格，版本语义参考 SemVer。
所有值得注意的变更都记录在这里；发布流程见 `CONTRIBUTING.md`。

## [Unreleased]

计划中（见 `README.md` 的 Roadmap）：

- 合并 / 变基冲突的逐行三方编辑视图
- 提交图的分支名称标签与按作者 / 日期的聚合视图
- 应用图标的多风格切换、Apple 公证与签名发布
- SSH 密钥的硬件密钥（sk-ssh-ed25519）与 ssh-agent 状态显示

## [1.3.0] - 2026-11-11

布局重构 + 更新能力版本。

### Fixed

- **顶部布局重构**：此前「品牌条 + 顶栏」上下两行重复显示仓库名与分支，把内容区压矮。现在仓库/分支/领先落后并入品牌行单行展示，操作行只留分支切换、拉取、推送、刷新。
- **页签自适应**：六个页签改用原生 `Layout` 流式布局，窄窗口自动换行，不再硬挤压截断文字。

### Added

- **关于面板**：品牌大图标、版本（v1.3.0 / build 4）、系统要求、MIT 协议、仓库地址；「GitHub 仓库 / 问题反馈 / 发布历史」链接按钮；入口在品牌行 logo、菜单栏右侧、应用菜单「关于」。
- **检查更新**：`UpdateService` 查询 GitHub Releases（`releases/latest`），语义化版本比较（含预发布后缀）；关于面板手动「检查更新」（⌘U）+ 有新版时显示「前往下载」；启动时距上次 ≥24h 才静默检查一次，失败静默、绝不轮询；品牌行出现「新版本 x.y.z」徽标提醒。
- 应用菜单与菜单栏常驻入口均增加「检查更新 / 关于」。
- 自检新增 M 节 10 项（版本比较含 `2.0.0-beta < 2.0.0`、`1.10.0 > 1.9.0` 等边界），共 **139 项**。

### Changed

- 版本信息集中到 `AppConfig`（`appVersion` / `repoSlug` / 各链接），`Brand` 与关于面板均从其读取。
- 版本号 1.3.0（build 3 → 4）；自检标题同步。

## [1.2.0] - 2026-11-11

品牌与系统级存在感版本。

### Added

- 产品正式命名 **「码牛 MooGit」**（工程 / 仓库标识仍为 `GitGlass`，避免影响已有配置目录）。
- 应用图标与 Dock 图标改用用户提供的毛毡小牛插画：`scripts/make-brand-assets.swift` 自动裁掉右下角水印、做 macOS 圆角，生成 `AppIcon.icns` 与页头 `BrandHeader.png`；`make-icon.swift` 保留为无源图时的程序化兜底。
- **屏幕顶部菜单栏常驻入口**（SwiftUI `MenuBarExtra`）：显示当前仓库与改动数，可打开主窗口、手动刷新、拉取、推送、退出；关掉主窗口仍常驻。
- 应用菜单「关于 码牛 MooGit」、窗口标题「码牛 MooGit」。
- 窗口玻璃品牌页头：小牛 logo + 名称 + 版本徽标 + 当前仓库 / 分支胶囊。

### Changed

- `Info.plist`：`CFBundleName` = 码牛、`CFBundleDisplayName` = 码牛 MooGit、版本 1.2.0（build 3）。
- 分发包版本升为 1.2.0；README、Markdown / HTML 手册、Issue 模板、推送脚本同步。
- 自检输出标题更新为「码牛 MooGit 深度自检 v1.2.0」。

## [1.1.0] - 2026-11-11

首个可分发版本，同时建立 GitHub 维护基线。

### Added

- **核心 Git 能力**：仓库添加 / 批量扫描 / 新建 / 克隆，状态与分支维护，暂存与提交，差异预览，远程源增删改，拉取 / 抓取 / 推送。
- **历史与搜索**：`git log --graph` 彩色分支轨道（Canvas 重绘）、即时内存过滤、深度搜索语法（`author:` / `message:` / `file:` / `hash:` / `since:` / `until:`）、提交详情 Inspector（元信息 / 统计 / 变更文件树 / 逐文件 diff）。
- **借鉴 Sourcetree**：遴选 Cherry-pick、还原 Reverse commit、储藏 Stash（apply / pop / drop）、轻量与附注标签、冲突文件可视化处理（采用 ours / theirs / 标记已解决 / 继续 / 中止）。
- **多平台 SSH 密钥**：GitHub / GitLab / Gitee / Bitbucket / CODING / 自建平台，ED25519 生成、指纹、公钥复制、连接测试、权限检查与修复、`~/.ssh/config` 托管块写入与自动备份。
- **界面**：macOS 26 原生 Liquid Glass、事件驱动弹簧动效、玻璃高光描边、面板滑入、目录树视图、新手引导；支持「减弱动态效果」与「降低透明度」。
- **工程化**：SwiftPM 三 target 分层、类型化中文错误、脱敏结构化日志、129 项真实仓库自检、一键打包脚本、可迁移分发包、完整操作手册（Markdown + HTML）。
- **分发与维护**：本地生成的应用图标、`.gitignore`、MIT 协议、CONTRIBUTING、Issue / PR 模板、GitHub Actions CI（`macos-26`）与自动 Release 工作流。

### Design decisions

- 零第三方依赖、零 WebView，仅链接系统框架；应用体积约 4.4 MB，空闲 footprint 约 38 MB。
- **刷新只由事件触发**（启动 / 手动 / 切仓库 / 切分支 / 写操作 / 深度搜索），不引入 Timer、文件监听或轮询。
- 所有动画事件驱动、结束即停；支持系统无障碍设置回退。
- 私钥内容从不读取、展示、复制或记录；命令参数按数组传递并用 `--` 分隔路径。

### Fixed

- 空仓库（首次提交前无 HEAD）`git restore --staged` 失败：改用 `git rm --cached`。
- `git stash push` 在干净工作区退出码为 0 导致误报成功：显式识别 "No local changes to save"。
- 快速切换仓库时刷新被 `isBusy` 静默丢弃：用 continuation 排队等待。
- 遴选冲突失败后不刷新、冲突横幅不出现：增加失败后刷新。
- 超时 kill 可能误伤被复用的 pid：增加线程安全完成标志。
- 密钥指纹逐个串行执行形成 N+1 等待：改为并行解析。

## [1.0.0] - 2026-11-11

内部初版：SwiftUI 原生骨架、Git 服务与 SSH 服务、34 项基础自检、首个 `.app` 打包。未对外发布。
