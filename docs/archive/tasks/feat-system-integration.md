---
type: feat
status: awaiting-author
weight: full
created: 2026-11-19
baseline: a562c88 (gate: test 586p/0f, swift-test 80p/0f)
---

# 小组件、控制中心开关、快捷指令、parallux:// 链接、/Applications 检查、内核通知与关于页

## 来源

PLAN M5「小组件、控制中心、快捷指令」与 `docs/research/sfm-parity.md` 的 #9（导入链接的 URL scheme）、#108（快捷指令）、#110（关于与源码链接）、#111（内核通知）、#112（必须在 /Applications）。决策 16：现在写完，作者统一手测。SFM 同功能：`WidgetExtension/ServiceToggleControl.swift`、`WidgetTunnelControl.swift`、`IntentsExtension/Intents.swift`、`Library/Network/UserServiceXPC.swift`（扩展把通知转给用户会话）。

## 范围

- **独占：** 新 target `ParalluxWidget`（`apple/ParalluxWidget/`）；`apple/Parallux/Intents/`、`apple/Parallux/URLRouter.swift`、`apple/Parallux/AppModel+Shared.swift`、`apple/Parallux/ApplicationsLocation.swift`、`apple/Parallux/WidgetSnapshotWriter.swift`、`apple/Parallux/Settings/AboutSection.swift`；`apple/ParalluxKit/Sources/ParalluxKit/System/` 与对应测试；`SettingsTab.swift`（加 `.about`）。
- **只加少量行：** `apple/project.yml`（新 target、URL types）、`AppDelegate.swift`（启动时 3 行调用 + 一个 `application(_:open:)` 方法）、`Settings/SettingsView.swift`（switch 加一行）、`apple/PacketTunnel/ExtensionPlatform.swift`（只改 `send` 与 `cancelNotification`）、`TunnelXPC.swift` 与 `CommandXPCService.swift`（追加方法）、`scripts/check-apple-config.sh`、`scripts/build-signed.sh`、`docs/LICENSES.md`（追加行）。
- **不碰：** `core/`、`server/`、发布脚本与 Sparkle（另一张卡）、配置 / 会话 / 线路 / 叠加 / 概览 / 面板 / 主窗口代码。

## 观测面

- 纯函数（ParalluxKit/System）：`URLRoute.parse` 的返回值；`ApplicationsLocation.classify` 的返回值；`WidgetSnapshot` 的编解码与 `isStale`；`WidgetSnapshotThrottle` 的写入决策；`CoreNotification` 的编解码；`AppIntentAction` 映射。
- 生成的 Info.plist 与 entitlements（`check-apple-config.sh`）；签名构建里小组件扩展的签名与构建号（`build-signed.sh`）。
- GREEN 被截断的方式：路由对未知链接返回 nil 而测试只看已知链接——测试逐条断言未知 host、错 scheme、缺参数都是 nil；节流函数永远返回「写」——测试断言 5 秒内的第二次不写，状态变化时立即写。

## 环境假设

- **控制中心开关跑在小组件进程里，不在 App 里。** 依据：SFM `ServiceToggleControl` 的 `ToggleServiceControlIntent: SetValueIntent` 在扩展里直接用 `NETunnelProviderManager.loadAllFromPreferences()` 启停（`WidgetTunnelControl.swift`），不唤起 App；WWDC24「Extend your app’s controls across the system」（developer.apple.com/videos/play/wwdc2024/10157）的控件 intent 同样在扩展执行。所以开关在扩展里直接启停 VPN 配置：**关**直接 `stopVPNTunnel()`；**开**用扩展持久化过的启动参数（`PacketTunnelProvider.resolveStartOptions` 在没有新参数时读上次的副本），所以 `startVPNTunnel()` 不带参数即可。首次从未连接过时扩展没有副本，会启动失败——开关的 intent 在这种情况下改为 `openAppWhenRun` 的另一个 intent 不可行（一个 control 只能绑一个 intent），故首次启动失败时提示「请先在 Parallux 里连接一次」。待手测。
- **系统扩展不能直接发用户通知。** 系统扩展以 root、在用户会话之外运行（Apple 论坛 thread 800887 关于 root 家目录；SFM 在 `Variant.useSystemExtension` 下改走 `UserServiceClient.sendNotification`，即转给 App）。本卡照此：扩展把通知放进有上限的队列，App 每次拉 linkStats 一样经 XPC 取走（追加的 `drainNotifications(reply:)`），由 App 用 `UNUserNotificationCenter` 发。轮询而非 SFM 的反向 endpoint：App 已有每秒一次的 XPC 轮询（`LinkStatsPoller`），复用它更简单；代价是通知最多晚 1 秒。
- 快捷指令：App Intents 放在 App target 里、`AppShortcutsProvider` 自动注册（Apple「App Intents」文档）；intent 在 App 进程执行，需要 App 在运行，`openAppWhenRun = false` 时系统会在后台启动 App。待手测。
- URL scheme：`CFBundleURLTypes` 声明后，`NSApplicationDelegate.application(_:open:)` 收到链接（AppKit 文档）。`sing-box://` 也声明，以接 SFM 的导入链接；如果本机装了 SFM，系统会把 `sing-box://` 交给先注册的那个——待手测。
- 没有 git remote（2026-11-19 `git remote -v` 为空），源码链接按决策 9 的 Bundle ID 写成 `https://github.com/visual-z/parallux`，**未验证**。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** `URLRoute.parse`：`parallux://aggregation-server?…` → 添加服务器（原样保留整条链接）；`parallux://` 与 `sing-box://` 的 `import-remote-profile` → 导入订阅；`parallux://connect|disconnect|toggle` → 对应动作；未知 host、别的 scheme、空串 → nil。
  - 检：test `urlRoutesCoverEveryLinkAndRejectTheRest`
