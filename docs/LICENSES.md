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
| sing-box v1.14.4 `cmd/internal/build_libbox` | GPLv3 | `scripts/build-core.sh` | 照搬构建标签与链接参数 |
| `sagernet/gomobile` v0.1.12 | BSD-3-Clause | `scripts/build-core.sh` | 构建工具 |
| `sing-box-mygo`（同一作者的旧 Parallux）`internal/redact` | GPLv3 | `core/internal/redact` | 原样拷贝（2026-11-18） |
| `sing-box-mygo` `reference/` | GPLv3（源自 sing-box） | `reference/` | 原样拷贝：官方 daemon proto 与配置 schema |
| `sing-box-mygo` `docs/research/sfm-feature-matrix.md`、`docs/tasks/parity.md` | GPLv3 | `docs/research/` | 拷贝后加注：状态待重判 |
| `WuSiYu/singbox-multipath` | 待确认（GitHub 未识别许可证） | 计划用于 M4 叠加出站 | 尚未引用；引用前确认许可证 |
