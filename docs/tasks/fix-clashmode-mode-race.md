---
type: fix
status: done        # todo | doing | blocked | awaiting-author | done
weight: light
created: 2026-11-26
baseline: b437205a441b
---

# 切换路由模式时，核心读到的模式名不会被撕裂

## 问题

2026-11-26 跑 `keel gate` 时 `TestTheAddedModeRulesRouteByTheSelectedMode` 偶发失败：`-race` 报
`clashmode.(*Manager).SetMode()`（manager.go:88，写 `m.mode`）与 `route.(*ReferenceManager).update()` 里的
`Manager.Mode()`（manager.go:63，读 `m.mode`）同时访问。`go test -race -count=30` 两轮各至少 1 次。

`Manager.mode` 是一个 Go 字符串（指针 + 长度两个字），`Mode()` 不加锁读、`SetMode` 不加锁写。
App 里对应「流量正在路由时切换 规则/全局/直连」：路由器读到半新半旧的字符串，可能按错规则走，也可能让扩展崩溃。
上游 SagerNet/sing-box 的 `testing` 分支（2026-11-26 查看）同样不加锁；是 fork 跟着上游带进来的，一直就有。

修法（作者 2026-11-26 同意改 fork 并升 go.mod 里的版本）：在 fork 的 `parallux/v1.14.4` 分支给 `mode` 加读写锁，
`Start`、`Mode`、`SetMode` 都经过它；`SetMode` 在锁内比较并赋值，放锁后再调更新钩子（钩子会回头调 `Mode()`）。
再把 `go.mod` 的 replace 指到新提交。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** 一边反复切换模式、一边读当前模式，`-race` 下不报竞态，读到的永远是完整的模式名。
  - 检：test `TestSwitchingTheModeWhileItIsReadIsRaceFree`
- **D2** 原有的模式路由测试不变且通过，连跑 30 次（`-race`）无竞态。
  - 检：cmd `go test -race -count=30 -run '^TestTheAddedModeRulesRouteByTheSelectedMode$' ./core/aggregate/`
- **D3** gate 全绿；测试计数只因本卡新增的测试而增加，既有测试没有被弱化。
  - 检：cmd `keel assert-guard --card docs/tasks/fix-clashmode-mode-race.md`

## 证据

RED: a4210bb -race -run '^TestSwitchingTheModeWhileItIsReadIsRaceFree$' ./core/aggregate/  # D1

开卡时：`-race` 报 `WARNING: DATA RACE`（`clashmode.(*Manager).SetMode` 写、`Mode` 读），`--- FAIL`，3/3 次。
fork 提交 `visual-z/sing-box@e6a7d1e8`（分支 `parallux/v1.14.4`）加锁后：本测试 `-count=3` 通过；
D2 `go test -race -count=30 -run '^TestTheAddedModeRulesRouteByTheSelectedMode$' ./core/aggregate/` 退出 0，`DATA RACE` 0 次。
GATE: a4210bbcec62+dirty ok tree:ce6476b91f81 build=0 vet=0 test=0[628p/0f] fmt=0 swift-test=0[211p/0f] apple-build=0 server-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-26)

## 交接

- 做了什么：fork 给 `clashmode.Manager.mode` 加读写锁（`e6a7d1e8`），`go.mod` 的 replace 指到它；新增竞态测试。
- 卡在哪：无。
- 下一步：上游 sing-box 也有同样的问题，可以考虑提交给上游。
