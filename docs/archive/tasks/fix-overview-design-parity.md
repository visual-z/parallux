---
type: fix
status: awaiting-author
weight: full
created: 2026-11-19
baseline: 1a86636 (gate: test 590p/0f, swift-test 114p/0f)
---

# 概览与主窗口工具栏照设计稿 v0.2：流向图按量程换算宽度并经中柱汇流，卡片与文案对齐

## 来源

2026-11-19 作者贴出设计稿概览的截图：「现在的 UI 跟设计稿区别太大了，一致性很差」。PLAN 决策 7（界面以设计稿 v0.2 为准）。对已安装的签名构建截屏（同日，主备、两条线路、46 Kbps）逐项对照，差在：

- 流向图永远撑满高度，46 Kbps 也画成一整块；设计稿的宽度按固定量程换算（`CAP`），小流量就是细带。
- 流带从线路直接画到出口；设计稿是线路 → 中间汇流柱 → 出口两段，中柱上各股首尾相接。
- 节点挤在中间按固定间距堆叠、外面套一个灰底框；设计稿的线路上下铺开，出口居中展开，直接画在内容区。
- 没有设计稿的流动粒子、待命线路的虚线、停用线路的淡色节点。
- 多线路时直连出口显示成绿色的「direct」：组合器把用户的 `direct` 出站换成同名的 `aggregate` 出站，`FlowSummary` 只认类型 `direct`。这是随 `feat-links-aggregate` 引入的缺陷。
- 卡片标题写成「速率 / 模式 / 系统代理」，设计稿是「流量 / 路由模式 / 系统 HTTP 代理」；三张卡不等高，路由模式分段控件不占满，开关不靠右。
- 工具栏缺「分流 / 叠加 / 主备」分段控件；副标题是「已连接 · 主备 · 2 条线路」，设计稿是「3 条线路 · 叠加 · 经东京 VPS」。

## 范围

- **独占：** `apple/ParalluxKit/Sources/ParalluxKit/Interface/`（`SankeyLayout`、`FlowSummary`，新增 `FlowScale`、`FlowParticles`、`OverviewCopy`）及对应测试；`apple/Parallux/Overview/`；`apple/Parallux/MainWindow.swift` 的工具栏；`LinkColors` 的配色；`PanelView` 里迷你流向图的调用点（只跟随 `FlowDiagram` 的参数变化）。
- **不碰：** `SankeyLayout.make(left:right:height:gap:)` 四参数调用的既有行为与既有断言（INV-3）；面板其余布局、设置与其他页面（后续卡）；决策 20 的八项侧栏与路由页；`core/`；设计稿里只为演示存在的东西（「闲时 / 正常 / 满载」开关、「试试切换负载…」提示、模拟数据）；`design-additions.md` 里需要内核配合的待做项（含「命中最多」一行，内核目前不给概览提供规则命中数）。

## 不变量

- INV-3（既有）：每个节点高度等于流经它的流带宽度之和，左右两侧总高度相等。
- INV-7（新）：带量程的流向图里，节点、中柱与流带都不超出绘图高度，同列相邻节点间距不小于最小间距，中柱上的流带首尾相接且总和等于中柱 — 检查方式：代码断言 + property `aFlowLayoutWithCapacityIsProportionalAndNeverOverflows`。
- INV-8（新）：流向图的粒子数不超过 `FlowParticles.limit`，每个粒子都落在一股现存流带的范围内 — 检查方式：property `flowParticlesStayBoundedAndInsideTheirBands`。

## 观测面

- 纯 Swift 返回值：`SankeyLayout.make(…capacity:)` 的几何、`FlowScale.capacity(peak:)`、`FlowParticles` 步进后的粒子、`FlowSummary.exits`、`OverviewCopy` 的字符串。
- 画出来的样子：仓库外的一次性脚本把 `FlowDiagram` 与卡片用设计稿的数字渲染成图，和设计稿截图并排看（不进仓库）；真实窗口由作者看。
- GREEN 被截断的方式：布局对空输入提前返回而测试只跑非空——测试显式跑 0、1、上限；粒子实现什么都不做也满足「不超过上限」——测试同时断言有流量时确实产生了粒子；量程函数返回一个巨大常数也满足「不小于峰值」——测试同时断言不超过峰值的 2.5 倍。

