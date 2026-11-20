---
type: fix
status: awaiting-author
weight: full
created: 2026-11-20
baseline: a93301acc513 (gate: test 594p/0f, swift-test 152p/0f)
---

# 概览：卡片贴底、流向图随窗口伸缩、图上是「从哪进来 → 走了哪条规则 → 从哪个节点出去」

## 来源

2026-11-20 作者看了装上的新版（附截图与一张参考图）：「空白区域有点太多了」——

1. 下面的三张卡片应该始终在最下面；
2. 流向图应该有响应式；
3. 图的逻辑：左边是流量从哪进来，中间是走了哪条规则，最后从哪个节点出去。参考图是一张多栏桑基图（来源 → 节点 → 入站 → 分类 → 主机），作者说场景不同，不必一样。

截图里：流向图固定 330 pt 高，三张卡片紧跟在下面，窗口下半是空的；图是「线路 → 汇流柱 → 出口」，中间那一栏只是一根柱子，不表达任何信息。

## 范围

- **独占：** `apple/Parallux/Overview/`（`OverviewView` 的版面、`FlowModel`、`FlowDiagram`、`FlowLayer` 的三栏支持）；`ParalluxKit` 里本卡新增的纯函数（`FlowColumns`、三栏布局）与测试。
- **不碰：** 面板里的迷你流向图（仍是两段：线路 → 出口，它只有 64 pt 高，放不下规则名）；`SankeyLayout` 两栏布局的既有行为与测试；路由页。

## 不变量

- INV-12（新）：三栏流向图里，每一栏的节点高度之和相等（都等于共同的高度），每个节点高度等于流经它的流带之和，每股流带在三处一样厚 — 检查方式：property `threeColumnFlowConservesWidthEverywhere`。

## 观测面

- 纯 Swift 返回值：`FlowColumns.make`（连接 → 三栏的节点与两段流）；`SankeyLayout.make(columns:)`（三栏几何）。
- 画出来的样子：仓库外脚本离屏渲染三栏图；装上之后在真实 App 里截图。
- GREEN 被截断的方式：所有流量都归到「其他」也能让守恒通过——测试断言前几大的规则与节点按名字出现，「其他」只收超出上限的部分。

## 环境假设

- libbox 的 `Connection.chain` 是倒序的出站链：sing-box `common/trafficcontrol/tracker.go` 的 `newTrackerMetadata` 对 `OutboundChain`（`route/route.go` 的 `resolveOutbound`：从规则选中的出站开始，逐层取分组当前的选择）做了 `slices.Reverse`，所以首项是最终节点、末项是规则选中的出站。`ConnectionRow.outbound` 是最终节点（同一函数里取 `OutboundChain` 的最后一项）。2026-11-20 读源码确认。
- 规则名：连接的 `rule` 字段与配置规则的匹配沿用 `RouteMap.classes`（`fix-flow-stability`）；`rule` 为空即 `route.final`。
- 「从哪进来」：每条连接没有记录走的是哪条线路（`design-additions.md` 里的待做项），所以左栏是**线路**，线路到规则的分配按各线路的速率占比分摊（同现在的「线路 → 出口」）。这一点写进界面说明之前先告诉作者。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** 三栏的数据：按连接把流量归到「规则」（配置里的规则名；`route.final` 为「其余流量」）与「节点」（连接的最终出站；直连类为「直连」）；规则与节点各自按速率取前几个，其余并入「其他」；规则 → 节点的每一股等于同时属于两者的连接速率之和；没有速率的连接不计入；所有股之和等于计入的连接速率之和。
  - 检：test `flowColumnsGroupConnectionsByRuleAndNode`
- **D2** INV-12：三栏布局对任意输入（0 股、1 股、多股，含 0 速率）——每栏都铺满同一高度（扣去该栏的间距之后取三栏中最小的那段），节点不越出绘图区，同栏相邻间距不小于 `gap`，每个节点等于流经它的流带之和，每股流带在左、中、右三处一样厚，中栏节点的入流与出流相等；没有流量时没有流带。
  - 检：property `threeColumnFlowConservesWidthEverywhere`
- **D6** 三栏拆成连续的流带：每股流带从一条线路经一条规则到一个节点，在三处一样厚；每个节点（三栏都是）恰好被经过它的流带铺满；没有线路流量或没有规则流量时没有流带；流带的标识唯一；流量大的规则不画得比流量小的细。
  - 检：property `threeColumnBandsRunFromLinkThroughRuleToNode`
- **D7** 规则名取自连接的 `rule` 字段：空为「其余流量」，规则集用中文名（`TrafficLabel` 的同一张表），私有地址为「局域网」，域名与进程同路由页的写法；认不出的条件显示条件本身，不编「规则 N」。
  - 检：test `connectionRulesReadAsTrafficClasses`
- **D8** 规则柱按规则着色（作者 2026-11-20 要求）：同时显示的规则颜色互不相同；一条规则在屏上期间颜色不变；离开的规则让出颜色，给下一条新规则用；「其他」不占颜色（中性灰）；规则多于颜色时颜色循环使用，不崩溃；没有调色板时不着色。
  - 检：test `rulesKeepDistinctStableColours`
- **D3** 计数：测试数只因本卡新增的测试而增加（基线 swift-test 152）。
  - 检：cmd `keel gate`
- **D4** 不弱化既有测试。
  - 检：cmd `keel assert-guard --card docs/tasks/fix-overview-layout-and-flow.md`
