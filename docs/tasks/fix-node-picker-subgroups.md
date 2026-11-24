---
type: fix
status: awaiting-author  # todo | doing | blocked | awaiting-author | done
weight: light
created: 2026-11-24
baseline: 348886f9b2e8
---

# 断线清空代理组时，路由页的代理组选择器不再强解包崩溃

## 问题

作者 2026-11-24 13:26:05 拔掉网线，Parallux 以 `EXC_BREAKPOINT (SIGTRAP)` 意外退出
（`~/Library/Logs/DiagnosticReports/Parallux-2026-11-24-132606.ips`，0.1.0 构建 20261120133309，pid 737）。
用该版本的 dSYM 符号化，崩在 `apple/Parallux/Routing/NodePicker.swift:103` 的
`groupsByTag[item.tag]!`（`closure #3 in closure #5 in NodePicker.body.getter`）：
主线程正在 `ForEachChild.updateValue()` 里回调 `ForEach(subgroups)` 的内容闭包，
崩溃寄存器的 x20 正是 `_swiftEmptyDictionarySingleton`，函数尾部冷路径是「释放这个空字典 → `brk #1`」。

`groupsByTag` 是计算属性，每次访问都现读 `app.session.groups`；`subgroups` 却来自上一次 body 求值。
断线重连时 `CoreSession.stop()` 把 `groups` 清空（`CoreSession.swift:128`），
SwiftUI 仍用旧元素回调内容闭包，查表落空，`!` 解包 nil。
缺陷从路由页第一版（0c7dbbd，2026-11-19）就在：只要主窗口停在路由页、选中的出口下面有子代理组，
任何一次让 groups 变空的断线或重连都会走到这一行。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** 新纯函数 `OutboundGroupModel.split(among:)` 对任意输入都成立：每一行都带着它所指的那个组
  （`row.group.tag == row.item.tag`），行与节点按原顺序拼起来恰好是全部 items，且拼起来恰好覆盖它们；
  组快照为空时没有行、全部落到节点；组里有同名 tag 时取第一个。边界覆盖 0 条、1 条和随机多条。
  - 检：property `randomSnapshotsPartitionTheItemsIntoRowsAndNodes`
- **D2** 选择器的每一行在渲染时不再查表、不再强解包：行里带的组就是求值 `body` 那次快照里的组，
  之后组列表被清空也改不动它。
  - 检：test `aRowKeepsTheGroupFromTheSnapshotItWasSplitAgainst`
- **D3** gate 全绿；测试计数只因本卡新增的测试而增加，既有测试没有被弱化。
  - 检：cmd `keel assert-guard --card docs/tasks/fix-node-picker-subgroups.md`
- **D4** 作者手测：已连接时打开主窗口 › 路由，选中一个有子代理组的出口，拔掉网线；App 不崩溃，
  代理组区域随后消失而不是退出。
  - 检：author 拔网线复现原路径

## 证据

RED(swift): 4bd5477 randomSnapshotsPartitionTheItemsIntoRowsAndNodes  # D1
RED(swift): 4bd5477 aRowKeepsTheGroupFromTheSnapshotItWasSplitAgainst  # D2
GATE: 32ebe5ed389a+dirty ok tree:eb7fb251033e build=0 vet=0 test=0[596p/0f] fmt=0 swift-test=0[150p/0f] apple-build=0 server-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-24)

## 交接

- 做了什么：`OutboundGroupModel.split(among:)` 一次快照算出「行（带组）」与「节点」；NodePicker 的 body 只用它，
  闭包里不再查表、不再强解包。INV-15 登记了这个性质。
- 卡在哪：等作者按 D4 拔网线手测（原路径：主窗口 › 路由，选中带子代理组的出口）。
- 下一步：作者确认 D4 后改 done。
