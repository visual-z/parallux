---
type: feat
status: awaiting-author
weight: full
created: 2026-11-19
baseline: 30d9908 (gate: test 9p/0f, swift-test 49p/0f)
---

# 辅助服务以 root 运行：按进程分流、工作目录、崩溃报告

## 来源

PLAN 决策 12（root 辅助服务，SMAppService.daemon，SFM HelperService 同款）；决策 16（作者暂不能手测，写完后统一手测）。SFM 参照（`SagerNet/sing-box-for-apple` 768b3de）：`HelperService/`（main、RootHelperService、WorkingDirectoryManager、LaunchDaemons plist）、`Library/Network/HelperServiceManager.swift`、`RootHelperXPC.swift`、`ConnectionOwnerLookup.swift`；sing-box `common/process/searcher_darwin_shared.go`（socket → 进程的匹配规则）。

本卡做按进程分流、工作目录、崩溃报告三项；安装更新属于 M6（决策 19，Sparkle），不在本卡。

## 范围

- **独占：** `apple/ParalluxHelper/`（新目标）、`apple/ParalluxKit/Sources/ParalluxKit/Helper/` 与对应测试、`apple/Parallux/Helper/`、`apple/Parallux/Settings/HelperSettingsSection.swift`、`apple/project.yml` 的辅助服务部分、`scripts/check-apple-config.sh` 与 `scripts/build-signed.sh` 的辅助服务检查。
- **只改一处：** `apple/Parallux/Settings/SettingsView.swift` 的 `CoreSettings` 加一行 `HelperSettingsSection()`；`apple/PacketTunnel/ExtensionPlatform.swift` 只改 `findConnectionOwner`。
- **不碰：** `core/**`；App 的 AppModel、面板、主窗口各页；ParalluxKit 的 Interface、Links、Session、Profiles、Tunnel（只读）。

## 不变量

无新增。连接归属的匹配是纯函数，用 property 测试覆盖。

## 观测面

- 纯 Swift：`SocketOwnerMatcher.match` 的返回值；`CrashReportCatalog.list` / `read` 的返回值；`HelperXPCClient` 经匿名 NSXPCListener 的往返与超时。
- 签名运行：设置 › 内核 › 辅助服务的状态、工作目录大小、崩溃报告列表（作者手测）；按进程分流规则生效（作者手测）。
- GREEN 被截断的方式：匹配器在候选为空时返回第一个元素或崩溃——测试显式跑 0、1、多个候选；客户端在对端不回复时永远等待——测试断言超时错误与耗时上限；读崩溃报告不限长度——测试用超过上限的文件断言截断。

## 环境假设

- `SMAppService.daemon(plistName:)` 要求 plist 放在 `Contents/Library/LaunchDaemons/`，`BundleProgram` 是相对 App 包的路径；守护进程要用同一团队签名，首次注册需要用户在 系统设置 › 通用 › 登录项 里批准（Apple「Updating helper executables from earlier versions of macOS」；SFM 同布局：`Contents/Helpers/RootHelper`）。**待手测。**
- 系统扩展以 root 运行且在沙盒里，`homeDirectoryForCurrentUser` 解析为 `/var/root/Library/Containers/<扩展 bundle id>/Data`（SFM `WorkingDirectoryManager.extensionBasePath` 写死同一路径）。Parallux 扩展的 libbox 工作目录是其下的 `Working/`（`PacketTunnelProvider.swift`），崩溃报告在 `Working/crash_reports/`（libbox `log.go:71`，读源码确认）。**路径待手测确认**：辅助服务读不到时设置页显示「目录不存在」。
- 辅助服务以 root 运行、不在沙盒里，可以读该容器、用 libproc 遍历全部进程的 socket（`proc_listpids`、`proc_pidinfo(PROC_PIDLISTFDS)`、`proc_pidfdinfo(PROC_PIDFDSOCKETINFO)`、`proc_pidpath`；`<libproc.h>`）。
- 匹配规则照 sing-box `matchDarwinConnectionEntry`：本地端口与地址族相同；本地地址与对端地址端口都相等为精确匹配；无对端时本地地址相等即匹配；UDP 另有「本地地址相等」与「本地地址为通配」两级回退。地址先去掉 IPv4 映射前缀（`normalizeDarwinAddrPort`）。
- Finder 打不开 root 的容器（权限 700），设置页只显示路径并提供「拷贝路径」，不提供「在访达中显示」。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** 匹配器：精确匹配优先；无对端时按本地地址；UDP 按本地地址再按通配地址回退；TCP 不回退；IPv4 映射的 IPv6 地址与 IPv4 等价；地址族不同不匹配；0 个候选返回空。
  - 检：test `SocketOwnerMatcherTests`
