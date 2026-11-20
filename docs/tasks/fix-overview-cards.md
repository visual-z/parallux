---
type: fix
status: awaiting-author        # todo | doing | blocked | awaiting-author | done
weight: full
created: 2026-11-20
baseline: 355e86af57ea
---

# 概览：出口只写速率，卡片不留空白，配置卡显示订阅流量

## 来源

作者 2026-11-20 的截图（概览页，分流，两条线路）标了三处：

1. 出口名字下面的「按连接分到各线路 · 7.4 Kbps」：「这个文案没用，直接去掉」。
2. 流量卡下半截是空的：「响应式有问题」。
3. 配置卡下半截也是空的：「应该显示一个总流量/使用流量的图，如果订阅没有流量就按照使用流量/无限」。

三处都是一直就有的，不是哪次提交带进来的：文案来自设计稿 v0.2；三张卡片等高，是最高的那张（路由模式卡）撑出来的，另外两张的内容高度固定，多出来的地方就空着。

## 范围

- **独占：** `apple/ParalluxKit/Sources/ParalluxKit/Profiles/SubscriptionUsage.swift` 及其测试；`apple/Parallux/Overview/OverviewCards.swift`。
- **接缝：** `OverviewCopy.exitDetail`；`Profile`（加一个可缺省的 `usage` 字段）；`ProfileService` 的下载与更新；`OverviewView` 给配置卡传值；`FlowModel` 调用处。
- **不碰：** 流向图的布局与数据；路由模式卡；面板；`RateFormat`；订阅的下载上限与超时。

## 观测面

- 纯函数的返回值：`SubscriptionUsage.parse(header:)`、`UsageSummary.make(…)`、`OverviewCopy.exitDetail(rate:)`。
- `Profile` 经 JSON 编码再解码后的值；一段没有新字段的旧 JSON 解码后的值。
- 卡片的版面只能看：App 的视图不在 ParalluxKit 的测试里，测试钉不住「看起来不空」。这一条是作者检查。
- GREEN 可能被截断的方式：解析测试如果只给规整的输入，实现照着样例写也能过。挡法：同一个测试里有乱序、大小写、空值、未知键、小数与指数、负数、溢出、只有到期时间、整段 HTML。

## 环境假设

- 订阅服务器用响应头 `subscription-userinfo` 报告用量，格式 `upload=<字节>; download=<字节>; total=<字节>; expire=<Unix 秒>`，各项都可能缺；`total=0` 表示不限量。这是 Clash 系客户端和各家面板通行的约定，没有正式规范。**没有拿作者的真实订阅对拍**：订阅地址在作者的配置库里，我不读它。真实订阅返回什么要等作者更新一次订阅后看配置卡（D7）。
- `HTTPURLResponse.value(forHTTPHeaderField:)` 不区分大小写（Apple 文档）。
- 旧版本存下的配置索引里没有 `usage` 键：Swift 合成的 `Codable` 对可选属性用 `decodeIfPresent`，测试里用一段旧 JSON 钉住。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** 出口名字下面只有速率，三种聚合方式都一样。
  - 检：test `overviewCopyFollowsTheDesign`
- **D2** `subscription-userinfo` 解析出上传、下载、配额与到期：顺序、大小写、空格任意；缺配额或配额为 0 是不限量；`expire=0` 是没有到期；小数与指数写法可读；负数按 0，超出范围的数饱和而不崩溃；只有到期时间、数值不可读、空串、不是这个格式的内容都得不到结果。
  - 检：test `theUserinfoHeaderGivesUsedTotalAndExpiry`
- **D3** 配置卡的用量：有配额时是「已用 X / Y」和 0–1 之间的占比（0、恰好用完、超出都不越界），到期日按用户所在时区的日历日写，过期的写明已到期；订阅报了用量但没有配额时是「已用 X / 无限」、没有占比；订阅什么都没报（或是本地配置）时是「本次会话已用 X / 无限」。
  - 检：test `theProfileCardShowsUsedOverQuotaOrOverUnlimited`
- **D4** 配置的用量随配置一起保存；没有这个字段的旧数据照常读出。
  - 检：test `aProfileKeepsItsUsageAndOlderDataStillLoads`
- **D5** 计数：Swift 176 只因本卡的 3 个新测试增加，Go 625 不变；gate 全绿。
  - 检：cmd `keel gate`
- **D6** 不弱化既有测试（下面 WEAKEN-OK 列出的、因作者要求改变文案的断言除外）。
  - 检：cmd `keel assert-guard --card docs/tasks/fix-overview-cards.md`
- **D7** 作者看：概览三张卡片等高且都没有大块空白（窗口拉宽、拉窄到卡片竖排各看一次）；流量卡的曲线填满卡片；配置卡有用量条，更新一次真实订阅后显示的已用与总量和订阅面板上的一致。
  - 检：author 概览页，窗口宽窄各一次；配置页更新订阅后回到概览

