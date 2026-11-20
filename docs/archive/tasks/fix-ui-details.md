---
type: fix
status: awaiting-author
weight: full
created: 2026-11-20
baseline: 2f8883d (gate: test 593p/0f, swift-test 147p/0f)
---

# 侧栏、试一下、按钮尺寸与配置预览照作者的反馈改；操作失败不再冒充「读不到内核」

## 来源

2026-11-20 作者装上新版后的反馈（附截图）：

- 「试一下」这个地方的 UI 完全不是新的苹果 UI 风格。（真实截图：方角的等宽输入框、一排 small 尺寸的灰色小按钮、其余一片空白。）
- 左侧菜单栏也跟设计稿不一致。（设计稿：选中项是强调色的淡底，图标是强调色的细线图标，诊断是一条脉搏线；App：系统的灰色选中底，诊断是听诊器。）
- 界面上有好多特别小的按钮。（截图是线路与配置行里的「⋯」与「更新」「查看内容」：`fix-pages-design-parity` 里我给药丸按钮加了 `controlSize(.small)`，「⋯」是没有边框的菜单按钮，点击区域只有一个字形大。）
- 配置页会自动把配置预览出来，不对；应该手动点击、需要编辑时才出。（也是 `fix-pages-design-parity` 里我照设计稿加的。）
- 截图里概览的副标题是「已连接，但读不到内核：url test: get command client: probe command server: rpc error: code = DeadlineExceeded…」。内核读得到；失败的是一次延迟测试。`CoreSession.perform` 把一次性操作的失败写进了流错误 `lastError`，于是被当成「读不到内核」，而且一直留到流重连。延迟测试对每个分组各开一个独立客户端并发执行（路由页的测速按钮、面板节点页的测速按钮都是一个循环），19 个分组就是 19 个并发探测，容易超时。

## 范围

- **独占：** `apple/Parallux/Sidebar.swift`（新增）与 `MainWindow.swift` 的侧栏；`Routing/ExplainView.swift` 的「试一下」页；`Design/` 的部件（药丸按钮、更多菜单、搜索框）；`Profiles/ProfilesView.swift` 的预览；`Session/CoreSession.swift` 的 `perform` 与延迟测试；`ParalluxKit` 里本卡新增的纯函数与测试。
- **不碰：** 侧栏的项目与分组（决策 20 的八项）；「试一下」的取数与内核接口；路由页的检查器与分组视图的布局（只换其中过小的按钮）；各页功能。

## 观测面

- 纯 Swift 返回值：`CoreAction.failure`、`StatusLine.text`。
- 画出来的样子：仓库外的脚本渲染侧栏、试一下的各部件、行里的按钮；真实窗口装上之后用无障碍接口切页截图核对。
- GREEN 被截断的方式：失败文案全返回同一句也满足「非空」——测试逐个比对并断言互不相同。

## 环境假设

- SF Symbol `waveform.path.ecg` 存在（2026-11-20 用 `NSImage(systemSymbolName:)` 对拍：true）。
- 侧栏不用系统的选中绑定、自己画选中底之后，`List(.sidebar)` 仍然给出玻璃侧栏与分组标题：动工时在屏幕上渲染对拍，结果写进证据。
- libbox 的 command client 可以在一个连接上连续调用多次 `urlTest`（现在是每次调用新建一个）：读 `CommandTarget.standalone()` 与 `perform` 的用法确认，失败时回到逐个执行并在证据里说明。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** 一次性操作失败时显示的是「什么失败了」：延迟测试、切换节点、切换路由模式、关闭连接、清除日志各有一句不同的短文案，不含底层错误原文；它作为状态行的操作错误显示，不带「读不到内核」。
  - 检：test `actionFailuresSayWhatFailedNotThatTheCoreIsGone`
- **D2** 计数：测试数只因本卡新增的测试而增加（基线 swift-test 147）。
  - 检：cmd `keel gate`
- **D3** 不弱化既有测试。
  - 检：cmd `keel assert-guard --card docs/tasks/fix-ui-details.md`
- **D4** 作者看真实窗口：侧栏选中项是强调色淡底、图标是强调色、诊断是脉搏线图标，键盘上下键仍能切换；「试一下」是药丸形输入框加主按钮、最近的连接是正常大小的药丸按钮、结果在圆角卡片里、没有结果时有一句说明；各页行尾的「⋯」与「更新」等按钮是正常大小（点击区域不小于 28 pt）；配置页不再自动预览，内容从行尾菜单的「查看内容 / 编辑内容」打开。
  - 检：author 逐项看
- **D5** 作者确认：做一次延迟测试（路由页或面板节点页的测速按钮）不再让副标题出现「读不到内核」；真失败时显示「延迟测试失败」，几秒后消失。
  - 检：author 点测速按钮

## 设计

- **侧栏自己画选中底。** 系统侧栏的选中底是灰色，没有接口换成强调色；设计稿（决策 22）要强调色淡底。做法：`List(.sidebar)` 保留（玻璃、分组标题、滚动都是系统的），行是按钮，选中状态自己画，键盘上下键用 `onMoveCommand` 接回来。否决：整个侧栏自己画（丢掉系统的玻璃与折叠行为）；保留系统选中再叠一层底色（两层选中底）。
- **「更多」按钮做成一个部件**（`DesignMoreMenu`）：28 pt 的圆形点击区域，所有行共用。药丸按钮回到 regular 尺寸。开关在页面的行里用 regular，在卡片与面板这些紧凑容器里保留 small（系统自己的检查器与面板也是这样）。
- **搜索框做成一个部件**（`DesignSearchField`），面板节点页与「试一下」共用。
- **操作失败单独存放**（`actionError`），不进流错误；几秒后自动清掉（上限常量带 why），下一次操作成功也清掉。延迟测试改成一个客户端上顺序执行。
- 否决：把底层错误原文放进提示——又长又没有可操作的信息；需要时看日志页。

