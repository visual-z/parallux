---
type: fix
status: awaiting-author
weight: full
created: 2026-11-20
baseline: cfadb8a (gate: test 593p/0f, swift-test 141p/0f)
---

# 概览与路线图不再闪：节点有记忆地进出、顺序不动、宽度按占比

## 来源

2026-11-20 作者装上新版后反馈（附截图）：概览「图右边的线路会不断变动、一直闪烁」；「按流量显示的线最好按占比来分……连接频繁变动，按绝对大小显示体验不是特别友好」；路由「也会来回闪烁（因为会频繁变动），路线图完全看不出是什么」。截图里还有一个出口有速率却没有流带。

取证（2026-11-20，只读地从运行中的 App 的无障碍标签每秒读一次流向图，120 秒，夹具见 `FlowRecording`）：出口的集合在 119 步里变了 85 次，留下来的出口之间的顺序变了 34 次；同时显示的出口数在 1 到 5 之间跳。原因在三处，都是这几张卡之前就有的行为，被新的流向图放大了：

- `FlowSummary.exits` 每秒只取「此刻有速率的连接」，按速率排序，取前 4 个。于是出口每秒重新入选、重新排序。
- `FlowHold`（`feat-link-view`）只在「一个出口都没有」时保留上一幅图，对单个出口的进出不起作用。
- 路线图 `RouteMap.build` 每秒按速率给全部流量类别重新排序，行跟着速率上下跳；流带宽度按当次最大值换算。
- 宽度按「速率 ÷ 最近峰值量程」（`fix-overview-design-parity`）：流量小时整幅图只剩细线，连接一变就全图缩放。
- 截图里「有速率没流带」：线路速率来自网口计数、出口来自连接，两者口径不同；出口合计远小于线路时，那个出口的流带细到不画，但节点和数字还在。

## 范围

- **独占：** `apple/ParalluxKit/Sources/ParalluxKit/Interface/FlowStability.swift`（新增）、`SankeyLayout`（按占比的布局）、`FlowScale` 的用法；`apple/Parallux/Overview/FlowModel.swift`、`OverviewView` 里的 `HeldFlowDiagram`；`apple/Parallux/Routing/RoutingView.swift` 的路线图部分与 `RoutingModel`；对应测试。
- **不碰：** `FlowSummary.exits` 与 `RouteMap.build` 的既有行为和测试（它们仍是「此刻的快照」，平稳是在它们之上的一层）；`FlowHold` 与它的测试（不再被概览使用，留给 `feat-link-view` 的卡说明）；路由页的其余部分（检查器、分组视图）；`core/`。

## 不变量

- INV-10（新）：平稳后的节点集合里，已经显示的节点只在闲置超过保留时长后才离开，离开之前相对顺序不变；同一时刻节点数不超过上限 — 检查方式：property `flowSlotsKeepTheirPlaceWhileTrafficComesAndGoes`。

## 观测面

- 纯 Swift 返回值：`FlowSlots.update` 之后的节点序列与平滑后的速率；`SankeyLayout.make(…shares:)` 的几何；`RouteRows` 的行序。
- 录制夹具 `FlowRecording`（真实 App 的 120 秒）：断言平稳之后的变动次数。
- GREEN 被截断的方式：实现「永远不移除」也满足顺序不变——测试断言闲置超过保留时长后确实离开；实现「什么都不显示」满足变动次数为 0——测试断言每一秒有流量的出口都在显示里（除非被上限挤掉）；平滑系数取 0 也满足「不抖」——测试断言持续的流量在若干秒内达到真实值的九成。

## 环境假设

- 概览与路由页的数据每秒到一次（`statusInterval` 1 秒，`feat-m2-interface` 已对拍）；连接事件流在流量变化时每秒也到。平稳模型按「每次更新带上时间」写，不假设间隔恰好是 1 秒。
- 夹具的来源是无障碍标签里格式化过的文字（「2.1 Mbps」「736 bps」），精度是两到三位有效数字；对「集合与顺序是否变化」的断言足够，对速率数值的断言不用它。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** INV-10：任意进出序列（含空、一个节点、超过上限）下，已显示的节点在闲置不超过 `FlowSlots.retention` 时不离开，超过后离开；留下的节点之间相对顺序不变（新节点排在后面）；节点数不超过上限，超出时先让闲置最久的离开，仍超出时把速率最小的并入「其他」；「其他」始终在最后。
  - 检：property `flowSlotsKeepTheirPlaceWhileTrafficComesAndGoes`
- **D2** 速率平滑：持续不变的输入在 5 次更新内达到它的九成以上并且不超过它；输入归零后数值单调下降；单次尖峰（一秒的 100 倍）之后的显示值不超过尖峰的一半。
  - 检：test `flowSlotsSmoothRatesWithoutLag`
