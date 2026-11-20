---
type: feat
status: awaiting-author
weight: full
created: 2026-11-19
baseline: 4b1a7d3 (gate: test 589p/0f, swift-test 96p/0f)
---

# 路由页：路线图与分组两种视图、展平的出口链、节点选择器、试一下、改走

## 来源

决策 20（2026-11-19）：作者评审 `docs/design/routing-v0.3.html` 后要求按它实现，并保留一个 Clash 式的旧视图；遵循 macOS 26 的 Apple 设计规范。取代主窗口的「节点」与「规则」两页。

## 范围

- **独占：** `core/pxbridge/explain.go`、`apple/ParalluxKit/Sources/ParalluxKit/Routing/`、对应测试、`apple/Parallux/Routing/`、`SidebarItem`（合并为 `.routing`）、`MainWindow` 的路由入口、扩展 XPC 新增 `explainRoute`、`AppModel` 的覆盖层接入（组合时改写规则出站）。
- **不碰：** `core/aggregate`、`core/bond`；面板（面板的节点下钻保留）；连接与日志页（只加「为什么走这里」入口）。

## 不变量

- INV-6：覆盖层改写后的配置里，每条规则的出站仍是一个存在的 tag；只改写被覆盖的规则，其余规则逐字节不变 — 检查方式：property `overridesOnlyTouchTheirRulesAndNeverDangle`。

## 观测面

- 纯函数（ParalluxKit）：`RouteMap.build`（规则 + 分组 + 连接 → 流量类别、出口、展平的链、速率）、`ExitChain.flatten`、`TrafficLabel.name`、`NodeRegion.infer`、`LatencyGrade`、`RouteOverrides.apply`。
- Go：`pxbridge.ExplainRoute` 对夹具配置的输出（命中规则序号、动作、出站链）。
- GREEN 被截断的方式：展平遇到环（selector 互相引用）死循环——测试含环且断言有上限；解释接口对未命中的目标返回空——测试断言落到 `route.final`。

## 环境假设

- 扩展里能拿到运行中的 router：libbox `CommandServer` 嵌入 `*daemon.StartedService`，其 `Instance().Box().Router().Rules()` 返回规则，每条有 `Match(*InboundContext)` 与 `Action()`（sing-box 源码 `daemon/started_service.go:2114`、`daemon/instance.go:199`、`box.go:664`、`adapter/rule.go:9-19`，2026-11-19 读源码确认）。gomobile 不导出这些类型，所以解释函数放在 Go 侧，经 pxbridge 以 JSON 字符串交出；扩展用 libbox 的 command server 句柄调用它。待对拍：pxbridge 能否拿到扩展里那个 `*libbox.CommandServer`——方案是扩展创建后把它注册给 pxbridge（`pxbridge.SetCommandServer`）。
- 规则匹配需要的元数据：只填 `Domain`、`Destination`、`Network`、`Protocol`（若猜得出）；`process_*` 与 `rule_set` 的远程规则集在运行时已加载，能直接匹配。依赖嗅探的规则（`protocol`）在「试一下」里只能按端口推断，界面注明。
- 延迟三档阈值 400 / 800 ms（设计稿 v0.3）。新增 `LatencyGrade` 给路由页用；v0.2 的 `DelayGrade`（150 ms 一刀切）及其测试不动，面板与诊断页以后再统一。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** 出口链展平：selector 跟随选中项、urltest 跟随当前选中、到非分组出站为止；遇到环或超过 8 层停止并标记；不存在的 tag 标为缺失。
  - 检：test `exitChainsFlattenAndStopOnCycles`
- **D2** 路线图：每条路由规则一个流量类别（带默认名与出口），`route.final` 作为「其余流量」；速率按连接的 rule 字段归到类别；只显示有出站的规则（sniff、hijack-dns 等动作不显示）；超过 12 类时按速率保留前 12，其余合并计数。
  - 检：test `theRouteMapGroupsTrafficByRule`
- **D3** 流量类别默认名：常见 geosite / geoip 规则集有中文名，域名规则用主域名，其余用条件摘要；用户重命名优先。
  - 检：test `trafficLabelsReadLikeTheDesign`
- **D4** 节点地区：从旗帜表情或地名推断，未知归「其他」；倍率标签（「0.5 倍率」「x2」）单独提取；延迟三档：未测、<400、<800、≥800。
  - 检：test `nodeRegionsAndMultipliersAreInferred`
- **D5** INV-6：改走覆盖只改写对应规则的出站，其余规则不变，不产生指向不存在出站的规则；指向已不存在出站的覆盖被忽略并报告。
  - 检：property `overridesOnlyTouchTheirRulesAndNeverDangle`
