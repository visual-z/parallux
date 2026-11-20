---
type: fix
status: awaiting-author        # todo | doing | blocked | awaiting-author | done
weight: light
created: 2026-11-19
baseline: 4f4b1c84225f
---

# 日志页不显示终端颜色码

## 问题

2026-11-19 冒烟时，日志页每行都夹着原始的终端颜色码，例如 `[36mINFO[0m[0061] [[38;5;224m2116080080[0m 0ms]`。libbox 的日志是给终端看的，带 ANSI SGR 序列；App 收到后原样存进 `LogEntry.message`，导出的日志也带着这些码。这个问题从日志页接上真实内核起就有。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** `LogEntry.message` 里没有 ESC 开头的 CSI 序列（含 `ESC[…m` 和其他 CSI 结尾字母），其余文字原样保留；空串、没有颜色码的文本、末尾残缺的 `ESC[` 都要覆盖。
  - 检：test `logMessagesDropTerminalColorCodes`
- **D2** gate 全绿；测试计数只因本卡新增的测试而增加，既有测试没有被弱化。
  - 检：cmd `keel assert-guard --card docs/tasks/fix-log-ansi-codes.md`
- **D3** 作者手测：日志页和导出的日志里没有 `[36m` 这类字样。
  - 检：author 统一手测

## 证据

RED(swift): 9258b18 logMessagesDropTerminalColorCodes  # D1
GATE: 85b70e4ef986+dirty ok tree:36aa990f1bf1 build=0 vet=0 test=0[590p/0f] fmt=0 swift-test=0[119p/0f] apple-build=0 server-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-19)

## 交接

- 做了什么：LogEntry 在初始化时去掉 CSI 序列。
- 卡在哪：等作者手测 D3。
- 下一步：无。
