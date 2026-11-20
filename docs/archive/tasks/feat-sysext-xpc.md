---
type: feat
status: awaiting-author
weight: full
created: 2026-11-18
baseline: e25ded5 (gate: test 7p/0f, swift-test 8p/0f)
---

# App 经 XPC 拿到扩展里 command server 的连接，读到运行状态与流量

## 来源

PLAN 决策 11（取代原 `research-sysext-ipc`：Fable 审计已在 SFM 源码里找到答案，研究卡改为复现卡）。参照 SFM（`SagerNet/sing-box-for-apple` 768b3de）：`Library/Network/ExtensionProvider.swift`（NSXPCListener）、`CommandXPC.swift`（传回 command.sock 的 FileHandle、`setCodeSigningRequirement`）、`SystemExtension.swift`（激活请求）、`ExtensionProfile.swift`（NETunnelProviderManager）、`ExtensionPlatformInterface.swift`（openTun、默认网口监视）；libbox `command_client.go` 的 `SetXPCDialer` / `ConnectWithFD`。

2026-11-18 作者决定：签名用 Apple Development，允许 xcodebuild 自动注册 App ID、能力与本机设备；M1 等手测期间并行推进 M2 不依赖签名的部分（记为决策 14）。

## 范围

- **独占：** `apple/PacketTunnel/`、`apple/Parallux/Tunnel/`、`apple/ParalluxKit/Sources/ParalluxKit/Tunnel/`、对应测试、`scripts/build-signed.sh`、`PLAN.md`（决策 14、15）。
- **不碰：** `core/aggregate`；`core/pxbridge` 的导出 API；界面布局（M2 的界面卡）。

## 观测面

- 纯 Swift 部分（ParalluxKit）：`swift test` 里用匿名 `NSXPCListener` 起真实 XPC 连接，经它把 socketpair 的一端作为 FileHandle 传过去，断言对端读到写入的字节；超时测试断言耗时上限与错误类型。
- 签名运行：App 菜单栏面板的状态行（已连接 / 首条状态消息的上下行速率）；扩展日志 `log stream --predicate 'subsystem BEGINSWITH "io.github.visual-z.parallux"'`。
- GREEN 被截断的方式：XPC 回调根本没调（测试会因超时而非成功返回）——成功路径断言读回的字节相等，超时路径断言错误是 `.timedOut`；编码往返若吞掉字段，测试逐字段比较而非只比较 configContent。

## 环境假设

- Apple Development 签名能产出带 `packet-tunnel-provider`、`system-extension.install`、App Group 的 App 与扩展。**已对拍（2026-11-18）**：`xcodebuild -allowProvisioningUpdates -allowProvisioningDeviceRegistration` 在团队 ABCDE12345 下注册 App ID 与设备后 BUILD SUCCEEDED；`codesign -d --entitlements -` 读到上述三项与 `get-task-allow`；扩展 Info.plist 的 `NEMachServiceName` 为 `ABCDE12345.io.github.visual-z.parallux.tunnel.0.0.1`。
- SIP 开启时，开发签名的系统扩展只要 App 在 /Applications 里就能激活（Apple「Installing System Extensions and Drivers」；`systemextensionsctl developer on` 才需要关 SIP）。本机 SIP 开启；激活需要作者在系统设置里批准一次——author 检查覆盖。
- 本机已装 SFM（P8XK3KHB48）与 Surge 的网络扩展；同一时间只有一个 VPN 能处于连接状态，手测前需断开它们。
- 系统扩展以 root 运行，它的 App Group 容器在 root 家目录，App 读不到（developer.apple.com/forums/thread/800887）；所以配置经 `startVPNTunnel(options:)` 传入，扩展在自己的家目录落盘。SFM 同做法（`ExtensionProvider.swift` 用 `homeDirectoryForCurrentUser`）。
- libbox 1.14.4 的 command server 在 `basePath/command.sock` 上监听 unix socket（`experimental/libbox/command_server.go:141-160`，读源码确认），App 侧 `ConnectWithFD` 直接在传来的 fd 上说 gRPC（`command_client.go:264-278`）。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** 扩展经 XPC 传回的 FileHandle 是一条可用的字节流：App 侧收到的 fd 能读到扩展侧写入的字节。
  - 检：test `aCommandSocketHandedOverXPCCarriesBytes`
- **D2** 扩展不应答时，App 侧的拨号在超时上限内失败，不会无限等待（SFM 的 `semaphore.wait()` 没有超时）。
  - 检：test `dialingAServiceThatNeverRepliesTimesOut`
- **D3** 启动参数往返不丢字段：配置内容与全部隧道开关编码后再解码，与原值逐字段相等。
  - 检：property `startOptionsSurviveARoundTrip`
- **D4** Mach 服务名只在位于 App Group 之内且带版本后缀时可用；不签名构建（无 Team 前缀）得到「无」。
  - 检：test `aMachServiceOutsideTheAppGroupIsRejected`
- **D5** 签名构建脚本能产出签名的 App 与扩展（需要 Local.xcconfig）。
  - 检：cmd `scripts/build-signed.sh`
- **D6** PLAN 写入决策 14（M1 等手测时并行 M2 不依赖签名的部分）与决策 15（开发签名用 Apple Development，权限值 `packet-tunnel-provider`）。
  - 检：grep `| 15 |`
