# PLAN — Parallux

本文件是目标、决策和里程碑的唯一权威来源。改动已定决策要先和作者讨论（AGENTS.md「Ask first」）。

## 1. 目标

让一台 Mac 同时用上它的所有网络出口（Wi‑Fi、网线、iPhone USB 共享、经网桥接入的第二个 Wi‑Fi），并且在此之上照常使用 sing-box 订阅代理。成功的样子：

- 多线程下载在「分流」下的吞吐接近各线路之和（≥ 各线路单独测速之和的 80%，诊断页可测）。
- 单条 TCP 连接在「叠加」下明显快于最快的单条线路（两条线路、目标 ≥ 1.6 倍最快线路，参照 singbox-multipath 在本机回环测得 13.4 → 26.7 Mb/s）。
- 任一线路掉线时，「主备」在 2 秒内把新连接切到其他线路。不经聚合服务器时，掉线那条线路上的已有连接会断开重连；只有叠加（经聚合服务器）能让正在进行的连接不断。
- SFM（sing-box 官方 Mac 客户端）的功能全部可用：`docs/research/sfm-parity.md` 每条都有结论。

## 2. 非目标

- 用内置网卡同时连两个独立 AP：macOS 不向应用开放第二个 Wi‑Fi 客户端连接（CoreWLAN 只给 `en0`，2026-11-18 实测）。第二个 Wi‑Fi 靠外接网桥，App 只负责识别它。
- macOS 26 以下的系统：不做兼容层，界面只按 Liquid Glass 设计。
- Windows、Linux、iOS 客户端：先把 Mac 做好；Go 内核保持可移植，但不为它们写代码。
- App Store 分发：系统扩展加 Developer ID 签名和公证，从官网分发。
- 自己实现代理协议：协议全部来自 sing-box。

## 3. 原则与硬约束

- **一个程序接管流量。** 只有网络扩展里的 sing-box 接管系统路由，避免与别的 VPN/代理抢路由（Codex 会话里已确认 net-merge 与 sing-box TUN 同开会冲突）。
- **内核跑在沙盒化的系统扩展里。** 不能启动子进程（边界规则「core 不启动子进程」）。需要 root 的少数事情（按进程分流、工作目录、崩溃归档、安装更新）交给辅助服务（决策 12）。
- **许可证 GPLv3。** sing-box 是 GPLv3，整个项目随之开源；引用的代码登记在 `docs/LICENSES.md`。
- **零遥测。** 不收集使用数据；崩溃与日志只在本机，导出前经 `core/internal/redact` 脱敏。
- **有界资源。** 队列、缓冲、重试都有上限常量（AGENTS.md「Never」）。

## 4. 架构

见 AGENTS.md「架构速览」。数据流：系统流量 → 网络扩展（utun）→ sing-box 路由规则 → 出站。Parallux 在出站这一层加两种东西（决策 13）：

- **线路出站**：每条线路一个 sing-box `direct` 出站，`bind_interface` 绑到对应物理网口。
- **聚合出站**（`aggregate`，`core/aggregate`）：带 `mode`（balance / bond / failover）与 `links`（线路出站的 tag）。节点用 `detour` 指向它，所以节点数不会乘以线路数。界面上的全局三选一只是改写这些出站 mode 的预设。
  - 分流：按连接轮转线路；不需要服务器。
  - 主备：按优先级用第一条可用线路。
  - 叠加：同一连接拆到多条线路，在用户自己的聚合服务器上重组。先基于 singbox-multipath（两条线路，**只聚合 TCP，协议本身不加密**，需由子协议加密），之后换支持 N 条线路的多路径传输；叠加传输按「以出站为 leg」抽象，换实现不动配置格式。

- **中继线路出站**（决策 24）：局域网里的中继主机各算一条线路。出站是 sing-box 自带的 `shadowsocks`，`detour` 指向承载它的物理线路出站；tag 同样列进聚合出站的 `links`，并在 `relays` 里标明，内核据此不让它承载局域网目标。

聚合出站类型要注册进 sing-box，而 libbox 每次新建注册表、不能从外部扩展，所以用 fork 加一个注册钩子（决策 10）。

