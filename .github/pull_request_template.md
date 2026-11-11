## 这次改了什么

<!-- 一句话说明，关联 Issue：Closes # -->

## 为什么

<!-- 解决的真实问题 / 场景 -->

## 检查清单

- [ ] `swift build` 无 error / warning
- [ ] `swift run GitGlassSelfTest` 输出「0 失败」，且新增能力补了真实仓库断言
- [ ] `./scripts/build-app.sh` 能组装出 `.app`
- [ ] `CHANGELOG.md` 的 Unreleased 段已更新
- [ ] 用户可见变化已同步 `docs/操作手册.md` 与 `docs/操作手册.html`
- [ ] 没有引入 Timer / 轮询 / 后台常驻任务 / 循环动画
- [ ] 没有硬编码密钥、令牌、绝对路径；日志已脱敏
- [ ] 危险操作有二次确认，错误有中文恢复建议
- [ ] 新增 UI 检查了 Reduce Motion / Reduce Transparency 回退

## 验证输出

<!-- 粘贴自检最后一行与编译结果 -->
