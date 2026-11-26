---
type: refactor
status: awaiting-author  # todo | doing | blocked | awaiting-author | done
weight: full
created: 2026-11-26
baseline: 98d4203d6bc1
---

# 对扩展的 XPC 请求挂起等待，不再占住 Swift 并发的线程

## 来源

2026-11-26 修 `TunnelXPC` 崩溃（`docs/archive/tasks/fix-tunnel-xpc-interface-race.md`）时看到的第二个问题，作者同日同意改。

App 里五处向扩展发请求的地方——链路统计（1 s）、通知（2 s）、路由解释、两处探测——都是 `Task.detached { CommandXPCDialer.xxx() }`，
里面用 `DispatchSemaphore.wait` 等 XPC 回复，最长 5 s（探测 7 s）。`Task.detached` 跑在 Swift 并发的协作线程池上，
池子大约每核一个线程，被阻塞的线程不会被补上。扩展不答时（替换中、卡住），每个请求都占住一个线程直到超时；
同时卡住的请求一多，App 里所有 `async` 工作（包括主界面里的 `Task`）都会排队。一直就有，不是某个提交引入的。

## 范围

- **独占：** `apple/ParalluxKit/Sources/ParalluxKit/Tunnel/TunnelXPCLink.swift`、`apple/Parallux/Tunnel/CommandXPCDialer.swift`、
  `apple/Parallux/CoreNotificationForwarder.swift`、`apple/Parallux/Links/LinkMonitor.swift`、`apple/Parallux/Links/LinksView.swift`、
  `apple/Parallux/DiagnosticsView.swift`、`apple/Parallux/Routing/ExplainView.swift`，以及两个测试文件 `TunnelXPCTests.swift`、`TunnelXPCLinkTests.swift`。
- **不碰：** XPC 协议 `TunnelXPCProtocol`（扩展侧不变）、超时与退避常量的取值、libbox 的拨号回调 `dialXPC`（Go 同步调用，只能同步，
  它占的是 Go 自己的线程，不是协作线程池）、既有断言。

## 不变量

- INV-20：对扩展的每个请求恰好结束一次——回复、连接错误、超时、取消四者先到者生效，其余被丢弃；晚到的命令 socket 描述符被关闭 — 检查方式：样例 + 并发压力（`aSilentExtensionTimesOutEveryCallTogetherInsteadOfInWaves`、`cancellingACallReturnsAtOnce`、既有 `aCommandSocketHandedOverXPCCarriesBytes`）。

## 观测面

- 返回值与抛出的错误（`timedOut`、`CancellationError`）；墙钟时间（并发批次总耗时、取消后多久返回）。
- GREEN 可能被截断的方式：
  - 测试用的服务端如果其实回复了，「超时不排队」就测不到——服务端用 `replies: false`，并断言每个调用都抛 `timedOut`（计数等于发出的数目）。
  - 并发数不够大，阻塞版本也只有一波，测不出差别——发 4 × `activeProcessorCount` 个，这台机器上是 72 个（实测阻塞版 4 波）。
  - 取消测试里如果调用先超时返回，就不是取消起的作用——超时设 5 s，断言抛的是 `CancellationError` 且 1 s 内返回。

## 环境假设

- **协作线程池约每核一个线程，被信号量阻塞的线程不补。** 对拍（2026-11-26，本机 18 核）：72 个 `Task.detached` 各自 `DispatchSemaphore.wait` 300 ms，
  整批 1.22 s（两次相同），即 4 波 × 0.3 s，池宽 18。所以 72 个各等 0.25 s 的阻塞调用约 1.0 s，挂起等待的版本约 0.25 s。
- **NSXPC 的回复块与错误块可能都不来**（扩展卡住），也可能来一个以后连接再报错；所以必须有独立的硬超时，结果必须先到者生效。
  先例：ChimeHQ/AsyncXPCConnection（BSD-3-Clause）说明直接把接口方法写成 `async` 在连接失败时会挂住，改为每次调用包一个处理错误的 continuation；
  社区的一致做法是 continuation + 只恢复一次的保护 + 硬超时，取消也要恢复 continuation。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** 扩展不答时，4 × `activeProcessorCount` 个同时发出的请求（超时 0.25 s）全部以 `timedOut` 结束，整批耗时不超过 0.75 s（一次超时加余量，而不是按线程池宽度分波）。
  - 检：test `aSilentExtensionTimesOutEveryCallTogetherInsteadOfInWaves`
- **D2** 等待中的请求被取消时，1 s 内以 `CancellationError` 返回，不等到 5 s 的超时。
  - 检：test `cancellingACallReturnsAtOnce`
