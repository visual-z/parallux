# 统一手测清单

决策 16：M1–M6 的代码在作者手测之前全部写完，这里是一次性手测的顺序。前一步不过就停下，把现象和日志贴回来；后面的步骤大多依赖前面的。每一步后面写着它确认的卡与完成定义编号，测过的在卡里那一行追加「已确认：日期」。

扩展与 App 的日志：

```bash
log stream --predicate 'subsystem BEGINSWITH "io.github.visual-z.parallux"'
```

## 0. 准备

1. Xcode › 设置 › Accounts 保持登录团队 ABCDE12345 的 Apple 账号（2026-11-19 已登录，签名构建已装好）。
2. 断开 SFM 与 Surge 的 VPN（同一时间只能有一个 VPN 连接）。
3. `scripts/build-signed.sh --install`，打开 /Applications/Parallux.app。

**在 1.4 通过之前只启用一条线路**（线路页停用其他线路，或拔掉第二条）。两条以上线路时配置会经过组合器、依赖尚未证实的网口绑定；只开一条可以把 M1 的问题和绑定问题分开。

## 1. 地基与 M1 通路

| # | 操作 | 期望 | 卡 |
|---|---|---|---|
| 1.1 | 左键菜单栏图标；右键菜单 | 面板按设计稿；右键菜单有设置…，能把设置窗口打开到最前 | `chore-m0-skeleton` D6、`refactor-m1-foundations` D8 |
| 1.2 | 面板开关 → 系统设置 › 通用 › 登录项与扩展 › 网络扩展里批准 → 再开 | 2 秒内「已连接」与实时速率；关掉回到「未连接」 | `feat-sysext-xpc` D8 |
| 1.3 | 再 `build-signed.sh --install`，设置 › 内核 › 重新安装 | `systemextensionsctl list` 版本号变了，仍能连接 | `fix-signed-run-hazards` D5 |
| 1.4 | 插第二条线路（这一步才启用它）（USB 网卡或 iPhone USB 共享）。隧道关着：诊断 › App 内检测；连上：扩展内检测；「探测配置连接」→「测速」；「拷贝全部结果」贴回 | 三组都有结果。**这一步决定分流与主备是否成立** | `research-sysext-bind-interface` D3、`feat-probe-arms` D3 |

## 2. M2 基线

| # | 操作 | 期望 | 卡 |
|---|---|---|---|
| 2.1 | 配置页：新建、导入 .json / .bpf、远程订阅（含带 `user:pass@` 的）、从链接导入、iCloud 文件、编辑 JSON（无效 JSON 不保存）、名称与更新、导出、分享二维码 | 都能用；远程配置只读 | `feat-profiles` D8、`feat-parity-polish` D6 |
| 2.2 | 用一份真实订阅连接 | 能上网 | `feat-profiles` D8 |
| 2.3 | 节点（选、测速、折叠）、连接（过滤、排序、隐藏 DNS、检查器、关闭）、日志（级别、暂停、清空、导出后文件里没有订阅 token）、规则（命中数） | 都有数据 | `feat-core-session` D8、`feat-parity-polish` D6 |
| 2.4 | 面板、右键菜单、概览（流向图、曲线、卡片右键隐藏与上移）、设置七个标签、菜单栏图标（深浅色） | 与设计稿一致 | `feat-m2-interface` D8、`feat-parity-tail` D5 |
| 2.4a | 路由页：路线图 / 分组 / 试一下 三种视图切换；点规则只高亮其路径；节点选择器筛地区、按延迟排序；连接检查器「评估连接」跳到试一下；「编辑规则…」改走后规则标「已覆写」 | 与 `docs/design/routing-v0.3.html` 一致 | `feat-routing-page` D8 |
| 2.4b | 逐页对照 `docs/design/copy-and-style.md`：文案来自 SFM / Clash Verge Rev；窗口拖到最小（760×520）时单列、无横向滚动；各页空态 | 无大块留白，空态有标题和主操作 | `chore-ui-polish-secondary` |
| 2.5 | 设置 › 内核 › 辅助服务 › 安装 → 系统设置 › 登录项里批准；工作目录、清空、崩溃报告；配置加 `{"process_name":["curl"],"outbound":"direct"}` 后跑 curl | 状态「已启用」；连接页显示进程名与该规则 | `feat-helper-service` D8 |

