---
type: feat
status: awaiting-author        # todo | doing | blocked | awaiting-author | done
weight: full
created: 2026-11-19
baseline: 4e622c761fcf
---

# 每条线路只有一份状态：速率取自网口计数，健康状态合并各聚合出站

## 来源

作者 2026-11-19：「修一下吧，要保证我们的聚合等功能都能正常使用。」排查中找到下面几处，都是一直就有的：

1. 流向图每条线路的速率来自聚合出站的连接计数，有三条路径不经过这个计数，于是速率偏低，甚至显示 0：
   - UDP（`ListenPacket` 返回的是原始连接）：QUIC 和 Hysteria2 节点都走这条。
   - 叠加：multipath 的各线路段直接拨线路出站，不经过 aggregate。
   - 截图里两条线路合计 19 Kbps，而内核报的总速率是 1.2 Mbps。
2. 健康状态有四处读取：面板、线路页、掉线通知、菜单栏图标。各自按「第一个 / 最后一个含这条线路的组」来取，组的顺序一变，结论就跟着变；掉线通知是后一个组覆盖前一个，可能误报「线路不可用」。
3. 连接列表里，用户的 `direct` 换成聚合出站之后，类型是 `aggregate`，流向图右侧显示成字面的「direct」，而不是「直连」。
4. 流向图在两次流量之间的空闲秒里会切到「暂无活动连接」，已连接时一秒一闪。
5. 只开聚合、聚合方式选叠加时，直连流量不经过聚合服务器（fix-aggregate-routing 的既定设计），实际按主备运行，界面却写着「叠加」。

## 范围

- **独占：** `apple/ParalluxKit/Sources/ParalluxKit/Links/LinkView.swift` 及其测试；`apple/Parallux/Links/InterfaceCounters.swift`；`LinkMonitor.swift` 的轮询；`LinkNotifier.swift`；`LinksView.swift`、`PanelView.swift` 的健康读取；`AppModel.menuBarState` 与 `effectiveMode`；`FlowSummary.swift`；`OverviewView.swift` 的流向图区。
- **不碰：** 内核（aggregate 的计数保留，诊断页还在用）；ProfileComposer；fix-aggregate-routing 定下的「直连不走叠加」。

## 观测面

- 速率：纯函数 `InterfaceRates.rates(previous:current:interval:)`，输入是按网口名的 64 位累计字节数。I/O 层只负责调 sysctl 取 `if_data64`。
- 健康：纯函数 `LinkView.merge(_ groups:)`。
- 流向图保持：纯函数 `FlowHold.next(...)`。
- 截断防护：测试遍历组的所有排列，并覆盖 0、1 和上限各边界。

## 环境假设

- macOS 的 `sysctl(NET_RT_IFLIST2)` 返回 `if_msghdr2`，里面的 `ifm_data` 是 `if_data64`，计数为 64 位；`getifaddrs` 的 `if_data` 只有 32 位，4 GiB 就回绕。对拍：2026-11-19 `netstat -I en0 -b` 显示 en0 已累计 10110467305 字节（超过 2^32），说明系统确实提供 64 位计数。
- 网口计数包含不经过隧道的流量（被排除的局域网流量、其他 VPN），这正是「这条线路上有多少流量」的本意；做成按线路显示，而不是按内核显示。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** 网口速率：按网口名分别求差、除以间隔；计数变小（重置）记 0；本次新出现的网口记 0；间隔 ≤ 0 返回空；结果以线路出站 tag（`link-<名字>`）为键；对任意前后样本都不出现负数。
  - 检：property `interfaceRatesAreNeverNegativeAndKeyedByLinkTag`
- **D2** 合并后的线路状态：只要有一个组标为不健康就是不健康；活跃连接数在各组间相加；结果与组的顺序无关（遍历所有排列）；没有组时为空。
  - 检：property `mergedLinkHealthIgnoresGroupOrder`
- **D3** 连接类型为 `aggregate` 的流量在流向图里算作「直连」。
  - 检：test `aggregateOutboundsCountAsDirect`
