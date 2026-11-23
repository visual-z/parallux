---
type: fix
status: doing       # todo | doing | blocked | awaiting-author | done
weight: full
created: 2026-11-23
baseline: a5caf406f403
---

# 没有聚合服务器时选不了叠加，不再悄悄按主备运行

## 来源

作者 2026-11-23 的截图：测速时流量始终只走一条线路，流向图的标题写着「主备」，而保存的聚合方式是叠加。原因是这台 Mac 上没有添加过聚合服务器，叠加在没有服务器时按主备运行，只在面板的选择器下面有一行小字。

一直就有，不是哪次提交带进来的。这是同一个误会第二次出现：上一次只在面板里补了那行提示，概览、设置、菜单里都没有，而且新安装的默认方式就是叠加，所以每个新装的用户一上来都在按主备运行。

作者 2026-11-23 的决定（两个选项里选的）：没有服务器时不让选叠加，点「叠加」直接打开聚合服务器的设置，设置完成前保持原来的方式；新安装的默认方式改为分流。

同一轮作者问「不能本机起一个聚合服务吗」：不能让单条连接变快，重组点必须在两条线路之后（`docs/research/bond-without-vps-2026-11-20.md` 的判据）。要不要做「App 经 SSH 自动把聚合服务器装到自己的机器上」还没有定，不在本卡。

## 范围

- **独占：** `apple/ParalluxKit/Sources/ParalluxKit/Links/ModeChoice.swift` 及其测试；`LinkSettings` 与 `AppSettings` 的默认聚合方式；`AppModel` 里改聚合方式、换服务器、增删服务器的入口；面板、概览工具栏、设置、菜单栏菜单、聚合服务器页、链接导入、快捷指令这七处对它们的调用；`keel.toml` 的一条边界规则；`PLAN.md` 决策表、`docs/INVARIANTS.md`、`docs/MANUAL-TEST.md`。
- **不碰：** `ProfileComposer` 与内核的 aggregate（组合结果不变）；运行中才出现的两种退回主备（只剩一条物理线路、钥匙串里的密钥读不出），它们的提示 `AggregationNotice.text` 原样保留；聚合服务器的链接格式；菜单栏图标。

## 不变量

- INV-16：保存的聚合方式是叠加时，一定选中了一台在列表里的聚合服务器；列表不空时选中的服务器一定在列表里，列表空时没有选中的服务器 — 检查方式：property

## 观测面

- 纯函数：`LinkSettings.choose`、`serversChanged`、`useServer` 的返回值与改动后的 `LinkSettings`；`AggregationMode.menuTitle`。界面只调用它们。
- 谁在改：边界规则保证 `apple/Parallux` 里除 `AppModel.swift` 外没有任何文件直接给 `mode`、`bondServerID` 赋值或增删服务器。
- GREEN 可能被截断的方式：
  - 测试借被测代码自己的判断来断言不变量：INV-16 在测试里另写一遍，不调用产品代码。
  - property 的随机序列如果从没走到「列表为空」「列表已满」或「叠加」，等于没测：断言三者都出现过；每一步还核对 `choose` 的返回值与「叠加且列表为空」是否一致。
  - 只测新写的设置会放过旧数据：用旧版本会存下的 JSON（叠加、没有服务器；叠加、服务器已不在列表里）解码后再检查。
  - 边界规则写了但匹配不到任何东西：加规则时现有的四个文件还在直接赋值，先跑一次确认它红，再改。

## 环境假设

- **未证实，留给作者手测（D8）：** 分段控件的选择被拒绝后会不会回到原来那一段。SwiftUI 的 `Picker` 与面板自己包的 `NSSegmentedControl` 只在视图重绘时才把选中的段改回绑定的值；拒绝一次选择并不改变保存的方式，视图未必重绘。实现上不依赖它自己回弹：`AppModel` 每拒绝一次就让一个计数加一，三处控件拿这个计数当身份，被拒绝后整个重建。这是按文档推出来的做法，没有在装好的 App 里看过。
- 没有其他外部假设：其余都是 `LinkSettings` 上的纯逻辑。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** 新安装的聚合方式是分流：`LinkSettings()`、缺少 `mode` 字段的旧数据都是分流；默认方式不需要聚合服务器。
  - 检：test `aFreshInstallStartsInAModeThatNeedsNoServer`
