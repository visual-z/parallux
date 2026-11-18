> 搬自 `sing-box-mygo`（旧 Go 全栈版 Parallux）`docs/research/sfm-feature-matrix.md`，2026-11-18。
> 基线是 2026-08-21 的 SFM 1.13.19；新架构（网络扩展 + 库内核）下需要和最新 SFM 重新比对。旧仓库以「无网络扩展」判为不适用的条目，在这里不再成立。

# SFM 功能清单（sing-box for Mac）

调研日期：2026-08-21。  
对象：SagerNet 官方 macOS 客户端 **SFM**（`sing-box-for-apple` 里的 `SFM` / `SFM.System`）。  
范围：用户可见功能；不含 iOS-only（SFI）/ tvOS-only（SFT）独占项，除非它能说明 SFM 边界。  
本文件只记调研结论与出处，不代表 Parallux 产品决策。

标注：

- **[文档]** 官方文档站原文。
- **[源码]** 仓库 `dev` 分支源码（本机 clone `/tmp/sing-box-for-apple`，commit 以该日 `dev` HEAD 为准）。
- **[内核]** `SagerNet/sing-box` 分支 `testing` 的 `experimental/libbox` 与 `daemon/*.proto`。
- **[发行]** Homebrew Cask / GitHub Releases。

两条发行线必须分开读，否则会把 System Extension 能力误当成 App Store 版也有：

