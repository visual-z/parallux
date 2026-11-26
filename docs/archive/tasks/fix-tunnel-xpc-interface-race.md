---
type: fix
status: awaiting-author  # todo | doing | blocked | awaiting-author | done
weight: light
created: 2026-11-26
baseline: 382b0eaf9dcf
---

# 共享的 XPC 连接不再在每次调用时换接口，并发轮询不再崩溃

## 问题

作者本机 0.0.1（build 20261125095454）两次 `EXC_BAD_ACCESS / SIGSEGV`：

- 2026-11-26 01:17：`TunnelXPC.fetchNotifications` → `swift_dynamicCast` → `-[_NSXPCDistantObject conformsToProtocol:]` → `objc_getProperty` → `objc_retain`
- 2026-11-26 04:38：`TunnelXPC.fetchLinkStats` → `-[NSXPCConnection remoteObjectProxyWithErrorHandler:]` → `objc_msgSend`

两次都在协作线程池上，经 `TunnelXPCLink.poll`（`LinkStatsPoller` 1 s / `CoreNotificationForwarder` 2 s）。

原因：`TunnelXPC.prepare` 每次调用都执行 `connection.remoteObjectInterface = makeInterface()`。
495d986（fix-tunnel-xpc-connection-churn）把每次调用一条连接改成全 App 共享一条已 resume 的连接后，
这一行变成多线程并发改同一条活连接的接口：一个线程换掉并释放旧接口时，另一个线程的代理正在读它。
引入提交：495d986；在那之前每条连接只被一个调用者用一次，所以不崩。

复现（2026-11-26，基线 382b0ea）：临时测试用一条匿名 listener 连接，接口设一次后 resume，
8 线程 × 2000 次交替 `fetchLinkStats` / `fetchNotifications(resume: false)`：
`scripts/swift-test.sh` 3/3 次进程被信号 11 杀死；只把 `prepare` 的赋值改成仅在 `resume == true` 时执行，
同一测试 3/3 通过。临时测试未入库。

修法：不在这一行上打补丁，而是删掉「静态函数接一条裸连接、每次自己配置」的形状（它是每次调用一条连接那一版的遗留）。
`NSXPCLinkTransport` 成为唯一持有并配置连接的类型：接口与 resume 只在 `init` 里做一次，之后只发消息。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** 经 transport 的每一种调用（拨命令 socket、链路统计、通知、路由解释、探测）都不改动连接在 resume 时设好的 `remoteObjectInterface`（同一个对象）。
  - 检：test `aKeptConnectionKeepsTheInterfaceItWasResumedWithAcrossEveryCall`
- **D2** 8 个线程同时经同一个 transport 发 4000 次混合调用，全部得到回复，进程不崩。
  - 检：test `concurrentCallsOverOneKeptConnectionAllGetTheirReply`
- **D3** 源码里只剩一处给 `remoteObjectInterface` 赋值，且在 `NSXPCLinkTransport.init` 里。
  - 检：grep `remoteObjectInterface =` 在 `apple/` 的非测试 Swift 源码里恰好 1 处
- **D4** gate 全绿；测试计数只因本卡新增的测试而增加，既有测试没有被弱化。
  - 检：cmd `keel assert-guard --card docs/tasks/fix-tunnel-xpc-interface-race.md`
- **D5** 作者装上新构建后，隧道连着、主窗口开着跑一晚，`~/Library/Logs/DiagnosticReports` 不再出现 Parallux 的 `TunnelXPC` 崩溃。
  - 检：author 观察崩溃报告

## 证据

RED(swift): 3647ac4 aKeptConnectionKeepsTheInterfaceItWasResumedWithAcrossEveryCall  # D1

D2 没有可被 verify-red 承认的红：修前它让测试进程被信号 11 杀死（3647ac4 上 `scripts/swift-test.sh <junit> concurrentCallsOverOneKeptConnection` exit=1，`unexpected signal code 11`），keel 不把被信号杀死算作红。
修后 `scripts/swift-test.sh <junit> TunnelXPCTests` 连跑 10 次 10/10 通过。

D3 按冻结时的写法不成立：`grep -rn "remoteObjectInterface =" apple --include='*.swift'`（排除 Tests）有 2 处，
另一处是 `HelperXPC.call`——每次调用新建连接、resume 前配置、用完即 invalidate，没有共享，不是本缺陷。
隧道这一侧（`apple/ParalluxKit/Sources/ParalluxKit/Tunnel`、`apple/Parallux`、`apple/PacketTunnel`）恰好 1 处，在 `NSXPCLinkTransport.init`。
修订提议见 `## 修订`，等作者确认。
GATE: 3647ac4d745d+dirty ok tree:4ba55b6e45ec build=0 vet=0 test=0[625p/0f] fmt=0 swift-test=0[184p/0f] apple-build=0 server-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-26)

## 修订

- D3 提议改为：「隧道 XPC 一侧（`apple/ParalluxKit/Sources/ParalluxKit/Tunnel`、`apple/Parallux`、`apple/PacketTunnel`）只有 1 处给 `remoteObjectInterface` 赋值，在 `NSXPCLinkTransport.init`；其余赋值都在新建、尚未 resume 的连接上」。原因：冻结时没看到 `HelperXPC` 的每次调用一条连接，它不共享连接，不在本缺陷范围。待作者确认。

## 交接

- 做了什么：删掉 `TunnelXPC` 里「接一条裸连接、每次调用重设接口」的静态请求函数（每次调用一条连接那一版的遗留）；`NSXPCLinkTransport` 在 init 里配置并 resume 一次，五种请求走同一个 `request` 帮手；登记 INV-17。
- 卡在哪：D3 原文把不相干的 `HelperXPC` 也算进去，修订待作者确认；D5 要作者装新构建跑一晚看崩溃报告。
- 下一步：作者确认 D3 修订与 D5 后改 done。
