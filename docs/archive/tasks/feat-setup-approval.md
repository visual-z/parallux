---
type: feat
status: awaiting-author
weight: full
created: 2026-11-19
baseline: db5d519 (gate: test 590p/0f, swift-test 105p/0f)
---

# 授权流程：批准后自动继续、设置清单直达对应面板、错误可读；面板改用系统组件

## 来源

2026-11-19 作者手测与反馈：
1. 「权限申请不是很合理」，问能否用苹果推荐的拖拽授权。
2. 面板「有些地方没用组件」。
3. 截图里状态行直接显示英文系统错误。

调查（2026-11-19）：
- 拖拽授权适用于「隐私与安全性」里的列表（辅助功能、完全磁盘访问等），社区库 PermissionFlow（MIT，★447）支持的面板也全在那里。Parallux 需要的三项都不是这种列表：
  - 网络扩展：系统设置 › 通用 › 登录项与扩展 › 网络扩展，是一个开关列表。本机 macOS 27.2.1 用 `x-apple.systempreferences:com.apple.ExtensionsPreferences?extensionPointIdentifier=com.apple.system_extension.network_extension.extension-point` 打开，截图确认是开关表，没有可拖入的位置。
  - 辅助服务：登录项里的开关。SFM 用 `SMAppService.openSystemSettingsLoginItems()`（`Library/Network/HelperServiceManager.swift`）。
  - VPN 配置：系统弹框，点「允许」。
- SFM 只在扩展报 `FullDiskAccessPermissionRequired` 时引导「完全磁盘访问」（`DashboardViewModel.swift:105`），而它的扩展代码里没有任何地方抛出这个错误（2026-11-19 grep 确认）。Parallux 不需要完全磁盘访问，所以拖拽授权没有用武之地。
- 真正不合理之处是一个缺陷：`SystemExtensionInstaller` 在 `requestNeedsUserApproval` 时就结束了等待，用户批准后系统发来的 `didFinishWithResult` 落到空的 continuation 上被丢弃，App 一直停在「请在系统设置中允许网络扩展」，开关关着，要用户再点一次。一直就有（`feat-sysext-xpc` 起）。

## 范围

- **独占：** `apple/ParalluxKit/Sources/ParalluxKit/Setup/`、对应测试、`apple/Parallux/Tunnel/SystemExtensionInstaller.swift`、`TunnelController.swift` 的安装部分、`apple/Parallux/Setup/`、`PanelView.swift`、`AppModel.statusLine` 的错误映射、`StatusLine` 的错误文案。
- **不碰：** 扩展；XPC；辅助服务的实现（只读它的状态）。不引入 PermissionFlow 等新依赖。

## 观测面

- 纯函数：`ActivationMachine.reduce(state, event)`；`SetupStep.items(status)`；`SystemExtensionErrorText.text(code)`。
- 界面：作者手测；面板截图核对。

## 环境假设

- `OSSystemExtensionRequestDelegate` 在需要批准时先回调 `requestNeedsUserApproval`，用户批准后同一个请求再回调 `request(_:didFinishWithResult:)`（Apple 文档对两个回调的说明；SFM 的 `SystemExtension.swift` 在 needsApproval 时 signal 后不再等结果，说明它也依赖用户再点一次）。待手测确认批准后确实收到 finish。
- 深链 `ExtensionsPreferences?extensionPointIdentifier=…network_extension…` 是社区整理的地址，不是 Apple 文档；本机 27.2.1 可用。打不开时回退到 `SMAppService.openSystemSettingsLoginItems()`。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** 激活状态机：needsApproval 之后再收到 finished → 已激活（不需要用户再操作）；needsApproval 之后收到 failed → 失败；finished(willCompleteAfterReboot) → 需重启；取消替换同版本 → 已激活；同一请求的重复事件不改变终态。
  - 检：property `activationMachineFinishesAfterApproval`
- **D2** 设置清单：系统扩展、VPN 配置、辅助服务、通知四项，每项状态（已完成 / 需要操作 / 不可用）由输入状态唯一决定；前一项未完成时后一项不可操作。
  - 检：test `setupStepsFollowTheirPrerequisites`
- **D3** 系统扩展错误码译成中文（取 SFM 与系统用语），未知码保留原文；状态行不再直接显示英文系统错误。
  - 检：test `systemExtensionErrorsAreReadable`
- **D4** 计数只因本卡新测试增加；不弱化既有测试；gate 全绿。
  - 检：cmd `keel gate`
- **D5** 作者手测：首次点「启动」→ 系统提示 → 点设置清单的「打开系统设置」直达网络扩展面板 → 打开 Parallux 开关后，App 自动完成安装并连接，无需再点；面板全部用系统组件（Form / LabeledContent / Picker / Menu / Button），截图与设计稿一致。
  - 检：author 统一手测

