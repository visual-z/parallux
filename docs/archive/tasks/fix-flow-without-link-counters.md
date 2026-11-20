---
type: fix
status: done
weight: light
created: 2026-11-19
baseline: cd1ff72
---

# 两条以上线路但还没有逐线路计数时，概览流向图没有流带、出口标签叠在一起

## 问题

`feat-links-interface`（57725cf）引入：`LinkFlow.columns` 在多条线路且 `linkRates` 为空时给每条线路 0，左列总量为 0，`SankeyLayout` 不画流带，右列节点高度全为 0、标签叠在同一处。刚连接的头一秒、聚合出站还没被拨号、或扩展统计取不到时都会这样。2026-11-19 截图核对时发现。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** 多条线路且没有任何逐线路计数时，内核总速率按线路数平分；只要有一条线路有计数，就按计数显示（没有计数的线路为 0）。
  - 检：test `linkRatesFallBackToAnEvenSplitWithoutCounters`
- **D2** 流向图的节点在总速率为 0 时仍按等高排开，标签不重叠；流带仍为空（INV-3 不变）。
  - 检：test `zeroRateNodesAreSpacedEvenly`
- **D3** gate 全绿；测试计数只因本卡新增的测试而增加，既有测试没有被弱化。
  - 检：cmd `keel assert-guard --card docs/tasks/fix-flow-without-link-counters.md`

## 证据

RED(swift): e6ccd1c linkRatesFallBackToAnEvenSplitWithoutCounters  # D1

- RED 时的失败原文：`Expectation failed: none.left.map(\.rate) == [500, 500]`（实为 [0, 0]）。
- D2 `zeroRateNodesAreSpacedEvenly` 冻结时已通过：`SankeyLayout` 本就按间距排开零高节点，标签叠在一起是视图层的间距（18）小于两行标签高度；改为 34，截屏核对。D2 不是行为红绿，只作为回归保护。
GATE: dfe2dde644b4+dirty ok tree:efde039b2b55 build=0 vet=0 test=0[590p/0f] fmt=0 swift-test=0[104p/0f] apple-build=0 server-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-19)
GATE: 33d6ae6415e1+dirty ok tree:efde039b2b55 build=0 vet=0 test=0[590p/0f] fmt=0 swift-test=0[104p/0f] apple-build=0 server-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-19)

## 交接

- 做了什么：没有逐线路计数时按线路数平分总速率；流向图节点间距不小于两行标签。
- 卡在哪：无。
- 下一步：无。
