import SwiftUI

// MARK: - 教学提示系统
// 全站统一的小问号「怎么用」教学弹层：标题 + 图文步骤 + 补充说明。
// 不同于 GlassCard.help 的纯文本，TeachingTip 面向新手教学：
// 这个区块是干什么的、按什么顺序操作、哪里容易踩坑。

/// 教学提示数据：一个功能区块的完整使用说明。
struct TeachingTip: Identifiable {
    let id = UUID()
    /// 教学标题（弹层第一行）
    var title: String
    /// 一句话说明这是干什么的
    var intro: String
    /// 操作步骤（有序展示）
    var steps: [Step] = []
    /// 补充提示 / 彩蛋 / 注意事项
    var footnote: String? = nil

    struct Step {
        var icon: String
        var title: String
        var detail: String

        init(_ icon: String, _ title: String, _ detail: String) {
            self.icon = icon
            self.title = title
            self.detail = detail
        }
    }

    init(title: String, intro: String, steps: [Step] = [], footnote: String? = nil) {
        self.title = title
        self.intro = intro
        self.steps = steps
        self.footnote = footnote
    }
}

/// 小问号按钮 + 教学弹层。可内嵌到任何标题行 / 工具条。
struct HelpQuestionButton: View {
    let tip: TeachingTip
    /// 弹层箭头方向（默认指向下方内容）
    var arrowEdge: Edge = .bottom

    @State private var show = false

