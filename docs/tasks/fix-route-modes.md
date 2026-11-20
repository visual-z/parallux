---
type: fix
status: awaiting-author        # todo | doing | blocked | awaiting-author | done
weight: full
created: 2026-11-20
baseline: 24eef98c918d
---

# 订阅没有定义模式时，路由模式也能在规则、全局、直连之间切换

## 来源

作者 2026-11-20 的截图：概览的路由模式卡片里只有「规则」一个按钮，「我也没办法切换规则 全局 等等之类的功能」。面板和右键菜单里的路由模式同样只有一项。

一直就有，不是哪次提交带进来的。sing-box 没有内置的模式：它给出的模式列表是从配置里带 `clash_mode` 的规则读出来的（`experimental/clashmode/mode_list.go`），再把默认模式 `Rule` 放在最前面。作者的订阅里没有这种规则，列表就只有 `Rule`。界面如实显示了内核给的列表，所以没得切。

## 范围

- **独占：** `apple/ParalluxKit/Sources/ParalluxKit/Routing/RouteModes.swift` 及其测试；`core/aggregate/modes_test.go`；`core/aggregate/testdata/composed-modes.json`。
- **接缝：** `AppModel.compose`（多一步）；`core/pxbridge` 的夹具校验测试。
- **不碰：** 订阅文件本身（只在连接时改写，和「改走」一样）；路由页显示的规则（它读的是订阅，不是改写后的配置）；路由覆盖层的规则编号；模式的名字与标题（`RouteMode.title`）；自己定义了模式的订阅。

## 观测面

- 纯函数 `RouteModes.add(to:)` 的输出：规则的位置、形状、指向的出站。
- 真实的路由器：`core/aggregate/modes_test.go` 起一个 sing-box 实例，带上和系统扩展里一样的模式管理器，逐个模式拨号，数两个出站各被拨了几次。
- 夹具交给 `libbox.CheckConfig`。
- GREEN 可能被截断的方式：
  - 只断言「加了两条规则」会放过加错位置或指错出站的实现：逐条比较规则的 JSON，并断言订阅自己的规则顺序不变。
  - 路由测试如果模式根本没切过去，三种模式的结果会一样而「规则」那几条照样通过：同一个目标在不同模式下的期望不同（`other.test` 在规则与全局下走代理、直连下走直连；`example.com` 相反），并先断言内核给出的模式列表。
  - 生成器很少产出「没有模式的订阅」时 property 证明不了什么：断言至少 100 轮确实加了规则。

## 环境假设

2026-11-20 对拍，都固化在 `TestTheAddedModeRulesRouteByTheSelectedMode` 里：

- 带平台日志写入器的 sing-box（系统扩展里就是这样）总会创建模式管理器，不需要配置 `experimental.clash_api`；测试构建里没有 clash api，配置了反而起不来（`clash api is not included in this build`）。
- 没有 `clash_mode` 规则时模式列表是 `[Rule]`；加上本卡的两条规则后是 `[Rule, Global, Direct]`。逻辑规则里面的 `clash_mode` 也算。
- 模式名比较不区分大小写（`strings.EqualFold`）。
- 逻辑规则 `and(clash_mode=Global, 非 ip_is_private)`：目标是域名（没有 IP）时「非私网」成立，走全局；目标是私网 IP 时不成立，落到后面的规则。
- 内核把这两条规则印成 `clash_mode=Direct` 与 `clash_mode=Global && !(ip_is_private=true)`（`route/rule/rule_abstract.go`），界面据此给连接起名。
- **未证实，留给作者手测：** 在装好的 App 里切换模式后，已有的连接不会被切断重连（sing-box 只对新连接生效）；选中的模式在重连后是否保留（取决于缓存文件）。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** 没有定义模式的订阅在连接时多出两条规则：直连模式全部走订阅的直连出站；全局模式除私网地址外全部走订阅的主代理。两条规则排在只做准备的规则（嗅探、解析、劫持 DNS、路由选项，以及旧写法里指向 dns 出站的规则）之后、订阅自己的第一条分流规则之前；订阅自己的规则和其余部分原样不动。
  - 检：test `aProfileWithoutModesGetsDirectAndGlobal`
  - 检：test `modeRulesComeAfterTheRulesThatOnlyPrepareAConnection`
- **D2** 全局模式的去向：`route.final` 指向分组或节点时就是它；指向直连、拦截、不存在的出站或没有写时，取第一个分组，没有分组取第一个节点；没有任何节点时不加全局模式。直连模式用订阅里第一个直连出站；订阅里没有就加一个，名字不与已有出站冲突。
  - 检：test `globalTargetsTheProfilesMainProxy`