- **D2** 列表里没有聚合服务器时选叠加：设置一个字节都不变，返回「需要服务器」。有服务器时选叠加：生效，并且用的是列表里的服务器（原来选中的还在就沿用，否则用第一台）。选分流或主备从不需要服务器。
  - 检：test `choosingBondWithoutAServerChangesNothingAndAsksForOne`
  - 检：test `choosingBondWithAServerAppliesAndUsesAListedServer`
  - 检：test `choosingBalanceOrFailoverNeverNeedsAServer`
- **D3** 旧版本存下的「叠加、没有可用服务器」在启动时变成分流；服务器还在、只是存的那台不在了，叠加保留并改用列表里的第一台。
  - 检：test `settingsSavedAsBondWithoutAServerBecomeBalance`
- **D4** 删除正在用的服务器：还有别的就改用下一台，方式不变；删到一台不剩时，叠加改为分流，其他方式不变。
  - 检：test `removingTheServerInUseMovesToTheNextAndTheLastOneEndsBond`
- **D5** 因为选叠加才去添加服务器的，添加之后自动切到叠加；没有选过叠加的，添加之后方式不变，新服务器只是备好；再添加一台不会抢走正在用的那台；只能改用列表里的服务器。
  - 检：test `addingAServerAfterAskingForBondFinishesTheSwitch`
  - 检：test `usingAServerOnlyTakesListedOnes`
- **D6** INV-16 对任意操作序列成立（选方式、添加、删除、清空、改用、读入旧数据；服务器数从 0 到上限）。
  - 检：property `anyChoiceSequenceKeepsBondBehindAServer`
- **D7** 菜单里的「叠加」在没有服务器时写作「叠加…」（点了会打开别的地方），有服务器时与其他方式一样只写名字。
  - 检：test `aMenuMarksBondAsOpeningSomethingWhileThereIsNoServer`
- **D8** `apple/Parallux` 里只有 `AppModel.swift` 直接改聚合方式、选中的服务器和服务器列表。
  - 检：cmd `keel check-boundaries`
- **D9** 计数：测试数只因本卡新增的测试而增加（基线 swift-test 191、go test 627）。
  - 检：cmd `keel gate`
- **D10** 除下方 WEAKEN-OK 列出的、因默认方式改变而改的那一条断言外，不弱化既有测试。
  - 检：cmd `keel assert-guard --card docs/tasks/fix-bond-needs-server.md`
- **D11** 作者手测（`docs/MANUAL-TEST.md` 4.9–4.12）：没有聚合服务器时，在面板、概览工具栏、设置、菜单栏右键菜单里点「叠加」，都会打开主窗口的聚合服务器页，页面上说明原因，聚合方式停在原来那一项；粘贴链接添加服务器后自动变成叠加；删除最后一台服务器前有确认，删除后变成分流；快捷指令设置叠加时报「请先添加聚合服务器」。
  - 检：author 统一手测

## 设计

**规则放在一处。** 现在有七处直接写 `mode` 或 `bondServerID`（面板两处、概览、设置、菜单、聚合服务器页三处、链接导入、快捷指令），「叠加要有服务器」这条规则只能靠事后的 `effectiveMode` 去发现并退回。改成三个纯函数（选方式、服务器列表变了、改用某台服务器），`AppModel` 是唯一的调用方，界面只调 `AppModel`；再加一条边界规则把它钉住。这样不变量是在写入时保证的，不是在读取时补救的。

