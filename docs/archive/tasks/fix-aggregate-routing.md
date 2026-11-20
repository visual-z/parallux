---
type: fix
status: done
weight: full
created: 2026-11-19
baseline: 6b3145c (gate: test 587p/0f, swift-test 94p/0f)
---

# 聚合出站绕过了自身：叠加时直连流量也进聚合服务器，并且分流、主备、计数从未真正生效

## 来源

2026-11-19 审查（顾问）指出两处，读 sing-box 源码后确认是同一个根因加一个配置错误。两处都是本会话引入的。

1. **聚合出站被路由器跳过**（`feat-links-aggregate` 引入，6472651）。`aggregate.Outbound` 实现了 `adapter.OutboundGroup`。sing-box 路由时 `resolveOutbound` 对 OutboundGroup 一路调用 `Selected()`，把链末端的出站拿去拨号（`route/route.go:178-195`，`route.go:169` 取 `chain[len(chain)-1]`）。所以聚合出站的 `DialContext` 根本不会被调用：
   - 分流只是 `Selected()` 不前进的「下一条」，实际上永远走同一条线路；
   - 主备没有失败重试（拨号失败不会换线路）；
   - 逐线路计数永远为 0（计数包在 `DialContext` 返回的连接上）；
   - 叠加的 bond 出站从不被拨号，只走线路。
   单元测试直接调 `DialContext`，绕过了路由器，所以没抓到。
2. **叠加时直连流量进了聚合服务器**（`feat-links-aggregate` 的组合器）。`ProfileComposer` 给替换用户 `direct` 的聚合出站也加了 `bond`，于是规则里写「直连」的流量（局域网、国内）也经 VPS 出去，且叠加协议本身不加密（PLAN §4、`feat-bond` 报告）。设计稿里直连与「东京 VPS → HK-03」是两个出口。

## 范围

- **独占：** `core/aggregate/`、`apple/ParalluxKit/Sources/ParalluxKit/Links/ProfileComposer.swift`、`apple/Parallux/Bond/AggregationServersView.swift` 的叠加说明文案、对应测试与夹具。
- **不碰：** `core/bond`；界面其他部分。

## 观测面

- Go：经 sing-box 真实路由器的端到端测试——用 `box.New` 起一个带 mixed 入站、聚合出站、两个假线路出站的实例，经入站发连接，断言哪个线路出站被拨号、计数是否增加。这条路径正是缺陷所在，单元测试直接调 `DialContext` 会再次绕过它。
- Swift：组合器输出里 `direct` 替换的聚合出站没有 `bond`。

## 环境假设

- 路由器只对实现 `adapter.OutboundGroup` 的出站展开 `Selected()`（`route/route.go:181`，2026-11-19 读源码确认）；不实现该接口的出站，路由器直接调用它的 `DialContext` / `NewConnection`。
- 不实现 OutboundGroup 的代价：界面的「节点」页不再把聚合出站列为分组（daemon 只列 OutboundGroup，`daemon/started_service.go:593-596`），这正好符合设计（线路在线路页）。
- 连接页的「出站链」只到聚合出站为止，不含实际线路；逐线路信息由 `LinkStatsJSON` 提供。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** 经 sing-box 路由器的连接会调用聚合出站的拨号：分流时两条连接分到两条线路，计数随之增加。
  - 检：test `TestRoutedConnectionsReachTheAggregateDialer`
- **D2** 经路由器时，主备的首选线路失败，连接改走下一条。
  - 检：test `TestRoutedFailoverSkipsAFailingLink`
- **D3** 叠加模式下，只有 `parallux-links` 聚合出站带 `bond`；替换用户 `direct` 的聚合出站按主备运行且不带 `bond`。
  - 检：test `bondModeKeepsDirectTrafficOffTheServer`
- **D4** 计数只因本卡新测试增加；不弱化既有测试；gate 全绿。
  - 检：cmd `keel gate`

## 设计

- `aggregate.Outbound` 不再实现 `adapter.OutboundGroup`（去掉 `All`、`Selected`、`AttachConnection`），保留 `adapter.Referrer`。依据见环境假设；SFM 和官方客户端都只把 selector / urltest 当分组。
- 组合器：`direct` 替换出站的模式在叠加时改为主备，不加 `bond`；`parallux-links`（节点的 detour）才带 `bond`。重新生成三个夹具并读 diff。
- 否决：保留 OutboundGroup 而让 `Selected()` 前进——`Selected()` 也被界面分组列表和 URL 测试历史调用，前进会搅乱轮转，并且仍然没有失败重试与计数。

## 验证命令

```bash
go test -race -count=1 ./core/aggregate/
scripts/swift-test.sh /tmp/r.xml bondModeKeepsDirect
keel verify-red docs/tasks/fix-aggregate-routing.md
keel gate --record docs/tasks/fix-aggregate-routing.md
```

## 证据

RED: f3e4507 -run ^TestRoutedConnectionsReachTheAggregateDialer$ ./core/aggregate/  # D1
RED: f3e4507 -run ^TestRoutedFailoverSkipsAFailingLink$ ./core/aggregate/  # D2
RED(swift): f3e4507 bondModeKeepsDirectTrafficOffTheServer  # D3

- RED 时的失败原文：D1 `balance through the router dialed link-a 2 and link-b 0 times, want one each`；D2 `dial through the box: socks5: request rejected, code=1`（首选线路失败后没有重试）；D3 `Expectation failed: direct["bond"] == nil`。
- 夹具 `composed-bond.json` 用生成器重写（`PARALLUX_WRITE_FIXTURES=1`），diff 只有 direct 那一项：去掉 `bond`，模式改为 `failover`；pxbridge 的 libbox 校验仍通过。
- 同时更正两处文案：线路页「不会断开正在进行的连接」不对——libbox `StartOrReloadService` 会关闭旧实例（`daemon/started_service.go:259-269`，读源码确认），连接会断开重连；聚合服务器页「直连流量在服务器之前是明文」随本修复不再成立。
GATE: d9db35aedb24+dirty ok tree:c3c11f35f4f8 build=0 vet=0 test=0[589p/0f] fmt=0 swift-test=0[95p/0f] apple-build=0 server-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-19)

## 修订

（无）

## 交接

- 做了什么：聚合出站不再是 OutboundGroup，路由器直接调用它的拨号；叠加只给节点的 detour 用，直连按主备走线路；更正两处文案。
- 卡在哪：无。手测随 `feat-links-aggregate` D10 与 `feat-bond-interface` D6。
- 下一步：无。
