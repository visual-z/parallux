---
type: fix
status: awaiting-author        # todo | doing | blocked | awaiting-author | done
weight: full
created: 2026-11-20
baseline: 75117aa7f096
---

# 概览的卡片随窗口宽度换行，数字不被截断，文字不在斜杠处折行

## 来源

作者 2026-11-20 的截图（上一张卡 `fix-overview-cards` 装机之后）和原话：「你这玩意设计的，压根没考虑响应式，参考一下 surge 等的设计，你这完全不符合设计规范」。圈出来的两处：

- 流量卡底部「本次会话 ↓ 273.5 MB · ↑ 188.3…」被截断。
- 配置卡的用量「本次会话已用 461.8 MB / 无限」在斜杠后折成两行。

另外路由模式卡里「命中最多：geosit…1 AnyTLS（21%）」中间被省略。

这三处是同一个原因，不是三个缺陷：每张卡片把几项数据拼成一句话放在一行里，而三张卡片无论窗口多窄都挤在同一排（现在的换行条件是三张各 190 pt 放不下，窗口的最小宽度下刚好还放得下）。上一张卡给用量文字加的缩放和折行只是把症状挪了个位置，这里撤掉。

## 范围

- **独占：** `apple/ParalluxKit/Sources/ParalluxKit/Interface/OverviewGrid.swift` 及其测试；`apple/Parallux/Overview/OverviewCards.swift`。
- **接缝：** `OverviewCopy`（命中最多的规则拆成几部分，原来的一句话保留给别处用）；`UsageSummary`（标签与数字分开）；`OverviewView` 给卡片传值。
- **不碰：** 流向图；面板；卡片的显示、隐藏与排序（`DashboardCards`）；路由模式的切换逻辑；窗口的最小尺寸。

## 不变量

- INV-15：对任意卡片数与任意宽度，行覆盖每张卡片恰好一次且顺序不变；同一行里的卡片都不窄于最小宽度；只有第一行可以比其余行短。检查方式：property。

## 观测面

- 纯函数 `OverviewGrid.rows(count:width:)` 的返回值；`OverviewCopy.topRuleParts`、`UsageSummary.label` / `value`。
- 版面只能看：装到本机后在三种窗口宽度下截图（最小 760、作者截图里的 937、默认 1040），逐张检查有没有截断或折行。测试钉不住「看起来对」，这一条另有作者检查。
- GREEN 可能被截断的方式：
  - 分行的测试如果只测几个宽度，实现可以照着样例写：property 在 0–2400 pt 上随机取 4000 组，并断言「再多一列就会挤」，防止实现偷懒全排成一列。
  - 截图如果在屏幕锁定时拍，拍到的是锁屏或空窗口（本机有过）：拍之前先查锁屏状态。

## 环境假设

- 主窗口最小 760 pt 宽（`MainWindow`），侧栏最小 200 pt，页面左右边距各 20 pt：概览内容区最窄约 520 pt。作者截图里的窗口是 937 pt，内容区约 677 pt。
- 竞品的做法（2026-11-20 查的源码）：Clash Verge Rev 的首页卡片在窄窗口下每行一张、宽窗口每行两张（`src/pages/home.tsx` 的栅格）；流量统计是六个独立的小格，标签在上、数值在下，上传和下载的累计各占一格，从不拼成一句（`enhanced-traffic-stats.tsx`）；订阅卡是「已用 / 总量」一行、到期日一行、百分比加一条线性进度条（`home-profile-card.tsx`）；模式切换是三个并排的按钮（`clash-mode-card.tsx`）。Surge 的界面不开源，没有可引用的一手来源，这里不拿它当依据。
- Apple 的布局规范要求布局随窗口尺寸变化并检查裁切（developer.apple.com/design/human-interface-guidelines/layout）；SwiftUI 的 `Layout` 协议可以按父视图给的宽度自己分行。
- **未证实：** 侧栏被拉宽或隐藏时的实际内容区宽度没有逐一量过；分行只依赖布局拿到的宽度，不依赖这些数。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** 卡片只在每张都不窄于最小宽度时才共用一行：三张放不下时第一张独占一行、后两张并排，两张也放不下时排成一列；恰好够与差一点各测一次；一张卡片时占满；宽度为 0、负数、非数时排成一列。
  - 检：test `cardsShareARowOnlyWhileEachKeepsItsMinimumWidth`
- **D2** INV-15。
  - 检：property `gridRowsCoverEveryCardOnceAndNeverSqueezeOne`
- **D3** 「命中最多」拆成规则、去向与占比三部分，拼起来仍是原来那句话；没有命中时没有这几部分。
  - 检：test `theMostHitRuleComesInPartsThatMakeTheSameSentence`
- **D4** 用量拆成标签与数字：数字「X / Y」不分开，标签里没有斜杠，拼起来是原来的文字。
  - 检：test `usageComesAsALabelAndFigures`
- **D8** 路由模式卡显示的规则名与流向图、路由页一致（规则集按名字、域名列表按第一项），不认识的规则集保留自己的名字。
  - 检：test `theMostHitRuleComesInPartsThatMakeTheSameSentence`
- **D5** 计数只因本卡的新测试增加；gate 全绿。
  - 检：cmd `keel gate`
- **D6** 不弱化既有测试。
  - 检：cmd `keel assert-guard --card docs/tasks/fix-overview-responsive.md`