- **D4** 流向图保持：本次有出口就显示本次的；本次没有时，在 `FlowHold.limit` 内沿用上一份非空的；超过之后为空；上限、刚好到达、刚好超过三个边界都覆盖。
  - 检：test `theFlowDiagramHoldsThroughIdleSeconds`
- **D5** 只开聚合并选了叠加时，提示「只开聚合时，直连流量不经过聚合服务器，暂按主备运行」，`effectiveMode` 为主备；代理开着时沿用原来的提示。
  - 检：test `aggregationOnlyBondSaysItRunsAsFailover`
- **D6** 计数只因本卡新测试增加；不弱化既有测试；gate 全绿。
  - 检：cmd `keel gate`
- **D7** 作者手测：分流下开多个下载时，两条线路的速率之和接近总速率；Hysteria2 节点的流量也显示在线路上；线路页的状态不闪；空闲时流向图不会每秒消失。
  - 检：author 统一手测

## 设计

- 网口计数是线路速率的唯一来源。否决「在内核里给 UDP 和 multipath 的线路段各加一层计数」：要改三处内核代码，还要动 fork 里的 multipath；而网口计数天然覆盖所有路径，也正是「这条线路有多快」的意思。aggregate 的计数保留给诊断页。
- 合并规则取「任一组不健康即不健康」：各组的探测器探的是同一组目标，正常情况下结论一致；不一致时说明这条线路正在变化，显示「不可用」比闪烁更诚实。
- `FlowHold.limit` = 5 秒：网页加载之间常有 1–3 秒的空闲；超过 5 秒没有流量，说明确实空闲了。假设值，测量方法是在概览上观察浏览时出现「暂无流量」的频率。
- 空态文案改为「暂无流量」：已连接时「暂无活动连接」不是事实（连接在，只是没有字节在动）。

## 验证命令

```bash
scripts/swift-test.sh /tmp/t.xml LinkViewTests
keel verify-red docs/tasks/feat-link-view.md
keel gate --record docs/tasks/feat-link-view.md
```

## 证据

RED(swift): e5adac7 interfaceRatesAreNeverNegativeAndKeyedByLinkTag  # D1
RED(swift): e5adac7 mergedLinkHealthIgnoresGroupOrder  # D2
RED(swift): e5adac7 aggregateOutboundsCountAsDirect  # D3
RED(swift): e5adac7 theFlowDiagramHoldsThroughIdleSeconds  # D4
RED(swift): e5adac7 aggregationOnlyBondSaysItRunsAsFailover  # D5

- 冒烟（2026-11-19 16:10，签名构建，两个开关都开，10 个并发国内下载）：
  - 分流：流向图里 Wi-Fi 53 Mbps、有线 32 Mbps 同时显示，修复前一条线路恒为 0。右侧出口显示「直连」，不再是字面的「direct」。
  - 主备：同样的下载，en0 +124 MB、en7 +0 MB。
  - 切回分流：en0 +71 MB、en7 +65 MB（`netstat -I <网口> -b` 前后相减）。
- 两条线路速率之和（85 Mbps）高于内核报的总速率（68 Mbps）：网口计数包含 TCP/TLS 开销和不经隧道的流量，符合设计里的说明。
GATE: cf1e76922a20+dirty ok tree:f56fdc08aa87 build=0 vet=0 test=0[593p/0f] fmt=0 swift-test=0[124p/0f] apple-build=0 server-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-19)

## 修订

- D5 被 feat-bond-direct 取代（作者 2026-11-20 决定直连也走叠加）：只开聚合时叠加会真的生效，不再提示「按主备运行」；对应的测试已改为 `aggregationOnlyBondRunsAsBond`，断言变更登记在 feat-bond-direct 的 WEAKEN-OK 里。

## 交接

- 做了什么：线路速率改取网口 64 位计数；健康状态合并为 LinkView，四处读取都用它；aggregate 类型的出口算作直连；流向图在空闲秒里保持 5 秒；只聚合时选叠加，提示「暂按主备运行」，effectiveMode 也是主备。
- 卡在哪：等作者手测 D7。还没在真机上验证的有：叠加（需要聚合服务器），以及线路真的断开时的主备切换（需要拔线或关 Wi-Fi）。
- 下一步：作者提供聚合服务器的链接后，端到端测叠加。
