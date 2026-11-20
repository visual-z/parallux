---
type: fix
status: done
weight: light
created: 2026-11-20
baseline: f91edea (gate: test 594p/0f, swift-test 160p/0f)
---

# 线路健康探测丢一个握手包不再把线路踢出轮转

## 问题

`core/aggregate/health.go` 的 `probeOnce` 按顺序拨探测目标，所有目标共用 1 s 预算。第一个目标的 SYN 丢了，macOS 要 1 s 后才重传，预算已经用完，第二个目标根本没机会拨，这一轮就判失败。失败一次就标为不健康，要连续成功 2 次（约 2 s）才回到分流轮转。代码一开始就是这样写的。

2026-11-20 在作者的 Mac 上实测（仓库外脚本，按 `probeOnce` 的方式绑网口拨号，不进仓库）：

- 有线 en7 空闲时 30 轮失败 2 轮，跑满下载时 60 轮失败 2 轮，没有连续两轮失败；Wi‑Fi en0 跑满时 60 轮 0 失败。满载不会拉高探测延迟（en7 p90 80 ms），失败来自偶发丢包，不是排队。
- 这个网络里 `1.1.1.1:443` 两条线路 0/10 都连不上（`1.1.1.1:53` 能连），所以默认的第二个目标形同虚设，探测实际上只剩 `223.5.5.5:53` 一个目标，一个包丢了就是一次误判。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** 每个探测目标的第一次拨号丢了（一直挂着，不返回）时，同一轮探测里会对它再拨一次，第二次成功就判这一轮成功；几个目标同时拨，不再排队等前一个。
  - 检：test `TestAProbeSurvivesOneLostConnectionAttempt`
- **D2** 线路真的断了，判定时间不变长：所有拨号都挂着，在 `probeTimeout` 内判失败；所有拨号都立刻报错时，不等重拨时刻就判失败；没有目标时直接判失败。`probeOnce` 返回时没有还在跑的拨号。
  - 检：test `TestAProbeOfADeadLinkFailsWithinItsTimeoutAndLeavesNoDialRunning`
- **D3** gate 全绿；测试计数只因本卡新增的测试而增加，既有测试没有被弱化。
  - 检：cmd `keel assert-guard --card docs/tasks/fix-probe-lost-syn.md`

## 设计

- 只改 `probeOnce` 一处：所有目标同时拨，过了 `probeRetryAfter` 还没结果的目标再拨一次，任何一次成功就成功。`probeInterval`、`probeTimeout`、`recoverAfter` 三个数值不动，检测死线路的时间也不变（全部挂起时最多还是 1 s）。
- 否决：
  - 连续失败两次才判不健康：死线路的判定时间从 ≤ 2 s 变成 ≤ 3 s，违背 PLAN 的 2 s 目标，而且是改阈值，要先问作者。
  - 「这一秒线路上还有流量就忽略探测失败」（评审提出的方案）：实测满载不是误判的原因；而且计数器只看得到经聚合出站的 TCP，UDP 节点和叠加线路段都看不到。
  - 换默认探测目标：哪些目标能连通取决于具体网络（这里 `1.1.1.1:443` 不通，`1.1.1.1:53` 通），这已经能用 `probe_targets` 配置。并发拨号以后，多一个不通的目标也不拖累判定。

## 证据

RED: 471f9a1 -run ^TestAProbeSurvivesOneLostConnectionAttempt$ ./core/aggregate/  # D1

- RED 时的失败原文：`1 target(s), first attempt to each lost: probe failed, want the retry to succeed`。
- D2 的测试在旧实现上就是绿的：它守的是「判定死线路不变慢、不留拨号」，不是本卡要改的行为。
- 实测方法（仓库外脚本，不进仓库）：Python 用 `IP_BOUND_IF`（选项值 25）把 socket 绑到 en0 / en7，每秒按 `probeOnce` 的顺序和 1 s 预算拨 `223.5.5.5:53`、`1.1.1.1:443`；满载时同网口并发 6 个 `curl --interface` 下载。
GATE: 471f9a1c82a8+dirty ok tree:b9b038263a5f build=0 vet=0 test=0[596p/0f] fmt=0 swift-test=0[160p/0f] apple-build=0 server-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-20)

## 交接

- 做了什么：`probeOnce` 改成所有目标同时拨，400 ms 还没结果的目标再拨一次；数值阈值不动。
- 卡在哪：—（不改界面，没有作者检查项）
- 下一步：装到机器上后，可用同一方法看分流轮转里线路被踢出的次数是否归零（需要扩展日志里有探测结果，目前没有）。
