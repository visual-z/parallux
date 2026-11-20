---
type: feat
status: awaiting-author
weight: full
created: 2026-11-19
baseline: 159e636 (gate: test 8p/0f, swift-test 37p/0f)
---

# 面板、右键菜单、概览、设置窗口与菜单栏图标按设计稿 v0.2 实现

## 来源

PLAN 决策 7（界面以设计稿 v0.2 为准）、M2「隧道设置」「路由模式」、M5「菜单栏模板图标」中不依赖签名的部分（决策 14）；设计稿各节：菜单栏面板与右键菜单、主窗口概览、设置窗口六个标签、菜单栏图标五种状态。2026-11-18 作者确认设计稿只决定布局与交互，词与配置格式以 PLAN 与词表为准。

## 范围

- **独占：** `apple/ParalluxKit/Sources/ParalluxKit/Interface/`、对应测试、`apple/Parallux/PanelView.swift`、`AppDelegate.swift`、`SettingsView.swift`、`apple/Parallux/Overview/`、`apple/Parallux/Settings/`、`TunnelController` 的启动参数与按需连接。
- **不碰：** 扩展；XPC；`core/`；线路发现、线路开关、聚合方式生效、聚合服务器（M3、M4）——界面上这些控件显示为停用并写明里程碑，不做假数据。

## 不变量

- INV-3：流向图布局里，每个节点的高度等于流经它的各股流带宽度之和，左右两侧总高度相等，都等于总速率换算的高度 — 检查方式：property `aSankeyLayoutConservesWidth` + 代码断言。

## 观测面

- 纯 Swift：`SankeyLayout` 的几何、`AppSettings` 的读写、设置到 `TunnelStartOptions` 的映射、按需规则校验、`MenuBarIcon` 生成的图像、`FlowSummary` 的出口汇总。
- 界面：作者手测。
- GREEN 被截断的方式：布局对 0 总量返回空而测试只查非空情况——测试显式跑 0、1、上限；映射漏一个开关而测试只比较一个——测试逐字段翻转每个开关。

## 环境假设

- 菜单栏图标用 `NSImage(size:flipped:drawingHandler:)` 画、`isTemplate = true`，系统负责深浅色与高亮（AppKit 文档）；在 `swift test` 里能光栅化（AppKit 在 macOS 测试进程可用，`RateFormat` 之外的首个 AppKit 测试，动工时对拍）。
- `SMAppService.mainApp.register()` 实现「登录时启动」，不需要额外权限（macOS 13+；SFM 同做法）。
- 按需连接用 `NETunnelProviderManager.onDemandRules`；SSID 匹配在 macOS 上可用（`NEOnDemandRule.ssidMatch`），SFM `OnDemandRule.swift` 同模型。
- 连接的实时速率：libbox `Connection.uplink` / `downlink` 是每个统计间隔的速率（sing-box `daemon/started_service.go` 计算 delta，读源码确认）。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** INV-3：任意输入（0 条、1 条、多条流，速率含 0 与上限）下守恒；流带两端落在对应节点范围内；总速率为 0 时没有流带。
  - 检：property `aSankeyLayoutConservesWidth`
- **D2** 设置有设计稿的默认值，写入后从同一 UserDefaults 读回一致。
  - 检：test `settingsRoundTripThroughUserDefaults`
- **D3** 隧道设置逐项进入启动参数：翻转任意一个开关，只有对应字段变化。
  - 检：property `everyTunnelSettingReachesTheStartOptions`
- **D4** 按需规则：Wi‑Fi 名称规则要求名称非空，探测规则要求 http(s) 地址；规则列表编解码往返不变。
  - 检：test `onDemandRulesValidateAndRoundTrip`
- **D5** 菜单栏图标五种状态（未连接、分流、叠加、主备、线路异常）都是 18×18 pt 模板图，两两像素不同。
  - 检：test `menuBarIconsAreDistinctTemplates`
- **D6** 出口汇总：按连接的实时速率把流量归到「直连」或节点，按速率降序，超过 4 个出口时其余合并为「其他」；没有流量时为空。
  - 检：test `flowSummaryGroupsTrafficByExit`
- **D7** 计数只因本卡新测试增加；不弱化既有测试；gate 全绿。
  - 检：cmd `keel gate`
- **D8** 作者手测：面板布局与设计稿一致（开关、迷你流向图、线路、聚合方式、出口、打开主窗口、更多）；右键菜单各项可用；概览有流向图、流量曲线、路由模式与系统代理、配置卡片；设置窗口六个标签，通用、隧道、按需连接、内核里的控件真实生效；菜单栏图标随状态变化，深浅色下都清楚。
  - 检：author 按「验证命令」里的手测步骤操作

## 设计