- **D7** 计数只因本卡新测试增加；不弱化既有测试；gate 全绿。
  - 检：cmd `keel gate`
- **D8** 作者手测：签名 App 拷到 /Applications 后，面板「启用」会请求安装系统扩展；批准后用一份最小配置连接，面板 2 秒内显示「已连接」与实时上下行速率；断开后状态回到「未连接」。
  - 检：author 按「验证命令」里的手测步骤操作

## 设计

- **ParalluxKit/Tunnel（纯 Swift，可测）**：`TunnelXPCProtocol`（`@objc`，`connectToCommandServer(reply:)`、`waitUntilReady(reply:)`）、`TunnelXPC.configure(_:)` 给 reply 里的 FileHandle 放行；`TunnelXPCClient.dialCommandSocket(connection:timeout:)` 用 `DispatchSemaphore.wait(timeout:)`，上限常量 `TunnelXPC.dialTimeout`；`UnixSocket.connect(path:)`；`TunnelStartOptions`（Codable，经 `NSData` 放进 options 字典的一个键，避免 SFM 那样逐键手写 NSNumber）；`MachService.resolve(_:appGroup:)`。
- **扩展**：`PacketTunnelProvider` 照 SFM：`LibboxSetup` → `LibboxNewCommandServer` → `start` → `NSXPCListener(machServiceName:)` → `startOrReloadService`；`ExtensionPlatform` 实现 libbox 1.14.4 的 `LibboxPlatformInterface` 与 `LibboxCommandServerHandler`（openTun 照 SFM 改写成用 TunnelStartOptions；按进程分流、shell、bridge 返回「不支持」，留给辅助服务卡）。XPC 连接用 `setCodeSigningRequirement` 只接受同团队的 App。
- **App**：`SystemExtensionInstaller`（OSSystemExtensionRequest，delegate 回调转 async，不阻塞主线程）、`TunnelController`（NETunnelProviderManager 的加载、安装、启停，`@Observable`）、`CommandXPCDialer`（实现 `LibboxXPCDialerProtocol`，调用 ParalluxKit 的拨号）、`StatusClient`（LibboxCommandClient 订阅 status，主线程发布）。
- 否决：App 直连 App Group 里的 command.sock（root 家目录，见环境假设）；复制 SFM 的 `semaphore.wait()` 无超时等待（违反「无界等待」）；为测试另起一个可执行的假扩展（匿名 listener 已能在进程内走真实 XPC 编解码）。
- 引用：SFM 代码为 GPLv3，openTun 的路由换算与 XPC 接口配置改写自 SFM，逐文件登记在 `docs/LICENSES.md`。

## 验证命令

```bash
scripts/swift-test.sh /tmp/xpc.xml TunnelXPC
scripts/build-signed.sh
keel verify-red docs/tasks/feat-sysext-xpc.md
keel gate --record docs/tasks/feat-sysext-xpc.md
# 手测（D8）：
#   1. 断开 SFM 与 Surge；scripts/build-signed.sh 后把 .build/xcode-signed/Build/Products/Debug/Parallux.app 拷到 /Applications
#   2. 打开 /Applications/Parallux.app，面板点「启用」，在 系统设置 › 通用 › 登录项与扩展 › 网络扩展 里批准
#   3. 面板选「示例配置」后连接，看状态与速率
```

## 证据

RED(swift): 31f47ca aCommandSocketHandedOverXPCCarriesBytes  # D1
RED(swift): 31f47ca dialingAServiceThatNeverRepliesTimesOut  # D2
RED(swift): 31f47ca startOptionsSurviveARoundTrip  # D3
RED(swift): 31f47ca aMachServiceOutsideTheAppGroupIsRejected  # D4

- RED 时的失败原文：D1 `Caught error: .noHandle`；D2 `expected error ".timedOut" of type DialError, but ".noHandle" of type DialError was thrown instead`；D3 `Expectation failed: decoded == options`；D4 `Expectation failed: MachService.resolve("OTHERTEAM1.io.github.visual-z.parallux.tunnel.0.0.1", appGroup: group) == nil`。
- D5：`scripts/build-signed.sh` 退出 0，输出 `signed .build/xcode-signed/Build/Products/Debug/Parallux.app`。脚本里的团队签名检查先演示过会红：对 ad-hoc 重签的副本，`codesign -dv` 给出 `TeamIdentifier=not set`，检查判失败。
GATE: 31f47cad7fa2+dirty ok tree:2747b2d5eaeb build=0 vet=0 test=0[8p/0f] fmt=0 swift-test=0[17p/0f] apple-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-18)

## 修订

- D1 开卡时是占位符；改写为 D1–D8，原 D1「2 秒内收到第一条状态消息」并入 D8，未放宽（作者确认 2026-11-18）
- D2 D3 D4 D5 D6 D7 D8 随 D1 的改写新增（作者确认 2026-11-18）

## 交接

- 做了什么：扩展跑 libbox command server，经 XPC 交出 command.sock；之后 M2–M6 的卡都建在这条通路上，代码已全部完成（决策 16）。
- 卡在哪：没有任何隧道功能在签名构建里跑过。签名构建已装到 /Applications（2026-11-19）。
- 下一步：作者按 `docs/MANUAL-TEST.md` 的顺序统一手测，本卡是第 1.2 步。
