---
type: fix
status: doing       # todo | doing | blocked | awaiting-author | done
weight: light
created: 2026-11-26
baseline: 1fc6918
---

# 线路通知只在有线路可改走、且变化持续时才发，文案写真实去向

## 问题

作者 2026-11-26 的截图（11-25 15:57–21:58）：只连着一个接口时也弹「线路不可用 / 已恢复」；文案固定写
「新连接改走其他线路」「重新参与聚合」，没有其他线路时是错的；同一分钟内成对出现（21:17、21:58 各一对「不可用→已恢复」）；
有两条写成 `link-en0`、`link-en7`，其余写成「Wi‑Fi（en0）」。

原因（`apple/Parallux/Links/LinkNotifier.swift`）：每次 linkStats 变化，只要某条线路的健康状态翻转就立刻发；不看有没有别的健康线路；
不等状态稳定；线路不在当前线路列表里时直接用出站 tag 当名字。一直就有，不是某个提交引入的。

作者 2026-11-26 选定：只有一条线路时不发；两条以上时，状态持续 10 秒才发；写出改走的线路名；没有其他可用线路时不写「改走其他线路」；名字不退化成 tag。

规则写成纯函数 `LinkAlerts`（ParalluxKit），`LinkNotifier` 只负责发。具体规则：

- 新状态连续 `LinkAlerts.hold`（10 s）才算数，期间翻回去就当没发生。
- 掉线只在此刻还有别的健康线路时宣布（只有一条线路、或其余也都不可用时不发：没有可改走的线路，系统自己会显示断网）。
- 恢复只在它的掉线被宣布过时宣布。
- 名字：当前列表里有就用列表里的；列表里暂时没有就用上次见过的；从没见过就用接口名（去掉 `link-` 前缀）。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** 只有一条线路时，无论掉线多久都不发。
  - 检：test `aSingleLinkNeverAlertsHoweverLongItIsDown`
- **D2** 两条线路时，短于 hold 的掉线不发；持续过 hold 的掉线发一条，文案写出掉线的线路与改走的线路名，不写「其他线路」。
  - 检：test `aFlapShorterThanTheHoldStaysQuiet`
  - 检：test `aLinkDownPastTheHoldNamesTheLinesTrafficMovesTo`
- **D3** 恢复只跟在宣布过的掉线之后；没有可改走线路时的掉线与随后的恢复都不发。
  - 检：test `aRecoveryIsAnnouncedOnlyAfterItsDropWas`
- **D4** 线路暂时不在列表里时沿用上次的名字；从没见过的线路显示接口名；文案里永远不出现 `link-`。
  - 检：test `aLinkMissingFromTheListKeepsItsLastNameAndNeverShowsItsTag`
- **D5** INV-21 对任意时间线成立：每条线路的通知按「掉线、恢复、掉线…」交替；掉线宣布时另有健康线路；宣布的状态在此前整个 hold 内都没变；单线路从不通知。
  - 检：property `randomTimelinesOnlyAnnounceLastingChangesWithAFallback`
- **D6** gate 全绿；测试计数只因本卡新增的测试而增加，既有测试没有被弱化。
  - 检：cmd `keel assert-guard --card docs/tasks/fix-link-alerts-single-line.md`
- **D7** 作者手测：只连 Wi‑Fi 时拔插/关开不弹线路通知；Wi‑Fi + 有线时拔掉网线超过 10 秒，弹一条「有线（en7）暂时不可用，新连接改走 Wi‑Fi（en0）」，插回 10 秒后弹「已恢复」；通知左侧显示 Parallux 图标。
  - 检：author

## 证据

## 交接
