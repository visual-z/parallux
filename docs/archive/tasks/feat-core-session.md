---
type: feat
status: awaiting-author
weight: full
created: 2026-11-18
baseline: a51cc2d (gate: test 8p/0f, swift-test 31p/0f)
---

# 节点、连接、日志、规则四页接上运行中的内核

## 来源

PLAN M2「节点与测速、路由模式、连接、日志」；设计稿 v0.2 的「节点」「连接」「日志」「规则」页与功能对照表；决策 14。SFM 同功能：`Library/Network/CommandClient.swift`、`ApplicationLibrary/Views/Groups`、`Connections`、`Log`。

## 范围

- **独占：** `apple/ParalluxKit/Sources/ParalluxKit/Session/`、对应测试、`apple/Parallux/Session/`、主窗口的节点、连接、日志、规则四页。
- **不碰：** 扩展；XPC 协议；面板与概览布局（`feat-m2-interface`）；`StatusClient` 之外的隧道控制。

## 不变量

- INV-2：日志与速率历史的环形缓冲长度永远不超过容量，并且按到达顺序保留最新的那些条目 — 检查方式：property `aRingBufferKeepsTheNewestEntriesInOrder` + 代码断言。

## 观测面

- 纯 Swift 部分：`RingBuffer`、日志级别映射与筛选、延迟分级、路由模式名、连接搜索、规则解析与命中统计的返回值。
- 界面：签名运行时四页的内容（作者手测）。
- GREEN 被截断的方式：筛选函数对空查询返回空——测试同时断言空查询返回全部；规则解析遇到不认识的字段直接丢弃整条——测试用含未知字段的规则断言仍列出。

## 环境假设

- libbox 1.14.4 command client 一个连接可以同时订阅多种命令（`LibboxCommandClientOptions.addCommand`，头文件已确认），连接事件由 libbox 自带的 `LibboxConnections` 存储合并（SFM `CommandClient.swift` 同做法，读源码确认）。
- sing-box 日志级别编号：panic 0、fatal 1、error 2、warn 3、info 4、debug 5、trace 6（sing-box `log/level.go`，与 SFM `LogLevel` 一致）。
- 路由模式名来自配置的 `experimental.clash_api.default_mode` 与规则里的 `clash_mode`，常见为 Rule / Global / Direct，大小写不定。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** INV-2：容量 0、1 与上限都成立，任意追加序列后保留最新的 min(n, 容量) 条且顺序不变。
  - 检：property `aRingBufferKeepsTheNewestEntriesInOrder`
- **D2** 日志级别按 sing-box 编号映射；按「不低于所选级别」与关键字（忽略大小写）筛选，空关键字不过滤。
  - 检：test `logsFilterByLevelAndText`
- **D3** 延迟分级：未测（≤0）、快（<150 ms）、慢（≥150 ms），边界值 0、1、149、150 各归其类。
  - 检：test `delaysAreGradedAtTheDesignThresholds`
- **D4** 路由模式名忽略大小写译成规则 / 全局 / 直连，其他名字原样显示。
  - 检：test `routeModesAreTitledInChinese`
- **D5** 连接搜索在进程、目标、规则、出站里忽略大小写匹配；空查询返回全部。
  - 检：test `connectionSearchMatchesEveryVisibleColumn`
- **D6** 规则页从配置的 `route.rules` 列出每条规则的条件摘要与动作，未知字段不丢规则；命中数按连接的 rule 字段统计。
  - 检：test `rulesAreListedFromTheProfileWithHitCounts`
- **D7** 计数只因本卡新测试增加；不弱化既有测试；gate 全绿。
  - 检：cmd `keel gate`
- **D8** 作者手测：隧道连接后，「节点」页按分组列出节点和延迟，点选切换 selector 的节点，闪电按钮整组测速；「连接」页实时刷新、可搜索、选中一行显示检查器、可关闭连接；「日志」页实时滚动、可按级别筛选、暂停、清空；「规则」页列出规则与命中数；工具栏能切路由模式。
  - 检：author 按「验证命令」里的手测步骤操作