## 验证命令

```bash
scripts/swift-test.sh /tmp/ui.xml 'actionFailuresSayWhatFailedNotThatTheCoreIsGone'
keel verify-red docs/tasks/fix-ui-details.md
keel gate --record docs/tasks/fix-ui-details.md
```

## 证据

RED(swift): 906023d actionFailuresSayWhatFailedNotThatTheCoreIsGone  # D1

- RED 时的失败原文：`Expectation failed: CoreAction.urlTest.failure == "延迟测试失败"`。
- 上屏渲染对拍（仓库外的脚本，真实的带标题栏窗口里放 `NavigationSplitView`，`screencapture` 截窗口；浅色与深色各一次）：侧栏仍是系统的玻璃侧栏与分组标题，选中项是强调色淡底，图标是强调色，诊断是脉搏线；线路行与配置行里的「⋯」是 28 pt 的圆、「更新」是 regular 尺寸；「试一下」是药丸输入框、主按钮、会换行的最近连接、居中的说明。环境假设里的第二条由此成立。
- 工具栏顺序（同一脚本，照 App 的结构：页面的工具栏项在内层、电源在外层）：电源用 `.primaryAction`、普通 `ToolbarItem`、挂在 `background` 上，三种都排在最前；只有挂在 `overlay` 上排在最后。App 改用 overlay。这一条不在作者这次的清单里，是对照设计稿时顺手改的（设计稿里电源在聚合方式右边）。
- 侧栏的键盘（2026-11-20，脚本里向真实窗口直接送事件，不需要屏幕）：先送一次真实的鼠标点击到「日志」那一行，再送两次 ↓——选中从「线路」变到「聚合服务器」，即点击生效、两次方向键也生效；点击之后窗口的第一响应者是 SwiftUI 的 `KeyViewProxy`，不是表格。另一种情况：人为把表格设成第一响应者后方向键不动（表格自己吃掉了），但真实点击不会走到那一步。对照组（系统选中绑定）同样可用。
- 延迟测试（读 libbox 源码，`experimental/libbox/command_client.go` 与 `daemon/started_service.go`）：`URLTest` 的服务端处理把测试丢进 goroutine 立即返回，调用不会等测试结束，所以顺序调用不会长时间占着按钮；独立客户端每次调用都重新拨号并做一次 2 秒超时的探测（`commandClientProbeTimeout`），调用后只关连接、对象可以再用。截图里的错误正是这次探测超时。环境假设第三条由此成立。**「19 个分组同时拨号导致探测超时」是推断，没有复现过**；顺序执行去掉了并发，是否就此不再超时要在真实 App 里点一次才知道。
- 小按钮的清查做了两遍：第一遍只搜了 `controlSize(.small|.mini)`，而作者截图里的「⋯」根本没有 controlSize——它是没有边框、只有字形的菜单。第二遍按 `buttonStyle(.borderless)`、`menuStyle(.borderlessButton)`、`labelStyle(.iconOnly)` 再搜，补上：分组视图与节点选择器里的测速按钮、分组视图的折叠箭头、设置里按需规则的删除、面板底部的「更多」，都换成 28 pt 的 `DesignIconButton` / `DesignMoreMenu`。面板里聚合服务器的下拉仍是无边框菜单（它带文字，点击区域是整段文字）。
- 之前截下的真实页面（旧版本）看完了：连接、诊断、聚合服务器、配置、日志。这一轮没有动、仍与其他页面不一致的两处：诊断页是居中的系统表单（其他页面是通栏的设计部件）；连接页的直连出站显示成原始的 `direct`。
- 没有验证的：真实 App 里的全部——VoiceOver 读出来的样子；「试一下」取到结果后的卡片；操作失败的提示 6 秒后消失；测速是否不再超时。
- 侧栏自己画选中之后失去的系统行为：类型选择（敲字母跳到对应项）。
GATE: 906023dfbce3+dirty ok tree:e52d6ce0869f build=0 vet=0 test=0[593p/0f] fmt=0 swift-test=0[148p/0f] apple-build=0 server-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-20)
GATE: 0505ddbd6bca+dirty ok tree:278bbc176385 build=0 vet=0 test=0[594p/0f] fmt=0 swift-test=0[148p/0f] apple-build=0 server-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-20)

## 修订

（完成定义无改动。）

## 交接

- 做了什么：侧栏改成自己画选中底（强调色淡底、强调色图标），诊断换成脉搏线图标；「试一下」用公共部件重排；药丸按钮回到 regular 尺寸，「⋯」做成 28 pt 的圆形按钮部件，线路行的开关回到 regular；配置页去掉自动预览；一次性操作的失败单独存放并显示成「延迟测试失败」这样的短句、6 秒后消失，不再写进流错误；延迟测试在一个客户端上顺序执行；电源按钮移到工具栏最右。
- 卡在哪：等作者看真实窗口（D4、D5）。没有合入主干、没有安装。
- 下一步：装上之后用无障碍接口切页截图核对各页，并点一次测速看副标题。
