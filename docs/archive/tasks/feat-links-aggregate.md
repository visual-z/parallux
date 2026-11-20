---
type: feat
status: awaiting-author
weight: full
created: 2026-11-19
baseline: 30d9908 (gate: test 9p/0f, swift-test 49p/0f)
---

# 分流与主备真正生效：线路健康检查、选线顺序、逐线路统计，以及把线路写进用户配置的组合器

## 来源

PLAN M3「线路发现与开关、按网口绑定出站、每线路速率统计」，决策 13（线路出站 + 聚合出站）与决策 16（不等手测，照决策 13 做）。目标里的「主备在 2 秒内把新连接切到其他线路」。

## 范围

- **独占：** `core/aggregate/`、`core/pxbridge/`（新增导出）、`apple/ParalluxKit/Sources/ParalluxKit/Links/`（新增文件）、`apple/ParalluxKit/Sources/ParalluxKit/Tunnel/TunnelXPC.swift`（新增 `linkStats`）、`apple/PacketTunnel/CommandXPCService.swift`、对应测试。
- **不碰：** `core/bond`（并行的 `feat-bond`）；辅助服务（并行的 `feat-helper-service`）；界面（`feat-links-interface`）。

## 不变量

- INV-4：任意模式、任意健康状态下，选线顺序是全部线路的一个排列；有健康的非备用线路时，第一条一定是健康的非备用线路 — 检查方式：property `TestLinkOrderIsAPermutationThatStartsHealthy` + 代码断言。
- INV-5：组合后的配置里，用户原有的每个出站 tag 都还在（direct 被替换为同 tag 的聚合出站），没有出站的 detour 指向不存在的 tag — 检查方式：property `composingKeepsEveryTagAndNoDanglingDetour`。

## 观测面

- Go：`linkOrder` 纯函数的返回值；`Outbound` 的拨号经过哪条线路（测试用假线路出站记录调用）；`pxbridge.LinkStatsJSON()` 的内容。
- Swift：`ProfileComposer.compose` 输出的 JSON 结构；`LinkInventory` 的分类结果。
- GREEN 被截断的方式：健康检查从不运行而测试只看初始状态——测试用可控的假拨号器让探测失败，断言状态在上限时间内翻转；组合器遇到不认识的出站直接返回原配置——测试断言输出里有线路出站。

## 环境假设

- sing-box `direct` 出站不接受 `detour`（2026-11-19 对拍：`libbox.CheckConfig` 返回 `` `detour` is not supported in direct context ``）。所以直连流量不能经 detour 进聚合，只能把用户的 direct 出站替换成同 tag 的聚合出站。
- `bind_interface` 按名字经 `net.Interfaces()` 解析（`route/network.go:274-286`、sing `bind_darwin.go`），网口不存在时拨号立刻失败，不会等超时。
- 健康探测目标默认 `223.5.5.5:53` 与 `1.1.1.1:443`，任一能连上即健康。假设：在中国大陆与境外都至少有一个可达；作者手测时验证，必要时改默认值。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** INV-4：主备按优先级排健康的非备用线路，然后健康的备用线路，最后不健康的；分流在健康的非备用线路之间轮转，全部健康时 n·k 次里每条线路恰好排第一 k 次。
  - 检：property `TestLinkOrderIsAPermutationThatStartsHealthy`
- **D2** 一条线路的探测失败后，在 2 秒内被标为不健康，新连接改走下一条；恢复需要连续 2 次成功。
  - 检：test `TestAFailingLinkIsMarkedUnhealthyWithinTwoSeconds`
- **D3** 经聚合出站的连接按线路计入收发字节与活跃连接数；`LinkStatsJSON` 输出每个聚合出站每条线路的统计。
  - 检：test `TestTrafficIsCountedPerLink`
- **D4** 叠加模式要求 `bond` 指向一个出站；拨号先走它，失败时按主备顺序退回线路。
  - 检：test `TestBondModeFallsBackToTheLinksWhenTheBondOutboundFails`
- **D5** `backup` 必须是 `links` 的子集，否则报错写明 tag。
  - 检：test `TestAggregateRejectsABackupLinkThatIsNotALink`
- **D6** INV-5：组合器把启用的线路写成 `link-<网口>` 的 direct 出站（继承用户 direct 的拨号选项、覆盖 bind_interface），用同 tag 的聚合出站替换用户的 direct，给没有 detour 的代理节点加 detour 指向聚合出站；少于 2 条线路时不改写。
  - 检：property `composingKeepsEveryTagAndNoDanglingDetour`
- **D7** 组合后的配置能通过 libbox `CheckConfig`（三种模式各一份夹具）。
  - 检：test `TestComposedFixturesPassLibboxCheckConfig`
