---
type: feat
status: awaiting-author
weight: full
created: 2026-11-19
baseline: 8b2d9be (gate: test 8p/0f, swift-test 47p/0f)
---

# 线路探针加两组对照：App 内不经隧道的同款探针，和经 sing-box `direct` + `bind_interface` 的探测配置

## 来源

2026-11-19 审查：`research-sysext-bind-interface` 的探针只在扩展内、隧道开着时跑原始 `IP_BOUND_IF`。
- 没有对照组：1.1.1.1:80 不可达时每个网口都是 ETIMEDOUT，与绑定失败分不开。
- 没测决策 13 的真实路径：分流与主备用的是 sing-box `direct` 出站的 `bind_interface`，不是原始 socket。
源码对拍（2026-11-19）：Darwin 上 sing-box 用 `interfaceFinder.Update()`（`net.Interfaces()`，全部系统网口）解析 `bind_interface` 的名字（`route/network.go:274-286`），再 `IP_BOUND_IF`（sing `common/control/bind_darwin.go`）；所以第二条线路能按名字找到，问题只剩隧道起来后内核是否放行。

## 范围

- **独占：** `apple/ParalluxKit/Sources/ParalluxKit/Links/LinkProbeProfile.swift`、对应测试、`apple/Parallux/DiagnosticsView.swift`、`docs/research/sysext-bind-interface.md` 的方法一节。
- **不碰：** XPC 协议；扩展；`research-sysext-bind-interface` 的完成定义。

## 观测面

- 探测配置生成器的输出（JSON 结构）；App 运行时再经 `LibboxCheckConfig` 校验。
- 诊断页三列结果：App 内（不经隧道或隧道关着时）、扩展内原始绑定、sing-box 出站测速。

## 环境假设

- sing-box `urltest` 分组对每个成员出站测延迟，结果出现在 command client 的 group 消息里（`OutboundGroupItem.urlTestDelay`，头文件已确认）。
- App 进程的 socket 在隧道开着时也走隧道；所以 App 内对照组要在隧道关着时跑才是「不经隧道」。诊断页写明这一点，并记录跑的时候隧道是否开着。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** 探测配置为每个候选网口生成一个 `direct` 出站（`bind_interface` 为网口名、tag 为 `probe-<网口>`），一个包含全部探测出站的 `urltest` 分组，tun 入站与 DNS 与示例配置一致；没有候选网口时不生成。
  - 检：test `theProbeProfileHasOneBoundDirectPerInterface`
- **D2** 计数只因本卡新测试增加；不弱化既有测试；gate 全绿。
  - 检：cmd `keel gate`
- **D3** 作者手测：随 `research-sysext-bind-interface` D3 一起——隧道关着时点「App 内检测」，再用「探测配置连接并测速」，三组结果都拷贝贴回。
  - 检：author 主窗口 › 诊断

## 设计

- `LinkProbeProfile.make(interfaces:)` 纯函数输出 JSON 字符串；`urltest` 的 url 用 `http://cp.cloudflare.com/generate_204`（sing-box 文档示例同类地址），interval 设长（10 分钟）避免后台测速，诊断页手动触发 `urlTest`。
- 诊断页：「App 内检测」直接调 `LinkProbe`（与扩展内同一函数）；「探测配置连接并测速」用生成的配置重连（断开当前隧道，提示会切换配置），连上后对 `probe` 分组调 `urlTest`，读 `session.groups`。
- 否决：把探测出站注入用户自己的配置——改写用户配置的结构，且与 M3 的线路出站生成重复，留给 M3 正式做。

## 验证命令

```bash
scripts/swift-test.sh /tmp/pp.xml ProbeProfile
keel verify-red docs/tasks/feat-probe-arms.md
keel gate --record docs/tasks/feat-probe-arms.md
```

## 证据

RED(swift): 4c5d69f theProbeProfileHasOneBoundDirectPerInterface  # D1

- RED 时的失败原文：`Expectation failed: LinkProbeProfile.make(interfaces: ["en0", "en7"])`（返回 nil）。
- 另加两条测试把 Swift 生成器与 Go 侧校验接起来：`theGeneratorMatchesTheFixtureLibboxChecks`（生成结果与 `core/pxbridge/testdata/probe-profile.json` 相等）与 `TestTheLinkProbeProfileShapePassesLibboxCheckConfig`（libbox 接受该夹具）。演示过：把夹具的 interval 改成 11m，Swift 测试红；改回后绿。
GATE: 0049f3603b37+dirty ok tree:40a129cbed2a build=0 vet=0 test=0[9p/0f] fmt=0 swift-test=0[49p/0f] apple-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-19)

## 修订

（无）

## 交接

- 做了什么：探测配置生成器（每网口一个 direct + bind_interface，urltest 分组）；诊断页三组：App 内对照、扩展内原始绑定、sing-box 测速，可一键拷贝全部结果。
- 卡在哪：等作者随研究卡 D3 一起手测 D3。
- 下一步：更新 sfm-parity、PLAN 状态与 PROGRESS，然后交给作者。