App 与扩展之间照 SFM：扩展在版本化的 `NEMachServiceName` 上开 XPC 监听，把它内部 command server 的 socket 文件描述符传给 App，App 用 libbox 的 command client（`SetXPCDialer`）说官方 StartedService gRPC（决策 11）。线路统计不在 StartedService 里，走同一条 XPC 连接上的额外方法。

**未证实的前提**：网络扩展接管默认路由后，扩展内的 socket 还能经 `IP_BOUND_IF` 绑到非默认的物理网口出去。sing-box 上游只在网口不是默认网口时才绑定；Apple 论坛有隧道起来后绑定失败（`EADDRNOTAVAIL`）的报告。M1 先用网口绑定实验（`docs/research/sysext-bind-interface.md`）证实，否则分流与主备的实现方式要重新设计。

## 5. 预算

| 指标 | 门槛 | 测法 | 实测或假设 |
|---|---|---|---|
| Libbox.xcframework 构建 | ≤ 3 分钟（M5 Pro，输入变化时） | `FORCE=1 time scripts/build-core.sh` | 实测：双架构 86 秒；换 fork 后首次 arm64 约 7 分钟（含模块下载），待复测 |
| 面板打开到首帧 | ≤ 100 ms | 待定（M2 加 signpost） | 假设，待测 |
| 扩展常驻内存 | ≤ 80 MB（不开叠加） | 活动监视器 / `footprint` | 假设，待测；macOS 对系统扩展无 iOS 那样的 50 MB 硬限 |
| 流向图动画 CPU | 面板可见时 ≤ 5%，不可见时 0 | Instruments | 假设，待测 |

## 6. 里程碑

每个里程碑是一层，每层有一条可检查的「定理」（退出条件）。下一层只在上一层的退出条件全绿之后才开始。

| 里程碑 | 退出条件（可检查） | 状态 |
|---|---|---|
| M0 骨架 | gate 全绿：Go 内核与 Swift 包有测试；Libbox.xcframework 可构建；App 与系统扩展不签名可编译并链接内核；边界规则至少一条并演示过会红 | 代码完成，等作者手测 |
| M1 扩展通路 | 签名构建能从 /Applications 安装系统扩展、启动 sing-box；App 经 XPC 拿到 command server 的连接，读到运行状态与流量；网口绑定实验证实扩展内能绑定非默认网口 | 代码完成，等作者手测（`docs/MANUAL-TEST.md` 第 1 节） |
| M2 SFM 基线 | 配置（本地 / iCloud / 远程订阅）、节点与测速、路由模式、连接、日志、隧道设置可用；辅助服务（SMAppService.daemon）就位；`sfm-parity.md` 重判完成 | 代码完成，等作者手测（第 2 节）；sfm-parity 已重判 |
| M3 分流与主备 | 线路发现与开关、按网口绑定出站、每线路速率统计、面板与主窗口流向图接真实数据 | 主体代码完成，等作者手测（`docs/MANUAL-TEST.md` 第 3 节，前提是 1.4 证实绑定）；设计稿新增项未全做，见 `docs/research/design-additions.md` |
| M4 叠加 | 叠加出站 + 聚合服务器一键部署；两条真实线路上单连接吞吐达到目标 | 代码完成，等作者手测（第 4 节，需要 VPS） |
| M5 全量与打磨 | SFM 对照全部有结论；小组件、控制中心、快捷指令；菜单栏模板图标 | 主体代码完成，等作者手测（第 5 节）；sfm-parity 剩 3 项待做，设计稿新增剩 10 项待做（`design-additions.md`） |
| M6 发布 | Developer ID 签名、公证、自动更新；首个公开版本 | 脚本完成，等作者配凭据（第 6 节） |

## 7. 决策记录

编号唯一且递增（`check-docs` 检查）。新决策只修订旧决策的某一条时，在旧条文原处加指针「（已由决策 N 修订）」，不改写其余条款。重大决策另写 `docs/adr/`。