- **D2** 匹配器对任意候选集合（固定种子）：返回的候选一定在集合里，且端口与地址族满足查询；把精确匹配的候选放进任意位置都能找到它。
  - 检：property `theMatcherOnlyReturnsCandidatesThatFitTheQuery`
- **D3** 崩溃报告列表最新在前，最多返回上限条；读单个报告超过字节上限时截断并标记；文件名不在目录里（如含 `..`）时拒绝。
  - 检：test `CrashReportCatalogTests`
- **D4** 辅助服务的 XPC 客户端：经匿名 listener 往返得到归属结果与工作目录信息；对端不回复时在超时上限内报超时；销毁工作目录要求确认口令，口令不对时服务端拒绝。
  - 检：test `HelperXPCTests`
- **D5** 生成的辅助服务配置有签名运行所需的键：launchd plist 的 `Label`、`BundleProgram`、`MachServices`（在 App Group 内且带版本与构建号）、`AssociatedBundleIdentifiers`；检查器先故意违规一次确认会红。
  - 检：cmd `scripts/check-apple-config.sh`
- **D6** 签名构建里辅助服务嵌在 `Contents/Library/LaunchDaemons/` 与 `BundleProgram` 指向的位置，用团队身份签名，构建号与 App 相同。
  - 检：cmd `scripts/build-signed.sh`
- **D7** 计数只因本卡新测试增加；不弱化既有测试；gate 全绿。
  - 检：cmd `keel gate`
- **D8** 作者手测：设置 › 内核 › 辅助服务「安装」后在系统设置批准，状态变为「已启用」，版本与 App 一致；工作目录显示路径与大小，「清空工作目录」二次确认后执行；有崩溃报告时能列出并查看；配置里写一条 `process_name` 规则（例如 `{"process_name": ["curl"], "outbound": "direct"}`），连接页里 curl 的连接显示进程名并命中该规则；「卸载」后状态回到「未安装」。
  - 检：author 按「验证命令」里的手测步骤操作

## 设计

- **ParalluxKit/Helper（纯 Swift，可测）**：
  - `SocketOwnerMatcher`：`SocketEntry`（pid、uid、proto、本地/对端地址与端口）+ `Query`；地址用 16 字节表示，IPv4 映射到 `::ffff:a.b.c.d` 后统一比较。
  - `CrashReportCatalog`：列目录、按修改时间倒序、上限 50 条；读文件上限 256 KiB；名字只允许单段文件名。
  - `HelperXPCProtocol`（@objc）、`HelperXPC.makeInterface()`、`HelperXPCClient`（每次调用新建连接、信号量加超时，同 `TunnelXPC`）、`HelperWorkingDirectory`（路径常量与 `destroyToken`）。
- **ParalluxHelper（新目标，命令行工具）**：`main.swift` 开 `NSXPCListener(machServiceName:)`，只接受同团队签名的 App 与扩展（`setCodeSigningRequirement`）；`ProcessSockets.swift` 用 libproc 采集 `SocketEntry`（上限 4096 个进程，单次查询 1 秒预算）；结果经匹配器选出，`proc_pidpath` 与 `getpwuid` 补全路径与用户名。
- **嵌入**：XcodeGen `copyFiles` 把工具放进 `Contents/Library/HelperTools/`，plist 放进 `Contents/Library/LaunchDaemons/`（plist 由构建阶段从模板展开版本变量）。Mach 服务名 `$(PARALLUX_APP_GROUP).helper.$(MARKETING_VERSION).$(CURRENT_PROJECT_VERSION)`，与隧道同理（被替换的守护进程仍占着旧端点）。
- **App**：`HelperServiceManager`（`SMAppService.daemon`，注册、注销、状态、打开登录项设置）；`HelperSettingsSection`（状态、安装/卸载、版本、工作目录路径/大小/拷贝路径/清空、崩溃报告列表与查看）。
- **扩展**：`findConnectionOwner` 经 `HelperXPCClient` 查询，超时 1 秒（在连接建立路径上，不能久等）；失败时抛错，sing-box 按「找不到进程」处理。
- 否决：用 libbox 的 `FindConnectionOwner`（SFM 做法）——它在 Go 里用 sysctl `net.inet.tcp.pcblist_n` 读内核表，要把 Libbox.xcframework（128 MB）链进辅助服务；libproc 版本只用系统库，辅助服务保持很小。也否决「辅助服务里跑内核」：决策 4、12 规定内核只在网络扩展里。
- 引用：上述 SFM 文件为 GPLv3，改写后逐文件登记在 `docs/LICENSES.md`。