- **D5** 作者看真实窗口：三张卡片始终贴在窗口底部；流向图占满卡片之上的全部高度，随窗口变高变矮、变宽变窄；图上是三栏（线路 → 规则 → 节点），规则栏写的是规则名；窗口最矮时（520 pt）图仍可读、卡片不被挤掉。
  - 检：author 拖动窗口大小看概览

## 设计

- **版面：卡片贴底，图填满其余。** 概览不再整体放在 ScrollView 里：卡片行固定在底部，流向图取剩下的全部高度（不低于 `minimumDiagramHeight`），窗口很矮时才让整页滚动。图的宽度本来就随窗口，高度现在也随。
- **三栏的数据从连接来。** 每条连接自带命中的规则与最终出站，一次遍历就能分好；规则名复用 `RouteMap.classes`。左栏仍是线路——连接不记录线路，线路到规则按速率占比分摊；这是近似，图例写明。
- **布局：一个通用的多栏函数。** `SankeyLayout.make(columns:links:)`：任意栏数、每栏的节点、相邻两栏之间的流。概览用三栏；面板的迷你图仍用两栏的旧函数。
- **平稳**：规则栏与节点栏各用一份 `FlowSlots`（`fix-flow-stability`），先来先占位、闲置 15 秒才让位。
- 否决：照参考图做五栏（来源 IP、节点、入站、分类、主机）——参考图是服务端视角，Parallux 的入站只有一个（TUN），来源都是本机；把主机放进来会让右栏有上百个节点。

## 验证命令

```bash
scripts/swift-test.sh /tmp/overview3.xml 'flowColumnsGroupConnectionsByRuleAndNode|threeColumnFlowConservesWidthEverywhere'
keel verify-red docs/tasks/fix-overview-layout-and-flow.md
keel gate --record docs/tasks/fix-overview-layout-and-flow.md
```

## 证据

RED(swift): c8db15d flowColumnsGroupConnectionsByRuleAndNode  # D1
RED(swift): c8db15d threeColumnFlowConservesWidthEverywhere  # D2
RED(swift): 95326ff65dcc threeColumnBandsRunFromLinkThroughRuleToNode  # D6
RED(swift): 95326ff65dcc connectionRulesReadAsTrafficClasses  # D7
RED(swift): bf822389fcca rulesKeepDistinctStableColours  # D8

- RED 时的失败原文：D1 `Expectation failed: result.rules.map(\.name) == ["youtube", "cn", TrafficLabel.finalName, FlowSummary.otherName]`；D2 `Expectation failed: layout.columns.map(\.count) == counts`；D6 `Expectation failed: layout.left.count == linkCount && layout.middle.count == ruleCount && layout.right.count == nodeCount`；D7 `Expectation failed: TrafficLabel.name(connectionRule: "") == TrafficLabel.finalName`（D6、D7 是 `keel snapshot` 的私有快照）。
- D8 冻结前的无效尝试：第一版测试在桩实现下标越界、进程崩溃（崩溃不算红），改成先 `#require` 后重新取了快照。离屏渲染看过浅色与深色：每条规则一种颜色，「其他」为灰。
- 实现中的一次错误：多栏布局第一版为了让「两侧口径不一致」时也守恒，把每股流带取成两端中较细的那一端——这让节点不再等于流经它的流带之和，违反了冻结的 D2，测试抓到了。改成全图一个尺度、两段的总量在数据层对齐（线路 → 规则按线路占比分摊规则的流量）。
- 渲染对拍（仓库外脚本，离屏，GPU 渲染器画进纹理再叠回页面）：804×640 与 1100×820 两种窗口下，三栏图填满卡片以上的高度，卡片贴底；线路 → 规则 → 出口的流带连续，流带按线路着色。
- 真实窗口（2026-11-20，装上的 build 20261120030257，深色，两条线路）：三栏图与贴底的卡片都在；发现节点标签写的是瞬时速率、宽度用的是平滑后的速率，所以有流带的规则写着「0 bps」——改成标签也用平滑后的速率。
- 没有验证的：窗口最矮（520 pt）时的样子（脚本里 560×470 的那次图被压到 240 pt、整页需要滚动，没有截下来看）；规则标签的底板在流带上的观感。
- 左栏是线路，不是「流量从哪来的那条线路」：连接不记录走的是哪条线路，所以线路 → 规则是按线路占比分摊的近似；只有一条线路时没有差别。
GATE: c8db15da54fb+dirty ok tree:2b22c0095c4e build=0 vet=0 test=0[594p/0f] fmt=0 swift-test=0[157p/0f] apple-build=0 server-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-20)
GATE: e5eb210196fb+dirty ok tree:f807e364f6b4 build=0 vet=0 test=0[594p/0f] fmt=0 swift-test=0[157p/0f] apple-build=0 server-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-20)
GATE: e3da9e68a84b+dirty ok tree:8adf85a27b0f build=0 vet=0 test=0[594p/0f] fmt=0 swift-test=0[160p/0f] apple-build=0 server-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-20)

## 修订

- D8 新增（加严）：作者要求中间一栏也按颜色区分规则（2026-11-20）。
- D6、D7 新增（加严）：动工时为了复用现有的 GPU 层与粒子，把三栏布局拆成连续的流带，并新增从连接的规则字段取名的函数；两者都是新的纯逻辑，各补一条判据与测试。2026-11-20。

## 交接

- 做了什么：概览的卡片贴在底部，流向图填满上面的全部高度并随窗口伸缩；图改成三栏——线路 → 规则（规则名取自每条连接命中的规则）→ 出口节点，每栏有标题；面板的迷你图仍是两栏。
- 卡在哪：等作者看真实窗口（D5）。
- 下一步：按作者的意见调。