- **D3** App 里除 libbox 的 `dialXPC` 外，不再有同步的扩展请求：`CommandXPCDialer` 的 `linkStats`、`notifications`、`explainRoute`、`probeLinks` 都是 `async`；
  `TunnelXPCTransport` 与 `TunnelXPCLink` 唯一的同步请求是 `dialCommandSocket`。
  - 检：grep `apple/Parallux/Tunnel/CommandXPCDialer.swift` 里这四个 `static func` 都带 `async`；`TunnelXPCLink.swift` 里 `DispatchSemaphore` 只出现在同步拨号路径
- **D4** 连接复用、失效后换新、失败退避、退避上限的既有行为不变（原有 `TunnelXPCLinkTests` 的断言照旧成立）。
  - 检：test `TunnelXPCLinkTests`
- **D5** 计数：测试数只因本卡新增的测试而增加（基线见 front matter 的 baseline）。
  - 检：cmd `keel gate`
- **D6** 不弱化既有测试。
  - 检：cmd `keel assert-guard --card docs/tasks/refactor-xpc-polls-suspend.md`
- **D7** 作者手测：装新版后，隧道连着打开概览与路由页，线路速率每秒刷新；路由页「解释」能出结果；诊断页「扩展内检测」能出结果。
  - 检：author

## 设计

- **请求挂起，回复从回调里恢复。** `NSXPCLinkTransport.request` 改为 `withTaskCancellationHandler` + `withCheckedThrowingContinuation`；
  一个 `Reply` 持有 continuation，回复块、错误块、`DispatchQueue.global().asyncAfter` 的硬超时、取消处理四处都调 `finish`，第一个恢复，其余丢弃。
  拨号仍要同步（libbox 从 Go 同步调用），保留信号量版本，两者共用同一个先到者生效的 `Reply`。
- **链路的冷却与连接复用不变**，只是 `poll` / `call` 多了 async 版本；锁只在同步的取连接、记成败时持有，不跨 `await`。
- **否决：引入 AsyncXPCConnection。** 它解决的正是这个问题，但这里只需要约 30 行，新增依赖要作者批准，且它不带超时（XPC 回复不来时仍要自己加）。
- **否决：`Task` + `Task.sleep` 做超时竞争（TaskGroup）。** 每个请求多开一个子任务；`asyncAfter` 不占线程，结果相同。
- **否决：给阻塞调用单开一个 `DispatchQueue` 再 continuation 回来。** 不占协作线程了，但仍然每个请求占一个 GCD 线程等 5 s，扩展不答时照样堆线程。

## 验证命令

```bash
scripts/swift-test.sh /tmp/j.xml TunnelXPC
keel verify-red docs/tasks/refactor-xpc-polls-suspend.md
keel gate --record docs/tasks/refactor-xpc-polls-suspend.md
```

## 证据

RED(swift): b437205 aSilentExtensionTimesOutEveryCallTogetherInsteadOfInWaves  # D1
RED(swift): b437205 cancellingACallReturnsAtOnce  # D2

开卡时的失败断言（占位实现仍然阻塞等待）：

- D1：`Expectation failed: ContinuousClock.now - started < .milliseconds(750)`，整批 1.271 s（72 个调用全部 `timedOut`，计数断言通过，只有耗时不过）。
- D2：`Expectation failed: ContinuousClock.now - started < .seconds(1)`；`expected error of type CancellationError, but ".timedOut" of type DialError was thrown instead`，耗时 5.005 s。

修后：`scripts/swift-test.sh <junit> TunnelXPC` 连跑 10 次 10/10 通过（19 个测试，每次约 0.3 s）。

D3：`CommandXPCDialer.swift` 的 `probeLinks`、`explainRoute`、`linkStats`、`notifications` 四个 `static func` 都是 `async`；
`TunnelXPCLink.swift` 里 `DispatchSemaphore` 只在 `Reply.wait`，`reply.wait` 只被 `NSXPCLinkTransport.dialCommandSocket` 调用；
协议与链路上唯一的同步请求是 `dialCommandSocket`。

D4：`TunnelXPCLinkTests` 三个测试原有断言逐条保留，只是调用改为 `await`。
GATE: a4210bbcec62+dirty ok tree:ce6476b91f81 build=0 vet=0 test=0[628p/0f] fmt=0 swift-test=0[211p/0f] apple-build=0 server-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-26)

## 修订

## 交接

- 做了什么：对扩展的 XPC 请求改为挂起等待（continuation + 先到者生效 + dispatch 定时器硬超时 + 取消即返回），五处调用方不再 `Task.detached` 阻塞；同步只剩 libbox 的拨号；登记 INV-20。
- 卡在哪：D7 作者手测（概览速率、路由解释、诊断扩展内检测）。
- 下一步：作者在新发布版上确认 D7 后改 done。
