---
type: fix
status: awaiting-author        # todo | doing | blocked | awaiting-author | done
weight: light
created: 2026-11-19
baseline: 3e16e869ca15
---

# 目标拒绝或超时不再把线路标成不可用

## 问题

`aggregate.Outbound.DialContext` 与 `ListenPacket` 遇到任何拨号错误都会 `markFailed`，然后换下一条线路再试。目标端口拒绝（ECONNREFUSED）、目标被墙（超时）、目标没有 IPv6 路由，这些错误在每条线路上都一样，结果每条线路都被标成不可用。`linkOrder` 把不健康的线路按固定顺序放在最后，于是在探测器把它们恢复之前（约 1 秒），分流退化成「全部走第一条线路」。refused 的情况还白白在每条线路上各拨一次。

这个缺陷从 aggregate 第一版就有。现象与作者看到的「分流时流量只在一条线路上」吻合；但 2026-11-19 用 10 个并发的国内下载对拍，en0 和 en7 的字节数都在增长（+81/+62 MB、+74/+69 MB），说明正常情况下分配是好的，问题只在出现拨号失败时。

另外 `Snapshot` 遍历 `sync.Map` 时顺序随机，App 每次可能拿到不同组的数据，线路状态会闪烁。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** 拨号错误分类 `dialFailure(err)`：
  - 目标拒绝（ECONNREFUSED、ECONNRESET）：不换线路，也不标记。
  - 超时，或目标不可达（EHOSTUNREACH）：换线路，但不标记。
  - 线路本身的错误（ENETUNREACH、ENETDOWN、EADDRNOTAVAIL、ENXIO 等，以及「没有该网口」）：换线路，并标记。
  - 调用方的 context 已取消：不换线路，也不标记。
  - 未知错误：换线路，但不标记。
  - 检：test `TestDialFailuresMarkOnlyTheLinkThatFailed`
- **D2** 两条线路都返回目标拒绝时，聚合出站只拨一次，两条线路仍然健康；一条线路返回 ENETDOWN 时，换另一条拨成功，且只有这一条被标为不可用。
  - 检：test `TestARefusedDestinationLeavesEveryLinkHealthy`
- **D3** `Snapshot` 按组 tag 排序。
  - 检：test `TestSnapshotIsSortedByGroupTag`
- **D4** gate 全绿；测试计数只因本卡新增的测试而增加，既有测试没有被弱化。
  - 检：cmd `keel assert-guard --card docs/tasks/fix-dial-errors-poison-health.md`

## 证据

RED: 1ae1850 -run ^TestDialFailuresMarkOnlyTheLinkThatFailed$ ./core/aggregate/  # D1
RED: 1ae1850 -run ^TestARefusedDestinationLeavesEveryLinkHealthy$ ./core/aggregate/  # D2
RED: 1ae1850 -run ^TestSnapshotIsSortedByGroupTag$ ./core/aggregate/  # D3
GATE: 5657e0617ec3+dirty ok tree:9ea93da8262d build=0 vet=0 test=0[593p/0f] fmt=0 swift-test=0[119p/0f] apple-build=0 server-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-19)

## 交接

- 做了什么：dialFailure 给拨号错误分类，只有线路本身的错误才标记不可用，并让探测器重新累计连续成功次数；目标拒绝时不再换线路重拨；Snapshot 按 tag 排序。
- 卡在哪：等作者统一手测（与 feat-link-view 一起）。
- 下一步：feat-link-view。