- **D8** 网口分类：Wi‑Fi、有线、iPhone USB 共享、其他；排除虚拟网口；显示名优先用系统给的。
  - 检：test `linkInventoryClassifiesInterfaces`
- **D9** 计数只因本卡新测试增加；不弱化既有测试；gate 全绿。
  - 检：cmd `keel gate`
- **D10** 作者手测：两条线路下，分流时连接页能看到连接分到两条线路；主备时拔掉首选线路，2 秒内新连接走另一条；线路页与概览的逐线路速率随下载变化。
  - 检：author 统一手测

## 设计

- **选线**：`linkOrder(mode, healthy, backup, cursor) []int` 纯函数；`Outbound` 在拨号时取快照调用它，依次尝试，失败的线路立即标记不健康。
- **健康检查**：每条线路一个 goroutine，每 1 秒经该线路出站 `DialContext` 探测目标（1 秒超时），一次失败即不健康、连续 2 次成功恢复；探测在 `Start` 开始、`Close` 停止。常量带 why；探测只有一个在途，不会堆积。
- **统计**：线路出站返回的连接包一层计数（原子计数，关闭时减活跃数）；包级注册表 `tag → *Outbound`，在 Start 注册、Close 注销。`pxbridge.LinkStatsJSON()` 返回 JSON（gomobile 只支持基本类型）。扩展 XPC 新增 `linkStats(reply:)`。
- **叠加**：`bond` 字段写出站 tag（`feat-bond` 的 multipath 出站）；先拨它，失败退回主备顺序，这样聚合服务器挂掉时仍能上网。
- **组合器**（ParalluxKit，纯函数）：输入用户配置 JSON、启用的线路（按优先级）、备用集合、模式、可选的叠加出站片段；输出新 JSON。否决：要求用户手写线路出站（设计稿要求开关即生效）。
- 否决：给每个节点 × 每条线路展开出站（决策 13 已否决）。

## 验证命令

```bash
go test -count=1 ./core/aggregate/ ./core/pxbridge/
scripts/swift-test.sh /tmp/links.xml Link
keel verify-red docs/tasks/feat-links-aggregate.md
keel gate --record docs/tasks/feat-links-aggregate.md
```

## 证据

RED: a17fe78 -run ^(TestLinkOrderIsAPermutationThatStartsHealthy|TestFailoverFollowsPriorityAndBalanceRotatesEvenly)$ ./core/aggregate/  # D1
RED: a17fe78 -run ^TestAFailingLinkIsMarkedUnhealthyWithinTwoSeconds$ ./core/aggregate/  # D2
RED: a17fe78 -run ^TestTrafficIsCountedPerLink$ ./core/aggregate/  # D3
RED: a17fe78 -run ^TestBondModeFallsBackToTheLinksWhenTheBondOutboundFails$ ./core/aggregate/  # D4
RED: a17fe78 -run ^TestAggregateRejectsABackupLinkThatIsNotALink$ ./core/aggregate/  # D5
RED(swift): a17fe78 composingKeepsEveryTagAndNoDanglingDetour  # D6
RED: a17fe78 -run ^TestComposedFixturesPassLibboxCheckConfig$ ./core/aggregate/  # D7
RED(swift): a17fe78 linkInventoryClassifiesInterfaces  # D8

- RED 时：冻结提交里 `linkOrder` 返回 nil、`probeLoop` 为空、计数不包装、bond 被拒、backup 不校验、组合器原样返回、夹具不存在，上述测试全部失败（`go test` 6 个失败、Swift 8 个失败）。
- D7 的实现中发现：用户配置里的 `domain_resolver: local` 要求 DNS 里有 `local`，测试用的用户配置补上了 `dns.servers`。叠加模式的夹具 `composed-bond.json` 需要 `multipath` 类型，等 `feat-bond` 合入后由 pxbridge 侧的测试检查；把 multipath 出站换成 direct 后，libbox 接受它（2026-11-19 临时对拍）。
GATE: 2e6f5c0314c3+dirty ok tree:56876a243533 build=0 vet=0 test=0[17p/0f] fmt=0 swift-test=0[57p/0f] apple-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-19)

## 修订

（无）

## 交接

- 做了什么：选线纯函数（主备、分流轮转、备用）；每秒健康探测；逐线路计数与 `LinkStatsJSON`；叠加模式先走 bond 出站、失败退回线路；组合器把线路写进任意配置；网口分类；扩展 XPC `linkStats`。
- 卡在哪：等统一手测 D10。
- 下一步：`feat-links-interface`（线路页、面板线路区、概览多线路流向图、聚合方式生效）。
