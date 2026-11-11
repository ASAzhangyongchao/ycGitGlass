# 变更日志

本项目遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 风格，版本语义参考 SemVer。
所有值得注意的变更都记录在这里；发布流程见 `CONTRIBUTING.md`。

## [Unreleased]

计划中（见 `README.md` 的 Roadmap）：

- 合并 / 变基冲突的逐行三方编辑视图
- 提交图的分支名称标签与按作者 / 日期的聚合视图
- 应用图标的多风格切换、Apple 公证与签名发布
- SSH 密钥的硬件密钥（sk-ssh-ed25519）与 ssh-agent 状态显示

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