- **D3** 订阅自己定义了任何模式（路由规则、逻辑规则里面、DNS 规则）时一个字节都不改；不是 JSON 的内容原样返回。
  - 检：test `aProfileWithItsOwnModesIsLeftAlone`
- **D4** 对任意订阅：订阅自己的规则按原顺序保留；规则指向的出站都存在；加两次等于加一次。
  - 检：property `addingModesKeepsEveryRuleAndNeverDangles`
- **D5** 真实路由器上，三种模式的走向符合 D1，全局模式下私网地址仍按订阅的规则走；内核给出的模式列表是规则、全局、直连。
  - 检：test `TestTheAddedModeRulesRouteByTheSelectedMode`
- **D6** 加了模式再组合线路的结果固化成夹具，libbox 接受它。
  - 检：test `composedModesFixtureMatchesTheGenerator`
  - 检：test `TestTheComposedModesProfilePassesLibboxCheckConfig`
- **D7** 被模式规则决定的连接在概览和连接页里叫「直连模式」「全局模式」。
  - 检：test `connectionsDecidedByAModeAreNamedAfterIt`
- **D11** 直连模式下域名交给订阅自己的本地 DNS 服务器解析（`type: local`，或 1.12 之前写法的 `address: local`），规则排在订阅的 DNS 规则最前面，其余 DNS 规则顺序不变；订阅没有本地服务器、服务器没有 tag 或没有 dns 一节时什么都不加。
  - 检：test `directModeResolvesNamesWithTheProfilesLocalServer`
- **D8** 计数只因本卡的新测试增加；gate 全绿。
  - 检：cmd `keel gate`
- **D9** 不弱化既有测试。
  - 检：cmd `keel assert-guard --card docs/tasks/fix-route-modes.md`
- **D10** 作者手测：代理开着时，概览、面板、右键菜单的路由模式都有规则、全局、直连三项；切到全局后新开的网页走代理（包括原本直连的国内网站），局域网设备照常访问；切到直连后全部直连；切回规则恢复原样。
  - 检：author 概览 › 路由模式，三种模式各开一个网页，看连接页的出站

## 设计

- **在连接时给配置补两条规则，不改订阅。** 这是 sing-box 官方文档里写模式的惯用法（`{"clash_mode": "Direct", "outbound": …}`、`{"clash_mode": "Global", "outbound": …}`），内核据此给出三种模式，界面不用动。放在 `AppModel.compose` 里「改走」之后、组合线路之前：「改走」按规则编号改写，先做它编号就不会错位；组合线路会把直连出站换成聚合出站但保留 tag，所以直连模式下流量照样分到各条线路。
- 否决：
  - 在界面上自己做一个三选一，切换时换一份配置重载。重载会断开所有连接，而内核的模式切换只影响新连接；还要自己记住选中的模式。
  - 只在界面上把另外两项画出来但置灰。作者要的是能切。
- **全局模式不带走私网地址。** 写成 `and(全局, 非私网)`：私网目标落到订阅自己的规则，和规则模式下一样。不这样的话切到全局，NAS、打印机、路由器管理页就都发给代理了。不在两条规则前面单加一条「私网直连」：那会改变规则模式下的行为，而规则模式必须和订阅写的一模一样。
- **和竞品不同的一处**：GUI.for.SingBox 与 sing-box-subscribe 的全局模式把私网地址也发给代理（它们的私网规则排在全局规则后面）。这里选择不带走私网，理由见上一条；这是实现的选择，待作者确认。Surge 的全局模式是否绕开局域网，手册里没有查到。
- **全局去哪里**：取订阅「其余流量」去的地方（`route.final`），因为那是订阅作者心目中的「代理」；它指向直连或拦截（白名单式的订阅）时退到第一个分组。
- **代理开关关着时不加。** 那时用的是全直连的配置，没有可选的去向；路由模式只剩「规则」一项是对的。诊断页自带的探测配置也不加（按原样运行）。
- 自己定义了模式的订阅不动，哪怕它只定义了一种：订阅作者写了模式规则，就是他要的行为。

## 验证命令

```bash
scripts/swift-test.sh /tmp/rm.xml RouteModesTests
go test ./core/aggregate -run TestTheAddedModeRulesRouteByTheSelectedMode -count=1
keel verify-red docs/tasks/fix-route-modes.md
keel gate --record docs/tasks/fix-route-modes.md
```

## 证据