    var body: some View {
        Button {
            show.toggle()
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(show ? GlassPalette.accent : Color.secondary)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("这是什么？点开看使用教学")
        .popover(isPresented: $show, arrowEdge: arrowEdge) {
            TeachingTipView(tip: tip)
        }
    }
}

/// 教学弹层内容：标题 → 简介 → 步骤 → 脚注。
struct TeachingTipView: View {
    let tip: TeachingTip

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 标题行
            HStack(spacing: 8) {
                Image(systemName: "lightbulb.max.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GlassPalette.amber)
                Text(tip.title)
                    .font(.system(size: 13, weight: .bold))
            }

            // 简介
            Text(tip.intro)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // 步骤
            if !tip.steps.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(Array(tip.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 9) {
                            ZStack {
                                Circle()
                                    .fill(GlassPalette.accent.opacity(0.13))
                                    .frame(width: 22, height: 22)
                                Image(systemName: step.icon)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(GlassPalette.accent)
                            }
                            VStack(alignment: .leading, spacing: 1.5) {
                                Text(step.title)
                                    .font(.system(size: 11.5, weight: .semibold))
                                Text(step.detail)
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .background(Color.primary.opacity(0.04),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            // 脚注
            if let note = tip.footnote {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                        .foregroundStyle(GlassPalette.violet)
                        .padding(.top, 1.5)
                    Text(note)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .frame(width: 300, alignment: .leading)
    }
}

// MARK: - 全站教学内容库（集中维护，各页引用）

enum Teachings {
    /// 提交页 · 代码变更列表
    static let commitFiles = TeachingTip(
        title: "怎么提交代码",
        intro: "这是工作区改动的清单。Git 的提交流程是：先勾选 → 暂存 → 写说明 → 提交。",
        steps: [
            .init("checkmark.circle", "勾选文件", "点每行左侧圆圈勾选要提交的文件；未跟踪的新文件也要勾。"),
            .init("plus.circle", "暂存所选", "点右上「⋯」菜单 → 暂存所选；或悬停文件行点 ＋ 快速暂存单个文件。"),
            .init("pencil.line", "写一句说明", "底部输入框写本次改动做了什么，可用 feat / fix 前缀按钮。"),
            .init("paperplane.fill", "提交", "点「提交」只存本地；点「提交并推送」同时上传远程（⌘⏎）。"),
        ],
        footnote: "点文件名在右侧展开预览；再点同一个文件或按 ⎋ 收起。面板宽度可拖、会记住。"
    )

    /// 提交页 · 差异预览
    static let commitDiff = TeachingTip(
        title: "怎么读差异（Diff）",
        intro: "这是单个文件改动前后的对照：左边减号行是旧内容，右边加号行是新内容。",
        steps: [
            .init("minus.circle", "红色行", "改动前就被删掉的内容（-）。"),
            .init("plus.circle", "绿色行", "这次新加的内容（+）。"),
            .init("text.badge.checkmark", "紫色 @@ 行", "行号定位标记，表示下一段差异在文件中的位置。"),
            .init("rectangle.portrait", "图片对比", "图片文件自动进入五模式对比视图（并排/滑块/淡入淡出/闪烁/差异分析）。"),
        ],
        footnote: "右侧面板左缘可拖宽，宽度会记住；⎋ 或关闭按钮收起，列表始终在场。"
    )

    /// 历史页 · 分支轨道
    static let historyGraph = TeachingTip(
        title: "怎么看分支轨道图",
        intro: "左侧彩色竖线是分支的演变轨迹：一种颜色一条分支，圆点是提交，斜线是合并/分叉。",
        steps: [
            .init("circle.fill", "圆点", "一次提交；带光环的是当前位置（HEAD）。"),
            .init("arrow.triangle.branch", "斜线", "分支从某条线分出去，或合并回来。"),
            .init("line.3.horizontal.decrease.circle", "找提交", "上方搜索框输入说明 / 作者 / hash 即时过滤，不打字时零开销。"),
            .init("sidebar.right", "看详情", "点任意提交，右侧展开详情：改了哪些文件、逐文件差异、遴选 / 还原。"),
        ],
        footnote: "并行分支太多时轨道自动收起让位给文字；此时在提交详情的「分支关系」里看局部轨道。"
    )

    /// 历史页 · 搜索与筛选
    static let historySearch = TeachingTip(
        title: "搜索与筛选技巧",
        intro: "输入即过滤已加载的提交（不发任何 git 命令，随便打字不卡）。",
        steps: [
            .init("text.magnifyingglass", "普通关键词", "在说明、作者、hash、标签里模糊匹配。"),
            .init("person.crop.circle", "author:张三", "只按作者过滤。"),
            .init("number", "hash:a1b2c3", "按提交号前缀过滤。"),
            .init("doc.badge.clock", "file:路径 / since:日期", "扫描完整历史——输完点「深度搜索」按钮。"),
        ],
        footnote: "「全部分支」勾上后能看到其它分支的提交；按作者排序时轨道会隐藏（行序打乱轨道会失真）。"
    )

    /// 工作台 · 快捷操作
    static let dashboardActions = TeachingTip(
        title: "今天要做的事",
        intro: "按推荐顺序三步走：先拉取远程，再处理改动，最后提交推送。",
        steps: [
            .init("arrow.down.circle", "1 · 拉取远程", "先把别人的提交下载下来，避免稍后推送被拒。"),
            .init("doc.text.magnifyingglass", "2 · 查看并暂存", "跳到提交页勾选文件、写说明。"),
            .init("paperplane.fill", "3 · 一键提交并推送", "没有写说明时自动生成「chore: 更新 N 个文件」。"),
        ],
        footnote: "最近提交列表点任意一条可跳到历史页查看详情。"
    )

    /// 储藏页
    static let stashes = TeachingTip(
        title: "储藏（Stash）怎么用",
        intro: "临时把改动「收起来」，让工作区变干净——切分支 / 拉代码前特别有用，随时能恢复。",
        steps: [
            .init("archivebox", "储藏", "「提交」页菜单或快捷键 ⌥⌘S 一键储藏当前全部改动；可写说明、可选含未跟踪文件。"),
            .init("arrow.uturn.backward", "恢复", "回到本页点某条储藏的「恢复」，改动原样回到工作区（记录保留）。"),
            .init("tray.and.arrow.up", "弹出", "「恢复并删除」= 恢复的同时删掉这条储藏记录。"),
            .init("exclamationmark.arrow.circlepath", "冲突处理", "遴选 / 合并冲突时这里会出现解决面板：采用我方 / 对方 / 手动解决。"),
        ],
        footnote: "标签管理也在本页下方：轻量标签当书签，附注标签可写说明。"
    )

    /// 远程源页
    static let remotes = TeachingTip(
        title: "远程源是什么",
        intro: "远程源（remote）= 代码托管服务器上的仓库地址。推送 / 拉取都从这里走。",
        steps: [
            .init("network", "默认源", "通常叫 origin，添加仓库时自动带上。"),
            .init("plus.circle", "添加远程源", "可加多个：比如公司 GitLab + 个人 GitHub 各一个。"),
            .init("arrow.down.circle", "抓取 / 拉取", "抓取只下载不合并；拉取下载并自动合并到当前分支。"),
        ],
        footnote: "地址支持 HTTPS 和 SSH；用 SSH 前先到「密钥」页配好密钥。"
    )

    /// 密钥页
    static let sshKeys = TeachingTip(
        title: "SSH 密钥怎么配",
        intro: "SSH 密钥 = 免密码身份凭证。配好后推拉代码不再输密码。",
        steps: [
            .init("key.fill", "1 · 生成密钥", "选平台（GitHub / GitLab / Gitee…）填邮箱，点生成。"),
            .init("doc.on.doc", "2 · 复制公钥", "点「复制公钥」，粘贴到平台的 SSH Keys 设置里。"),
            .init("checkmark.seal", "3 · 测试连接", "点「测试连接」验证平台已认你这把钥匙。"),
        ],
        footnote: "私钥永远不离开本机、不展示、不上传——应用只读公钥。~/.ssh/config 会自动托管带标记的配置块。"
    )

    /// 详情 · 遴选与还原
    static let cherryRevert = TeachingTip(
        title: "遴选与还原的区别",
        intro: "都是「搬运改动」，但方向不同，用错会误改历史。",
        steps: [
            .init("arrow.triangle.merge", "遴选 Cherry-pick", "把这条提交的改动「复制」成当前分支的新提交。原提交不动。适合把某个修复搬到别的分支。"),
            .init("arrow.uturn.backward", "还原 Revert", "生成一条「反向提交」抵消这条提交的改动。历史只增不改，适合已推送出去的提交。"),
            .init("exclamationmark.triangle", "冲突了？", "别慌，到「储藏」页有可视化冲突处理，或直接「中止当前操作」回到原样。"),
        ],
        footnote: "小知识：如果父提交、内容、作者、时间完全一致，遴选出的新提交 hash 可能与原提交相同，这是 Git 内容寻址的正常现象。"
    )

    /// 分支选择器 · 合并与删除
    static let mergeBranches = TeachingTip(
        title: "合并分支怎么选方向",
        intro: "点顶栏「仓库 · 分支」胶囊打开本面板。每个分支行右侧的合并图标有两个方向。",
        steps: [
            .init("arrow.down.right", "把 X 合并进当前", "最常用：我在 main 上，把 feature 的成果合进来。"),
            .init("arrow.up.right", "把当前合并到 X", "自动切到 X → 合并 → 切回来。冲突时会停在 X 上等你解决。"),
            .init("togglepower", "--no-ff 开关", "默认能快进就快进（不留合并提交）；勾选后强制生成合并提交，保留分支拓扑。"),
            .init("trash", "删除分支", "普通删除只删已合并分支（安全）；强制删除丢弃未合并提交，需二次确认。"),
        ],
        footnote: "顶部搜索框可按名字快速过滤分支；本地 / 远程分组展示。"
    )

    /// 分支图弹层（详情面板）
    static let branchPopover = TeachingTip(
        title: "分支图弹层",
        intro: "展示这条提交前后 ±8 条的局部分支轨道——轨道列收起时，这里就是看分支脉络的地方。",
        steps: [
            .init("circle.highlighter", "高亮圆点", "带光环的就是当前提交，上下是它的前后文。"),
            .init("paintpalette", "颜色", "同一颜色 = 同一条分支的轨迹；斜线是分叉 / 合并点。"),
        ],
        footnote: "对应完整轨道图的自动收起策略：并行分支过多时不抢提交信息的宽度。"
    )

    /// 图片对比
    static let imageDiff = TeachingTip(
        title: "图片对比的五种玩法",
        intro: "点开图片类文件的变更后自动进入图片对比视图，顶部菜单切换模式。",
        steps: [
            .init("rectangle.split.2x1", "并排", "总览两版差异，先看整体。"),
            .init("slider.horizontal.3", "滑块", "拖分割线对齐同一位置，看细节差异。"),
            .init("circle.lefthalf.filled", "淡入淡出", "透明度渐变找对齐偏移。"),
            .init("bolt.fill", "闪烁", "新旧交替闪烁——移动过的元素会「跳」出来。"),
            .init("wand.and.rays", "差异分析", "逐像素比对，洋红高亮不同区域；拖「容差」忽略压缩噪点级别的小差异。"),
        ],
        footnote: "差异分析在后台线程计算不卡界面；底部实时显示差异百分比。"
    )

    /// 吉祥物
    static let mascot = TeachingTip(
        title: "工位上的小牛 🐮",
        intro: "左下角这位是码牛本牛——工位常驻员工，有自己的情绪系统。",
        steps: [
            .init("figure.stand", "空闲", "慢悠悠地呼吸浮动——它在工位上摸鱼。"),
            .init("keyboard", "忙碌", "执行 git 操作时加速「敲键」抖动 + 冒汗 💧，操作完就消汗。"),
            .init("face.smiling.inverse", "点它！", "点一下小牛会生气 1 秒（泛红 + X 眼 + 「莫挨老子！」），然后继续干活。"),
            .init("clock", "头顶气泡", "实时显示日期和时间，分钟级刷新。"),
        ],
        footnote: "开启系统「减弱动态效果」后小牛会静止，只保留气泡反馈。"
    )
}