- **D6** Go 解释：对夹具配置，`youtube.com` 命中 rule_set 规则并给出序号与出站，局域网 IP 命中私有地址规则，未命中的目标落到 final；不打印配置之外的数据。
  - 检：test `TestExplainRouteReportsTheMatchingRule`
- **D7** 计数只因本卡新测试增加；不弱化既有测试；gate 全绿。
  - 检：cmd `keel gate`
- **D8** 作者手测：路由页两种视图可切换且记住选择；路线图连线随流量变化，点类别只高亮其路径；出口检查器的节点选择器能筛地区、排延迟、选节点；分组视图（Clash 式）能折叠、测速、选节点；试一下给出逐步解释；改走后规则显示「已覆盖」，重连后生效，可撤销；深浅色下都清楚。
  - 检：author 统一手测

## 设计

- **ParalluxKit/Routing**：`RouteProfile`（从配置 JSON 取规则：序号、条件摘要、动作、出站；取 `route.final`）、`ExitChain`、`RouteMap`、`TrafficLabel`、`NodeRegion`、`LatencyGrade`、`RouteOverrides`（按配置 id 保存：规则序号 + 原条件指纹 → 新出站、名称；指纹防止订阅更新后规则移位改错规则）。
- **Go**：`pxbridge.SetCommandServer(server)`、`pxbridge.ExplainRoute(target string) string`（JSON：步骤列表）。
- **App/Routing**：`RoutingView`（工具栏分段：路线图 / 分组 / 试一下；搜索；全部测速）、`RouteMapView`（左右两列 + Canvas 连线，宽度按速率；Liquid Glass 只用在工具栏与检查器）、`GroupsView`（Clash 式：分组标题、选中项、折叠、测速、节点网格）、`NodePicker`（地区筛选、延迟排序与分布、子分组行）、`ExplainView`、`RerouteSheet`。用系统控件：`Picker(.segmented)`、`.inspector`、`.searchable`、`Table`/`List`、`ContentUnavailableView`、SF Symbols；颜色只用语义色与 `.tint`。
- 否决：把解释放在 Swift 侧重写匹配（规则种类多，必然与 sing-box 漂移）。

## 验证命令

```bash
go test -count=1 -run TestExplainRoute ./core/pxbridge/
scripts/swift-test.sh /tmp/rt.xml Route
keel verify-red docs/tasks/feat-routing-page.md
keel gate --record docs/tasks/feat-routing-page.md
```

## 证据

RED(swift): 53ad784 exitChainsFlattenAndStopOnCycles  # D1
RED(swift): 53ad784 theRouteMapGroupsTrafficByRule  # D2
RED(swift): 53ad784 trafficLabelsReadLikeTheDesign  # D3
RED(swift): 53ad784 nodeRegionsAndMultipliersAreInferred  # D4
RED(swift): 53ad784 overridesOnlyTouchTheirRulesAndNeverDangle  # D5
RED: 53ad784 -run ^TestExplainRouteReportsTheMatchingRule$ ./core/pxbridge/  # D6

- RED 时：冻结提交里全是桩，Swift 五条与 Go 一条全部失败（Go：`youtube = {RuleIndex:0 …}, want rule 2 to proxy-stand-in`）。
- 冒烟（2026-11-19，DEBUG 构建 `-ParalluxPreview YES` 夹具，只在 DEBUG 编译）：路线图、分组、试一下三种视图在 1300×820 与 820×560 截屏核对过；窄窗口时路线图退成单列。之后按 `docs/design/copy-and-style.md` 改了文案（SFM / Clash Verge Rev 用词，例如「延迟测试」「代理组」「编辑规则」「已覆写」「评估连接」）。
GATE: e06f27eec9d8+dirty ok tree:efde039b2b55 build=0 vet=0 test=0[590p/0f] fmt=0 swift-test=0[104p/0f] apple-build=0 server-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-19)

## 修订

（完成定义无改动。）

- 既有测试 `theSidebarShowsNineItemsInThreeSectionsInDesignOrder` 改为 `theSidebarShowsEightItemsInThreeSectionsInDesignOrder`：期望从九项改成八项（节点、规则合成路由）。这是决策 20（作者 2026-11-19 选定）规定的界面变化，不是放宽断言——断言仍是逐项精确相等。

## 交接

- 做了什么：路由页三种视图（路线图、分组、试一下）；展平的出口链与节点选择器；pxbridge `ExplainRoute` 经 XPC；按配置保存的规则覆写，在组合时应用；连接检查器「评估连接」跳到试一下。
- 卡在哪：等统一手测 D8。
- 下一步：合入并行的界面润色分支（配置、线路、设置等页）。
