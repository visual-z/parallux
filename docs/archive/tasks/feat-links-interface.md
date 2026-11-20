---
type: feat
status: awaiting-author
weight: full
created: 2026-11-19
baseline: 4ef2681 (gate: test 17p/0f, swift-test 57p/0f)
---

# 线路页、面板线路区、概览多线路流向图接上真实线路，聚合方式开关生效

## 来源

PLAN M3「线路发现与开关、每线路速率统计、面板与主窗口流向图接真实数据」；设计稿「线路」页（开关、拖动排序、仅备用、同一公网出口提示）、面板线路区、概览流向图左列每条线路一股；决策 16。`feat-links-aggregate` 提供了内核侧。

## 范围

- **独占：** `apple/Parallux/Links/`、`apple/ParalluxKit/Sources/ParalluxKit/Links/LinkSettings.swift`、`AppModel.swift` 的连接与线路部分、`PanelView.swift` 的线路与聚合方式区、`Overview/FlowDiagram.swift` 的 `FlowModel`、`MainWindow.swift` 的线路页、`AppDelegate.swift` 的右键菜单线路与聚合方式项、`Settings/SettingsView.swift` 的聚合标签、对应测试。
- **不碰：** `core/`；扩展；`Settings/HelperSettingsSection.swift`（并行卡）；聚合服务器页（`feat-bond-interface`）。

## 观测面

- 纯函数：`LinkSettings` 的编解码与默认值；`LinkFlow.columns`（把线路速率与出口汇总成流向图的两列）；`SharedEgress.warning`（同一公网出口提示）。
- 界面：作者手测。
- GREEN 被截断的方式：流向图在只有一条线路时退回旧逻辑——测试分别跑 0、1、3 条线路。

## 环境假设

- `SCNetworkInterfaceCopyAll` 在非沙盒 App 里返回 BSD 名、类型与本地化显示名（SystemConfiguration 文档；App 未开沙盒，见 `feat-profiles` 的对拍）。待手测：iPhone USB 共享的显示名含「iPhone」。
- 线路的公网出口用扩展内探针（`LinkProbe` 的 trace）取得，所以「同一公网出口」提示只在隧道连接后、跑过一次探针才有数据。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** 线路设置（顺序、停用、仅备用、聚合方式、叠加用的服务器 id）存到 UserDefaults 再读回一致；缺字段用默认值（聚合方式默认叠加，与 AppSettings 一致）。
  - 检：test `linkSettingsRoundTripWithDefaults`
- **D2** 流向图两列：左列每条启用线路一个节点（速率来自逐线路统计），右列出口汇总；0 条线路没有左列，1 条线路时整股来自它，3 条时三股。
  - 检：test `flowColumnsFollowTheLinks`
- **D3** 两条以上线路的公网出口相同时给出提示，点名这些线路；出口不同或未知时不提示。
  - 检：test `sharedEgressIsReportedByName`
- **D4** 计数只因本卡新测试增加；不弱化既有测试；gate 全绿。
  - 检：cmd `keel gate`
- **D5** 作者手测：线路页列出 Wi‑Fi、有线、iPhone USB 共享；开关、拖动排序、仅备用改动后重连生效；面板与右键菜单能切聚合方式（分流、主备；叠加在没有聚合服务器时提示先添加）；概览流向图左列每条线路一股、宽度随下载变化。
  - 检：author 统一手测

## 设计

- **发现**：`LinkMonitor`（App）用 `getifaddrs` 取 flags 与 IPv4、`SCNetworkInterfaceCopyAll` 取类型与显示名，交给 `LinkInventory.classify`；NWPathMonitor 只作「有变化」的信号，再整体重读（mqvpn 记录的单路径问题不影响我们）。
- **连接**：`AppModel.connect` 读出配置后经 `ProfileComposer.compose(启用线路, 备用, 聚合方式, 叠加)`；少于两条线路时原样。线路设置或聚合方式变化时，已连接则用 `handleAppMessage` 重载（扩展已支持），不断开隧道。
- **统计**：`LinkStatsPoller` 连接时每秒经 XPC 取 `linkStats`，`LinkRates` 算速率；页面与流向图读它。
- 否决：每次切换聚合方式都断开重连（会断掉正在进行的连接；reload 是 sing-box 的原生做法）。

## 验证命令

```bash
scripts/swift-test.sh /tmp/li.xml LinkSettings
keel verify-red docs/tasks/feat-links-interface.md
keel gate --record docs/tasks/feat-links-interface.md
```

## 证据

RED(swift): 84d436e linkSettingsRoundTripWithDefaults  # D1
RED(swift): 84d436e flowColumnsFollowTheLinks  # D2
RED(swift): 84d436e sharedEgressIsReportedByName  # D3

- RED 时的失败原文：D1 `Expectation failed: LinkSettings.load(from: defaults) == changed`；D2 `Expectation failed: three.left.map(\.id) == ["en0", "en7", "en8"]`；D3 `try #require(SharedEgress.warning(...))` 为 nil。
- 范围外改动：`StatusLine` 加多线路文案（加了一条断言，未改既有断言）；`AppSettings.notifyLinkChanges`（设计稿「线路掉线时通知」）。
GATE: 84d436ec6e25+dirty ok tree:655cf0b2ae43 build=0 vet=0 test=0[17p/0f] fmt=0 swift-test=0[60p/0f] apple-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-19)

## 修订

（完成定义无改动。）

- 冻结提交 146db0d 里 `flowColumnsFollowTheLinks` 在桩实现下越界崩溃，崩溃不算红；把一处 `#expect` 改成 `#require`（同一断言，失败时停止而不是继续索引），重新冻结于下一提交。

## 交接

- 做了什么：线路发现（getifaddrs + SystemConfiguration）；线路页（开关、拖动排序、仅备用、健康与速率、同一出口提示）；面板线路区可点开关、聚合方式可切；右键菜单线路与聚合方式可用；概览流向图每条线路一股；线路或方式变化时重载内核（隧道不断，但正在进行的连接会断开重连，见 `fix-aggregate-routing`）；线路掉线通知。
- 卡在哪：等统一手测 D5。
- 下一步：合入 `feat-bond` 分支，做聚合服务器页与叠加接入（`feat-bond-interface`）。