## 设计

- `ActivationMachine`（ParalluxKit，纯 reducer）：状态 idle / requesting / awaitingApproval / activated / needsReboot / failed(code)；事件 submitted / needsApproval / finished(reboot) / failed(code) / cancelledSameVersion。`SystemExtensionInstaller` 改为把回调转成事件交给它，并通过 `AsyncStream` 推送状态，不再用一次性 continuation；`TunnelController` 订阅状态，变为 activated 时自动保存 VPN 配置并按用户原意连接。
- 设置清单 `SetupView`（主窗口概览空态与设置 › 内核共用）：每项一行 `LabeledContent` + 状态图标 + 主操作按钮（「打开系统设置」/「安装」/「允许」），按 SFM 用词。
- 面板：去掉手写的 HStack 行，改为 `Form(.grouped)` 内的 `Picker`、`LabeledContent`、`Menu`、`Button(role:)`，节点下钻用 `NavigationLink`。
- 否决：引入 PermissionFlow 做拖拽——它只覆盖隐私列表，Parallux 用不到（见来源）；新依赖还需先与作者讨论。

## 验证命令

```bash
scripts/swift-test.sh /tmp/setup.xml Setup
keel verify-red docs/tasks/feat-setup-approval.md
keel gate --record docs/tasks/feat-setup-approval.md
```

## 证据

RED(swift): c593fc2 activationMachineFinishesAfterApproval  # D1
RED(swift): c593fc2 setupStepsFollowTheirPrerequisites  # D2
RED(swift): c593fc2 systemExtensionErrorsAreReadable  # D3

- 截图核对（本机，未入库）：面板改为 `Form(.grouped)`，线路为 `Toggle` 行、聚合方式为分段 `Picker`、聚合服务器为 `Menu`、模式为 `Picker`、节点为 `NavigationLink`，节点下钻为 `List`；设置 › 内核的清单在未签名构建下四项显示「不可用」/「授权」。
GATE: 4e8734831f3f+dirty ok tree:c55d360a1e66 build=0 vet=0 test=0[590p/0f] fmt=0 swift-test=0[108p/0f] apple-build=0 server-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-19)
GATE: 71d619046f6b+dirty ok tree:4a60ddf86374 build=0 vet=0 test=0[590p/0f] fmt=0 swift-test=0[108p/0f] apple-build=0 server-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-19)

## 修订

- D2 措辞「前一项未完成时后一项不可操作」与冻结时的测试不一致：测试（c593fc2）只让 VPN 配置依赖系统扩展，辅助服务与通知彼此独立、也不依赖扩展（它们互不需要）。实现按测试走，未放宽测试；措辞请作者确认改为「VPN 配置依赖系统扩展，其余各项独立」。
- 设计里的 `AsyncStream` 改为 `@Observable` 的 `state` 加等待者列表：SwiftUI 直接观察状态，调用方用 `waitForCompletion()` 等待，效果相同、少一层桥接。
- `StatusLineTests` 中 awaitingApproval 的期望文案由「请在系统设置中允许网络扩展」改为「需要在系统设置中授权」，与 D3 的错误码文案（code 13）统一；属断言内容变更，请作者确认。
- 新增仅 DEBUG 的 `-ParalluxPanelPreview YES`（AppDelegate）：状态栏图标被刘海遮住时，把真实弹出面板锚定到主窗口截图。
- 范围外触及（为接线所需，均为小改）：`AppDelegate`（上条）、`MainWindow`（面板「新建服务器…」跳到聚合服务器页）、`SettingsView`（设置 › 内核放入清单）、`OverviewView`（首次运行显示清单）。
- 复查后补修（71d6190）：安装器按请求身份分派回调（属性请求的完成不会被当成激活，属性请求挂起时激活失败不再被吞）；所有等待加上上限（`approvalLimit` 15 分钟、`requestLimit` 60 秒，均为假设值）；清单的系统扩展状态改为向 macOS 查询，不再由「有无 VPN 配置」推断；弹出面板没有工具栏，节点页自带返回、标题与搜索。

## 交接

- 做了什么：激活状态机与安装器重写（批准后自动完成，不用再点）；设置清单（概览首次运行、设置 › 内核）直达「网络扩展」面板；面板改用系统组件。
- 卡在哪：等作者统一手测 D5，并确认修订里的前三条（D2 措辞、StatusLine 断言文案、AsyncStream 改为可观察状态）。
- 下一步：作者手测：签名构建 → 点启动 → 在系统设置里打开 Parallux 开关 → 应自动连接。