- **D7** 作者看：窗口从最小拉到最宽，三张卡片先是一张加两张、再是三张并排，没有哪个数字被省略号截断，没有哪行在斜杠处折断；只显示一张或两张卡片时也一样。
  - 检：author 概览页，拖动窗口宽度从最小到最宽

## 设计

- **一个原因，一处改。** 每项数据占一行，标签在左（可以被截短）、数值在右（不截短，等宽数字）。这是 Clash Verge Rev 的统计小格的做法，换成了 macOS 设置里「标签—数值」行的样子。卡片里不再有把几项数据连成一句的文字：流量卡是「下载 / 上传」两行；路由模式卡是「命中最多」一行规则加占比、去向另起一行；配置卡是「已用」一行、进度条一行、到期一行。
- **用量改成线性进度条**（竞品同款），撤掉上一张卡加的圆环。圆环要占固定的宽度，正是它把旁边的文字挤折行的；百分比写在标签行右侧不如直接看条。没有配额时画空轨道。
- **分行由布局按实际拿到的宽度算**，不看窗口宽度、不写断点：`OverviewGrid.rows` 是纯函数，SwiftUI 的 `Layout` 只负责摆放。列数取「每张不窄于最小宽度」的最大值，再把卡片从后往前填满，所以不满的是第一行——三张卡片在窄窗口下是流量卡独占一行（它有曲线，宽了更好看）、路由模式与配置并排。同一行的卡片等高，不同行各按内容定高。
- 否决：
  - `ViewThatFits`（现状）：只能在「全部并排」与「全部竖排」之间二选一，没有「一加二」。
  - `LazyVGrid` 的 adaptive 列：不满的是最后一行，而且同一行不等高。
  - 提高窗口的最小宽度：窗口最小尺寸在「不碰」里，改它是把问题推给用户。
  - 继续用缩放字号、允许折行来容纳长句：这就是上一张卡的做法，作者指出的正是它的结果。
- **最小卡片宽度 200 pt**：标签—数值行里最长的一行是「本次会话已用」加「999.9 MB / 无限」，在副标题字号下约 190 pt，加上卡片内边距后取整。假设值；判据是作者检查 D7。
- 流量卡的大号速率数字不动；曲线仍然占满剩余高度。

## 验证命令

```bash
scripts/swift-test.sh /tmp/og.xml OverviewGridTests
keel verify-red docs/tasks/fix-overview-responsive.md
keel gate --record docs/tasks/fix-overview-responsive.md
```

## 证据

RED(swift): 246c966 cardsShareARowOnlyWhileEachKeepsItsMinimumWidth  # D1
RED(swift): 246c966 gridRowsCoverEveryCardOnceAndNeverSqueezeOne  # D2
RED(swift): 246c966 theMostHitRuleComesInPartsThatMakeTheSameSentence  # D3
RED(swift): 246c966 usageComesAsALabelAndFigures  # D4

D8 是冻结之后加的：规则名不再转成界面的叫法，测试必须红。

```diff keel-inject(swift) theMostHitRuleComesInPartsThatMakeTheSameSentence
--- a/apple/ParalluxKit/Sources/ParalluxKit/Interface/OverviewCopy.swift
+++ b/apple/ParalluxKit/Sources/ParalluxKit/Interface/OverviewCopy.swift
@@ -69 +69 @@
-            rule.contains("=") ? TrafficLabel.name(connectionRule: rule) : TrafficLabel.setName(rule)
+            rule
```

失败断言原文（RED 时，桩实现下）：`Expectation failed: OverviewGrid.rows(count: 3, width: 3 * w + 2 * s - 1) == [0..<1, 1..<3]`；`Expectation failed: summary.text == "\(summary.label) \(summary.value)"`；`Expectation failed: OverviewCopy.topRuleParts(connections)`。

装机截图（2026-11-20，屏幕未锁定，开发签名构建 20261120100516）：窗口 760×640（最小宽度）时流量卡独占一行并横排，路由模式与配置并排，整页不用滚动；窗口 918×572 时三张并排。两种宽度下都没有被省略号截断的数字，没有在斜杠处折断的行；路由模式有规则、全局、直连三项。
GATE: a7c0c6d806d9+dirty ok tree:54dbefbdfbde build=0 vet=0 test=0[627p/0f] fmt=0 swift-test=0[191p/0f] apple-build=0 server-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-20)

## 修订

- D8（冻结之后加的判据，只加严）：第一次装机看到「命中最多」显示的是内核的原始条件（`rule_set=[geosite-openai geosite-anthrop…`），两行还是被省略。改为显示流向图用的名字，去向另起一行，原始条件放进悬停提示。
- 装机后追加的一处版面：流量卡独占一行时改成横排（速率、曲线、累计并排）。竖排时它把下面两张卡片挤出屏幕，最小窗口要滚动才看得到路由模式。

## 交接

- 做了什么：卡片按拿到的宽度分行（`OverviewCardGrid` + `OverviewGrid.rows`）；三张卡片里每项数据一行，标签在左、数值在右且不截断；用量从圆环改成线性进度条；「命中最多」显示规则的名字。两种窗口宽度下装机截图看过。
- 卡在哪：D7 等作者看。没看过的：只显示一张或两张卡片时；窗口很宽（三张卡片都超过 412 pt）时流量卡会变成横排，没有截图确认过好不好看；浅色外观下只看过旧版面。
- 下一步：作者拖动窗口宽度看一遍。
