---
type: feat
status: awaiting-author
weight: full
created: 2026-11-19
baseline: 714ad45 (gate: test 586p/0f, swift-test 85p/0f)
---

# SFM 对照的最后几项：Tailscale、OpenVPN / OpenConnect 端点、内存上限、概览卡片排序

## 来源

`docs/research/sfm-parity.md` 剩下的「待做」里不依赖并行卡（系统集成、发布）的项：#34 概览卡片开关与排序、#99 Tailscale 状态与出口节点、#101 Taildrop（只做状态与收件数，收发文件按 SFM 的复杂度留作后续并写明）、#103 OpenConnect / OpenVPN 状态与认证挑战、#105 OOM 内存上限。决策 16：统一手测前做完。

## 范围

- **独占：** `apple/ParalluxKit/Sources/ParalluxKit/Endpoints/`、`Interface/DashboardCards.swift`、对应测试、`apple/Parallux/Endpoints/`、主窗口新增「工具」项（侧栏之外的入口：诊断页里的「端点」分区）、概览卡片区、`TunnelStartOptions` 与扩展 `PacketTunnelProvider` 的 OOM 参数。
- **不碰：** XPC 协议；`Settings/`（并行卡）；`core/`。

## 观测面

- 纯函数：`DashboardCards` 的排序与显隐；`EndpointSummary`（端点状态 → 文案与是否需要用户操作）；`TunnelStartOptions` 新字段的编解码往返（已有 property 测试会覆盖，需扩到新字段）。
- 界面：作者手测（需要配置里有对应 endpoint）。

## 环境假设

- libbox 1.14.4 command client 有 `subscribeTailscaleStatus`、`subscribeOpenVPNStatus`、`subscribeOpenConnectStatus`、`setTailscaleExitNode`、`submitOpenVPNChallengeResponse`、`submitOpenConnectAuthResponse`、`cancel…`（头文件已确认）。
- OOM：`LibboxSetupOptions` 有 `oomKillerEnabled`、`oomKillerDisabled`、`oomMemoryLimit`（字节）（头文件已确认）；SFM macOS 默认关闭，开启后上限由用户设（MB）。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** 概览卡片：默认顺序为流量、路由模式、配置；可隐藏任一张、可重排；未知的卡片 id 被丢弃，新增的卡片补到末尾；全部隐藏后「重置」恢复默认。
  - 检：test `dashboardCardsOrderHideAndReset`
- **D2** 端点状态摘要：Tailscale 需要登录时给出登录地址且标为需要操作；OpenVPN / OpenConnect 有挑战时标为需要操作；已连接、连接中、错误各有文案。
  - 检：test `endpointSummariesFlagWhatNeedsTheUser`
- **D3** 启动参数带内存上限（开关与 MB）且往返不丢；上限 0 或关闭时扩展不开 OOM。
  - 检：property `startOptionsSurviveARoundTrip`
- **D4** 计数只因本卡新测试增加；不弱化既有测试；gate 全绿。
  - 检：cmd `keel gate`
- **D5** 作者手测：概览卡片能隐藏与排序；配置含 tailscale endpoint 时诊断页显示状态、登录地址、出口节点可选；含 openvpn / openconnect endpoint 时显示状态并能回应挑战；设置内存上限后扩展日志显示 OOM 已开启。
  - 检：author 统一手测

## 设计

- `DashboardCards`（ParalluxKit）：`order: [Card]`、`hidden: Set<Card>`，`visible` 计算属性；存 `AppSettings`（加字段，缺省用默认）。
- 端点：`EndpointsModel`（App）在诊断页可见时订阅三种状态（`CommandTarget.standalone()` 建 client），转成纯值 `EndpointStatus` 再交给 `EndpointSummary`；挑战表单提交对应 `submit…`。
- Taildrop 收发：SFM 用文件提供者与下载会话，量大；本卡只显示「待接收 n 个文件」，收发留作后续，sfm-parity #101 写明。
- OOM：`TunnelStartOptions` 加 `memoryLimitMB`（0 = 关），扩展 `start` 里设置 `LibboxSetupOptions`；设置入口放在内核标签——那是并行卡的文件，所以本卡把开关放在诊断页「内核」分区，合并后再挪（交接写明）。
- 否决：把 Tailscale SSH 终端（#100）一起做——设计稿明确先不做。

## 验证命令

```bash
scripts/swift-test.sh /tmp/pt.xml Dashboard
keel verify-red docs/tasks/feat-parity-tail.md
keel gate --record docs/tasks/feat-parity-tail.md
```

## 证据

RED(swift): 3a25cef dashboardCardsOrderHideAndReset  # D1
RED(swift): 3a25cef endpointSummariesFlagWhatNeedsTheUser  # D2
RED(swift): 3a25cef startOptionsSurviveARoundTrip  # D3

- RED 时：冻结提交里 `visible` 为空、`decode` 返回默认、`line` 返回空文案、`memoryLimitMB` 解码时恒为 0（property 160 处失败）。
- `TunnelStartOptions` 的解码改为缺字段用默认值：扩展持久化的旧启动参数没有 `memoryLimitMB`，否则按需连接重启会解码失败。
- OpenConnect 的认证是服务端下发的表单（`LibboxOpenConnectAuthForm.fields`），按 `submissionKey` 回填后经 `LibboxNewOpenConnectAuthFormResponse` 提交（sing-box `command_types_openconnect.go:172-183`，读源码确认）；浏览器登录挑战不支持，同 SFM 旧版本。
GATE: 4aaf2c8385e8+dirty ok tree:e38ac222fca8 build=0 vet=0 test=0[587p/0f] fmt=0 swift-test=0[87p/0f] apple-build=0 server-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-19)

## 修订

（无）

## 交接

- 做了什么：概览卡片可隐藏与排序（右键）；诊断页「端点」：Tailscale 状态、登录、出口节点、待收文件数，OpenVPN / OpenConnect 状态与认证；诊断页「内核」：内存上限（扩展启动时开 OOM）。
- 卡在哪：等统一手测 D5。内存上限的开关放在诊断页，系统集成分支合入后可挪到设置 › 内核。
- 下一步：合入系统集成与发布分支。
