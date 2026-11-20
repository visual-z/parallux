---
type: fix
status: done
weight: light
created: 2026-11-19
baseline: a4771f3
---

# 新插上的线路在已连接时不会加入聚合

## 问题

`feat-links-interface`（57725cf）引入：`AppModel` 只在用户切换线路开关、排序或聚合方式时调用 `applyLinkChanges`。隧道已连接时插上网线或 iPhone，`LinkMonitor.links` 变了，但没人重新组合配置，新线路要等手动切一次开关或重连才参与；拔掉一条线路时也一样（直到健康探测把它标为不可用）。设计稿「自动加入新线路」。审查发现。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** 线路集合变化（新增或消失的网口名）时判定需要重新组合；只是地址变化或顺序变化不重组；停用的线路变化不重组。
  - 检：test `linkSetChangesTriggerRecomposition`
- **D2** gate 全绿；测试计数只因本卡新增的测试而增加，既有测试没有被弱化。
  - 检：cmd `keel assert-guard --card docs/tasks/fix-new-links-recompose.md`

## 证据

RED(swift): 58740a3 linkSetChangesTriggerRecomposition  # D1

- RED 时的失败原文：`Expectation failed: prefs.needsRecomposition(from: [wifi], to: [wifi, lan])`。
- 重组走 `applyLinkChanges`，即内核重载：正在进行的连接会断开重连（`fix-aggregate-routing` 记录）。
GATE: 9e0d73165899+dirty ok tree:d176c43db6d6 build=0 vet=0 test=0[589p/0f] fmt=0 swift-test=0[96p/0f] apple-build=0 server-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-19)

## 交接

- 做了什么：启用线路集合变化时自动重组配置并重载内核。
- 卡在哪：无；手测随 `feat-links-interface` D5。
- 下一步：无。
