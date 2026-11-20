---
type: fix
status: awaiting-author        # todo | doing | blocked | awaiting-author | done
weight: light
created: 2026-11-19
baseline: 081fde03933e
---

# 内核重载后，连接与日志数据流自动重连

## 问题

作者 2026-11-19 在已连接状态下把聚合方式切到「分流」后，状态行变成「已连接，但读不到内核：connections stream recv: EOF」，概览的流量图显示「暂无活动连接」；隧道本身仍然连着（`scutil --nc list` 显示 Connected，经隧道访问外网返回 200）。

切换方式会走 `applyLinkChanges` → `TunnelController.reload` → 扩展的 `startOrReloadService`，内核重建服务时关闭了 command server 上的订阅流。`CoreSession.Stream` 只在创建时连接一次，断开后既不重连，也不清除错误。这个缺陷一直就有，首次热重载就会触发。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** 重连节奏 `StreamRetry.delay(after:)`：第 0 至第 `StreamRetry.attemptLimit - 1` 次断开后给出递增的等待时间，首次不超过 1 秒，之后不减少；达到 `attemptLimit` 返回 nil（停止重连，显示错误）。上限有限，0、1 和上限三个边界都要覆盖。
  - 检：test `streamRetriesGrowAndStopAtTheLimit`
- **D2** gate 全绿；测试计数只因本卡新增的测试而增加，既有测试没有被弱化。
  - 检：cmd `keel assert-guard --card docs/tasks/fix-stream-reconnect.md`
- **D3** 作者手测：已连接时切换聚合方式，状态行几秒内回到「已连接 · …」，概览流量图和连接页继续更新。
  - 检：author 统一手测

## 证据

RED(swift): 2414f6a streamRetriesGrowAndStopAtTheLimit  # D1

- 冒烟（2026-11-19 14:44，签名 build 20261119064200）：已连接时在设置 › 聚合把方式从主备切到分流，之后 18 秒内每 3 秒读一次窗口标题，都是「概览 – 已连接 · 分流 · 2 条线路」；概览流量图继续更新（103 个连接），经隧道访问 google.com 返回 200。
GATE: 593ecd2208a3+dirty ok tree:c7825dc6f1a9 build=0 vet=0 test=0[590p/0f] fmt=0 swift-test=0[114p/0f] apple-build=0 server-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-19)

## 交接

- 做了什么：数据流断开后按 StreamRetry 有上限地重连，重载后不再停在 EOF。
- 卡在哪：等作者手测 D3。
- 下一步：无。
