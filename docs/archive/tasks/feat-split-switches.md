---
type: feat
status: awaiting-author        # todo | doing | blocked | awaiting-author | done
weight: full
created: 2026-11-19
baseline: 1a8663637d10
---

# 聚合与代理是两个独立开关

## 来源

作者 2026-11-19：「我们的聚合跟代理应该两个独立的开关，可以手动选择是否打开。」我提出的语义，作者已确认（「是这个意思」）：

- 只开聚合：所有流量直连，但分到多条线路。
- 只开代理：按配置走节点，只用默认线路。
- 两个都开：即现有行为。
- 两个都关：断开。

同一轮还发现：选了「叠加」但没有聚合服务器时，会静默按主备运行，界面上只有流向图中间写着「主备」，作者因此以为叠加坏了。本卡一并把这个提示补上。

竞品对照（2026-11-19 检索）：
- Clash Verge Rev 把「系统代理」和「TUN 模式」做成两个独立开关，路由模式（规则 / 全局 / 直连）另外再选。
- Speedify 的 Bypass / App Bypass 会把流量连同加密和聚合一起绕过（support.speedify.com/article/943-app-bypass），没有「聚合但不加密」的组合。

所以「只聚合」由 Parallux 自己定义：把直连流量交给聚合出站。

## 范围

- **独占：** `apple/ParalluxKit/Sources/ParalluxKit/Interface/ConnectionSwitches.swift`、`Links/DirectProfile.swift` 及其测试；`AppModel` 的连接与重载路径；`PanelView` 头部；`MainWindow` 工具栏；`AppDelegate` 右键菜单；`OverviewView` 的未连接空态；`CONTEXT.md`；`PLAN.md` 的决策表。
- **不碰：** 内核与扩展；ProfileComposer 的改写规则；按需连接规则；聚合方式的三种取值。

## 观测面

- 开关逻辑是纯函数 `ConnectionSwitches.toggle`：输入当前开关、隧道是否在运行、拨动哪一个、拨到开还是关；输出新开关和要执行的动作（连接 / 重载 / 断开 / 无）。用 property 测试穷举全部输入。
- 「只聚合」用的配置是纯函数 `DirectProfile.make(from:)` 的输出，测试检查出站、路由与 tun 入站。再把它交给 `ProfileComposer.compose`，检查所有流量最终落在聚合出站上。
- 叠加退回主备的提示是纯函数 `AggregationNotice.text`。

## 环境假设

- sing-box 允许 `startOrReloadService` 用另一份配置热重载：现有 `TunnelController.reload` 已经在用，切换聚合方式时实测可行（fix-stream-reconnect 冒烟，2026-11-19 14:44）。
- 只聚合时，用户配置里的 DNS 服务器可能经由代理节点出去（`detour`）。所以 DirectProfile 不沿用用户的 dns 节，改用 `local`，与随附的 sample-profile 一致。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** 开关：隧道未运行时两个开关都显示为关；拨动后的结果只由「显示状态 + 这一次拨动」决定。两个都关时断开；未运行时打开任意一个就连接，而且只开刚拨的那一个；运行中拨动且至少一个仍开时重载；没有变化时什么也不做。「启动」（菜单、工具栏、URL、按需连接）沿用上次的开关组合，上次两个都关则两个都开。
  - 检：property `switchTogglesAreDecidedByWhatIsShown`
- **D2** 只聚合的配置：只有一个 `direct` 出站，`route.final` 是它；有 tun 入站，形状沿用用户配置里的 tun 入站（缺失或不是 JSON 时用默认）；规则只有 sniff 与 hijack-dns；DNS 只用 `local`。交给 ProfileComposer、带两条线路组合后，`direct` 被替换成聚合出站。
  - 检：test `aggregationOnlyRoutesEverythingDirectThroughTheLinks`
- **D3** 叠加的提示：选了叠加、实际按主备运行时，给出「尚未设置聚合服务器，暂按主备运行」；其他情况（选的方式就是实际方式，或线路不足两条）不给提示。
  - 检：test `bondWithoutServerSaysItRunsAsFailover`
- **D4** 计数只因本卡新测试增加；不弱化既有测试；gate 全绿。
  - 检：cmd `keel gate`
- **D5** 作者手测：面板和概览里有「聚合」「代理」两个开关，四种组合都按上面的语义工作，运行中拨动不断线；选了叠加但没有服务器时，聚合方式下面有提示。
  - 检：author 统一手测

## 设计

- `ConnectionSwitches { aggregation, proxy }` 存在 `LinkSettings` 里（新键，缺省两个都开；旧数据解码为两个都开，等于现有行为）。
- 显示状态 = 运行中 ? 存储的开关 : 两个都关。未运行时打开一个只开这一个，是为了「看到什么就是什么」：否则打开代理，上次留下的聚合也会悄悄打开。
- 连接内容：代理开 → 用户配置；代理关 → `DirectProfile.make(from: 用户配置)`。聚合开 → 启用的线路交给 ProfileComposer；聚合关 → 不交线路（不足两条时 compose 原样返回，走系统默认路由）。
- 工具栏的电源按钮和右键菜单的「启动 / 停止」保留，作为总开关，沿用上次的组合（D1）。
- 只有一条线路时，聚合开关禁用，并说明需要两条线路。
- 否决：把「只代理」实现为 clash mode 切换。clash mode 是配置自己的规则，有的配置根本没有直连模式，靠不住。

## 验证命令

```bash
scripts/swift-test.sh /tmp/t.xml ConnectionSwitches
keel verify-red docs/tasks/feat-split-switches.md
keel gate --record docs/tasks/feat-split-switches.md
```

## 证据

RED(swift): be0f96a switchTogglesAreDecidedByWhatIsShown  # D1
RED(swift): be0f96a aggregationOnlyRoutesEverythingDirectThroughTheLinks  # D2
RED(swift): be0f96a bondWithoutServerSaysItRunsAsFailover  # D3

- 冒烟（2026-11-19 14:58，签名构建，分流方式，两条线路）：
  - 两个都开：baidu 200，google 200。
  - 关掉代理（只聚合）：隧道保持 Connected，窗口标题「已连接 · 分流 · 2 条线路」，baidu 200，google 000（直连，符合预期）。
  - 再打开代理并关掉聚合（只代理）：标题「已连接 · 1 条线路（有线）」，google 200。
  - 再关掉代理（两个都关）：标题「概览 – 未连接」，`scutil` 显示 Disconnected。
  - 未连接时只打开聚合：连上，标题「已连接 · 分流 · 2 条线路」，日志里新连接在 `link-en0` 与 `link-en7` 之间轮流。
- 冒烟时还发现流向图每条线路的速率不对：一条有流量，另一条显示 0。根因在 `LinkRates.rates`，按标签合并多个聚合出站时互相覆盖；与本卡无关，另开 fix-link-rates-across-groups。
GATE: 786c8c67b6a4+dirty ok tree:ea0d0ea09b12 build=0 vet=0 test=0[590p/0f] fmt=0 swift-test=0[117p/0f] apple-build=0 server-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-19)

## 修订

- 设计细化：面板头部原来的总开关去掉，改为「聚合」「代理」两行开关（面板里三个开关会让人分不清）；总开关仍在工具栏的电源按钮和右键菜单的「启动 / 停止」。不涉及完成定义的改动。

## 交接

- 做了什么：ConnectionSwitches、DirectProfile 与叠加提示；面板、概览（模式卡片和未连接空态）、右键菜单都接上两个开关；签名构建已实测四种组合。
- 卡在哪：等作者手测 D5。
- 下一步：fix-link-rates-across-groups。