## 3. M3 分流与主备（需要 1.4 通过）

| # | 操作 | 期望 | 卡 |
|---|---|---|---|
| 3.1 | 线路页：列出 Wi‑Fi、有线、iPhone；开关、拖动排序、仅备用；「检测出口」 | 改动立即生效不断线；同一出口时有提示 | `feat-links-interface` D5 |
| 3.2 | 面板选「分流」，开多个下载 | 连接分到两条线路，概览左列两股 | `feat-links-aggregate` D10 |
| 3.3 | 选「主备」，拔掉首选线路 | 2 秒内新连接走另一条；收到「线路不可用」通知 | `feat-links-aggregate` D10 |

## 4. M4 叠加（需要一台 Linux VPS）

| # | 操作 | 期望 | 卡 |
|---|---|---|---|
| 4.1 | `scripts/build-server.sh`，把 `parallux-server` 与 `server/install.sh` 拷到 VPS，`sudo sh install.sh --binary ./parallux-server --name 东京VPS`，放行提示的端口 | 打印 `parallux://aggregation-server?…` | `feat-bond` D8 |
| 4.2 | 聚合服务器页粘贴链接 | 显示延迟，自动设为叠加服务器 | `feat-bond-interface` D6 |
| 4.3 | 面板选「叠加」；诊断 › 单线程下载测速 | 叠加 ≥ 最快单线路的 1.6 倍（PLAN 目标） | `feat-bond-interface` D6、`feat-bond` D8 |
| 4.4 | 诊断 › 网络质量、STUN | 有结果 | `feat-parity-polish` 修订 |

## 5. M5 全量

| # | 操作 | 期望 | 卡 |
|---|---|---|---|
| 5.1 | 加桌面小组件；控制中心加开关（先在 App 里连接过一次） | 小组件显示状态、方式、线路数、速率；开关能连能断 | `feat-system-integration` D8 |
| 5.2 | 快捷指令里找 Parallux | 六个动作 | `feat-system-integration` D8 |
| 5.3 | 打开 `parallux://connect`、一条聚合服务器链接、一条 SFM 导入链接 | 各自生效 | `feat-system-integration` D8 |
| 5.4 | 从「下载」文件夹启动一份拷贝 | 提示移到「应用程序」 | `feat-system-integration` D8 |
| 5.5 | 设置 › 远程控制：添加另一台开了 command server 的设备，查看 | 各页显示远端数据；切回本机恢复 | `feat-remote-control` D4 |
| 5.6 | 配置含 tailscale / openvpn / openconnect endpoint 时看诊断 › 端点；设置 › 内核 › 内存上限 | 状态、登录、出口节点、认证；扩展日志显示 OOM 已开启 | `feat-parity-tail` D5 |
| 5.7 | 设置 › 关于 | 版本与许可 | `feat-system-integration` D8 |

## 6. M6 发布（需要凭据，见 `docs/RELEASE.md`）

| # | 操作 | 期望 | 卡 |
|---|---|---|---|
| 6.1 | 配 notarytool 凭据、Sparkle 密钥、更新源；同意创建 Developer ID 描述文件 | — | `feat-release` |
| 6.2 | `scripts/release.sh 0.1.0` | 公证并装订的 DMG 与 appcast；`check-release.sh` 通过 | `feat-release` |
| 6.3 | 装 0.1.0，再发 0.1.1，检查更新 | Sparkle 替换 App，扩展随后替换 | `feat-release` |
