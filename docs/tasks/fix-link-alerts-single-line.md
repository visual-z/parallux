---
type: fix
status: awaiting-author  # todo | doing | blocked | awaiting-author | done
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

RED(swift): d66e74f aSingleLinkNeverAlertsHoweverLongItIsDown  # D1
RED(swift): d66e74f aFlapShorterThanTheHoldStaysQuiet  # D2
RED(swift): d66e74f aLinkDownPastTheHoldNamesTheLinesTrafficMovesTo  # D2
RED(swift): d66e74f aRecoveryIsAnnouncedOnlyAfterItsDropWas  # D3
RED(swift): d66e74f aLinkMissingFromTheListKeepsItsLastNameAndNeverShowsItsTag  # D4
RED(swift): d66e74f randomTimelinesOnlyAnnounceLastingChangesWithAFallback  # D5

开卡时占位实现照搬原 `LinkNotifier` 的规则，6 个测试全红（单线路、3 秒抖动都发；文案写「其他线路」；名字是 `link-en0`；性质测试 61426 处不成立）。
冻结后加严一处：性质测试要求 300 条时间线一共产生 100 条以上通知，免得检查空转。

图标：同一 bundle ID 在 LaunchServices 里登记了 27 份（各处构建产物），作者同意后 2026-11-26 注销了 `/Applications` 以外的 26 份并重启 `usernoted`；
防止再累积的脚本改动在 `docs/tasks/chore-forget-build-registrations.md`。图标是否显示由 D7 作者确认。
GATE: d66e74fef9b9+dirty ok tree:3df04e28fd05 build=0 vet=0 test=0[628p/0f] fmt=0 swift-test=0[217p/0f] apple-build=0 server-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-26)

## 交接

- 做了什么：通知规则抽成 `LinkAlerts`（单线路不发、10 s 防抖、写出改走的线路、恢复跟着宣布过的掉线、名字不退化），`LinkNotifier` 只负责发；登记 INV-21；清掉 26 份旧的 LaunchServices 登记。
- 卡在哪：D7 作者手测。
- 下一步：作者在新发布版上按 D7 试一次后改 done。
