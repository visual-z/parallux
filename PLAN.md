# PLAN — Parallux

本文件是目标、决策和里程碑的唯一权威来源。改动已定决策要先和作者讨论（AGENTS.md「Ask first」）。

## 1. 目标

让一台 Mac 同时用上它的所有网络出口（Wi‑Fi、网线、iPhone USB 共享、经网桥接入的第二个 Wi‑Fi），并且在此之上照常使用 sing-box 订阅代理。成功的样子：

- 多线程下载在「分流」下的吞吐接近各线路之和（≥ 各线路单独测速之和的 80%，诊断页可测）。
- 单条 TCP 连接在「叠加」下明显快于最快的单条线路（两条线路、目标 ≥ 1.6 倍最快线路，参照 singbox-multipath 在本机回环测得 13.4 → 26.7 Mb/s）。
- 任一线路掉线时，「主备」在 2 秒内切换，正在进行的连接不断开（叠加模式下由聚合服务器保证）。
- SFM（sing-box 官方 Mac 客户端）的功能全部可用：`docs/research/sfm-parity.md` 每条都有结论。

## 2. 非目标

- 用内置网卡同时连两个独立 AP：macOS 不向应用开放第二个 Wi‑Fi 客户端连接（CoreWLAN 只给 `en0`，2026-11-18 实测）。第二个 Wi‑Fi 靠外接网桥，App 只负责识别它。
- macOS 26 以下的系统：不做兼容层，界面只按 Liquid Glass 设计。
- Windows、Linux、iOS 客户端：先把 Mac 做好；Go 内核保持可移植，但不为它们写代码。
- App Store 分发：系统扩展加 Developer ID 签名和公证，从官网分发。
- 自己实现代理协议：协议全部来自 sing-box。

## 3. 原则与硬约束

- **一个程序接管流量。** 只有网络扩展里的 sing-box 接管系统路由，避免与别的 VPN/代理抢路由（Codex 会话里已确认 net-merge 与 sing-box TUN 同开会冲突）。
- **内核跑在沙盒化的系统扩展里。** 不能启动子进程（边界规则「core 不启动子进程」）。
- **许可证 GPLv3。** sing-box 是 GPLv3，整个项目随之开源；引用的代码登记在 `docs/LICENSES.md`。
- **零遥测。** 不收集使用数据；崩溃与日志只在本机，导出前经 `core/internal/redact` 脱敏。
- **有界资源。** 队列、缓冲、重试都有上限常量（AGENTS.md「Never」）。

## 4. 架构

见 AGENTS.md「架构速览」。数据流：系统流量 → 网络扩展（utun）→ sing-box 路由规则 → 出站。Parallux 在出站这一层加三样东西：

- **分流出站组**：同一节点按物理网口各建一个出站（`IP_BOUND_IF` 绑定），按连接均衡。不需要服务器。
- **叠加出站**：同一连接拆到多条线路，在用户自己的聚合服务器上重组；先基于 singbox-multipath（两条线路），之后换支持 N 条线路的多路径传输。
- **主备**：只走首选线路，失效时切换。

App 与扩展之间沿用 libbox 的 command server（StartedService gRPC，SFM 同款），聚合与线路统计另加一组消息。

## 5. 预算

| 指标 | 门槛 | 测法 | 实测或假设 |
|---|---|---|---|
| Libbox.xcframework 构建 | ≤ 3 分钟（M5 Pro） | `time scripts/build-core.sh` | 实测 86 秒（2026-11-18） |
| 面板打开到首帧 | ≤ 100 ms | 待定（M2 加 signpost） | 假设，待测 |
| 扩展常驻内存 | ≤ 80 MB（不开叠加） | 活动监视器 / `footprint` | 假设，待测；macOS 对系统扩展无 iOS 那样的 50 MB 硬限 |
| 流向图动画 CPU | 面板可见时 ≤ 5%，不可见时 0 | Instruments | 假设，待测 |

## 6. 里程碑

每个里程碑是一层，每层有一条可检查的「定理」（退出条件）。下一层只在上一层的退出条件全绿之后才开始。

| 里程碑 | 退出条件（可检查） | 状态 |
|---|---|---|
| M0 骨架 | gate 全绿：Go 内核与 Swift 包有测试；Libbox.xcframework 可构建；App 与系统扩展不签名可编译并链接内核；边界规则至少一条并演示过会红 | doing |
| M1 扩展通路 | 签名构建能安装系统扩展、启动 sing-box；App 经 command server 读到运行状态与流量（`research-sysext-ipc` 先回答 App Group 直连还是 XPC 中转） | todo |
| M2 SFM 基线 | 配置（本地 / iCloud / 远程订阅）、节点与测速、路由模式、连接、日志、隧道设置可用；`sfm-parity.md` 重判完成 | todo |
| M3 分流与主备 | 线路发现与开关、按网口绑定出站、每线路速率统计、面板与主窗口流向图接真实数据 | todo |
| M4 叠加 | 叠加出站 + 聚合服务器一键部署；两条真实线路上单连接吞吐达到目标 | todo |
| M5 全量与打磨 | SFM 对照全部有结论；小组件、控制中心、快捷指令；菜单栏模板图标 | todo |
| M6 发布 | Developer ID 签名、公证、自动更新；首个公开版本 | todo |

## 7. 决策记录

编号唯一且递增（`check-docs` 检查）。新决策只修订旧决策的某一条时，在旧条文原处加指针「（已由决策 N 修订）」，不改写其余条款。重大决策另写 `docs/adr/`。

| # | 日期 | 决策 | 理由与证据 | 状态 |
|---|---|---|---|---|
| 1 | 2026-11-18 | 采用 keel 工作区流程：卡先于代码、RED 可复验、完成定义冻结 | `docs/PRINCIPLES.md` | 生效 |
| 2 | 2026-11-18 | 只支持 macOS 26 及以上，界面按 Liquid Glass 设计 | 作者要求；不做降级 | 生效 |
| 3 | 2026-11-18 | 界面用 Swift 原生（SwiftUI + AppKit 状态项）；内核用 Go | 作者要求 | 生效 |
| 4 | 2026-11-18 | sing-box 作为库（gomobile 编成 Libbox.xcframework）跑在 NEPacketTunnelProvider 系统扩展里，不用独立进程 + root helper | 与 SFM 同构；Fable 审计未发现独立进程模型在 macOS 上的优势 | 生效 |
| 5 | 2026-11-18 | sing-box 钉 v1.14.4；构建参数照搬其 `cmd/internal/build_libbox` | singbox-multipath beta11 基于 v1.14.4 | 生效 |
| 6 | 2026-11-18 | 从零开始写代码；旧仓库 `sing-box-mygo` 只搬 redact、proto、SFM 对照文档，其余只作参考 | Fable 审计：可移植代码仅约 7%，旧架构排除网络扩展 | 生效 |
| 7 | 2026-11-18 | 界面以设计稿 v0.2 为准：菜单栏左键面板、右键原生菜单；主窗口九项侧栏；设置独立窗口；菜单栏用模板图标 | 设计稿 设计稿 v0.2（未入库） | 生效 |
| 8 | 2026-11-18 | Xcode 工程用 XcodeGen 从 `apple/project.yml` 生成，不入库 | 避免 pbxproj 合并冲突；生成物不手改 | 生效 |
| 9 | 2026-11-18 | Bundle ID 前缀 `io.github.visual-z.parallux`，App Group 为 `<Team ID>.io.github.visual-z.parallux` | 首次签名构建前可改；改动会影响已安装用户的数据位置 | 生效 |