| 发行 | Xcode scheme | Packet Tunnel 形态 | 分发 |
|---|---|---|---|
| App Store / TestFlight | `SFM` | **Application Extension** `packet-tunnel-provider`（`Extension/PacketTunnelProvider.swift`） | [App Store](https://apps.apple.com/app/sing-box-vt/id6673731168)、TestFlight（仅 [sponsors](https://github.com/sponsors/nekohasekai)） |
| Standalone（文档称 macOS standalone） | `SFM.System` | **System Extension** `packet-tunnel-provider-systemextension`（`SystemExtension/PacketTunnelProvider.swift`）+ Helper Service | [Homebrew Cask `sfm`](https://formulae.brew.sh/cask/sfm)（调研日版本 **1.13.19** Universal `.pkg`）、[GitHub Releases](https://github.com/SagerNet/sing-box/releases) |

出处：[clients/apple](https://sing-box.sagernet.org/clients/apple/)、[clients/apple/features](https://sing-box.sagernet.org/clients/apple/features/)、仓库 README、`Makefile`（`build_macos` vs `build_macos_standalone`）。

仓库 README 仍链到旧路径 `sing-box.sagernet.org/installation/clients/sfm/`，现站对应页是 `/clients/apple/`。

---

## 0. 五个关键事实（先读）

### 0.1 SFM 是 NetworkExtension Packet Tunnel，不是独立 `sing-box` 进程

**结论：** SFM **不** `exec` 一个用户空间 `sing-box` 二进制。内核以 **Libbox（gomobile / cgo 嵌入）** 的形式跑在 `NEPacketTunnelProvider` 里。GUI 进程通过本地 command/gRPC 客户端连扩展进程。

**怎么触发：** 用户点 Dashboard 工具栏 **Start** → `ExtensionProfile.start()` → `NETunnelProviderManager.connection.startVPNTunnel(options:)`，把当前 profile 的 JSON 塞进 `options["configContent"]`。

**依赖：**

- `NetworkExtension` Packet Tunnel Provider（App Store：App Extension；Standalone：System Extension）。
- 配置里通常有 `inbounds[].type = "tun"`；TUN fd 由扩展的 `openTun` 从 `NEPacketTunnelNetworkSettings` + `packetFlow` 取出，再交给 Libbox。官方原话：*「unprivileged TUN implementation through NetworkExtension」*。

**出处：**

- 文档：[features § Service / TUN](https://sing-box.sagernet.org/clients/apple/features/)
- 源码：`Extension/PacketTunnelProvider.swift`、`SystemExtension/PacketTunnelProvider.swift`（两者都是 `class PacketTunnelProvider: ExtensionProvider`）；`Library/Network/ExtensionProvider.swift` `startTunnel`；`Library/Network/ExtensionPlatformInterface.swift` `openTun0`；`Library/Network/ExtensionProfile.swift` `start()` / `install()`。

**TUN 怎么启用：** UI **没有**「打开 TUN」独立开关。是否建 TUN、是否 `auto_route`，由 **当前 profile JSON 的 `tun` inbound** 决定。客户端在 `openTun` 里把 `auto_route` / `address` / `mtu` / `route_address` 翻译成 `NEPacketTunnelNetworkSettings`。`Settings → Packet Tunnel` 里的开关（`includeAllNetworks` 等）改的是 **NE 协议层路由范围**，不是「有没有 tun inbound」。

### 0.2 「系统代理」是独立 Dashboard 开关，但只有 profile 声明了 HTTP 代理才出现

**结论：** 有独立用户概念 **System HTTP Proxy**（不是「完全由 inbound 决定、UI 无开关」）。但 **是否 available** 取决于内核告诉平台「HTTP 代理已启用」——对应 TUN inbound 的 `platform.http_proxy`。关掉后 App Store/Standalone 都会改 `NEProxySettings.httpEnabled/httpsEnabled`。

**怎么触发：** Dashboard 卡片 **System HTTP Proxy** 的 Toggle。仅当服务已连接 **且** `getSystemProxyStatus().available == true` 时渲染。

**行为：**

- 开：`LibboxCommandClient.setSystemProxyEnabled(true)` → 平台 `NEProxySettings.httpEnabled/httpsEnabled = true`（不整段重启隧道）。
- 关：先写 `SharedPreferences.systemProxyEnabled`，再 **`profile.restart()`**（整段停/启 VPN）。
- 默认偏好 `system_proxy_enabled = true`。
- 内核侧 `available` 的判定：`networkSettings.proxySettings.httpServer != nil`（由 `options.isHTTPProxyEnabled()` 填上）。

**出处：**

- TUN schema：[`platform.http_proxy`](https://sing-box.sagernet.org/configuration/inbound/tun/)
- 源码：`ApplicationLibrary/Views/Dashboard/Cards/HTTPProxyCard.swift`；`OverviewView.shouldShowCard(.httpProxy)`；`OverviewViewModel.setSystemProxyEnabled`；`SharedPreferences.systemProxyEnabled`；`ExtensionPlatformInterface.getSystemProxyStatus` / `setSystemProxyEnabled` / `openTun0` 里对 `NEProxySettings` 的赋值。

### 0.3 Profile 类型：Local / iCloud / Remote；远程默认 60 分钟

**结论：** 三种，枚举 `ProfileType: local = 0, icloud, remote`。官方通用客户端规范与 UI 文案一致。tvOS 没有 iCloud；SFM 有。

远程自动更新：

- UI 字段 **Auto Update**（Bool）+ **Auto Update Interval**（分钟，placeholder「In Minutes」，新建默认 **60**）。
- `autoUpdateInterval == 0` 时调度器用默认 **60 分钟**（`ProfileUpdateTask.defaultUpdateInterval = 60 * 60`）。
- 调度器实际 tick **下限 15 分钟**（`minUpdateInterval = 15 * 60`），即使 UI 填更小。
- macOS：进程内 `Timer`（`ProfileUpdateTask`）；iOS/tvOS：`BGAppRefreshTask`。
- 更新时 `HTTP GET` URL → `LibboxCheckConfig` → 写本地缓存 → 若该 profile 正在跑则 `reloadService()`。

**出处：**

- [clients/general § Profile](https://sing-box.sagernet.org/clients/general/)（明文：Remote 默认 60 minutes；iCloud 在 iOS/macOS）
- 源码：`Library/Database/Profile.swift`；`ApplicationLibrary/Views/Profile/NewProfileView.swift` / `EditProfileView.swift`；`ApplicationLibrary/Service/ProfileUpdateTask.swift`；`Library/Database/Profile+Update.swift`。

### 0.4 能在 App 内编辑配置；有校验

**结论：**

- **Local / iCloud：可编辑**（按钮 **Edit Content**）。macOS 用 CodeEdit + JSON schema 补全；保存/输入防抖后走 `LibboxCheckConfig`。
- **Remote：只读查看**（按钮 **View Content**），规范要求 viewer 而不是 editor。
- 创建 Local（手写 `{}` 或导入 JSON）和导入 Remote 内容时同样 `LibboxCheckConfig`，失败则拒绝创建。
- 另有 **Format**（`LibboxFormatConfig`）。

**出处：** [clients/general](https://sing-box.sagernet.org/clients/general/)；`ProfileActionToolbar.swift`；`MacLibrary/ProfileEditorWrapperView.swift`；`MacLibrary/ProfileValidationGate.swift`；`NewProfileViewModel.swift`；`EditProfileContentViewModel.swift`。

### 0.5 延迟测试 API：gRPC `StartedService.URLTest`，按 outbound **tag**（组或节点都能传）

**结论：** 不是 Clash HTTP `/group/{name}/delay`，也不是用户去填的 REST。SFM 调用 gomobile `LibboxCommandClient.urlTest(tag)`，在当前 `testing` 内核里映射为：

```
rpc URLTest(URLTestRequest) returns (google.protobuf.Empty);
message URLTestRequest { string outboundTag = 1; }
```

`StartedService.URLTest` 用 `outboundManager.Outbound(outboundTag)` 取对象：

- tag 是 **urltest 组** → `CheckOutbounds()`（整组）；
- tag 是 **其它 OutboundGroup**（如 selector）→ 并发测组成员（跳过嵌套组）；
- tag 是 **普通 outbound** → 单节点 `urltest.URLTest`。

所以 UI 既可以按组测也可以按节点测，RPC 本身只有一个 `outboundTag` 字段。

**怎么触发：**

- Groups 页组标题闪电按钮 → `urlTest(group.tag)`。
- 节点卡片右键 **URLTest** → `urlTest(item.tag)`。
- 菜单栏 Group 子菜单：组级 URLTest + **URLTest**（全部组）。

**本地通道：** Packet Tunnel 内 `LibboxNewCommandServer`；App 用 `LibboxNewStandaloneCommandClient()`。Standalone System Extension 再经 Mach XPC 转到扩展里的 `command.sock`。  
**远端通道：** Settings → Remote Control 连的是 1.14 **API service**（文档写明 graphical clients 的 Remote Control 走这套 gRPC；Bearer `secret`）。

**出处：**

- [configuration/service/api](https://sing-box.sagernet.org/configuration/service/api/)
- proto：`daemon/started_service.proto`（与本仓库 `reference/started_service.proto` 同形）
- 内核：`experimental/libbox/command_client.go` `URLTest`；`daemon/started_service.go` `URLTest`
- 客户端：`GroupListViewModel.doURLTest`；`StatusBarController.performURLTestForGroup` / `performURLTestForAllGroups`

---

## 1. Profile（配置文件）管理

| # | 功能名 | 触发 | 依赖 | 出处 |
|---|---|---|---|---|
| 1 | **Local** / 本地 Profile | New Profile → Type **Local**；可 Create New（空 `{}`）或 Import JSON | 本地文件 `configs/config_<id>.json`；`LibboxCheckConfig` | [general](https://sing-box.sagernet.org/clients/general/)；`ProfileType.local`；`NewProfileView.swift` |
| 2 | **iCloud** / iCloud Profile | New/Edit → Type **iCloud** + Path；footer「File will be located at iCloud Drive/sing-box/\(FileName)」 | iCloud Documents 容器 `iCloud.io.nekohasekai.sfavt`；entitlement `icloud-services=CloudDocuments` | [general](https://sing-box.sagernet.org/clients/general/)；`SFM/SFM.entitlements`；`Profile+RW.swift` `FilePath.iCloudDirectory` |
| 3 | **Remote** / 远程 Profile | New/Edit → Type **Remote** + URL | HTTP(S) 拉取；校验后写入本地 `configs/config_<id>.json` 缓存 | 同上；`Profile+Update.swift` |
| 4 | **Create Manually** / 手动创建 | Dashboard Profile 卡 **+** → New Profile 菜单 → **Create Manually** | 无额外内核能力 | `NewProfileMenuView.swift` |
| 5 | **Import from File** / 从文件导入 | 同一菜单 **Import from File**；`.json` 走 LocalImport；其它走 `.bpf`（`LibboxProfileContent`） | Uniform Type `*.bpf`（`CFBundleDocumentTypes`） | `NewProfileMenuView.handleFileImport`；`SFM.System/Info.plist` |
| 6 | **Scan QR Code** / 扫码导入 | New Profile 菜单 **Scan QR Code**（相机） | 相机权限 `NSCameraUsageDescription`；二维码解析 `LibboxParseRemoteProfileImportLink` 或 QRS 二进制 | `QRScannerView`；`SFM.System/Info.plist` |
| 7 | **Share as QRS Code** / QRS 分享 | Profile 卡分享菜单 **Share as QRS Code** | Luby Transform 编码 profile 二进制（`ApplicationLibrary/LubyTransform`） | `ProfileCard.prepareQRSShare` |
| 8 | **Share URL as QR Code** / 远程 URL 二维码 | 仅 Remote：分享菜单该项 | Remote `remoteURL` | `QRCodeSheet` / macOS popover |
| 9 | **URL Scheme import-remote-profile** / 从链接导入远程配置 | 打开 `sing-box://import-remote-profile?url=urlEncodedURL#urlEncodedName` | URL scheme `sing-box` | [general](https://sing-box.sagernet.org/clients/general/)；`MainViewModel.openURL` |
| 10 | **Import .bpf via URL/file open** / 打开 bpf 文件 | 系统打开 `.bpf` 或 `onOpenURL` pathExtension `bpf` | 文档类型 Owner | `MainViewModel.importURLProfile` |
| 11 | **Edit Profile** / 编辑元数据 | Profile 卡铅笔；Type 选择器创建后 **disabled** | 改 name / remote URL / auto update | `EditProfileView.swift` |
| 12 | **Edit Content** / 应用内编辑 JSON | Local/iCloud：Edit Profile 底栏 **Edit Content** → 独立窗口 | `LibboxCheckConfig` 防抖校验；`LibboxFormatConfig`；macOS JSON completion（`ConfigSchema.swift`） | `ProfileActionToolbar`；`ProfileEditorWrapperView` |
| 13 | **View Content** / 只读查看 | Remote：按钮文案换成 **View Content**，`readOnly: true` | 规范要求 viewer | [general](https://sing-box.sagernet.org/clients/general/)；`ProfileActionToolbar` |
| 14 | **Auto Update** / 自动更新 | Remote 表单 Toggle | 见 §0.3 | `NewProfileView` / `EditProfileView` |
| 15 | **Auto Update Interval** / 自动更新间隔（分钟） | 同表单 TextField，prompt **In Minutes**，默认 60 | 调度下限 15 min；0 → 默认 60 min | `ProfileUpdateTask.swift`；[general「default interval is 60 minutes」](https://sing-box.sagernet.org/clients/general/) |
| 16 | **Update remote now** / 立即更新远程 | Profile 卡刷新箭头（仅 Remote） | 同 `updateRemoteProfile` | `ProfileCard.updateButton` |
| 17 | **Last Updated** / 上次更新时间 | Edit Profile Status 段；Profile 卡 caption | `profile.lastUpdated` | `EditProfileView`；`ProfileCard.profileInfo` |
| 18 | **HTTP Basic authorization** / HTTP 基本认证 | 无独立账号框；URL 里带 `user:pass@` 时 `SetBasicAuth` | 官方规范要求 Remote 必须实现 Basic auth | [general](https://sing-box.sagernet.org/clients/general/)；内核 `experimental/libbox/http.go` `SetURL` |
| 19 | **Profile picker / switch** / 列表与切换 | Profile 卡选择器 → **Profiles** sheet；点一项即 `selectedProfileID` 并在已连接时 `reloadService()` | 正在跑的 Packet Tunnel | `ProfilePickerSheet`；`OverviewViewModel.switchProfile` |
| 20 | **Delete / reorder profiles** / 删除与排序 | Profiles sheet 进入 Edit 后 `onDelete` / `onMove` | GRDB `ProfileManager.delete` | `ProfilePickerSheet.swift` |
| 21 | **Save File / Share File** / 导出 bpf | 分享菜单 **Save File** / **Share File** | `.bpf` | `ProfileCard.shareMenu` |
| 22 | **Save / Share Content JSON** / 导出 JSON | 分享菜单对应项 | 读 profile 内容 | 同上 |
| 23 | **User-Agent on fetch** / 拉取远程时的 UA | 后台 `HTTPClient`，用户不可改 | `SFM/<version> (Build …; sing-box <LibboxVersion>; language …)` | `Library/Network/HTTPClient.swift` |

---

## 2. Dashboard 与核心控制

macOS 侧栏：未连接时 **Dashboard / Logs / Tools / Settings**；已连接且有组时 Dashboard 段变成 **Overview / Groups / Connections**，下面仍是 Logs / Tools / Settings。  
出处：`NavigationPage.swift`；`MacLibrary/SidebarView.swift`。

| # | 功能名 | 触发 | 依赖 | 出处 |
|---|---|---|---|---|
| 24 | **Install Network Extension** / 安装网络扩展 | 尚无 VPN 配置时 Dashboard 中央按钮 | `NETunnelProviderManager.saveToPreferences`；用户系统授权 VPN | `InstallProfileButton.swift`；`ExtensionProfile.install` |
| 25 | **Install System Extension** / 安装系统扩展 | 仅 Standalone：未安装时 Dashboard 中央 **Install System Extension**；Settings → App → System Extension | `OSSystemExtensionManager`；entitlement `system-extension.install`；可能 **Need Reboot** | [features § Service](https://sing-box.sagernet.org/clients/apple/features/)；`InstallSystemExtensionButton.swift`；`MacAppView` |
| 26 | **Start / Stop** / 启动与停止 | 窗口工具栏播放/停止；菜单栏 header | Packet Tunnel 已安装且至少有一个 profile（`emptyProfiles` 时禁用） | `StartStopButton.swift` |
| 27 | **Runtime duration** / 已运行时长 | Start 按钮旁 `h:mm:ss` | `NEVPNConnection.connectedDate` | `StartStopButton` |
| 28 | **Status** / 状态卡 | Dashboard 卡：Memory、Goroutines | gRPC `SubscribeStatus` / Libbox command status | `StatusCard.swift`；[general § Dashboard Status](https://sing-box.sagernet.org/clients/general/) |
| 29 | **Connections**（计数卡） / 连接计数 | Dashboard 半宽卡：Inbound / Outbound 计数 | 同上 `Status.connectionsIn/Out` | `ConnectionsCard.swift` |
| 30 | **Upload / Download** / 上下行流量 | 两张半宽卡：速率 + 累计 + sparkline | `SubscribeStatus` 的 uplink/downlink | `UploadTrafficCard.swift` / `DownloadTrafficCard.swift` |
| 31 | **System HTTP Proxy** / 系统 HTTP 代理 | 全宽 Toggle，见 §0.2 | TUN `platform.http_proxy` + `NEProxySettings` | `HTTPProxyCard.swift`；[tun platform.http_proxy](https://sing-box.sagernet.org/configuration/inbound/tun/) |
| 32 | **Mode / Clash Mode** / 模式 | 配置里 ≥2 个 `clash_mode` 时出现分段或菜单 | `SubscribeClashMode` / `SetClashMode` | `ClashModeCard.swift`；[general § Mode](https://sing-box.sagernet.org/clients/general/) |
| 33 | **Profile** 卡 / 当前配置 | 始终显示；含 + / 编辑 / 更新 / 分享 | 见 §1 | `ProfileCard.swift`；`DashboardCard.profile` |
| 34 | **Dashboard Items** / 仪表盘卡片管理 | 工具栏方格按钮；可开关、排序、**Reset** | `SharedPreferences.enabledDashboardCards` / `dashboardCardOrder` | `CardManagementSheet.swift`；`DashboardCard.swift` |
| 35 | **Reload on profile change** / 切换配置热加载 | 改选 profile 且已连接 → `reloadService()`（向扩展 `sendProviderMessage`） | Packet Tunnel session | `ExtensionProfile.reloadService` |
| 36 | **Disconnect error / FDA** / 启动失败与完全磁盘访问 | Start 失败后 `fetchLastDisconnectError`；App Store 扩展缺 FDA 时弹 **Full Disk Access permission is required**（**SFMExtension**） | macOS Privacy_AllFiles | `DashboardViewModel.checkLastDisconnectError` |

默认卡片顺序：Upload, Download, Status, Connections, System HTTP Proxy, Clash Mode, Profile（`DashboardCard.defaultOrder`）。

---

## 3. 组与节点（含延迟测试）

macOS 上 Groups 是 **独立侧栏页**，仅 `status.isConnectedStrict` 且 `groups` 非空时出现（iOS/tvOS 从 Dashboard 再进）。规范仍把它算 Dashboard 能力。

| # | 功能名 | 触发 | 依赖 | 出处 |
|---|---|---|---|---|
| 37 | **Groups** / 策略组列表 | 侧栏 **Groups** | 配置含 selector / urltest 等组 outbound；`SubscribeGroups` | `GroupListView.swift`；[general § Groups](https://sing-box.sagernet.org/clients/general/) |
| 38 | **Expand / collapse group** / 展开组 | 组头 chevron 或点击标题 | `SetGroupExpand` | `GroupListViewModel.toggleExpand` |
| 39 | **Select outbound** / 选择节点 | 组 `selectable` 时点节点卡片 | `SelectOutbound(groupTag, outboundTag)` | `GroupItemView`；proto `SelectOutboundRequest` |
| 40 | **URLTest (group)** / 按组延迟测试 | 组头闪电 | `URLTest(outboundTag=group.tag)`，见 §0.5 | `GroupHeaderView` |
| 41 | **URLTest (node)** / 按节点延迟测试 | 节点 context menu **URLTest** | 同一 RPC，tag=节点 | `GroupItemView.contextMenu` |
| 42 | **Delay display** / 延迟着色 | 节点右下 `Nms`；折叠时色点网格 | `urlTestDelay`；0 不显示数字；绿/黄/红阈值在 `OutboundGroupItem+SwiftUI` | `GroupItemView`；`GroupContentView.dotGrid` |
| 43 | **Menu bar groups** / 菜单栏切组 | 菜单栏 **Group** 子菜单：各节点、组级 URLTest、总 URLTest、Close All Connections | 服务已连接 + Show in Menu Bar | `StatusBarController.swift` |

---

## 4. 连接与日志

| # | 功能名 | 触发 | 依赖 | 出处 |
|---|---|---|---|---|
| 44 | **Connections** / 连接列表 | 侧栏 **Connections**（仅已连接） | `SubscribeConnections` | `ConnectionListView.swift` |
| 45 | **State filter** / 状态过滤 | 工具栏菜单 **State**：All / Active / Closed | `ConnectionStateFilter` | `CommandClient.swift` |
| 46 | **Sort** / 排序 | 菜单 **Date / Traffic / Traffic Total** | `sortByDate` / `sortByTraffic` / `sortByTrafficTotal` | 同上 |
| 47 | **Search connections** / 搜索 | 工具栏放大镜（macOS 14+） | 本地过滤 destination/domain，以及 `network:` `inbound:` `source:` 等 | `Connection.performSearch` |
| 48 | **Connection details** / 连接详情 | 点一行 | 字段：State、时间、上下行、Inbound/Type、IP Version、Network、Source、Destination、Domain、Protocol、User、From Outbound、Match Rule、Outbound/Type、Chain。**没有进程名列**（进程匹配是路由规则能力，见 §5） | `ConnectionDetailsView.swift` |
| 49 | **Close** / 关闭单条 | 行 context menu **Close**（仅 Active） | `CloseConnection` | `ConnectionView.closeConnection` |
| 50 | **Close All Connections** / 关闭全部 | 列表菜单；菜单栏 Group 子菜单同名 | `CloseAllConnections` | `ConnectionListViewModel`；`StatusBarController` |
| 51 | **DNS connections hidden** / 隐藏 DNS 连接 | 自动 | `outboundType == "dns"` 丢弃 | `ConnectionListViewModel.convertConnections` |
| 52 | **Logs** / 内核日志 | 侧栏 **Logs** | `SubscribeLog`；扩展 `logMaxLines = 3000` | `LogView.swift`；`ExtensionProvider` |
| 53 | **Log Level** / 日志级别过滤 | 工具栏菜单 Default / Error / Warn / Info / Debug / Trace | 客户端过滤；Default 用服务端 `GetDefaultLogLevel` | `LogView.swift` `LogLevel` |
| 54 | **Pause / Resume** / 暂停滚屏 | 工具栏暂停/播放 | UI 状态 | `LogViewModel.togglePause` |
| 55 | **Search logs** / 搜索日志 | 工具栏放大镜 | 本地 | `LogView` |
| 56 | **Save logs** / 导出日志 | 菜单 To Clipboard / To File / Share | 无额外权限以外的文件选择 | `LogView` |
| 57 | **Clear Logs** / 清空 | 菜单破坏性项 | `ClearLogs` RPC | 同上 |
| 58 | **View Service Log**（文档旧称） / 服务崩溃日志 | 文档写 *Settings → View Service Log*；**当前 `dev` 源码没有这句文案**。对应实现是 **Tools → Crash Report**（及 OOM Report） | 扩展/Helper 崩溃文件 | [features § Chore](https://sing-box.sagernet.org/clients/apple/features/)；`CrashReportListView.swift` |

---

## 5. 设置与系统集成

路径一律 **Settings** 侧栏（`⌘,` 也可）。子页：App / Core / Packet Tunnel / On Demand Rules / Profile Override / Remote Control；（Standalone）Sponsors。

### 5.1 App

| # | 功能名 | 触发 | 依赖 | 出处 |
|---|---|---|---|---|
| 59 | **Language** / 语言 | Picker：System Default + bundle 本地化（en / zh-Hans / zh-Hant / ru / fa） | 改完提示 Restart Required | `MacAppView.swift`；`Info.plist CFBundleLocalizations` |
| 60 | **Start At Login** / 开机启动 | Toggle。说明：若同时开 Menu Bar + Keep in Background，登录时不自动打开窗口 | `SMAppService.mainApp` | `MacAppView.updateLoginItems` |
| 61 | 登录后自动拉起 VPN | `applicationDidFinishLaunching`：若作为 login item 启动且 `started_by_user` 则 `ExtensionProfile.start()` | **当前 `dev` 树只读该偏好、没有任何 `set` 调用**（默认 `false`），因此这条路径在现源码里实际上不会启动 VPN | `MacLibrary/ApplicationDelegate.swift`；`SharedPreferences.startedByUser` |
| 62 | **Show in Menu Bar** / 菜单栏图标 | Toggle，默认 true | `NSStatusItem` | `SharedPreferences.showMenuBarExtra`；`StatusBarController` |
| 63 | **Real-time Speed** / 菜单栏实时速度 | Disabled / Enabled / Unified | command status 流 | `MenuBarExtraSpeedMode` |
| 64 | **Keep Menu Bar in Background** / 后台保留菜单栏 | 关窗口不退出（accessory policy） | 与 Start At Login 组合 | `MacAppView`；`ApplicationDelegate.applicationShouldTerminateAfterLastWindowClosed` |
| 65 | **Cache Size / Clear Cache** / 缓存 | 展示大小；有缓存时 **Clear Cache** | 应用 cache 目录 | `MacAppView` |
| 66 | **Ghostty Configuration** / 终端主题 | App → Tailscale → Ghostty Configuration | Tailscale SSH 终端（Tools） | `GhosttyConfigurationView.swift` |
| 67 | **Update Track** / 更新通道 | 仅 Standalone：Stable / Beta | GitHub Releases | `MacAppView` Update Settings |
| 68 | **GitHub Token** | 同上 SecureField | 提高 API rate limit | 同上 |
| 69 | **Automatic Update Check / Check Update** | Toggle + 按钮；可 Force Show | Standalone only | `UpdateManager`；`Library/Update/` |
| 70 | **System Extension Install / Update / Uninstall** | App → System Extension | 见 §0.1 | `MacAppView` |
| 71 | **Helper Service** / 助手服务 | App → Helper Service：Install / Enable（系统设置批准）/ Update / Uninstall。footer 写明：给 `process_name` / `process_path` 查进程，并管理 working directory | `SMAppService.daemon`；需系统设置 Login Items 批准 | `HelperServiceManager.swift`；`MacAppView` footer |

### 5.2 Core

| # | 功能名 | 触发 | 依赖 | 出处 |
|---|---|---|---|---|
| 72 | **Version** / 内核版本 | Core 页只读 | `LibboxVersion()` | `CoreView.swift`；[general § Core](https://sing-box.sagernet.org/clients/general/) |
| 73 | **Data Size** / 工作目录大小 | 只读；Standalone 无 Helper 时显示 Unavailable，点一下跳 App Settings | Helper（Standalone）或直接读目录（App Store） | `CoreView` |
| 74 | **Open working directory** / 打开工作目录 | App Store 版 **Open**（Finder） | 非 System Extension | `CoreView` |
| 75 | **Destroy** / 销毁工作目录 | 红色按钮；运行中先停服务 | 同上 | `CoreView.confirmDestroyWorkingDirectory` |
| 76 | **Disable Deprecated Warnings** / 关闭弃用警告 | 仅 `LibboxVersion()` 含 `-` 的 Beta | 偏好 | `CoreView`；`Variant.isBeta` |

官方 general 还写 Core 区应有 **memory limiter switch**。SFM 把它放在 **Tools → OOM Report → Enable Memory Limit**（见 §6），不在 Core 页。

### 5.3 Packet Tunnel

全部改完会在已连接时 `profile.restart()`。文案直接引用 Apple `NEVPNProtocol` 文档。

| # | 功能名 | 触发 | 依赖 | 出处 |
|---|---|---|---|---|
| 77 | **includeAllNetworks** | Settings → Packet Tunnel | 开启后文档写默认 TUN stack 改为 `gvisor`，`system`/`mixed` 不可用 | `PacketTunnelView.swift`；[Apple includeAllNetworks](https://developer.apple.com/documentation/networkextension/nevpnprotocol/3131931-includeallnetworks)；[features UI options](https://sing-box.sagernet.org/clients/apple/features/) |
| 78 | **excludeAPNs** | 同上（macOS 13.3+） | 仅 `includeAllNetworks` 为 true 时生效 | 同上；[Apple excludeAPNs](https://developer.apple.com/documentation/networkextension/nevpnprotocol/4140516-excludeapns) |
| 79 | **excludeCellularServices** | 同上 | 主要对 iOS 有意义；macOS 仍暴露 | [Apple excludeCellularServices](https://developer.apple.com/documentation/networkextension/nevpnprotocol/4140517-excludecellularservices) |
| 80 | **excludeLocalNetworks** | 同上 | 需 `includeAllNetworks` 或 `enforceRoutes` | [Apple excludeLocalNetworks](https://developer.apple.com/documentation/networkextension/nevpnprotocol/3143658-excludelocalnetworks) |
| 81 | **enforceRoutes** | 同上 | 覆盖系统路由表 | [Apple enforceRoutes](https://developer.apple.com/documentation/networkextension/nevpnprotocol/3689459-enforceroutes) |
| 82 | **excludeDeviceCommunication** | macOS 14.4+ | 源码注释「No documentation」 | [Apple excludeDeviceCommunication](https://developer.apple.com/documentation/networkextension/nevpnprotocol/excludedevicecommunication) |
| 83 | **Reset** Packet Tunnel | 红按钮 | `SharedPreferences.resetPacketTunnel` | `PacketTunnelView` |

TUN inbound 字段在 Apple 客户端的可用性（官方表，摘 SFM 相关）：`interface_name` 由 Darwin 管理；`gso`/`strict_route`/`include_interface`/`exclude_interface`/`include_uid`/`exclude_uid`/`include_package`/`exclude_package` **未实现**；`stack`/`auto_route`/`address`/`mtu`/`route_*`/`platform` 可用。  
出处：[features § TUN](https://sing-box.sagernet.org/clients/apple/features/)。

### 5.4 On Demand Rules

对应官方 UI option **Always On**。

| # | 功能名 | 触发 | 依赖 | 出处 |
|---|---|---|---|---|
| 84 | **Mode: Disabled** | Settings → On Demand Rules | VPN 不自动连 | `OnDemandRulesView.swift`；[features Always On](https://sing-box.sagernet.org/clients/apple/features/) |
| 85 | **Always On** | Mode = Always On | `NEOnDemandRuleConnect` + probe `http://captive.apple.com`，任意接口 | `ExtensionProfile.makeDefaultOnDemandRules` |
| 86 | **Enabled**（自定义规则） | Mode = Enabled；+ 添加规则 | `NEOnDemandRule` | `OnDemandRule.toNERule` |
| 87 | 规则 **Action** | Connect / Disconnect / Evaluate Connection / Ignore | NetworkExtension | `OnDemandRuleAction` |
| 88 | **Interface Type** | Any / Ethernet / Wi-Fi（macOS） | 同上 | `OnDemandRuleInterfaceType` |
| 89 | 条件：SSID / DNS Search Domain / DNS Server / Probe URL | 规则编辑页 | Probe 仅允许 http/https | `OnDemandRulesView` |
| 90 | **Evaluate Connection** 子规则 | Connect If Needed / Never Connect；Match Domains；DNS Servers；Probe URL | `NEEvaluateConnectionRule` | 同上 |

### 5.5 Profile Override（改写正在跑的 tun 路由，不改文件）

改完 `reloadService()`。

| # | 功能名 | 触发 | 依赖 | 出处 |
|---|---|---|---|---|
| 91 | **Hide VPN Icon** / 隐藏 VPN 图标 | Toggle。说明：向 `route_exclude_address` 追加 `0.0.0.0/31` 与 `::/127` | NE 路由排除默认路由，菜单栏 VPN 图标可不亮 | `ProfileOverrideView.swift` |
| 92 | **No Default Route** / 不用默认路由 | Toggle。用子网段代替 `0.0.0.0/0`；配置里已有 route_address 则不覆盖。说明：macOS 上会让 Internet Sharing 不正常 | `auto_route` | 同上 |
| 93 | **Exclude APNs Route** / 排除 APNs 路由 | 向 `bypass_domain` 加 `push.apple.com`，向 `route_exclude_address` 加 `17.0.0.0/8` | HTTP 代理 bypass + 路由排除 | 同上 |

### 5.6 Remote Control

| # | 功能名 | 触发 | 依赖 | 出处 |
|---|---|---|---|---|
| 94 | **Remote Control** / 远程控制 | Settings → Remote Control；工具栏 Local Device 菜单 | 远端 `services: [{type:"api", secret}]`；URL `host:port` / `http(s)://`；Secret → Bearer | [api service](https://sing-box.sagernet.org/configuration/service/api/)；changelog 1.14.0-alpha.32「Add dashboard support for the API service」；`RemoteControlView.swift`；`EditRemoteServerView.swift` |
| 95 | **Probe reachability** / 探测可达 | 编辑服务器时自动 | `CommandTarget.probe` → `getStartedAt` | `EditRemoteServerView` |
| 96 | 远程模式下 Dashboard/Groups/Connections/Logs/Tools 打远端 | 工具栏选中某 Server | `LibboxNewRemoteCommandClient` | `CommandClient.performConnection` |

文档：[api](https://sing-box.sagernet.org/configuration/service/api/) *「accessed by the sing-box graphical clients for iOS, macOS, and Android (via the Remote Control feature)」*。

### 5.7 路由规则平台能力（配置里写，不是独立开关）

官方表（[features](https://sing-box.sagernet.org/clients/apple/features/)）：

| 规则字段 | SFM App Store | SFM Standalone |
|---|---|---|
| `process_name` / `process_path` / `process_path_regex` / `user` / `user_id` | 否 | **是**（Helper `findConnectionOwner`） |
| `wifi_ssid` / `wifi_bssid` | 文档写 Only iOS；macOS 扩展仍可能 `needWIFIState()` 并要定位权限（SSID） | Standalone entitlement 含 `networking.wifi-info` + Location |
| `package_name` | 不适用 | 不适用 |

Helper footer 原文：*「process lookup for `process_name` and `process_path` routing rules」*。

---

## 6. 其它

| # | 功能名 | 触发 | 依赖 | 出处 |
|---|---|---|---|---|
| 97 | **Network Quality** / 网速质量测试 | Tools → Network Quality：URL、Serial、HTTP/3、Max Runtime | gRPC `StartNetworkQualityTest` | `NetworkQualityView.swift`；`started_service.proto` |
| 98 | **STUN Test** / STUN 测试 | Tools → STUN Test | `StartSTUNTest` | `STUNTestView.swift` |
| 99 | **Tailscale** 状态 / 本机 / Exit Node | Tools → Tailscale（配置里有 endpoint 才出现） | Tailscale endpoint；`SubscribeTailscaleStatus` / `SetTailscaleExitNode` | `TailscaleEndpointView.swift` |
| 100 | **Connect via SSH** / Tailscale SSH 终端 | 右键或 peer 页；Ghostty 终端窗口 | endpoint SSH；Standalone 才支持 **Forward Agent**（App Store 禁用） | `TailscaleSSHPromptView`；`TailscaleSSHTerminalWindow.swift` |
| 101 | **Taildrop** / 文件收发 | Tools 内 inbox/send；Share Extension 标题 **Taildrop**；URL `sing-box://taildrop` | Tailscale Taildrop（changelog：图形客户端可收发） | `ShareView.swift`；`MainViewModel.openURL`；[changelog Taildrop](https://sing-box.sagernet.org/changelog/) |
| 102 | **Share Extension** / 系统分享到 Taildrop | 其它 App 分享表 → sing-box | SFM：`ShareExtension.appex`；Standalone：`ShareExtension.System.appex` | `project.pbxproj` Embed Foundation Extensions |
| 103 | **OpenConnect / OpenVPN** | Tools 在配置有对应 endpoint 时出现；含 auth challenge | `SubscribeOpenConnectStatus` / `SubscribeOpenVPNStatus` | `ToolsView.swift` |
| 104 | **USB/IP** | Tools → USB/IP（配置有 usbip-server）；macOS 可提供本地 USB 设备 | USB entitlement `security.device.usb`；`ProvideUSBDevices` | `USBIPServerView.swift`；`USBIPProviderViewModel`；[usbip-client](https://sing-box.sagernet.org/configuration/service/usbip-client/)（macOS 需 CGO，SFM 已嵌入） |
| 105 | **OOM Report / Enable Memory Limit** / 内存限制 | Tools → OOM Report：Enable Memory Limit、Memory Limit picker、Kill Connections | Standalone 可关；iOS 扩展里 `oomKillerEnabled = true` 写死。官方 general 的 memory limiter | `OOMReportListView.swift`；[general § Core](https://sing-box.sagernet.org/clients/general/) |
| 106 | **Crash Report** / 崩溃报告 | Tools → Crash Report | 扩展/Helper 崩溃转储 | `CrashReportListView.swift` |
| 107 | **Taiwan Flag Available** / 台湾旗标检测 | Tools → Debug | 本地图形能力探测，与代理无关 | `ToolsView`；`SettingViewModel.checkTaiwanFlagAvailability` |
| 108 | **App Intents / Shortcuts** / 快捷指令 | 系统 Shortcuts：**Start / Stop / Restart / Toggle / Update Profile / Get status / Get current profile** | SFM 嵌入 `IntentsExtension.appex` | `IntentsExtension/Intents.swift` |
| 109 | **Sponsors** | Settings About（仅 Standalone `useSystemExtension`） | 外链 GitHub Sponsors | `SponsorsView.swift` |
| 110 | **Documentation / Changelog / Source Code / Rate on the App Store** | Settings About | 外链 | `SettingView.swift` |
| 111 | **Notifications OPEN_URL** | 内核通知；横幅按钮 Copy URL / Open | `UNUserNotificationCenter` | `ApplicationDelegate` |
| 112 | **Must live in /Applications** / 必须在应用程序文件夹 | 仅 Standalone 启动检查 | System Extension 路径约束；可用管理员权限搬运 | `MainViewModel.checkApplicationPath` |
| 113 | **Include All Networks**（文档 UI options 名） | 见 Packet Tunnel | 与 §77 同一开关 | [features UI options](https://sing-box.sagernet.org/clients/apple/features/) |

**明确不是 SFM 的能力（避免串台）：**

- tvOS **Import profile from iPhone/iPad**（`ImportProfileView`，`#if os(tvOS)`）。
- iOS **Widget / Control Center Toggle**、**FileProvider**（Files 里浏览工作目录）、**Action Extension**（`project.pbxproj` 挂在 SFI 的 Embed 阶段）。
- iOS jailbreak 版 Tailscale SSH server 与 process matching（[clients/apple](https://sing-box.sagernet.org/clients/apple/) Additional features）——那是 **SFI jailbreak**，不是 SFM。

---

## 7. SFM 功能 → 是否依赖 macOS 私有/受限能力

「私有」这里取实务含义：需要 **Apple Developer 受限 entitlement**、**系统扩展公证/用户批准**、**隐私权限**、或 **沙盒以外的 root helper**。不是说 SPI 私有 API 调用（源码未见直接链私有框架符号；System Extension / NetworkExtension 都是公有 API，但分发受能力限制）。

| 功能 | App Store SFM | Standalone SFM.System | 受限点 |
|---|---|---|---|
| Packet Tunnel 跑 Libbox + TUN | 需要 | 需要 | `packet-tunnel-provider` vs `packet-tunnel-provider-systemextension`；用户批准 VPN |
| 安装/更新 System Extension | 无此形态 | **需要** | `com.apple.developer.system-extension.install`；系统扩展批准；可能重启 |
| Helper Service（进程查找、工作目录、部分崩溃/OOM） | 无 | **需要** | `SMAppService` daemon；系统设置 Login Items 批准 |
| `process_name` / `process_path` / `user` 路由 | **不可用** | Helper + `findConnectionOwner` | 官方写明 Only macOS standalone（及 iOS jailbreak） |
| `wifi_ssid` / `wifi_bssid` | 文档标 iOS；macOS 扩展仍可能要定位 | Location + `networking.wifi-info` | 定位权限文案写「WIFI SSID and BSSID rules」 |
| includeAllNetworks 等 NE 路由旗标 | 公有 NE API | 同左 | 无额外 entitlement |
| On Demand / Always On | 公有 `NEOnDemandRule` | 同左 | 无 |
| System HTTP Proxy | 公有 `NEProxySettings` | 同左 | 无；但要 profile `platform.http_proxy` |
| iCloud Profile | iCloud Documents 容器 | 同左 | `icloud-container` / CloudDocuments（标准能力，需开发者账号） |
| App Group 共享配置 | `group.io.nekohasekai.sfavt` | TeamID+bundle 形式 | App Group |
| 沙盒 | **有** `app-sandbox` | Standalone **主程序 entitlement 无 sandbox 键**（`SFM.System/SFM.entitlements`）；System Extension 自身仍 sandbox | App Store 强制沙盒 |
| Start At Login / 菜单栏后台 | `SMAppService.mainApp`（公有） | 同左 | 无 |
| 相机扫码 | `security.device.camera` | 同左（Info.plist 有 Usage） | 隐私权限 |
| USB/IP 提供本地设备 | USB entitlement | `security.device.usb` | 外设权限 |
| Full Disk Access（扩展读额外路径） | 启动失败会引导开 **SFMExtension** FDA | 工作目录在用户目录，路径不同 | TCC |
| 远程 API / Dashboard gRPC | 普通网络客户端 | 同左 | 无受限 entitlement |
| App Intents | 嵌入 IntentsExtension | （Standalone 工程未嵌同一套 Embed ExtensionKit，Shortcuts 以 App Store 线为准） | 无 |
| GitHub 自动更新安装 pkg | 无 | Helper `UpdateInstaller` | 管理员/helper |
| 把 App 移到 `/Applications` | 无 | `NSAppleScript` `with administrator privileges` | 管理员授权，非私有 API |
| Widget / Control Center | **无**（SFI） | 无 | — |
| 独立 `sing-box` 进程 | **无** | **无** | 两者都是 NE 内嵌 Libbox |

---

## 8. 证据索引

| 资源 | URL |
|---|---|
| Apple 客户端总页（SFI/SFM/SFT） | https://sing-box.sagernet.org/clients/apple/ |
| Apple 功能 / TUN 字段表 | https://sing-box.sagernet.org/clients/apple/features/ |
| 图形客户端统一规范 | https://sing-box.sagernet.org/clients/general/ |
| 图形客户端入口 | https://sing-box.sagernet.org/clients/ |
| Changelog | https://sing-box.sagernet.org/changelog/ |
| TUN inbound（含 `platform.http_proxy`） | https://sing-box.sagernet.org/configuration/inbound/tun/ |
| API service（Remote Control / Dashboard） | https://sing-box.sagernet.org/configuration/service/api/ |
| 源码仓库 | https://github.com/SagerNet/sing-box-for-apple |
| 内核 libbox + daemon proto | https://github.com/SagerNet/sing-box/tree/testing/experimental/libbox ；`daemon/started_service.proto` |
| Homebrew Cask | https://formulae.brew.sh/cask/sfm |
| GitHub Releases（含 SFM pkg） | https://github.com/SagerNet/sing-box/releases |

条目计数：上表 **#1–#113** 为用户可见功能条目（§0 五个关键事实不另计）。
