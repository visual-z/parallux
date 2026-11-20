---
type: fix
status: awaiting-author
weight: full
created: 2026-11-19
baseline: 3ff23db (gate: test 593p/0f, swift-test 136p/0f)
---

# 线路、配置、聚合服务器、诊断、连接、日志与设置窗口照设计稿 v0.2 排版与用词

## 来源

2026-11-19 作者看过概览与面板的改动后决定：其余页面「全都按你说的干，以设计稿为准」（决策 22，本卡的冻结提交里登记）。此前 `chore-ui-polish-secondary` 按 `docs/design/copy-and-style.md` 把这些页面改成了系统的 `List(.inset)` / `Form(.grouped)` 与竞品用词；作者对同一做法的面板节点页的评价是「跟设计稿的风格很不契合」。同一次回复里作者还定了：「命中最多」排除 DNS 查询。

## 范围

- **独占：** `apple/Parallux/Design/`（新增，设计稿的公共部件）；`apple/Parallux/Links/LinksView.swift`、`Profiles/ProfilesView.swift` 的列表页、`Bond/AggregationServersView.swift`、`DiagnosticsView.swift` 的测速一节、`Session/SessionPages.swift`（连接、日志）、`Settings/SettingsView.swift` 的文案；`ParalluxKit` 里本卡新增的纯函数与测试；`docs/design/copy-and-style.md`。
- **不碰：** 路由页（决策 20，设计稿 v0.3）；各页的功能与数据（只换排版与用词，不增不减功能）；设置里「配置重载」三项的名称（它们对应 SFM 的具体行为，设计稿只画了一项，不猜对应关系）；诊断页的网络质量、端点、接口探测三节（设计稿没有画，保持系统表单）；设计稿里要内核配合才有的数据（每条连接的线路分摊、网关与 MTU、RTT 与丢包、服务器带宽、重组后的出口；见 `docs/research/design-additions.md`），不放假数据。

## 观测面

- 纯 Swift 返回值：`OverviewCopy.topRule`、`SpeedTest.fractions`、`ConnectionCopy.duration`。
- 画出来的样子：仓库外的一次性脚本用设计稿的数字渲染各页的行与部件；真实窗口由作者看。
- GREEN 被截断的方式：比例函数对空输入、全失败提前返回而测试只跑正常情况——测试跑 0 条、1 条、全部失败、含 0 速率；时长函数只测一个量级——测试跑 0、59、60、3599、3600 与负数。

## 环境假设

- SwiftUI 的 `.draggable` / `.dropDestination(for: String.self)` 在 macOS 26 可用，行内的按钮与开关仍能点击（Apple 文档；交互本身只能由作者在真实窗口里确认）。
- `Connection.rule` 与 DNS 判定沿用 `ConnectionQuery.isDNS`（53 端口或嗅探到的 DNS 协议，SFM 同款），不新增判定。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** 「命中最多」不计 DNS 查询：统计与占比的分母都只含非 DNS 的连接；只有 DNS 连接命中规则时不显示。
  - 检：test `topRuleLeavesDNSLookupsOut`
- **D2** 测速条的比例：每条等于它的速率除以最快的一条，在 0…1 之间；失败或速率为 0 的是 0；没有结果时为空；全部失败时全是 0。
  - 检：test `speedTestFractionsAreSharesOfTheFastest`
- **D3** 连接持续时间的写法：不足一分钟「N 秒」，不足一小时「M 分 S 秒」，再长「H 小时 M 分」；负数按 0。
  - 检：test `connectionDurationReadsAsTheDesignWritesIt`
- **D8** 拖动排序的换位：把一行拖到另一行上，它占那一行的位置（往下拖落在目标之后，往上拖落在目标之前）；拖到自己、未知的行或未知的目标上不动；给出的偏移量与 `move(fromOffsets:toOffset:)` 的同一次移动等价。
  - 检：test `aRowDroppedOnAnotherTakesItsPlace`
- **D4** 计数：测试数只因本卡新增的测试而增加（基线 swift-test 136）。
  - 检：cmd `keel gate`
- **D5** 不弱化既有测试。
  - 检：cmd `keel assert-guard --card docs/tasks/fix-pages-design-parity.md`
- **D6** 作者看真实窗口，下列页面与设计稿 v0.2「主窗口」一节一致，功能与改动前相同：线路（圆角列表卡片；行里是线路色圆形图标、名称与网口、地址、状态与速率、开关；「仅备用」在行尾的更多菜单里并在名称后有标记；可拖动排序；同一出口时有橙色提示条）；配置（圆角列表卡片；行里是类型图标、名称与「使用中」标记、说明、远程配置的「更新」按钮、更多菜单；点一行即选用；可拖动排序；下方是选中配置的只读预览）；聚合服务器（圆角列表卡片，「在线 / 待命 / 不可用」标记与延迟；「添加服务器」标题旁是主按钮，下方是安装命令的代码块）；诊断的测速一节（标题旁主按钮「开始测试」，每条线路一行彩色比例条）；连接（列名「进程 / 目标 / 规则 / 出站 / ↓ / 流量」，规则是小标签；检查器是「进程 / 规则 / 出站链 / 协议 / 持续」加「关闭连接」）；日志（等宽、圆角底框，级别着色）。
  - 检：author `scripts/build-signed.sh --install` 后逐页对照设计稿（`docs/MANUAL-TEST.md` 2.4g）