RED(swift): e2006f1 aProfileWithoutModesGetsDirectAndGlobal  # D1
RED(swift): e2006f1 modeRulesComeAfterTheRulesThatOnlyPrepareAConnection  # D1
RED(swift): e2006f1 globalTargetsTheProfilesMainProxy  # D2
RED(swift): e2006f1 addingModesKeepsEveryRuleAndNeverDangles  # D4
RED(swift): e2006f1 composedModesFixtureMatchesTheGenerator  # D6

D3 与 D7 在冻结点上就是绿的（桩什么都不改；模式规则的名字此前已经能认），用故障补丁证明这两个测试抓得住东西：不再看逻辑规则里面的模式，D3 必须红；去掉按模式起名，D7 必须红。

```diff keel-inject(swift) aProfileWithItsOwnModesIsLeftAlone
--- a/apple/ParalluxKit/Sources/ParalluxKit/Routing/RouteModes.swift
+++ b/apple/ParalluxKit/Sources/ParalluxKit/Routing/RouteModes.swift
@@ -118 +118 @@
-            return definesModes((rule["rules"] as? [[String: Any]]) ?? [])
+            return false
```

```diff keel-inject(swift) connectionsDecidedByAModeAreNamedAfterIt
--- a/apple/ParalluxKit/Sources/ParalluxKit/Routing/RouteModel.swift
+++ b/apple/ParalluxKit/Sources/ParalluxKit/Routing/RouteModel.swift
@@ -264 +264 @@
-        if let mode = items["clash_mode"]?.first { return "\(RouteMode.title(mode))模式" }
+        if let mode = items["no_such_key"]?.first { return "\(RouteMode.title(mode))模式" }
```

D11 是冻结之后加的：不加那条 DNS 规则，测试必须红。

```diff keel-inject(swift) directModeResolvesNamesWithTheProfilesLocalServer
--- a/apple/ParalluxKit/Sources/ParalluxKit/Routing/RouteModes.swift
+++ b/apple/ParalluxKit/Sources/ParalluxKit/Routing/RouteModes.swift
@@ -100 +100 @@
-            dns["rules"] = [["clash_mode": direct, "server": local]] + dnsRules
+            dns["rules"] = dnsRules
```

D5 测的是 sing-box 的路由器在这两条规则下的行为，不是本仓库的代码，没有可注入的故障；它在动工前就跑过（见环境假设），用途是保证规则的形状在真实内核里成立。

失败断言原文（RED 时，桩实现下）：

- `Expectation failed: now.count == was.count + 2`
- `Expectation failed: try position(nil) == 0`
- `Expectation failed: try targets(usualOutbounds, final: "Proxy").global == "Proxy"`
- `core/aggregate/testdata/composed-modes.json is missing`
GATE: 456626c4ddea+dirty ok tree:6535856179c3 build=0 vet=0 test=0[627p/0f] fmt=0 swift-test=0[187p/0f] apple-build=0 server-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-20)

## 修订

- D11（冻结之后加的判据，只加严）：竞品调研回来后补的。GUI.for.SingBox 的默认规则（`frontend/src/constant/profile.ts`）和 sing-box-subscribe 的模板都给模式规则配了对应的 DNS 规则；人们切到直连往往正是因为节点不通，这时经节点的 DNS 服务器什么都解析不出来。随之改了 `aProfileWithoutModesGetsDirectAndGlobal` 里「其余部分不变」的断言：dns 一节现在多一条规则，改为分别断言服务器不变、规则恰好是这一条，比原来更严。夹具重新生成，diff 是 dns 下多了六行。
- 测试修正（不改判据）：`addingModesKeepsEveryRuleAndNeverDangles` 里「这份订阅有没有自己的模式」原先按抽到的规则算，而八轮里有一轮生成的订阅根本没有规则，抽到什么都不算数，测试自己记错了账。改为按订阅实际的规则算。D4 的文字未动。

## 交接

- 做了什么：连接时给没有定义模式的订阅补两条路由规则（直连模式、全局模式）和一条 DNS 规则（直连模式下用订阅的本地 DNS）。订阅文件不改；自己定义了模式的订阅不动；代理开关关着时不加。真实路由器上三种模式的走向测过（`TestTheAddedModeRulesRouteByTheSelectedMode`）。界面没有改：模式列表本来就读内核给的，现在内核会给三项。
- 卡在哪：D10 等作者手测。没有在装好的 App 里实际切换过；切换后已有连接是否保留、重连后模式是否记得，都没验证。全局模式不带走私网地址，这一点和 GUI.for.SingBox、sing-box-subscribe 不一样，是实现的选择，待作者确认。
- 下一步：作者装上新版后在概览切一次全局和直连，看连接页的出站。
