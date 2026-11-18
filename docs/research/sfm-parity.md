> 搬自 `sing-box-mygo` `docs/tasks/parity.md`，2026-11-18。113 条定义保留；**状态列全部作废，待重判**：旧项目没有网络扩展，#2、#24–25、#70、#77–91 等在新架构下变为必做（Fable 审计结论）。

# SFM 功能对照（M6 退出门）

基线：`docs/research/sfm-feature-matrix.md` #1–#113。状态只有四种：

- **做** — 已实现，写明在哪（卡号 / 文件）。
- **等价** — 用我们架构下的等价机制实现，写明差异。
- **不适用** — SFM 的这一项依赖我们刻意不用的东西（NetworkExtension、App Store、Apple 账号容器），写明为什么，且**不在 UI 上放空开关**（原则 5）。
- **待做** — 有卡、未完成。M6 退出时不允许存在「未判定」。

## 1. Profile

| # | 功能 | 状态 | 说明 |
|---|---|---|---|
| 1 | Local profile | 做 | M2-1 `profile.Store.CreateLocal`；M3-3 |
| 2 | iCloud profile | 不适用 | 需要 Apple 开发者账号绑定的 iCloud 容器。Local + 用户自己的同步目录可替代，但不伪装成 iCloud |
| 3 | Remote profile | 做 | M2-1 |
| 4 | Create Manually | 做 | M3-3 |
| 5 | Import from File（.json / .bpf） | 做 | M3-3；.bpf 经 worker `DecodeProfile`（`app/bpf.go`） |
| 6 | Scan QR Code | 等价 | M6-1：新建菜单「从二维码图片导入…」（截图/照片）：导入链接 → 远程配置；单帧 QRS → 配置。多帧 QRS 需要连续摄像头帧，图片做不到，提示改用 .bpf（#5/#10）。桌面上不做摄像头扫码 |
| 7 | Share as QRS Code | 做 | M6-1：卡片菜单「以 QRS 动态码分享…」，`internal/qrs` 与 SFM 线格式逐字节兼容（SFM 自测向量通过；真内核 .bpf → QRS → 解码字节一致），帧率 1–30、分片 300–1500 |
| 8 | Share URL as QR Code | 做 | M6-1：远程配置卡片菜单「以二维码分享链接…」，内容与 libbox `GenerateRemoteProfileImportLink` 一致（测试对比真 libbox 输出）；可复制链接 |
| 9 | `sing-box://import-remote-profile` | 做 | `profile.ParseImportLink` + `mygo.json` urlSchemes；也认 `parallux://` |
| 10 | 打开 .bpf 文件 | 做 | `app.ImportBPF`；文件关联见 M6-2 |
| 11 | Edit Profile 元数据 | 做 | M3-3 |
| 12 | Edit Content（校验 + 格式化） | 做 | M3-3；校验/格式化经内核 worker |
| 13 | View Content（Remote 只读） | 做 | M2-1 + M3-3 |
| 14 | Auto Update | 做 | M2-1 调度 |
| 15 | Auto Update Interval（下限 15 / 0→60） | 做 | M2-1，单测锁住 |
| 16 | 立即更新 | 做 | M3-3 |
| 17 | Last Updated | 做 | M3-3 |
| 18 | HTTP Basic auth | 做 | M2-1（userinfo → Basic，错误信息里 redact） |
| 19 | 切换 profile（运行中热加载） | 做 | `Controller.SelectProfile` |
| 20 | 删除 / 排序 | 做 | M3-3 |
| 21 | Save / Share File（.bpf） | 做 | `app.ExportBPF` |
| 22 | Save / Share JSON | 做 | M3-3 |
| 23 | 拉取 UA | 做 | `cmd/parallux` 注入 `Parallux/<ver> (sing-box; darwin)` |

## 2. Dashboard 与核心控制

| # | 功能 | 状态 | 说明 |
|---|---|---|---|
| 24 | Install Network Extension | 等价 | 「安装特权助手」（SMAppService daemon，ADR 0003） |
| 25 | Install System Extension | 等价 | 同上 |
| 26 | Start / Stop | 做 | Activity 页头、概览、菜单栏 |
| 27 | 运行时长 | 做 | Activity 页头 h:mm:ss |
| 28 | Status 卡（内存、协程） | 做 | Activity |
| 29 | Connections 计数卡 | 做 | Activity |
| 30 | Upload / Download 卡 + sparkline | 做 | Activity |
| 31 | System HTTP Proxy 开关 | 做 | Activity + 概览；`ManagedService.SetSystemProxyEnabled`，宿主为 `platform_darwin.go` |
| 32 | Mode | 做 | Activity 分段、菜单栏 |
| 33 | Profile 卡 | 做 | Activity |
| 34 | Dashboard Items（开关、排序、重置） | 做 | Activity「仪表盘卡片」 |
| 35 | 切换即热加载 | 做 | 同 #19 |
| 36 | 启动失败 / FDA 提示 | 等价 | 启动错误原样显示；TUN 权限错误给出「安装特权助手」的补救（`explainStartError`）；FDA 在权限面板 |

