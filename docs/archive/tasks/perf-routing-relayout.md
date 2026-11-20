---
type: perf
status: awaiting-author
weight: full
created: 2026-11-20
baseline: a93301acc513 (gate: test 594p/0f, swift-test 152p/0f)
---

# 路由页收起与展开侧栏不再卡：布局时不再解析配置

## 来源

2026-11-20 作者：「展开和收起侧边栏的时候特别卡」（附路由页截图）。

取证（2026-11-20，在作者正在运行的 App 上：路由页，用无障碍接口按了六次侧栏按钮，同时 `sample` 9 秒）：主线程 95% 的时间在忙。其中 55% 在 Core Animation 的提交里，下面是整窗的布局与 `NSHostingView.minSize()` 的尺寸计算（经路由页的 `ScrollView` 量到 `RouteColumns`）。侧栏的动画每一帧都改变内容区的宽度，每一帧都要重新量一遍路线图。

路线图量一次贵在哪：每一行的出口链都调用 `RoutingModel.chain`，它每次都经 `outboundTags` 用 `JSONSerialization` 把整份配置重新解析一遍（采样里 `chain` 4.1%，`outboundTags` 2.6%，都在布局之内）；检查器每次重绘还会再调一次 `map(app:)`，它又对配置做一次覆盖层改写与解析。配置是订阅下来的，上百 KB 很常见。这是 `feat-routing-page` 起就有的写法；侧栏动画只是让它每秒发生六十次。

## 范围

- **独占：** `apple/Parallux/Routing/`（`RoutingModel`、`RoutingView` 的路线图、`NodePicker` 里的检查器）；`ParalluxKit` 的 `ExitChains`（新增）与测试。
- **不碰：** 路由页的外观与交互；`ExitChain.flatten`、`RouteMap.build` 的行为与既有测试；概览（另一张卡）。

## 观测面

- 纯 Swift 返回值：`ExitChains.chain`，对照逐个调用 `ExitChain.flatten`。
- 采样：改动后在真实 App 上重复同样的六次侧栏切换，比较主线程忙碌比例与 `chain` / `outboundTags` 是否还出现在布局之内。
- GREEN 被截断的方式：`ExitChains` 对所有出口返回同一个结果也能让「不为 nil」通过——测试逐个对照参考实现，含环、缺失、空分组。

## 环境假设

- 配置在路由页的生命周期内只在 `load` 时变化（切换配置、更新订阅都会重新调用 `load`）；覆盖层的变化由 `RouteOverrideStore` 发布。读 `RoutingModel.load` 与 `RoutingView` 的 `.task(id:)` 确认。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** 出口链一次算出：给定配置的出站 tag、分组与要显示的出口，`ExitChains` 给出的每条链与逐个调用 `ExitChain.flatten`（出站集合为配置 tag ∪ 分组 tag ∪ 分组成员）的结果相同；没有 tag、没有分组、出口不存在、分组成环、分组为空时也相同；没被问到的出口返回 nil。
  - 检：test `exitChainsComputedOnceMatchFlattening`
- **D2** 计数：测试数只因本卡新增的测试而增加（基线 swift-test 152）。
  - 检：cmd `keel gate`
- **D3** 不弱化既有测试。
  - 检：cmd `keel assert-guard --card docs/tasks/perf-routing-relayout.md`
- **D4** 在真实 App 上同样的六次侧栏切换：`RoutingModel.chain`、`outboundTags`、`JSONSerialization` 不再出现在布局的调用栈里；主线程忙碌比例明显低于 95%（数字写进证据）。
  - 检：measure `sample` 9 秒，脚本同来源一节
- **D5** 作者在路由页反复收起与展开侧栏：动画跟手，不卡。
  - 检：author 路由页点侧栏按钮几次

## 设计

- **配置载入时解析一次。** `load` 里算好出站 tag 与生效的路由配置（覆盖层改写之后的），存起来；`outboundTags`、`effectiveProfile` 变成读缓存。覆盖层变了才重算。
- **出口链随数据每秒算一次，布局只读。** 路线图已经每秒采样一次（`fix-flow-stability`），出口链放进同一份采样结果；检查器也读这份结果，不再自己调 `map(app:)`。
- 否决：给 `chain` 加记忆化缓存——还要处理分组选择变化时的失效，而每秒一次的采样本来就有正确的时机。

## 验证命令

```bash
scripts/swift-test.sh /tmp/relayout.xml 'exitChainsComputedOnceMatchFlattening'
keel verify-red docs/tasks/perf-routing-relayout.md
keel gate --record docs/tasks/perf-routing-relayout.md
```

## 证据

RED(swift): c8db15d exitChainsComputedOnceMatchFlattening  # D1

- RED 时的失败原文：`Expectation failed: chains.chain(exit) == reference(exit, tags: tagSet, groups: groupSet)`。
- 改法：配置的出站 tag 在 `load` 时解析一次；覆盖层改写后的配置只在覆盖层变了时重算；出口链在每秒的路线图采样里一次算好（`ExitChains`），路线图的行与检查器都读这份结果，检查器不再自己重建一份路线图。
- D4（2026-11-20，装上的 build 20261120030257，同样在路由页用无障碍接口按六次侧栏按钮，同时 `sample` 9 秒）：主线程忙碌 95% → 30%；`RoutingModel.chain` 4.1% → 0.0%，`outboundTags` 2.6% → 0.2%（只剩每秒采样的那一次），`RouteColumns` 8.3% → 0.1%，整窗尺寸计算 `sizeThatFits` 24.5% → 4.5%。两次的网络流量不同，忙碌比例只能大致比较。
GATE: c8db15da54fb+dirty ok tree:2b22c0095c4e build=0 vet=0 test=0[594p/0f] fmt=0 swift-test=0[157p/0f] apple-build=0 server-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-20)

## 修订

（完成定义无改动。）

## 交接

- 做了什么：路由页布局时不再解析配置；出口链每秒算一次，布局只读。
- 卡在哪：作者手感（D5）。
- 下一步：装上后重做取证一节的采样，数字写进证据。
