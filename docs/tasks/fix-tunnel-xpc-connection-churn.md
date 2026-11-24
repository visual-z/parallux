---
type: fix
status: doing        # todo | doing | blocked | awaiting-author | done
weight: light
created: 2026-11-24
baseline: b9199e7abb98
---

# 隧道 Mach 服务不再每次调用新建 XPC 连接，扩展不答时退避

## 问题

作者 2026-11-24 13:26 崩溃重启后的进程（pid 7598）日志里每约半秒一对
`activating connection … name=…parallux.tunnel.0.1.0.20261120133309` /
`invalidated because the current process cancelled the connection by calling xpc_connection_cancel()`，
一直刷屏。

复测（2026-11-24 13:59，隧道已连接、扩展健康、窗口开着）：
`log stream --predicate 'process == "Parallux" AND eventMessage CONTAINS "parallux.tunnel"'` 20 秒记到 43 次
`activating connection`，间隔交替约 0.4 s 和 1.0 s——稳态就有每秒约 2 次。

原因：`apple/Parallux/Tunnel/CommandXPCDialer.swift` 的 `connection()` 与
`apple/Parallux/CoreNotificationForwarder.swift` 的 `fetch()` 每次调用都新建一个 `NSXPCConnection`，
发完消息立刻 `invalidate()`。两个轮询器——`LinkStatsPoller`（1 s）与 `CoreNotificationForwarder`（2 s）——
合起来正好每秒 1.5 次以上的建连/拆连，和实测节奏对得上：`activate` 与 `cancel` 相隔几毫秒，
两次建连相隔 0.4 s / 1.0 s。

代价：每秒约 3 次 mach 查找，被调端每秒 3 次 `shouldAcceptNewConnection` 与新的导出对象；
扩展不可达（替换中、内核未起、隧道断开）时同样照打，没有退避——作者看到的就是这个刷屏。
缺陷从第一版就在，不是 0.1.0 引入的。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** 一个目标只建一次连接：`TunnelXPCLink` 连续 N 次轮询只打开 1 个 transport；
  transport 失效（`isAlive == false`）后，下一次调用才换新的。边界覆盖 1 次、N 次和换连接的 1 次。
  - 检：test `theLinkOpensOneConnectionHoweverManyPollsArrive`
- **D2** 出错才退避：一次轮询失败后，退避窗口内的下一次轮询直接返回中性值，既不建连接也不发消息；
  窗口过去后才重试；成功一次即清零失败计数。
  - 检：test `aFailingExtensionCoolsThePollsDownInsteadOfDialingEveryTick`
- **D3** 退避有上限：`TunnelXPCPollRetry.delay(after:)` 对 0 次失败返回 nil，1 次起为正、不减少，
  到上限后不再增长；上限是有限常量。
  - 检：test `thePollCooldownGrowsAndStopsAtItsCap`
- **D4** gate 全绿；测试计数只因本卡新增的测试而增加，既有测试没有被弱化。
  - 检：cmd `keel assert-guard --card docs/tasks/fix-tunnel-xpc-connection-churn.md`
- **D5** 作者手测：隧道连着时 `log stream` 观察 30 秒，`parallux.tunnel` 的 `activating connection` 不随轮询出现；
  扩展不可达期间也不再是每半秒一次。
  - 检：author 观察 log stream

## 证据

（RED：本提交即冻结点，hash 与过滤串在下一次提交写回）

## 交接

- 做了什么：开卡；冻结 `TunnelXPCLink` 的复用与退避判据。
- 卡在哪：先提 RED（stub + 三条测试），再实现并接进两处调用点。
- 下一步：RED 提交后实现，`CommandXPCDialer` 与 `CoreNotificationForwarder` 改走这条连接。