- **D3** 对真实录制（`FlowRecording`，120 秒）：经平稳之后，留下来的出口之间的顺序变化为 0 次；出口集合变化的步数不超过原始的四分之一（原始 85 次）；每一秒里有速率的出口要么在显示里，要么已并入「其他」。
  - 检：test `theRecordedFlowIsSteadyAfterSmoothing`
- **D4** 按占比的布局：给了 `shares` 时，有流量的一侧总是占满可用高度（节点间距之外），每个节点的高度等于它在本侧的占比 × 这段高度，与速率的绝对值和量程无关（全部速率同乘任意正数，布局不变）；每个有速率的节点不矮于 `SankeyLayout.thinnestShare`（按比例从别的节点让出），所以有速率就一定有可见的流带；INV-3（左右等高、节点 = 流带之和）仍成立；没有流量时没有流带。
  - 检：property `shareLayoutFillsTheHeightAndIgnoresAbsoluteRates`
- **D5** 路线图的行序：行按配置里的规则顺序排（`route.final` 最后），不随速率变化；有过流量的行与没有流量的行分成两段，行在两段之间的移动也经过同样的保留时长（刚断流的行不会立刻掉到下面）；上限与合并规则同 `RouteMap`。
  - 检：test `routeRowsKeepProfileOrderAndOnlyMoveAfterRetention`
- **D9** 粒子的疏密表达绝对速率（宽度改成占比之后，绝对快慢只剩它和数字）：没有流量为 0；有流量至少有一点；100 Mbit/s 及以上为满；对速率单调不减；100 Kbit/s 与 100 Mbit/s 相差 3 到 20 倍；粒子的生成量与它成正比。
  - 检：test `particleDensityFollowsTheAbsoluteRate`
- **D6** 计数：测试数只因本卡新增的测试而增加（基线 swift-test 141）。
  - 检：cmd `keel gate`
- **D7** 不弱化既有测试。
  - 检：cmd `keel assert-guard --card docs/tasks/fix-flow-stability.md`
- **D8** 作者看真实窗口：概览右侧的出口不再每秒换位置、进进出出；流量小的时候图也是满的，宽窄看得出各自占多少；有速率的出口都有流带；路线图的行不再上下跳，看得出哪类流量走哪个出口。
  - 检：author 打开概览与路由 › 路线图各看 30 秒

## 设计

- **一层有记忆的「槽位」模型，概览和路线图共用。** `FlowSlots`：按出现顺序给节点分配位置，闲置超过保留时长才收回；速率做指数平滑。它不关心节点是什么（出口、流量类别都行）。`FlowSummary.exits` 与 `RouteMap.build` 仍然只回答「此刻」，不改。否决：在这两个函数里各自加记忆——两套实现，两种手感。
- **顺序按「先来先占位」，不按速率。** 按速率排序正是闪烁的来源：两个速率接近的出口每秒互换位置。看哪个大，宽度已经说了。否决：按平滑后的速率排序（仍会换位，只是慢一点）；按名称排序（新节点会插到中间，把别的挤开）。
- **保留时长 15 秒、平滑时间常数约 2 秒：假设值。** 网页加载之间的空闲通常几秒（`feat-link-view` 记录的是 1–3 秒）；15 秒内再来流量的出口不该闪走。测量方法：对 `FlowRecording` 试 5 / 10 / 15 / 30 秒，数集合变化的步数，写进证据。
- **宽度按占比（作者定）。** 整幅图永远占满；绝对快慢由中柱上的总速率数字和流量卡片的曲线表达。这推翻了 `fix-overview-design-parity` 里「按量程换算、小流量就是细带」的设计（那是照设计稿演示的理解，作者实际用过之后不要）；`FlowScale` 不再用于概览的宽度。
- **两侧口径不一致时**：左右各按自己的占比铺满（左侧按线路速率占比，右侧按出口速率占比），中柱等于共同的高度；不再让「出口合计小于线路」把右侧压成细线。数字仍然各显示各的真实值。
- **路线图**：行序跟配置走（用户写规则的顺序，也是内核匹配的顺序），活跃的一段在上。流带宽度按占比的平方根换算并设上下限，保持「细的也看得见、粗的不盖住别人」。

## 验证命令

```bash
scripts/swift-test.sh /tmp/stab.xml 'flowSlots|theRecordedFlowIsSteady|shareLayoutFills|routeRowsKeepProfileOrder'
keel verify-red docs/tasks/fix-flow-stability.md
keel gate --record docs/tasks/fix-flow-stability.md
```

## 证据