## 环境假设

- libbox 的 `Connection.outboundType` 是命中出站的类型；多线路时用户的 `direct` 出站被 `ProfileComposer` 换成同 tag 的 `aggregate` 出站（读 `ProfileComposer.compose`「Replace each user direct with an aggregate of the same tag」）。对拍：2026-11-19 签名构建实机截屏，直连流量的出口名是「direct」、颜色是节点的绿色，与推断一致。
- 节点不会以 `aggregate` 类型出现在连接上：节点保持自己的类型，只是 `detour` 指向 `parallux-links`；规则直接指向 `parallux-links` 的配置不存在（它是组合器加的 tag）。
- `TimelineView(.animation(minimumInterval:paused:))` 加 `Canvas` 在 macOS 26 可用；`paused` 为真时不再触发重绘（SwiftUI 文档）。`accessibilityReduceMotion` 环境值反映「减弱动态效果」。窗口被遮挡或关闭时 `NSWindow.occlusionState` 不含 `.visible`（AppKit 文档）。动工时用仓库外脚本对拍 Canvas 在离屏窗口里能画出来。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** INV-7：任意输入（0 条、1 条、多条，速率含 0 与上限，量程从远小于到远大于总量）下，给了量程的布局里节点与流带都在 `[0, height]` 内；同列相邻节点间距 ≥ `gap`；每个节点高度等于流经它的流带之和；中柱等于总量，其上的流带按「出口、线路」顺序首尾相接，每股在线路、中柱、出口三处一样厚；放得下时厚度 = 速率 ÷ 量程 × 高度（宽度与速率成正比），放不下时按能放下的比例缩小；总量为 0 时没有流带。
  - 检：property `aFlowLayoutWithCapacityIsProportionalAndNeverOverflows`
- **D2** 量程：`FlowScale.capacity(peak:)` 不小于峰值、不小于下限 `FlowScale.floor`、不超过 max(下限, 峰值 × 2.5)，取值是下限的 1、2、5 × 10ⁿ 倍，对峰值单调不减；峰值为 0、负数、1、恰好等于某一档、`Int64.max` 时都不溢出。
  - 检：test `flowCapacityIsASteppedCeilingWithAFloor`
- **D3** INV-8：任意步进序列（时间步含 0、一帧、远超一帧）之后粒子数 ≤ `FlowParticles.limit`；每个粒子属于当次传入的某一股流带，纵坐标在那股流带两端的上下沿之间；有流带时确实产生粒子；流带消失后它的粒子在下一步被丢弃。
  - 检：property `flowParticlesStayBoundedAndInsideTheirBands`
- **D4** 多线路时被换成 `aggregate` 出站的直连流量汇总到「直连」，不以出站 tag 另列一个出口。
  - 检：test `flowSummaryCountsRewrittenDirectOutboundsAsDirect`
- **D5** 概览文案：副标题是「N 条线路 · 聚合方式 · 经<聚合服务器>」（只有叠加带「经…」，只有一条线路时不带聚合方式）；线路说明是「已停用」「待命」或速率；出口说明在叠加 / 分流 / 主备下分别以「叠加后转发」「按连接分到各线路」「仅主线路」开头，直连只有速率；叠加时出口名是「<聚合服务器> → <节点>」；中柱标签是「聚合方式 · 速率」。
  - 检：test `overviewCopyFollowsTheDesign`
- **D6** 计数：测试数只因本卡新增的测试而增加（基线 swift-test 114）。
  - 检：cmd `keel gate`
- **D7** 不弱化既有测试。
  - 检：cmd `keel assert-guard --card docs/tasks/fix-overview-design-parity.md`