## 设计

- **ParalluxKit/Session（纯 Swift）**：`RingBuffer<Element>`（固定容量，O(1) 追加）、`LogEntry` / `LogLevel` / `LogQuery`、`DelayGrade`、`RouteMode.title`、`ConnectionRow` / `ConnectionQuery`、`RuleSummary.parse(config:)` 与 `hits`。
- **App/Session**：`CoreSession`（`@MainActor @Observable`）持有一个 command client，订阅 status、group、clash mode；连接与日志各用按需开启的 client（页面出现时连上、消失时断开），避免后台一直搬运连接事件。动作：选节点、测速、切路由模式、关连接、清日志。
- 常量：日志缓冲 3000 行（SFM `logMaxLines` 同值，内存约 1 MB 量级）、速率历史 120 个点（1 秒一个，两分钟曲线），都带 why。
- 否决：自己合并连接事件（libbox 已提供 `LibboxConnections`，自写会与上游语义漂移）；一个 client 订阅全部命令（连接事件量大，页面不可见时也在搬运）。

## 验证命令

```bash
scripts/swift-test.sh /tmp/session.xml Session
keel verify-red docs/tasks/feat-core-session.md
keel gate --record docs/tasks/feat-core-session.md
# 手测（D8）：scripts/build-signed.sh --install；连接后依次打开 节点、连接、日志、规则
```

## 证据

RED(swift): 4751754 aRingBufferKeepsTheNewestEntriesInOrder  # D1
RED(swift): 4751754 logsFilterByLevelAndText  # D2
RED(swift): 4751754 delaysAreGradedAtTheDesignThresholds  # D3
RED(swift): 4751754 routeModesAreTitledInChinese  # D4
RED(swift): 4751754 connectionSearchMatchesEveryVisibleColumn  # D5
RED(swift): 4751754 rulesAreListedFromTheProfileWithHitCounts  # D6

- RED 时的失败原文：D1 `Expectation failed: buffer.elements == Array(reference.suffix(capacity))`；D2 `Expectation failed: LogLevel(sing: 0) == .panic`；D3 `Expectation failed: DelayGrade(milliseconds: 1) == .fast`；D4 `Expectation failed: RouteMode.title("Rule") == "规则"`；D5 `Expectation failed: ConnectionQuery.filter(rows, text: "").map(\.id) == ["1", "2", "3"]`；D6 `Expectation failed: rules.count == 5`。
- 实现中 D6 的测试抓到一个真问题：配置里的未知字段进了匹配键，sing-box 的 Connection.rule 不会打印它，命中数因此为 0。改为只用 sing-box 会打印的条件字段组成匹配键。
GATE: 2ee1b07808fa+dirty ok tree:0c9240fc7c52 build=0 vet=0 test=0[8p/0f] fmt=0 swift-test=0[37p/0f] apple-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-18)

## 修订

（完成定义无改动。）

- 环境假设补读（2026-11-19）：开卡时引用的 sing-box `log/level.go` 当时未读；补读确认 panic 0、fatal 1、error 2、warn 3、info 4、debug 5、trace 6（iota 顺序），与实现一致。
- 规则命中的截断格式在 `fix-rule-hit-truncation` 修正：只有 domain、domain_suffix、domain_keyword、ip_cidr、source_ip_cidr 会截断。

## 交接

- 做了什么：ParalluxKit 会话模型（RingBuffer、日志筛选、延迟分级、路由模式名、连接搜索、规则解析与命中匹配）；App `CoreSession` 取代 `StatusClient`，基础流常开、连接与日志按页面引用计数开关；节点、连接（检查器）、日志、规则四页。
- 卡在哪：等作者手测 D8。
- 下一步：`feat-m2-interface`（面板、概览桑基图、设置窗口按设计稿）。