RED(swift): 24182d8 flowSlotsKeepTheirPlaceWhileTrafficComesAndGoes  # D1
RED(swift): 24182d8 flowSlotsSmoothRatesWithoutLag  # D2
RED(swift): 24182d8 theRecordedFlowIsSteadyAfterSmoothing  # D3
RED(swift): 24182d8 shareLayoutFillsTheHeightAndIgnoresAbsoluteRates  # D4
RED(swift): 24182d8 routeRowsKeepProfileOrderAndOnlyMoveAfterRetention  # D5
RED(swift): d5999131dab0 particleDensityFollowsTheAbsoluteRate  # D9

- RED 时的失败原文：D1 `Expectation failed: ids(one) == ["a"]`；D2 `Expectation failed: steady.slots.first.rate`；D3 `Expectation failed: shown.contains(item.id) || hasOther`；D4 `Expectation failed: idle.left.count == 2 && idle.right.count == 1`；D5 `Expectation failed: rows.idle == order`；D9 `Expectation failed: FlowParticles.intensity(bytesPerSecond: 0) == 0`（`keel snapshot` 的私有快照）。
- 冻结时的笔误：`routeRowsKeepProfileOrderAndOnlyMoveAfterRetention` 第一版在第 40 秒期望 `final` 仍在活跃段，而它最后一次有流量是第 17.5 秒，按 D5 早该移走——测试自相矛盾。实现之前发现，给那一步补上 `final` 的流量后修正了冻结提交（本会话自己的提交，未推送）；断言没有减少。
- 对录制的测量（一次性测试，量完删掉；119 步，App 当时画出来的集合变化 85 次、顺序变化 34 次）：平稳之后顺序变化都是 0。集合变化——4 个座位、保留 0 秒 83 次，5 秒 31 次，10 / 15 / 30 秒都是 21 次（剩下的来自新出口占用闲置座位，再延长保留没有用）；保留 15 秒时 5 个座位 9 次，6 个 12 次，7 个 13 次。概览因此用 5 个座位（`FlowModel.exitSeats`）。D3 的测试用的是 4 个座位，21 次，正好压在「不超过四分之一」的线上。
- 我写注释时先填了几个「测量值」，量过之后发现不对（15 秒写成了 14 次、30 秒写成 9 次），已改成实测数字。
- 渲染对拍（仓库外的脚本，离屏）：作者截图那种情况（一条线路 24 Kbps，两个出口 12 / 5.8 Kbps，再加一个 0 bps 的）——图铺满、两个有速率的出口都有流带、0 bps 的只有节点、粒子稀疏；设计稿数字的满载图粒子密。
- 没有验证的：真实 App 里的样子。路线图的行与两栏布局只编译过（它依赖 App 的数据，脚本渲染不了）。
- 更正（2026-11-20，复查）：上一版这里写「默认窗口宽度下两栏放得下，是按宽度算的（两栏最少 150 + 56 + 150）」——算错了量。`ViewThatFits` 按分支的**理想**宽度选，而一栏的理想宽度是它最长的一行字（一条规则能列十几个规则集），调小最小宽度不改变选哪个分支；真实截图里走的正是退化成单列列表的那个分支。现在两栏的理想宽度钉在 150（与概览卡片同一个毛病，已写进 PLAYBOOK §11）。仍然没有在真实 App 里看到两栏。
- 按钮文字更正：「只显示有流量的规则」实际会留下有流量的行加上凑满 12 条的闲置行，改成「收起没有流量的规则」。
- 留下的两处死代码，等作者点头再删（删除要去掉既有测试，属于弱化）：`SankeyLayout.make(…capacity:)` 与 `FlowScale`（`fix-overview-design-parity` D1、D2；宽度改成占比之后没有生产调用点）；`FlowHold`（`feat-link-view` D4；概览改用 `FlowSlots` 之后没有生产调用点）。
GATE: 24182d895481+dirty ok tree:f26ad69057db build=0 vet=0 test=0[593p/0f] fmt=0 swift-test=0[147p/0f] apple-build=0 server-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-20)

## 修订

- D9 新增（加严）：按占比渲染后发现 24 Kbps 与几百 Mbps 的粒子一样密，绝对快慢看不出来；补一条判据与测试。2026-11-20。

## 交接

- 做了什么：新增 `FlowSlots`（节点先来先占位、闲置 15 秒才让位、速率平滑）与 `RouteRows`（行按配置顺序、分有流量 / 无流量两段、换段要过保留时长）；概览的出口与路线图的行都改用它们，并且每秒采样一次，不再随每次连接变化重算。流向图的宽度改成占比（两侧各自铺满），粒子的疏密表达绝对速率。路线图：流带宽度按占比、颜色跟规则走、两栏的最小宽度调小、超过 12 条的无流量规则折叠成一个按钮。
- 卡在哪：等作者看真实窗口（D8）；两处死代码等作者决定（见证据）。
- 下一步：装上之后在真实 App 里录一次，数集合与顺序的变化，和这次的 85 / 34 对比。
