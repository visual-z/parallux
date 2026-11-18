# 第三方出处登记

本项目整体 GPLv3。引用的代码、思路与资产在这里登记（AGENTS.md「Never」最后一条）。

| 出处 | 许可 | 用在哪 | 怎么用的 |
|---|---|---|---|
| sing-box v1.14.4 `experimental/libbox` | GPLv3 | `apple/Frameworks/Libbox.xcframework` | 依赖，gomobile 绑定 |
| sing-box fork `visual-z/sing-box` 分支 `parallux/v1.14.4` | GPLv3 | `go.mod` replace | 上游加一个注册钩子提交（决策 10） |
| `SagerNet/sing-box-for-apple` | GPLv3（附加条款：衍生品不得使用其名称或暗示关联） | `apple/Config/Base.xcconfig` 的版本化 Mach 服务名 | 借鉴做法 |
| SFM 768b3de `Library/Network/CommandXPC.swift` | GPLv3（同上） | `apple/ParalluxKit/Sources/ParalluxKit/Tunnel/TunnelXPC.swift`、`apple/PacketTunnel/CommandXPCService.swift` | 改写：接口配置与 fd 传递；拨号加了超时上限 |
| SFM 768b3de `Library/Network/ExtensionProvider.swift` | GPLv3（同上） | `apple/PacketTunnel/PacketTunnelProvider.swift` | 改写：启动顺序与参数持久化 |
| SFM 768b3de `Library/Network/ExtensionPlatformInterface.swift` | GPLv3（同上） | `apple/PacketTunnel/ExtensionPlatform.swift` | 改写：openTun 路由换算、默认网口监视，按 libbox 1.14.4 的协议裁剪 |
| SFM 768b3de `Library/Network/SystemExtension.swift`、`ExtensionProfile.swift` | GPLv3（同上） | `apple/Parallux/Tunnel/SystemExtensionInstaller.swift`、`TunnelController.swift` | 改写：回调转 async，不阻塞主线程 |
| SFM 768b3de `WidgetExtension/ServiceToggleControl.swift`、`WidgetTunnelControl.swift` | GPLv3（同上） | `apple/ParalluxWidget/ParalluxWidgetBundle.swift` | 改写：控件结构与「在扩展里直接启停 NETunnelProviderManager」的做法；去掉 wasOnDemandEnabled 记账，加状态小组件 |
| SFM 768b3de `Library/Network/ExtensionPlatformInterface.swift` `send` / `cancelNotification`、`UserServiceXPC.swift` | GPLv3（同上） | `apple/PacketTunnel/ExtensionPlatform.swift`、`apple/Parallux/CoreNotificationForwarder.swift` | 借鉴做法：系统扩展不直接发通知而交给用户会话；改为有上限的队列 + App 经 XPC 拉取，不建反向 endpoint |
| sing-box v1.14.4 `cmd/internal/build_libbox` | GPLv3 | `scripts/build-core.sh` | 照搬构建标签与链接参数 |
| `sagernet/gomobile` v0.1.12 | BSD-3-Clause | `scripts/build-core.sh` | 构建工具 |
| `sing-box-mygo`（同一作者的旧 Parallux）`internal/redact` | GPLv3 | `core/internal/redact` | 原样拷贝（2026-11-18） |
| `sing-box-mygo` `reference/` | GPLv3（源自 sing-box） | `reference/` | 原样拷贝：官方 daemon proto 与配置 schema |
| `sing-box-mygo` `docs/research/sfm-feature-matrix.md`、`docs/tasks/parity.md` | GPLv3 | `docs/research/` | 拷贝后加注：状态待重判 |
| `WuSiYu/singbox-multipath` | 待确认（GitHub 未识别许可证） | 计划用于 M4 叠加出站 | 尚未引用；引用前确认许可证 |
| `WuSiYu/singbox-multipath` d99530a `protocol/multipath`（含 `stream/`，连同包内测试） | GPLv3，附加条款：衍生品不得使用其名称或暗示关联（上游 `LICENSE` 末段，2026-11-19 确认） | `core/bond/`、`core/bond/stream/` | 原样移植：只改包名（`multipath`→`bond`）、import 路径、把 `option.Multipath*Options` 改为包内类型、`C.TypeMultipath` 改为包内 `Type`，gofmt 调整 import 顺序；未移植上游 `test/` 集成测试目录（依赖其整套 sing-box 测试夹具） |
| `WuSiYu/singbox-multipath` d99530a `option/multipath.go`、`option/multipath_test.go` | 同上 | `core/bond/options.go`、`core/bond/options_test.go` | 移植：包名改为 `bond`，`ListenOptions` 改引 sing-box `option.ListenOptions` |
| SFM 768b3de `HelperService/RootHelperService.swift`、`HelperService/WorkingDirectoryManager.swift`、`HelperService/main.swift` | GPLv3（附加条款同 SFM 行） | `apple/ParalluxHelper/HelperService.swift`、`main.swift` | 改写：同团队签名要求、工作目录大小与清空、版本；只保留按进程查找、工作目录、崩溃报告三项，清空要求确认口令 |
| SFM 768b3de `HelperService/LaunchDaemons/*.plist` | GPLv3（同上） | `apple/Config/helper-launchd.plist` | 改写：键相同（Label、BundleProgram、MachServices、AssociatedBundleIdentifiers、RunAtLoad、KeepAlive），值改为构建变量 |
| SFM 768b3de `Library/Network/HelperServiceManager.swift` | GPLv3（同上） | `apple/Parallux/Helper/HelperServiceManager.swift` | 改写：注册、注销、状态与打开登录项设置；改为 @Observable |
| SFM 768b3de `Library/Network/RootHelperXPC.swift` | GPLv3（同上） | `apple/ParalluxKit/Sources/ParalluxKit/Helper/HelperXPC.swift` | 改写：接口只保留本卡的方法，回复改为 JSON，每次调用有超时上限 |
| sing-box v1.14.4 `common/process/searcher_darwin_shared.go` `matchDarwinConnectionEntry` | GPLv3 | `apple/ParalluxKit/Sources/ParalluxKit/Helper/SocketOwnerMatcher.swift` | 用 Swift 重写同一组匹配规则（精确、本地回退、通配回退、去掉 IPv4 映射） |
