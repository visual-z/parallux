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
| 2.4c | 概览对照设计稿 v0.2（已连接、两条以上线路）：流向图直接画在内容区，线路 → 中柱 → 出口两段流带，粗细随流量变化（闲时是细带，不是一整块）；待命线路是虚线、停用线路变淡；粒子流动，系统设置里开「减弱动态效果」后静止；三张卡片等高，窗口拖窄后叠成单列；工具栏有「分流 / 叠加 / 主备」与电源按钮；副标题「N 条线路 · 聚合方式 · 经服务器」，出错时显示错误。活动监视器看 Parallux：概览可见与最小化后各 10 秒 | 与设计稿一致；CPU 可见时 ≤ 5%，最小化后为 0 | `fix-overview-design-parity` D8、D9 |
| 2.4d | 左键面板对照设计稿「菜单栏」一节：迷你流向图上叠着速率；「聚合」「代理」两个开关；线路行的圆形开关（启用时是线路色）、「主 / 备」、右侧速率或待命或已停用；分隔线；整宽的聚合方式；选「叠加」才出现「聚合服务器」；出口区「路由」「节点」；点「节点」能下钻并返回 | 与设计稿一致（标题右侧的总开关已由决策 21 的两个开关取代） | `fix-panel-design-parity` D3 |
| 2.4e | 面板 › 节点：圆形返回按钮、居中标题；药丸搜索框（进入即聚焦）与圆形测速按钮；分组标题可折叠；行没有白底和分隔线，悬停高亮；选中项只有对勾变色；搜索时无匹配的组消失；同一节点在多个组里都显示 | 与设计稿「菜单栏」节点下钻页一致 | `fix-panel-nodes-design-parity` D3 |
| 2.4f | 概览与面板的流向图各看 10 秒：粒子流动顺滑；流量变化时流带平滑过渡；断流几秒后静止 | 流畅；标签随新数据直接到位（不滑动）是否可接受；活动监视器里 Parallux 约 4–5%，最小化后为 0 | `perf-flow-animation` D4 |
| 2.4g | 逐页对照设计稿「主窗口」一节：线路（列表卡片；拖一行到另一行上能换位且立即生效；行尾更多菜单里的「仅备用」；开关）、配置（点一行即选用并出现「使用中」；拖动排序；远程配置的「更新」；更多菜单各项；下方只读预览随选中项变化）、聚合服务器（「在线 / 待命 / 不可用」、启用、更多 › 删除、复制命令、添加）、诊断（测速比例条）、连接（列名、规则标签、检查器的持续时间每秒变、关闭连接、评估连接）、日志（等宽底框、新日志滚到底、暂停后不滚） | 与设计稿一致，功能与之前相同 | `fix-pages-design-parity` D6 |
| 2.4h | ⌘, 设置：通用、聚合、隧道、按需连接、内核各标签的用词 | 与设计稿「设置窗口」一节一致；开关仍然生效 | `fix-pages-design-parity` D7 |
| 2.5 | 设置 › 内核 › 辅助服务 › 安装 → 系统设置 › 登录项里批准；工作目录、清空、崩溃报告；配置加 `{"process_name":["curl"],"outbound":"direct"}` 后跑 curl | 状态「已启用」；连接页显示进程名与该规则 | `feat-helper-service` D8 |

## 3. M3 分流与主备（需要 1.4 通过）