- **ParalluxKit/Interface**：`SankeyLayout`（纯几何：输入左右节点的速率与流，输出节点矩形与流带端点）、`AppSettings`（Codable，存 UserDefaults 的一个键；`startOptions(content:)` 产出启动参数）、`OnDemandRuleModel`、`MenuBarIcon`（AppKit 画 18 pt 模板图）、`FlowSummary`。
- **概览**：左列是线路（M3 之前只有「默认网口」一条，名称来自 NWPathMonitor），中间汇流柱，右列是出口汇总；宽度 = 实时速率。速率曲线来自 `CoreSession.rateHistory`。没有流量时显示空状态，不画假数据。
- **面板**：照设计稿分区；线路区显示当前网口（只读）；聚合方式分段控件停用并注明「M3 接入」；出口区是路由模式菜单与节点下钻（列表 + 搜索 + 测速）。
- **右键菜单**：开启/关闭、聚合方式（停用）、路由模式、节点（每个 selector 分组一个子菜单）、配置、打开主窗口 ⌘O、设置 ⌘,、退出 ⌘Q。
- **设置**：通用（登录时启动、菜单栏显示速率、关窗后保留）；聚合（默认聚合方式，停用并注明 M3）；隧道（SFM 同款的 NE 参数与配置覆盖）；按需连接（开关与规则列表）；内核（扩展版本、重新安装、卸载、内核版本）；远程控制（M5，标签保留、内容写明尚未提供）。设计稿里的语言、更新通道属 M6，不放假控件。
- 否决：在概览里用模拟数据画三条线路（设计稿的演示数据）——会让作者误以为 M3 已完成。

## 验证命令

```bash
scripts/swift-test.sh /tmp/ui.xml
keel verify-red docs/tasks/feat-m2-interface.md
keel gate --record docs/tasks/feat-m2-interface.md
# 手测（D8）：scripts/build-signed.sh --install；左键面板、右键菜单、主窗口概览、⌘, 设置
```

## 证据

RED(swift): c8c13f9 aSankeyLayoutConservesWidth  # D1
RED(swift): c8c13f9 settingsRoundTripThroughUserDefaults  # D2
RED(swift): c8c13f9 everyTunnelSettingReachesTheStartOptions  # D3
RED(swift): c8c13f9 onDemandRulesValidateAndRoundTrip  # D4
RED(swift): c8c13f9 menuBarIconsAreDistinctTemplates  # D5
RED(swift): c8c13f9 flowSummaryGroupsTrafficByExit  # D6

- RED 时的失败原文：D1 `Expectation failed: layout.left.count == left.count`；D2 `Expectation failed: AppSettings.load(from: defaults) == changed`；D3 `Expectation failed: options[keyPath: option] == settings.tunnel[keyPath: setting]`；D4 `Expectation failed: OnDemandRuleModel(match: .wifi(ssid: ""), action: .connect).problem != nil`；D5 图像尺寸不是 18×18；D6 `Expectation failed: exits.count == FlowSummary.maxExits + 1`。
- D6 的测试在冻结后改过一个字面量：总和 640 是我算错了（100+50+420+30+20+10+5 = 635），实现是对的；改成 635 是修正测试的算术，不是放宽断言，assert-guard 通过。
- 冒烟（2026-11-19，不签名构建）：主窗口概览、面板布局与菜单栏模板图标截屏核对过；发现并修正「Zero KB」（ByteCountFormatter 默认写文字），加了 `byteTotalsAreAlwaysNumeric`。
GATE: d44a273c3ef1+dirty ok tree:9e806a2b5a92 build=0 vet=0 test=0[8p/0f] fmt=0 swift-test=0[44p/0f] apple-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-19)

## 修订

（完成定义无改动。）

- 范围说明（2026-11-19，审查发现）：实现中还改了「独占」以外的文件：`apple/Parallux/Session/CoreSession.swift`（连接行带上实时速率与出站类型）、`apple/ParalluxKit/Sources/ParalluxKit/Session/SessionModels.swift`（`ConnectionRow` 加字段，冻结提交里已含）、`Tunnel/SystemExtensionInstaller.swift`（卸载与读版本）、`RateFormat.swift`（「Zero KB」修正）。都是为本卡的功能服务的最小改动，未改既有断言。
- 环境假设更正（2026-11-19）：「Connection.uplink / downlink 是每个统计间隔的速率，读源码确认」当时并未读到填值处。补读：libbox `command_types.go:146` 把每次 UPDATE 事件的 `UplinkDelta` 写进 `Uplink`；delta 由 `daemon/started_service.go:972` 按订阅间隔计算，间隔取 `statusInterval`（我们设 1 秒），无流量时发一次 0。所以在 1 秒间隔下它就是字节每秒，结论成立。

## 交接

- 做了什么：`AppModel` 统一连接路径；面板（开关、迷你流向、线路、聚合方式（停用待 M3）、出口与节点下钻、更多）；右键菜单（开关、聚合方式、线路、路由模式、节点、配置、⌘O、⌘,、⌘Q）；概览（流向图、速率曲线、路由模式与系统代理、配置卡片）；设置六个标签；菜单栏模板图标与可选速率；按需规则写进 NETunnelProviderManager。
- 卡在哪：等作者手测 D8。
- 下一步：辅助服务（SMAppService.daemon，决策 12）与 `sfm-parity.md` 重判，完成 M2 剩余项。