- **D8** 作者看真实窗口，概览与设计稿 v0.2 一致：流向图直接画在内容区、高 330 pt，线路 → 中柱 → 出口两段流带，线路上下铺开、出口居中展开，待命线路是虚线、停用线路变淡，线路配色与设计稿相同；粒子沿流带流动，打开「减弱动态效果」后静止；三张卡片等高，标题「流量 / 路由模式 / 配置」，路由模式分段控件占满卡片宽度，「系统 HTTP 代理」开关靠右；工具栏有「分流 / 叠加 / 主备」分段控件与电源按钮；副标题如 D5。
  - 检：author `scripts/build-signed.sh --install` 后打开主窗口概览，对照设计稿
- **D9** 流向图动画的 CPU 占用在 PLAN §5 的预算内（可见时 ≤ 5%，窗口不可见时为 0）。
  - 检：author 活动监视器里看 Parallux：概览可见时与最小化后各看 10 秒

## 设计

- **量程不是固定的 1000 Mbps。** 设计稿的 `CAP = 1000` 配的是演示数据（三条线路共约 700 Mbps）；照搬的话家用宽带日常的几 Mbps 画出来不到 1 pt。改为随最近的峰值取档：`FlowScale.capacity` 取速率历史（120 秒）峰值向上的 1-2-5 档，下限 1 Mbit/s。宽度仍然与速率成正比（设计稿「宽度 = 实时速率」），只是满刻度跟着最近的峰值走。否决：永远撑满（现状，看不出快慢）；对数刻度（两股的宽度比不再等于速率比）。
- **一个布局函数。** `SankeyLayout.make` 增加可选的 `capacity`：不给时行为与既有测试完全一样；给了就用设计稿的几何（线路铺满高度、出口中心展开约半个高度、中柱汇流）。不另起一个类型，既有的 INV-3 断言继续管这段代码。
- **粒子是纯模型。** `FlowParticles` 只管「有哪些粒子、走到哪」，生成量按流带厚度算（每 pt 厚度每秒 0.85 个，折算自设计稿的 `v/45*dt*10`），总量有硬上限；视图只负责画。粒子的横向进度用流带贝塞尔曲线自己的参数方程，所以粒子不会画到带外（设计稿用线性横坐标，粒子会略微出带）。
- **视图不认 AppModel。** `FlowDiagram` 与三张卡片只收值和 Binding，取数留在 `OverviewView`；这样仓库外的脚本能用设计稿的数字单独渲染它们。
- **占满宽度的分段控件**用 `NSSegmentedControl`（`segmentDistribution = .fillEqually`）包一层：SwiftUI 的分段 `Picker` 在 macOS 上不随容器变宽（面板截屏里它缩在中间）。仍是系统控件。
- **配色**用设计稿的十六进制值（深浅色各一套）；`copy-and-style.md` 允许图表配色手写。
- 否决：把「闲时 / 正常 / 满载」做成隐藏的调试开关——那是设计稿的演示控件，App 里不放假数据（`feat-m2-interface` 已否决）。

## 验证命令

```bash
scripts/swift-test.sh /tmp/overview.xml 'aFlowLayoutWithCapacity|flowCapacityIsASteppedCeiling|flowParticlesStayBounded|flowSummaryCountsRewrittenDirect|overviewCopyFollowsTheDesign'
keel verify-red docs/tasks/fix-overview-design-parity.md
keel gate --record docs/tasks/fix-overview-design-parity.md
```

## 证据

RED(swift): e7c85cd aFlowLayoutWithCapacityIsProportionalAndNeverOverflows  # D1
RED(swift): e7c85cd flowCapacityIsASteppedCeilingWithAFloor  # D2
RED(swift): e7c85cd flowParticlesStayBoundedAndInsideTheirBands  # D3
RED(swift): e7c85cd flowSummaryCountsRewrittenDirectOutboundsAsDirect  # D4
RED(swift): e7c85cd overviewCopyFollowsTheDesign  # D5