## 验证命令

```bash
scripts/swift-test.sh /tmp/helper.xml Helper
scripts/check-apple-config.sh
scripts/build-signed.sh
keel verify-red docs/tasks/feat-helper-service.md
keel gate --record docs/tasks/feat-helper-service.md
# 手测（D8）：scripts/build-signed.sh --install；打开 设置 › 内核 › 辅助服务
```

## 证据

RED(swift): 0379284 SocketOwnerMatcherTests  # D1
RED(swift): 0379284 theMatcherOnlyReturnsCandidatesThatFitTheQuery  # D2
RED(swift): 0379284 CrashReportCatalogTests  # D3
RED(swift): 0379284 HelperXPCTests  # D4

- RED 时的失败原文：D1 `Expectation failed: M.Address("10.0.0.2") == M.Address("::ffff:10.0.0.2")`（解析返回 nil）；D3 `Caught error: .notFound`；D4 `Caught error: .timedOut`（桩实现不发请求）。
- D5 检查器演示（2026-11-19）：删掉模板的 `MachServices` 并把 `PARALLUX_HELPER_MACH_SERVICE` 改成不带版本，`scripts/check-apple-config.sh` 退出 1，两条 FAIL（`missing MachServices.$(PARALLUX_HELPER_MACH_SERVICE)`、`must start with $(PARALLUX_APP_GROUP).helper. and contain …`）；复原（与备份逐字节相同）后退出 0。
- D6：`scripts/build-signed.sh` 退出 0，`signed … (build 20261118180425, …)`；辅助服务 `codesign -dv` 为 `Identifier=io.github.visual-z.parallux.helper`、`TeamIdentifier=ABCDE12345`、`flags=0x10000(runtime)`；LaunchDaemons plist 的 MachServices 为 `ABCDE12345.io.github.visual-z.parallux.helper.0.0.1.20261118180425`。
- 实现中发现：`plutil -extract MachServices.<名字>` 把带点的服务名当成键路径，签名构建里正确的 plist 被判缺键；改为取出 MachServices 字典后按整行比较键（先捕获再 grep，避开 pipefail 下的 SIGPIPE）。
- 新增测试 `theHelperServiceMustSitInsideTheAppGroup`（`HelperMachService.resolve`）。
GATE: 7dbbb0a2110a+dirty ok tree:e072ab7a4bf2 build=0 vet=0 test=0[9p/0f] fmt=0 swift-test=0[65p/0f] apple-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-19)

## 修订

（完成定义无改动。）

- 范围说明：实现时还改了 `.gitignore`（忽略生成的 `apple/ParalluxHelper/Info.plist`）、`apple/Config/Base.xcconfig`（加 `PARALLUX_HELPER_LABEL`、`PARALLUX_HELPER_MACH_SERVICE`）、新增 `apple/Config/helper-launchd.plist`（launchd 模板）与 `ParalluxKit/Helper/HelperMachService.swift`（读 Mach 服务名，配测试）。

## 交接

- 做了什么：新目标 `ParalluxHelper`（launchd 守护进程，嵌在 `Contents/Library/HelperTools/`，plist 在 `Contents/Library/LaunchDaemons/`，Mach 服务带版本与构建号）；libproc 扫 socket 加纯函数匹配器（照 sing-box 规则）；工作目录大小与清空（要确认口令）；崩溃报告列表与有上限的读取；同团队签名才接受连接；App 设置 › 内核 › 辅助服务；扩展的 `findConnectionOwner` 改经辅助服务（1 秒上限）。
- 卡在哪：等作者手测 D8；工作目录路径（root 容器）与 `SMAppService` 批准流程都没在真机上跑过。
- 下一步：作者手测。`SettingsView.swift` 里「工作目录、缓存与服务日志在辅助服务就位后提供」这行提示已过时，交给主线程改（本卡只允许加一行）。