- **D2** `ApplicationsLocation.classify`：`/Applications/X.app` 与 `/Applications/Sub/X.app` 为 ok；`~/Applications/X.app` 为 ok；AppTranslocation 路径为 translocated；DerivedData、下载目录、`.build` 为 notInApplications。
  - 检：test `applicationsLocationIsClassifiedFromTheBundlePath`
- **D3** 小组件快照编解码往返不丢字段；超过 60 秒的快照视为未知；节流：同状态 5 秒内只写一次，状态（连接、方式、线路数）变化立即写。
  - 检：test `widgetSnapshotsRoundTripAndGoStale`
- **D4** 内核通知编解码往返；扩展侧队列有上限，超出时丢最旧的。
  - 检：test `coreNotificationsAreQueuedWithACap`
- **D5** `.about` 是设置窗口的最后一个标签，标题「关于」。
  - 检：test `aboutIsTheLastSettingsTab`
- **D6** 生成的小组件 Info.plist 声明 `NSExtensionPointIdentifier = com.apple.widgetkit-extension`，entitlements 有 app-sandbox 与 App Group；App 的 Info.plist 声明 `parallux` 与 `sing-box` 两个 URL scheme。检查器先故意违规一次确认会红。
  - 检：cmd `scripts/check-apple-config.sh`
- **D7** 计数只因本卡新测试增加；不弱化既有测试；gate 全绿（不签名构建包含小组件 target）。
  - 检：cmd `keel gate`
- **D8** 作者手测：桌面能添加 Parallux 小组件并显示状态、方式、线路数、速率；控制中心能添加开关并启停隧道；快捷指令 App 里有「连接 / 断开 / 切换 Parallux、设置聚合方式、使用配置、更新订阅」；点 `parallux://connect` 能连接；粘贴的 `parallux://aggregation-server?…` 链接点开即添加服务器；从下载目录打开 App 时提示移到「应用程序」；配置里带 `clash_api` 等会触发通知的内核事件能在通知中心看到；设置 › 关于显示版本与第三方许可。
  - 检：author 统一手测

## 设计

- **ParalluxKit/System**：`URLRoute`、`ApplicationsLocation`、`WidgetSnapshot`（connected、mode、linkCount、rate、profileName、updatedAt）与 `WidgetSnapshotThrottle`、`CoreNotification` 与 `NotificationQueue`（上限 32，why：内核通知是零星事件，32 条够覆盖一次重连风暴）、`AppIntentAction`（intent → 动作的枚举，App 里统一执行）。
- **小组件扩展**：读 App Group 的 `UserDefaults` 快照；`TimelineProvider` 每 5 分钟刷新，App 在状态变化时调用 `WidgetCenter.shared.reloadAllTimelines()`；控件 `ControlWidgetToggle` 的值由 `NETunnelProviderManager` 的状态决定，intent 在扩展里启停（见环境假设）。
- **快照写入**：`WidgetSnapshotWriter` 观察 `AppModel`，经节流写 App Group，状态变化时刷新小组件与控件。
- **Intents**：`ConnectIntent`、`DisconnectIntent`、`ToggleIntent`、`SetAggregationModeIntent`、`SelectProfileIntent`（`ProfileEntity` 来自配置库）、`UpdateProfilesIntent`，都经 `AppModel.shared` 执行；`ParalluxShortcuts: AppShortcutsProvider` 给中文短语。
- **通知**：扩展 `send` 入队；XPC 追加 `drainNotifications(reply:)`；App 在 `LinkStatsPoller` 之外起一个 2 秒的轮询（不改 Links 目录）取走并发出。
- 否决：SFM 的反向 XPC endpoint（App 注册 listener 给扩展）——多一个 listener 与生命周期管理，收益只是省掉最多 2 秒延迟。否决：小组件扩展经 XPC 连扩展读速率——小组件进程短命，快照足够。