| # | 日期 | 决策 | 理由与证据 | 状态 |
|---|---|---|---|---|
| 1 | 2026-11-18 | 采用 keel 工作区流程：卡先于代码、RED 可复验、完成定义冻结 | `docs/PRINCIPLES.md` | 生效 |
| 2 | 2026-11-18 | 只支持 macOS 26 及以上，界面按 Liquid Glass 设计 | 作者要求；不做降级 | 生效 |
| 3 | 2026-11-18 | 界面用 Swift 原生（SwiftUI + AppKit 状态项）；内核用 Go | 作者要求 | 生效 |
| 4 | 2026-11-18 | sing-box 作为库（gomobile 编成 Libbox.xcframework）跑在 NEPacketTunnelProvider 系统扩展里，不用独立进程跑内核（「不用 root helper」一句已由决策 12 修订） | 与 SFM 同构；Fable 审计未发现独立进程模型在 macOS 上的优势 | 生效 |
| 5 | 2026-11-18 | sing-box 钉 v1.14.4；构建参数照搬其 `cmd/internal/build_libbox` | singbox-multipath beta11 基于 v1.14.4 | 生效 |
| 6 | 2026-11-18 | 从零开始写代码；旧仓库 `sing-box-mygo` 只搬 redact、proto、SFM 对照文档，其余只作参考 | Fable 审计：可移植代码仅约 7%，旧架构排除网络扩展 | 生效 |
| 7 | 2026-11-18 | 界面以设计稿 v0.2 为准：菜单栏左键面板、右键原生菜单；主窗口九项侧栏（侧栏已由决策 20 修订）；设置独立窗口；菜单栏用模板图标 | 设计稿 设计稿 v0.2（未入库） | 生效 |
| 8 | 2026-11-18 | Xcode 工程用 XcodeGen 从 `apple/project.yml` 生成，不入库 | 避免 pbxproj 合并冲突；生成物不手改 | 生效 |
| 9 | 2026-11-18 | Bundle ID 前缀 `io.github.visual-z.parallux`，App Group 为 `<Team ID>.io.github.visual-z.parallux` | 首次签名构建前可改；改动会影响已安装用户的数据位置 | 生效 |
| 10 | 2026-11-18 | sing-box 用 fork `github.com/visual-z/sing-box` 分支 `parallux/v<版本>`，只含一个注册钩子提交（`include.Register*Extension`），go.mod replace 钉住；Parallux 的协议代码都在本仓库 `core/` | libbox 1.14.4 `baseContext` 未导出、每次新建注册表（`experimental/libbox/config.go:29-40`）；不直接依赖 singbox-multipath 的 fork，升级不受制于人。作者选定 | 生效 |
| 11 | 2026-11-18 | App 与扩展经 Mach XPC 通信：扩展在 `<App Group>.tunnel.<版本>` 上监听，传回 command server 的 socket fd；App 用 libbox command client | SFM `CommandXPC.swift` 同款；系统扩展以 root 运行，App Group 容器在 root 家目录，App 无法直连（developer.apple.com/forums/thread/800887）；版本后缀避开 launchd 占着旧端点 | 生效 |
| 12 | 2026-11-18 | 加 root 辅助服务（SMAppService.daemon，SFM HelperService 同款），只做 SFM 需要它的事：按进程分流、工作目录、崩溃归档、安装更新；内核仍在网络扩展里 | 完整对齐 SFM 需要它（SFM `ExtensionPlatformInterface.swift`、`HelperServiceManager.swift`）。作者选定 | 生效 |
| 13 | 2026-11-18 | 聚合模型：每条线路一个 `direct` + `bind_interface` 出站；一个 `aggregate` 出站（mode + links）承载分流 / 主备 / 叠加，节点用 `detour` 指向它；全局三选一只是预设 | 避免节点 × 线路展开；singbox-multipath 本就以出站 tag 为 leg。Fable 审计 | 生效 |
| 14 | 2026-11-18 | M1 的退出条件只差作者手测（签名安装、两条真实线路）时，可以并行推进 M2 里不依赖签名与网口绑定的部分（界面、配置管理、数据层）；依赖网口绑定的 M3 仍等网口绑定实验的结论 | 作者选定；M1 手测需要作者在场，等待期间不空转 | 生效 |
| 15 | 2026-11-18 | 日常开发用 Apple Development 签名，`PARALLUX_NE_PROVIDER = packet-tunnel-provider`；由 `xcodebuild -allowProvisioningUpdates -allowProvisioningDeviceRegistration` 在团队账号上注册 App ID、App Group 与本机；Developer ID 留给 M6 发布（Developer ID 的描述文件见决策 26） | 作者选定并授权改动开发者账号；2026-11-18 对拍：签名构建成功，entitlements 齐全 | 生效 |
| 16 | 2026-11-19 | 作者暂时不能手测：M3–M6 不再等上一层手测通过，代码全部写完后统一手测；M3 照决策 13 实现，网口绑定实验若证伪，只换线路出站的实现，配置格式与界面不动 | 作者选定。PLAN §6「下一层只在上一层全绿后开始」中「手测」一项由本决策暂缓，gate 仍须全绿 | 生效 |
| 17 | 2026-11-19 | 叠加：把 singbox-multipath（beta11，d99530a）的 `protocol/multipath` 整包移植进 `core/bond`，经 fork 的注册钩子注册为 `multipath` 出站与入站；`aggregate` 的 bond 模式生成到它的配置 | 作者选定；GPLv3 与本项目一致（附加条款：不得用 sing-box 名称）；只依赖 sing-box 公开包与 quic-go（已在依赖图里）；不依赖它的 fork，理由同决策 10 | 生效 |
| 18 | 2026-11-19 | 聚合服务器：仓库加 `server/`（Go，复用 `core/bond` 的入站）与一键安装脚本（systemd、生成 psk、输出导入链接）；App 粘贴链接添加服务器 | 作者选定；设计稿「添加服务器」一节 | 生效 |
| 19 | 2026-11-19 | 发布：写 Developer ID 签名、公证、DMG 打包脚本；自动更新用 Sparkle（新依赖，MIT）；公证凭据由作者之后配进钥匙串，脚本缺凭据时报错并说明，不推送、不发布 | 作者选定；Sparkle 是 macOS 独立分发 App 的通行做法（SFM 走 App Store，不适用） | 生效 |
| 20 | 2026-11-19 | 路由页按设计稿 v0.3（`docs/design/routing-v0.3.html`）：「节点」与「规则」合成「路由」，侧栏改为八项；路由页有两种视图——路线图（从流量出发）与分组（Clash 式的分组与节点）；「改走」存为 App 内的路由覆盖层（按配置分别保存，连接时改写规则的出站，配置文件不动），被覆盖的规则在界面上标明；流量类别名默认由规则条件生成，可重命名，名字也存在覆盖层；界面遵循 macOS 26 的 Apple 设计规范 | 作者评审设计稿后选定，并要求保留旧式分组视图 | 生效 |
| 21 | 2026-11-19 | 聚合与代理拆成两个独立开关（`ConnectionSwitches`）：只开聚合时用由用户配置派生的直连配置并交给线路；只开代理时不交线路；两个都关即断开；电源按钮与「启动」沿用上次的组合 | 作者提出并确认语义；Clash Verge Rev 也把系统代理与 TUN 做成两个独立开关；Speedify 没有「聚合但不加密」的组合 | 生效 |
| 22 | 2026-11-19 | 主窗口各页、面板与设置窗口的排版与用词以设计稿 v0.2 为准（决策 7 的重申）；`docs/design/copy-and-style.md` 只管设计稿没有画到的地方。控件仍用系统控件，容器（列表卡片、标记、代码块）照设计稿自己画；路由页仍按决策 20 的 v0.3 | 作者看过照 `copy-and-style.md` 改成系统列表与表单的页面后选定（「跟设计稿的风格很不契合」「以设计稿为准」） | 生效 |
| 23 | 2026-11-20 | 叠加时直连流量也经聚合服务器，推翻此前「叠加时直连流量不进聚合服务器」的做法；局域网目标（私有、环回、链路本地、CGNAT、组播地址与 `.local` 等本地名）和聚合服务器自身由内核 aggregate 排除（「聚合服务器自身」一条已由决策 25 修订：只对直连流量用的聚合出站排除）；主备保留 | 作者决定；直连本来就明文经过运营商，叠加并不增加暴露；代价是国内网站看到 VPS 的 IP | 生效 |
| 24 | 2026-11-20 | 中继线路（作者草图的方案 D）：局域网里的机器跑 `parallux-server -role relay`（sing-box 自带的 shadowsocks 2022 入站加 direct 出站），App 把每台中继主机当成一条线路——一个 `shadowsocks` 出站，`detour` 指向承载它的物理线路出站，列进聚合出站的 `links` 与 `relays`。中继线路只承载公网目标（内核沿用决策 23 的本地目标判定）、不做叠加的线路段、健康检查要一次真实往返；导入链接 `parallux://relay?v=1`（`docs/research/relay-link.md`）。聚合服务器仍然必须在公网（`docs/research/bond-without-vps-2026-11-20.md`） | 作者要求实现方案 D（2026-11-20；按设备限速的办公网里，作者实测 4 台节点合计 53–77 Mbps）。协议只用 sing-box 自带的（§2 非目标）；选 shadowsocks 2022 是因为不用证书、带认证与防重放、TCP 与 UDP 都转。回环对拍：上游不通时经中继的拨号仍然成功，所以健康检查不能只看连接。没有找到同类做法的社区先例 | 生效；协议选型（shadowsocks 2022）、`relays` 配置字段、导入链接格式与 16 条上限由实现提出，作者 2026-11-20 确认 |
| 25 | 2026-11-20 | 聚合服务器可以装在代理节点的机器上（同机节点）。服务端：`-self` 告诉它客户端用哪些地址或名字找到这台机器；目标是这些地址时走本机投递（先连本机发包用的地址，连不上或没人监听再按原地址拨），绝不连自己的监听端口；名字先解析，环回、私网、链路本地（含云元数据地址）与 100.64/10 的目标一律拒绝；服务从命令行参数启动，psk 只在 `/etc/parallux-server/psk`。客户端：节点用的聚合出站不再把聚合服务器地址排除在叠加之外，直连流量用的照旧（作者 2026-11-20 选定） | 作者选定做这一项（2026-11-20）。对拍：服务器够不着目标时客户端的叠加拨号仍然成功、随后读到 EOF，不会回退到线路，所以「自己拨自己的公网地址」不通就是整个节点不通；节点带 `domain_resolver` 时到达聚合出站的是 IP，按字面比较主机名识别不了同机。先例：engarde 把同机的 WireGuard 写成 `127.0.0.1`；3x-ui 与 OpenMPTCProuter 默认把环回或私网目标送进黑洞；没有云厂商文档保证虚拟机能连自己的公网 IP（`docs/research/node-hosted-aggregation-2026-11-20.md`） | 生效；拒绝私网目标是服务端行为的改变，由实现提出，待作者确认 |
| 26 | 2026-11-20 | 发布流程：归档用 Apple Development 签名，导出时由 Xcode（27 及以上）换成 Developer ID 签名并创建它托管的 Developer ID 描述文件，脚本带 `-allowProvisioningUpdates`；Sparkle 密钥按账户 `io.github.visual-z.parallux` 取，公钥在发布时从密钥读出；更新源放 GitHub Pages（`gh-pages` 分支），安装包放 GitHub Releases；公证凭据的档案名由 `PARALLUX_NOTARY_PROFILE` 指定。修订决策 15（只授权过开发签名的自动注册）与决策 19 里「公证凭据由作者之后配」一句 | 作者 2026-11-20 选定（发布 0.1.0 时：让 Xcode 自动创建描述文件、用已有的公证凭据、0.1.0 标为预发布）。对拍：Xcode 27.2 的 developer-id 自动导出把四个组件都签成 Developer ID、网络扩展权限改成 `-systemextension`；Apple 工程师称 Xcode 26 及更早不处理这个权限（developer.apple.com/forums/thread/737894）。更新源放 Pages、安装包放 Releases 是 Ice 等项目的做法（`release-0.1.0`） | 生效 |
| 27 | 2026-11-23 | 叠加只有在添加了聚合服务器之后才能选：没有服务器时点「叠加」不改变聚合方式，直接打开聚合服务器页；添加之后自动切到叠加；删除最后一台服务器前确认，删除后改为分流。新安装的默认聚合方式由叠加改为分流。界面上选的方式就是运行的方式；运行中才出现的情况（只剩一条物理线路、密钥读不出）仍按决策 24 退回主备并提示。聚合服务器不能起在本机：重组点必须在两条线路之后 | 作者 2026-11-23 决定（`fix-bond-needs-server`）：没有服务器时叠加悄悄按主备运行，作者第二次因此以为叠加坏了。作者在「没有服务器时按分流运行」（Peplink、Connectify Dispatch 在没有对端时的做法）和「不让选」之间选了后者；本机不能重组的依据见 `docs/research/bond-without-vps-2026-11-20.md` | 生效 |