## 3. 组与节点

| # | 功能 | 状态 | 说明 |
|---|---|---|---|
| 37 | Groups | 做 | M3-4 |
| 38 | 展开 / 折叠 | 做 | M3-4 `SetGroupExpand` |
| 39 | 选择节点 | 做 | M3-4、菜单栏 |
| 40 | 组 URLTest | 做 | M3-4、菜单栏 |
| 41 | 节点 URLTest | 做 | M3-4 右键菜单 |
| 42 | 延迟着色 / 色点网格 | 做 | M3-4 `Palette.Delay` |
| 43 | 菜单栏切组 | 做 | M5-1 |

## 4. 连接与日志

| # | 功能 | 状态 | 说明 |
|---|---|---|---|
| 44 | Connections | 做 | M3-5 |
| 45 | State 过滤 | 做 | `Runtime.Connections` + M3-5 |
| 46 | Sort | 做 | 同上 |
| 47 | 搜索（含 `network:` 等） | 做 | `matchConnection` 单测 |
| 48 | 连接详情 | 做 | M3-5（另加进程路径——SFM 没有） |
| 49 | 关闭单条 | 做 | M3-5 |
| 50 | 关闭全部 | 做 | M3-5、菜单栏 |
| 51 | 隐藏 dns 连接 | 做 | 单测锁住 |
| 52 | Logs | 做 | M3-6（上限 3000，与内核环一致） |
| 53 | 日志级别 | 做 | M3-6 |
| 54 | 暂停 / 继续 | 做 | M3-6 |
| 55 | 搜索 | 做 | M3-6 |
| 56 | 导出（剪贴板 / 文件） | 做 | M3-6，导出前 redact |
| 57 | 清空 | 做 | M3-6 `ClearLogs` |
| 58 | 服务崩溃日志 | 做 | M3-7 崩溃报告（`DesktopService.ListCrashReports`） |

## 5. 设置与系统集成