## 设计

- **出口只写速率。** 聚合方式已经写在图的标题（「线路 · 分流 · 32 Kbps」）和窗口副标题里，每个出口下面再重复一遍没有信息量。作者圈的是分流的那句；叠加的「叠加后转发」和主备的「仅主线路」是同一类，一并去掉——这是我的推断，作者只圈了一处。`exitDetail` 不再需要方式参数，只收速率。
- **卡片里要有一样东西能长高。** 三张卡片等高是对的（设计稿），空白来自内容高度写死。流量卡让曲线占满剩下的高度（最小仍是原来的 46 pt）；配置卡把用量块放在底部，中间留弹性。否决：让每张卡片各自按内容定高——一排参差不齐，和设计稿不符。
- **用量从订阅的响应头来，存在配置上。** 下载订阅时顺手读 `subscription-userinfo`，解析结果存进 `Profile.usage`。否决：为了用量单独再请求一次订阅地址——多打一次服务器，订阅服务器普遍限频。更新失败时保留上一次的用量，不清空。
- **没有配额就不画占比。** 「无限」没有分母，条画成空轨道，文字说明已用多少。订阅什么都没报时，手头唯一的数字是内核报的本次会话流量，文字里写明「本次会话」，不冒充订阅的累计用量。否决：自己累计历史流量——要新增持久化的计数和重置规则，超出这张卡。
- 文案：「已用」「无限」「到期」是作者的原话和通行说法；`copy-and-style.md` 的竞品词表里没有对应条目。

WEAKEN-OK: apple/ParalluxKit/Tests/ParalluxKitTests/OverviewDesignTests.swift 出口说明不再带聚合方式的文案，五条断言改为三条只断言速率（作者确认 2026-11-20：「这个文案没用，直接去掉」）

## 验证命令

```bash
scripts/swift-test.sh /tmp/ov.xml SubscriptionUsageTests
keel verify-red docs/tasks/fix-overview-cards.md
keel gate --record docs/tasks/fix-overview-cards.md
```

## 证据

RED(swift): 401c1ed overviewCopyFollowsTheDesign  # D1
RED(swift): 401c1ed theUserinfoHeaderGivesUsedTotalAndExpiry  # D2
RED(swift): 401c1ed theProfileCardShowsUsedOverQuotaOrOverUnlimited  # D3

D4 在冻结点上就是绿的（桩里已经加了字段），用故障补丁证明：构造配置时丢掉用量，测试必须红。

```diff keel-inject(swift) aProfileKeepsItsUsageAndOlderDataStillLoads
--- a/apple/ParalluxKit/Sources/ParalluxKit/Profiles/Profile.swift
+++ b/apple/ParalluxKit/Sources/ParalluxKit/Profiles/Profile.swift
@@ -50 +50 @@
-        self.usage = usage
+        self.usage = nil
```

失败断言原文（RED 时，桩实现下）：

- `Expectation failed: OverviewCopy.exitDetail(rate: 125_000) == "1.0 Mbps"`
- `Expectation failed: SubscriptionUsage.parse(header: "upload=1073741824; download=2147483648; total=107374182400; expire=179…`
- `Expectation failed: quota.text == "已用 \(RateFormat.bytes(25 * gib)) / \(RateFormat.bytes(100 * gib))"`
GATE: ca2e06283fe4+dirty ok tree:283f1724838d build=0 vet=0 test=0[625p/0f] fmt=0 swift-test=0[179p/0f] apple-build=0 server-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-20)

## 修订

- 装到本机后看到用量文字在 " / " 处折成两行（「本次会话已用 5.3 MB / 无限」，卡片宽约 217 pt）：圆环从 52 pt 改为 46 pt，文字允许先缩到 85% 再折行。只动了版面，D3 钉的文字没变。

## 交接

- 做了什么：出口下面只写速率；流量卡的曲线占满卡片剩余高度；配置卡底部加了用量环（有配额画占比和百分比，没有配额画空环和 ∞）与「已用 X / Y」；下载或更新订阅时读 `subscription-userinfo` 存进配置。2026-11-20 装到本机截图看过一次（分流、两条线路、窗口默认大小）：三张卡片等高、没有空白，出口只有速率。
- 卡在哪：D7 等作者看。两件事我没验证：窗口拉窄到卡片竖排时的样子；真实订阅返回的用量——作者现有的订阅是旧版本更新的，还没有用量，更新一次之后才会显示订阅报的数字，在那之前显示的是「本次会话已用 … / 无限」。订阅如果不发这个响应头，就一直是后者。
- 下一步：作者在配置页点一次更新，回概览看用量是否与订阅面板一致。