- **D7** 作者看设置窗口，用词与设计稿「设置窗口」一节一致：通用（登录时启动、关闭窗口后保留在菜单栏及其说明、菜单栏显示实时速率）、聚合（默认聚合方式）、隧道（五项中文名下面是属性名；「配置覆盖」）、按需连接（启用按需连接及其说明、添加规则…）、内核（系统扩展「已安装 · 版本 …」、重新安装、内核版本）。
  - 检：author ⌘, 打开设置逐个标签看

## 设计

- **一套公共部件，不是每页各画各的。** `apple/Parallux/Design/DesignComponents.swift`：页面容器（统一页边距）、列表卡片（可选拖动排序）、标记、区块标题、代码块、提示条、说明文字、键值表。概览的卡片改用同一个填充色。各页只负责把数据摆进部件里；行视图只收值与闭包，仓库外的脚本能单独渲染。
- **控件仍是系统控件**（按钮、开关、菜单、表格）；自己画的只有容器与标记。与面板的取舍一致。
- **拖动排序**用 `.draggable` / `.dropDestination`，线路与配置共用列表卡片里的同一段实现。否决：线路与配置保留 `List`、其余用卡片——同一种外观两套实现，行高与分隔线对不齐。
- **连接页保留系统 `Table`**：设计稿画的就是一张平铺的表，系统表格自带列宽调整与选中，只换列名与单元格样式。设计稿的「线路」列要内核按连接记录线路（待做），这一列的位置暂时放「流量」（排序菜单里有按流量排序）。
- **日志**用 `LazyVStack`：最多 3000 行（`CoreSession.logCapacity`），整段拼成一个 `Text` 每来一行都要重排全部文字。
- 否决：照设计稿把服务器页的「服务器带宽」「重组后的出口」两张卡片先摆上——没有数据来源，摆了就是假数据。

## 验证命令

```bash
scripts/swift-test.sh /tmp/pages.xml 'topRuleLeavesDNSLookupsOut|speedTestFractionsAreSharesOfTheFastest|connectionDurationReadsAsTheDesignWritesIt'
keel verify-red docs/tasks/fix-pages-design-parity.md
keel gate --record docs/tasks/fix-pages-design-parity.md
```

## 证据

RED(swift): 19bfc63 topRuleLeavesDNSLookupsOut  # D1
RED(swift): 19bfc63 speedTestFractionsAreSharesOfTheFastest  # D2
RED(swift): 19bfc63 connectionDurationReadsAsTheDesignWritesIt  # D3
RED(swift): ed13abe7bb69 aRowDroppedOnAnotherTakesItsPlace  # D8

- RED 时的失败原文：D1 `Expectation failed: OverviewCopy.topRule(rows) == "命中最多：geosite-cn → 直连（75%）"`；D2 `Expectation failed: SpeedTest.fractions([result(500)]) == [1]`；D3 `Expectation failed: ConnectionCopy.duration(0) == "0 秒"`；D8 `Expectation failed: ListReorder.moving("a", onto: "c", in: ids) == ["b", "c", "a", "d"]`（`keel snapshot` 的私有快照）。
- 渲染对拍（仓库外的一次性脚本，离屏窗口，不进仓库）：用设计稿的数字渲染了线路行（宽、窄、深色）、聚合服务器行与添加区、测速条、配置行与预览、日志框、检查器的键值表、四种标记。线路页第一版各行的地址列没有对齐（右侧状态列宽度随文字变），给状态列定宽后对齐。
- 没有验证的：各页在真实窗口里的整体样子与全部交互——拖动排序（`.draggable` / `.dropDestination`，行内开关与菜单是否仍然好点）、点配置行选用、连接表格与检查器、日志滚动到底、设置窗口的用词。脚本里主按钮是灰的：离屏窗口不是活动窗口，系统的强调色按钮不着色；真实窗口里应为强调色，没有看到。
- 与设计稿仍不同、且是有意的：连接页「线路」列的位置放的是「流量」；服务器页没有「服务器带宽」「重组后的出口」两张卡片；线路页没有网关、MTU、RTT、丢包；设置 › 隧道「配置覆盖」三项沿用 SFM 的名称；设置 › 通用没有「在菜单栏中显示」「语言」（没有对应的设置）。都因为没有数据或功能，见范围。
GATE: 19bfc6362b5e+dirty ok tree:199b52604ae0 build=0 vet=0 test=0[593p/0f] fmt=0 swift-test=0[140p/0f] apple-build=0 server-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-19)

## 修订

- 既有测试 `topRuleNamesTheMostHitRuleAndItsShare`（`fix-design-parity-followups` D3）里有一条断言用 `protocol=dns` 作例子，证明的是「非规则集的条件保留 key=value 写法」。D1（作者 2026-11-19 定：排除 DNS）之后这个例子本身不再成立，换成了 `process_name=curl`，断言数量与要证明的事不变。
- D8 新增（加严，不放宽既有判据）：拖动排序的换位规则原来只写在「设计」里，动工时抽成了纯函数，补一条判据与测试。2026-11-19。

## 交接

- 做了什么：新增 `apple/Parallux/Design/` 一套公共部件（页面容器、列表卡片含拖动排序、标记、区块标题、代码块、提示条、键值表、比例条）；线路、配置、聚合服务器三页改成设计稿的列表卡片；配置页加了选中配置的只读预览（最多 40 行）；诊断的测速结果改成比例条；连接页换列名、规则改成小标签、检查器改成键值表并显示持续时间；日志改成等宽底框；设置窗口换成设计稿的用词；「命中最多」不再计 DNS。登记了决策 22。
- 卡在哪：等作者逐页看（D6、D7），步骤在 `docs/MANUAL-TEST.md` 2.4g、2.4h。
- 下一步：按作者的意见调整；之后回到 `perf-flow-animation`（流量变化时 6–7%，超出 5%）。