| # | 功能 | 状态 | 说明 |
|---|---|---|---|
| 59 | Language | 做 | M3-2（en / zh-Hans） |
| 60 | Start At Login | 做 | M3-2 `mygo.App.SetOpenAtLogin`（SMAppService.mainApp） |
| 61 | 登录后自动启动 VPN | 做 | 「打开应用时启动」——SFM 现源码只读不写该偏好，我们是真开关 |
| 62 | Show in Menu Bar | 做 | M5-1 |
| 63 | Real-time Speed | 做 | M5-1 |
| 64 | Keep in Background | 做 | M5-1 |
| 65 | Cache Size / Clear Cache | 等价 | GUI 无独立缓存；内核工作目录的大小与销毁见 #73 #75 |
| 66 | Ghostty Configuration | 做 | M6-3：设置 › 终端——浅/深色各选一个 Ghostty 主题（含 ~/.config/ghostty/themes）、字号、Option 作 Alt |
| 67 | Update Track | 等价 | MyGo 的更新 feed 构建期写死、运行期不可切；Beta 构建另设 `tagPrefix: beta-v`，渠道即所装构建（`docs/RELEASE.md`）。不做假开关（原则 5） |
| 68 | GitHub Token | 不适用 | Stable 检查读 `releases/latest/download/`，不经 API、无限流；Beta 每天一次 API 远低于 60/h（`docs/RELEASE.md`） |
| 69 | Automatic Update Check | 做 | M6-4：设置 › 关于「自动检查更新」（默认开、每 24 h）+「检查更新」+ 安装进度 +「重新启动以完成更新」；`mygo.Updater` 验签；无公钥的构建明示不支持 |
| 70 | System Extension 安装/更新/卸载 | 等价 | 特权助手 安装 / 卸载（权限面板） |
| 71 | Helper Service | 等价 | 同一个特权助手同时承担 TUN 与进程查找（root 内核自带进程匹配） |
| 72 | 内核版本 | 做 | M3-2 内核 |
| 73 | Data Size | 做 | M3-2 `diag.WorkingDirectory` |
| 74 | 打开工作目录 | 做 | M3-2 `Host.Reveal` |
| 75 | Destroy | 做 | M3-2 `diag.DestroyWorkingDirectory` |
| 76 | Disable Deprecated Warnings | 做 | M3-2（Settings 字段；弃用警告来自 `GetDeprecatedWarnings`） |
| 77 | includeAllNetworks | 不适用 | NE 协议层旗标。我们的 TUN 由 root 内核建 utun，等价控制在配置的 `strict_route` |
| 78 | excludeAPNs | 不适用 | NE 旗标；APNs 排除走 Profile Override #93 |
| 79 | excludeCellularServices | 不适用 | NE 旗标，Mac 无蜂窝 |
| 80 | excludeLocalNetworks | 不适用 | NE 旗标；等价写法是配置的 `route_exclude_address` |
| 81 | enforceRoutes | 不适用 | NE 旗标；utun 由 `auto_route` 直接改路由表 |
| 82 | excludeDeviceCommunication | 不适用 | NE 旗标 |
| 83 | Reset Packet Tunnel | 不适用 | 无 NE 设置可重置 |
| 84–90 | On Demand Rules | 不适用 | `NEOnDemandRule` 只存在于 NetworkExtension。v1 不发明替代（原则 5）；需求明确后另开卡 |
| 91 | Hide VPN Icon | 不适用 | utun 不会让 macOS 显示 VPN 图标，开关将无事可做（`settings.go` 注释） |
| 92 | No Default Route | 做 | `app.ApplyOverride`，子网段与 SFM 源码一致，单测锁住 |
| 93 | Exclude APNs Route | 做 | 同上 |
| 94 | Remote Control | 做 | `Controller.ConnectRemote` + M3-2 |
| 95 | 探测可达 | 做 | `control.Client.Probe`（`GetStartedAt`） |
| 96 | 远程模式下各页打远端 | 做 | 同一 Session；本机专属动作（Start/Stop、系统代理、工作目录）在远程时禁用并说明 |
| — | 路由规则平台能力（process / wifi） | 等价 | 特权助手下内核自带进程匹配；wifi_ssid 需定位权限（权限面板） |

## 6. 其它

| # | 功能 | 状态 | 说明 |
|---|---|---|---|
| 97 | Network Quality | 做 | M3-7 |
| 98 | STUN Test | 做 | M3-7 |
| 99 | Tailscale 状态 / Exit Node | 做 | M3-7 |
| 100 | Tailscale SSH 终端 | 做 | M6-3：工具 › Tailscale 的 peer「SSH…」→ 用户名（按 peer 记住）+ Forward Agent → MyGo terminal（libghostty-vt）窗口，走内核 `StartTailscaleSSHSession`；内核补了上游缺的 `PlatformHandler`，Forward Agent 只在用户态内核且有 SSH_AUTH_SOCK 时可开 |
| 101 | Taildrop | 做 | M6-5：工具 › Tailscale 的 endpoint 卡内收件箱（保存到下载 / 删除 / 取消接收）+ 在线 peer「发送文件…」 |
| 102 | Share Extension | 不适用 | 需 App Extension 打包与签名能力；Taildrop 发送走 #101 的文件选择 |
| 103 | OpenConnect / OpenVPN 状态与认证挑战 | 做 | 工具 › VPN（`internal/ui/tools/vpn.go`）；浏览器登录挑战明示不支持（需要 web view） |
| 104 | USB/IP | 不适用 | macOS 上需 cgo（官方注明），我们的内核 `CGO_ENABLED=0` |
| 105 | OOM Report / 内存限制 | 做 | M3-7 报告 + M3-2 内存限制（`StartOptions`） |
| 106 | Crash Report | 做 | M3-7 |
| 107 | Taiwan Flag 检测 | 不适用 | 与代理无关的 Apple 字体探测 |
| 108 | App Intents / Shortcuts | 等价 | `parallux://start|stop|toggle|restart|update-profiles`，快捷指令用「打开 URL」 |
| 109 | Sponsors | 不适用 | SFM 自身的赞助入口 |
| 110 | 文档 / 源码链接 | 做 | M3-2 关于 |
| 111 | 内核通知（OpenURL） | 做 | `app/notify.go` + `cmd/parallux` |
| 112 | 必须在 /Applications | 做 | M6-2-a：不在 /Applications 时 `RequestGrant` 拒装 helper 并说明；权限面板与概览增强模式卡不给安装、显示同一句说明 |
| 113 | Include All Networks（文档名） | 不适用 | 同 #77 |