- RED 时的失败原文：D1 `Expectation failed: abs(layout.total.length - total * scale) <= tolerance`；D2 `Expectation failed: FlowScale.capacity(peak: 0) == floor`；D3 `Expectation failed: sawParticles`（traffic never produced a particle）；D4 `Expectation failed: exits == [.init(name: "HK-03", rate: 420), .init(name: FlowSummary.directName, rate: 155)]`；D5 `Expectation failed: OverviewCopy.subtitle(links: 3, mode: .bond, server: "东京 VPS") == "3 条线路 · 叠加 · 经东京 VPS"`。
- 冻结前的无效尝试：D2 的测试第一版在量程小于下限时会死循环（`while mantissa % 10 == 0`，mantissa 为 0），桩实现下整个测试进程挂住；冻结前加了 `mantissa > 0` 的守卫，断言没变。
- 渲染对拍（仓库外的一次性脚本，离屏窗口，不进仓库）：用设计稿截图里的数字（177 / 453 / 102 Mbps，直连 278、节点 454）渲染 `FlowDiagram` 与三张卡片，与设计稿截图并排看过；另看了闲时（48 Kbps、一条待命、一条停用）、五个出口、深色、560 pt 窄宽度。脚本第一次运行就崩在 `Canvas` 的 `child view IDs must be unique`（两个按下标的 `ForEach` 都从 0 起），标签因此移出 Canvas。
- 窗口不可见时停画（2026-11-19，同一脚本，保留 App 自己的 `WindowVisibility`）：离屏窗口 `occlusionState` 不含 visible，CPU 0.0% / 0.0%，画面里没有粒子；放到屏幕上 4.2% / 4.2%，粒子在动。
- CPU（同一脚本，Debug 构建，离屏，满载约 900 个粒子，`top -l 2` 取 3 次）：标签在 Canvas 里、每个粒子单独填充时 8.8–11.9%；标签移出、粒子按线路与透明度合批后 4.0–4.1%。真实窗口上的数字由作者看（D9）。
GATE: e7c85cd6b621+dirty ok tree:fff56d1ce728 build=0 vet=0 test=0[590p/0f] fmt=0 swift-test=0[119p/0f] apple-build=0 server-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-19)

## 修订

（完成定义无改动。）

- D8 的描述因合并主干而补充（2026-11-19）：主干的决策 21 给路由模式卡片加了「聚合」「代理」两个开关，卡片里现在是分段控件、「命中最多」、聚合、代理、系统 HTTP 代理五行；设计稿只有三行。跟随已定决策，其余各项不变，请作者确认。
- 证据更正（2026-11-19）：上面「CPU 8.8–11.9% → 4.0–4.1%」是离屏窗口量的，离屏窗口不参与合成，数字偏低；同一实现上屏、60 帧时是 10–12.6%。动画随后在 `perf-flow-animation` 里重做（粒子改由 GPU 画），以那张卡的数字为准。
- 范围更正（2026-11-19，复查发现）：「不碰」里写「命中最多一行，内核目前不给概览提供规则命中数」是错的——每条连接都带着命中的规则，App 侧就能数。这一行在 `fix-design-parity-followups` 里补上。同一张卡还补了副标题盖住错误提示的问题（本卡把副标题从 `statusLine` 换掉时引入）。

## 交接

- 做了什么：流向图换成设计稿的几何（按量程换算宽度、线路 → 中柱 → 出口、线路铺开、出口居中展开、待命虚线、停用变淡、粒子）；直连在多线路下不再显示成「direct」；三张卡片等高并改用设计稿文案；工具栏加「分流 / 叠加 / 主备」，电源改成按钮；副标题「N 条线路 · 聚合方式 · 经服务器」。合并主干后卡片里多了决策 21 的两个开关（见修订）。
- 卡在哪：2026-11-19 应作者要求合入主干并装到 /Applications（build 20261119120557）。真实窗口的概览截图看过一张（深色、1 条线路），布局与离屏渲染一致；D8 其余各项（浅色、多线路、待命虚线、窄窗口、减弱动态效果）与 D9 仍等作者看。D9 实测未达标，见 `perf-flow-animation`。
- 下一步：作者看过后，决定线路、聚合服务器、诊断、配置、连接、日志、设置这些页面以设计稿还是以 `docs/design/copy-and-style.md` §2 为准，再开卡。