## 验证命令

```bash
scripts/swift-test.sh /tmp/sys.xml System
scripts/check-apple-config.sh
scripts/build-signed.sh
keel verify-red docs/tasks/feat-system-integration.md
keel gate --record docs/tasks/feat-system-integration.md
```

## 证据

RED(swift): 7bb7fa9 urlRoutesCoverEveryLinkAndRejectTheRest  # D1
RED(swift): 7bb7fa9 applicationsLocationIsClassifiedFromTheBundlePath  # D2
RED(swift): 7bb7fa9 widgetSnapshotsRoundTripAndGoStale  # D3
RED(swift): 7bb7fa9 coreNotificationsAreQueuedWithACap  # D4
RED(swift): 7bb7fa9 aboutIsTheLastSettingsTab  # D5

- RED 时：冻结提交里 `parse` 返回 nil、`classify` 一律 ok、快照不编码、队列不入队、`.about` 标题为空，五条测试共 23 处失败。
- D6 检查器演示（2026-11-19）：把 project.yml 里小组件的 `NSExtensionPointIdentifier` 改成 `com.apple.broken` 并重新生成，`check-apple-config.sh` 退出 1（`NSExtension.NSExtensionPointIdentifier is 'com.apple.broken', want 'com.apple.widgetkit-extension'`）；复原后退出 0。
- 另加 `coreNotificationsComeBackOverXPC`：通知经真实 XPC 编解码往返。
- 签名构建（D8 前提）**未通过**：`scripts/build-signed.sh` 在 ParalluxWidget 处报 `No Accounts: Add a new account in Accounts settings` 与 `No profiles for 'io.github.visual-z.parallux.widget'`。新的 App ID 需要 `-allowProvisioningUpdates` 在开发者账号上注册，而本次会话里 xcodebuild 读不到 Xcode 的账号（同一台机器上 2026-11-18 的签名构建能注册，说明账号在作者的 Xcode 里；这个 worktree 的会话环境拿不到它）。不签名构建通过（gate 的 apple-build），App 里嵌入了 `ParalluxWidget.appex`，Info.plist 的 URL types 与扩展点正确。作者在自己的会话里跑一次 `scripts/build-signed.sh` 即可注册 `io.github.visual-z.parallux.widget`。
GATE: bec79ec4c184+dirty ok tree:41e4f2d04220 build=0 vet=0 test=0[586p/0f] fmt=0 swift-test=0[86p/0f] apple-build=0 server-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-19)

## 修订

（完成定义无改动。）

- 范围说明：`CommandXPCDialer.swift` 不在范围内，没有改它；通知拉取在新文件 `CoreNotificationForwarder.swift` 里直接调用 `TunnelXPC`。AppDelegate 只加了一行 `SystemServices.start(app)` 与 `application(_:open:)` 方法；`SystemServices.swift` 统一启动共享模型、快照写入、通知转发与 /Applications 检查。
- 设计变更：/Applications 检查放在 `SystemServices` 里而不是 AppDelegate 再加一行，以守住「AppDelegate 只加一行」。

## 交接

- 做了什么：ParalluxKit/System（链接路由、/Applications 判定、小组件快照与节流、内核通知队列）；小组件扩展（状态小组件 + 控制中心开关）；6 个 App Intents 与快捷指令短语；`parallux://` 与 `sing-box://` 链接；启动时提示移到「应用程序」；内核通知经 XPC 转给 App 发出；设置 › 关于。
- 卡在哪：签名构建要先在作者的 Xcode 账号下注册小组件的 App ID（见证据）；之后等统一手测 D8。
- 下一步：作者跑 `scripts/build-signed.sh` 注册 App ID，再按 D8 手测。