**为什么不是「没有服务器就按分流运行」。** 我给作者的推荐是它：Peplink 在没有对端时按会话分流（[connectivity101](https://connectivity101.com/peplink-101/bonding-behaviors/)：负载均衡「No tunnel is required」，聚合「require a tunnel endpoint on the far side」），Connectify Dispatch 也是按连接放到不同网口。作者选了更严格的一种：界面上选的方式永远等于运行的方式，不存在任何「选的是甲、跑的是乙」。两种做法里默认方式都得改成分流，这一点没有分歧。

**为什么不是本机起一个聚合服务。** 见来源。检索到的聚合产品（Speedify、Peplink、OpenMPTCProuter）都在远端重组；不要服务器的做法（aria2 多网口、dispatch-proxy）都只对多条连接有效，也就是我们的分流。

**删除正在用的服务器时改用下一台，不是清空。** 原来的做法是清空，于是「列表里有服务器、却一台都没选中、方式是叠加」这个状态是可达的，它同样会悄悄按主备运行。现在列表不空就一定有一台选中，面板里也不能把唯一选中的那台取消。

**留下的两种运行时退回。** 叠加运行中只剩一条物理线路（网线被拔掉；决策 24 定的是退回主备），和钥匙串里的密钥读不出。两者都不是用户选出来的，拦不住；提示 `AggregationNotice.text` 照旧。后者现在的提示文字是「尚未设置聚合服务器」，不准确，记在交接里，不在本卡改。

**默认方式改了既有断言。** `InterfaceTests` 里 `fresh.defaultAggregationMode == .bond` 断言的正是被作者改掉的默认值；`LinkSettingsTests` 要求两处默认值一致，所以 `AppSettings.defaultAggregationMode` 跟着改成分流。这个字段现在没有任何读取方，是否删掉留给作者。

WEAKEN-OK: apple/ParalluxKit/Tests/ParalluxKitTests/InterfaceTests.swift 新安装的默认聚合方式由叠加改为分流，断言的取值随之改变（作者确认 2026-11-23）

## 验证命令

```bash
scripts/swift-test.sh /tmp/t.xml ModeChoiceTests
keel check-boundaries
keel verify-red docs/tasks/fix-bond-needs-server.md
keel gate --record docs/tasks/fix-bond-needs-server.md
```

## 证据

<!-- RED 的 commit 在开卡提交之后填入。 -->

开卡时的失败断言（占位实现保持现有行为）：

- `aFreshInstallStartsInAModeThatNeedsNoServer`：`LinkSettings.defaultMode == .balance`
- `choosingBondWithoutAServerChangesNothingAndAsksForOne`：`settings.choose(.bond, servers: []) == .needsServer`
- `choosingBondWithAServerAppliesAndUsesAListedServer`：`none.bondServerID == first`
- `settingsSavedAsBondWithoutAServerBecomeBalance`：`bare.mode == .balance`
- `removingTheServerInUseMovesToTheNextAndTheLastOneEndsBond`：`bonded.bondServerID == second`
- `addingAServerAfterAskingForBondFinishesTheSwitch`：`asked.choose(.bond, servers: []) == .needsServer`
- `usingAServerOnlyTakesListedOnes`：`settings.bondServerID == second`
- `anyChoiceSequenceKeepsBondBehindAServer`：`bondIsBehindAServer(settings, servers)`，第 0 步，叠加、0 台服务器
- `aMenuMarksBondAsOpeningSomethingWhileThereIsNoServer`：`AggregationMode.bond.menuTitle(hasServer: false) == "叠加…"`
- `choosingBalanceOrFailoverNeverNeedsAServer` 开卡时就是绿的：它钉的是不许变的行为，不算 RED。

## 修订

## 交接

- 做了什么：开卡，九个红测试和保持现有行为的占位实现。
- 卡在哪：还没有实现。
- 下一步：实现三个纯函数，把七处入口收到 `AppModel`，加边界规则。
