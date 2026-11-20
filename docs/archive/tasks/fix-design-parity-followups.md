---
type: fix
status: awaiting-author
weight: light
created: 2026-11-19
baseline: d8a520bed857
---

# 概览副标题不再盖住错误，主 / 备跟随线路健康，路由模式卡片补上「命中最多」

## 问题

`fix-overview-design-parity` 与 `fix-panel-design-parity` 收尾后复查出的三处，都是这两张卡引入或漏掉的：

- 概览运行时的副标题从 `statusLine` 换成了「N 条线路 · 聚合方式 · 经服务器」。`statusLine` 在已连接时还负责显示上一次操作的错误与「已连接，但读不到内核」；换掉之后主窗口运行时没有地方显示它们。
- `LinkStanding` 只看顺序与「仅备用」。内核的选线顺序是：健康的非备用线路、健康的备用线路、不健康的线路（`core/aggregate/order.go` 的 `linkOrder`）。第一条线路不健康时，面板仍把它标成「主」，旁边却写着「不可用」。
- 设计稿路由模式卡片里的「命中最多：geosite‑cn → 直连（61%）」没做。`fix-overview-design-parity` 的范围里写「内核目前不给概览提供规则命中数」，这句话是错的：每条连接都带着它命中的规则（libbox `Connection.rule`，`daemon/started_service.go` 里取 `metadata.Rule.String()`，只有条件、不含动作），在 App 里数一遍就有。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** 有错误要显示时，概览副标题就是那条错误文字；没有错误（nil 或空串）时才是设计稿的「N 条线路 · 聚合方式 · 经服务器」。
  - 检：test `overviewSubtitleGivesWayToAProblem`
- **D2** 线路角色跟随内核的选线顺序：主备下「主」是第一条健康的非备用线路，没有就是第一条健康的备用线路，都不健康才是第一条；分流与叠加下健康的非备用线路都在承载，其余待命，一条健康的非备用线路都没有时按主备的规则选一条承载。不传健康信息时结果与原来一样。
  - 检：test `linkStandingFollowsTheCoresLinkOrder`
- **D3** 「命中最多」取命中连接数最多的规则：文字是「命中最多：<规则> → <出口>（<占全部连接的百分比>）」；单个 rule_set 只显示集合名；出口是这些连接里最常见的出站，直连类出站写「直连」；并列时取规则文字较小的一个；没有任何连接带规则时不显示。
  - 检：test `topRuleNamesTheMostHitRuleAndItsShare`
- **D5** 最常见的出口未知（内核没给出站）时，「命中最多」不带「→ 出口」，只有规则与占比。
  - 检：test `topRuleOmitsAnExitItDoesNotKnow`
- **D4** gate 全绿；测试计数只因本卡新增的测试而增加，既有测试没有被弱化。
  - 检：cmd `keel assert-guard --card docs/tasks/fix-design-parity-followups.md`

## 证据

RED(swift): fc062fd overviewSubtitleGivesWayToAProblem  # D1
RED(swift): fc062fd linkStandingFollowsTheCoresLinkOrder  # D2
RED(swift): fc062fd topRuleNamesTheMostHitRuleAndItsShare  # D3
RED(swift): c4fea3fb1d89 topRuleOmitsAnExitItDoesNotKnow  # D5

- RED 时的失败原文：D1 `Expectation failed: OverviewCopy.subtitle(links: 2, mode: .bond, server: "东京 VPS", problem: "已连接，但读不到内核：EOF") == "已连接，但读不到内核：EOF"`；D2 `Expectation failed: LinkStanding.all(enabled: three, backup: [], unhealthy: ["en7"], mode: .failover) == ["en7": .standby, "en0": .primary, "en8": .standby]`；D3 `Expectation failed: OverviewCopy.topRule(rows) == "命中最多：geosite-cn → 直连（61%）"`。
- D5 是冻结后加严的一条（复查发现空出口会印成「→ （100%）」）；RED 用 `keel snapshot` 的私有快照，失败原文 `Expectation failed: OverviewCopy.topRule([row]) == "命中最多：geosite-cn（100%）"`。
- 「命中最多」把 DNS 查询也算在内（内核报什么就数什么）。配置按规则分流 DNS 时，这一行可能显示 DNS 那条规则；要不要像连接页的「隐藏 DNS」那样排除，留给作者定。
- 渲染时发现并修掉（2026-11-19）：「命中最多」一行很长时，卡片的理想宽度跟着变长，700 pt 宽的内容区里三张卡片被挤成单列。卡片的理想宽度钉在 190 pt 后，640 / 700 / 804 pt 都是一排，560 pt 叠成单列，长文字中间截断并带悬停提示。
- 本卡没有 author 类判据：三条都是纯函数的行为。接进界面的那几行（副标题、面板与概览的主 / 备、卡片里的一行字）跟着前两张卡的 D8 / D3 一起由作者在真实窗口里看。
GATE: fc062fdfa71f+dirty ok tree:6d4f03791f39 build=0 vet=0 test=0[590p/0f] fmt=0 swift-test=0[128p/0f] apple-build=0 server-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-19)
GATE: a04c760ed5cd+dirty ok tree:46eb8060cbb0 build=0 vet=0 test=0[590p/0f] fmt=0 swift-test=0[129p/0f] apple-build=0 server-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-19)
GATE: b77666fa058e+dirty ok tree:4375fea53244 build=0 vet=0 test=0[593p/0f] fmt=0 swift-test=0[129p/0f] apple-build=0 server-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-19)

## 修订

- D5 新增（加严，不放宽既有判据）：空出口时不印箭头。复查发现，2026-11-19。

## 交接

- 做了什么：副标题在有错误时显示错误；`LinkStanding` 按内核的选线顺序（健康的非备用、健康的备用、不健康）定主 / 备；路由模式卡片加「命中最多」一行（按连接自带的规则计数）；更正了 `fix-overview-design-parity` 范围里那句错话。
- 卡在哪：无。
- 下一步：装到 /Applications 让作者看真实窗口；之后其余页面逐项对照设计稿。