| # | 操作 | 期望 | 卡 |
|---|---|---|---|
| 3.1 | 线路页：列出 Wi‑Fi、有线、iPhone；开关、拖动排序、仅备用；「检测出口」 | 改动立即生效不断线；同一出口时有提示 | `feat-links-interface` D5 |
| 3.2 | 面板选「分流」，开多个下载 | 连接分到两条线路，概览左列两股 | `feat-links-aggregate` D10 |
| 3.3 | 选「主备」，拔掉首选线路 | 2 秒内新连接走另一条；收到「线路不可用」通知 | `feat-links-aggregate` D10 |
| 3.4 | 中继线路（需要局域网里至少两台 Linux 机器，时钟开着 NTP）。**先在一台节点上跑 `dig +tcp . NS @223.5.5.5`**：1 秒内没有回答就停下告诉我，中继线路的健康检查靠它，办公网不放行的话要换探测目标。然后 `scripts/build-server.sh`，把 `parallux-server` 与 `server/install.sh` 拷到每台机器，`sudo sh install.sh --relay --binary ./parallux-server --name worker-1`；线路页「添加中继线路 › 添加」，把几条链接一起粘进去 | 每台打印一条 `parallux://relay?…`；线路页多出几行，第二行写着「中继 · 经有线（en…）」，几秒内状态变成「已连接」；面板与概览的流向图左列有它们 | `feat-relay-links` D19、D20 |
| 3.5 | 选「分流」，开多线程下载（或诊断 › 测速逐条线路） | 中继线路各自有速率，合计超过单台设备的配额；有线那一行显示的是它自己承载的部分 | `feat-relay-links` D19 |
| 3.6 | 在一台中继主机上 `sudo systemctl stop parallux-relay`；访问 NAS 或打印机；关掉线路页的「有线」 | 2 秒内那条中继线路「不可用」并收到通知，其余连接照常；局域网设备照常访问；关掉有线后经它的中继线路变成「未使用」 | `feat-relay-links` D19 |

## 4. M4 叠加（需要一台 Linux VPS）

| # | 操作 | 期望 | 卡 |
|---|---|---|---|
| 4.1 | `scripts/build-server.sh`，把 `parallux-server` 与 `server/install.sh` 拷到 VPS，`sudo sh install.sh --binary ./parallux-server --name 东京VPS`，放行提示的端口 | 打印 `parallux://aggregation-server?…` | `feat-bond` D8 |
| 4.2 | 聚合服务器页粘贴链接 | 显示延迟，自动设为叠加服务器 | `feat-bond-interface` D6 |
| 4.3 | 面板选「叠加」；诊断 › 单线程下载测速 | 叠加 ≥ 最快单线路的 1.6 倍（PLAN 目标） | `feat-bond-interface` D6、`feat-bond` D8 |
| 4.4 | 诊断 › 网络质量、STUN | 有结果 | `feat-parity-polish` 修订 |
| 4.5 | 同机节点：在**自己的代理节点那台机器**上跑 4.1 的安装命令（公网 IP 不在网卡上的云主机要加 `--host <公网地址>`）；App 里选这个节点，聚合方式选叠加；诊断 › 单线程下载测速 | 安装不动节点原有的服务；测速里「叠加」比最快单线路快，连接页里这个节点的连接经 parallux-bond | `feat-node-hosted-aggregation` D12 |
| 4.6 | 节点机器上起一个只听 127.0.0.1 的服务（`python3 -m http.server --bind 127.0.0.1 8099`）；Mac 上叠加开着，访问 `http://<节点公网地址>:8099` | 打不开。注意这一步服务端做什么都会通过（卡的修订里有说明），真正的证据是自动测试；走一遍只是确认没有意外 | `feat-node-hosted-aggregation` D12 |
| 4.7 | 之前按 4.1 装过的服务器：重跑一次安装命令 | 打印的链接和原来的一样（密钥沿用），`/etc/parallux-server/config.json` 没有了，服务在跑 | `feat-node-hosted-aggregation` D12 |
| 4.8 | 看清本机投递的边界：节点机器上 `python3 -m http.server 8099`（听所有网卡），云安全组**不**放行 8099；Mac 上叠加开着，访问 `http://<节点公网地址>:8099`，再关掉叠加访问一次 | 叠加开着时**打得开**，关掉打不开。这是预期的：经聚合服务器到本机的连接不过安全组。你不接受的话告诉我，要另想办法 | `feat-node-hosted-aggregation` D16 |

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
