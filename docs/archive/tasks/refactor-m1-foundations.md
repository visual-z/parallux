---
type: refactor
status: awaiting-author
weight: full
created: 2026-11-18
baseline: 44a40cd
---

# M1 之前的架构地基：sing-box 注册钩子、XPC 通路、签名配置、按内容缓存的内核构建

## 来源

作者在 2026-11-18 要求 Fable 审计 M0 架构，并授权为避免局部最优而重构。审计结论（会话记录，摘要见本卡「设计」）与作者当日的两条决定：

- sing-box 改动放在 GitHub fork `visual-z/sing-box` 的 `parallux/v1.14.4` 分支，只含一个注册钩子提交，go.mod 用 replace 钉住。
- 加 root 辅助服务（SMAppService.daemon），只承担 SFM 需要它的事；内核仍在网络扩展里。

## 范围

- **独占：** `go.mod`、`go.sum`、`core/aggregate/`、`scripts/`、`apple/project.yml`、`apple/Config/`、`apple/ParalluxKit/Sources/ParalluxKit/AppGroup.swift`、`apple/Parallux/`、`PLAN.md`、`CONTEXT.md`、`keel.toml`、`mise.toml`、`docs/tasks/research-sysext-ipc.md`。
- **不碰：** `core/pxbridge` 的导出 API；`core/internal/redact`。

## 观测面

- Go：`libbox.CheckConfig` 的返回值（libbox 用自己的注册表建 box，正好是 App 与扩展会走的路径）。
- Swift：`swift test` 计数；生成的 entitlements 与 Info.plist 由 `scripts/check-apple-config.sh` 用 `plutil` 读取比对。
- GREEN 被截断的方式：CheckConfig 因别的原因（缺字段）报错而测试只看「有错」——测试断言错误里出现具体字段名；钩子没注册时错误是 `unknown outbound type`，第一条测试专门排除它。

## 环境假设

- libbox 1.14.4 的 `baseContext` 未导出，每次用 `include.OutboundRegistry()` 新建注册表（`experimental/libbox/config.go:29-40`，2026-11-18 读源码确认）。所以只能在 `include` 里加钩子。
- `libbox.CheckConfig` 会调用 `box.New`，构造出站但不 `Start`（同文件 51-67 行）。出站之间的引用只在 Start 时解析，所以「link 不存在」无法在 CheckConfig 阶段报错，留给 M3。
- XcodeGen 2.46.0 在 `entitlements.path` 没有 `properties` 时把文件重写为空字典（2026-11-18 实测 M0 产物）。
- SFM 的系统扩展 `NEMachServiceName` 带版本后缀，理由是扩展替换后 launchd 仍占着旧端点（SFM `Library/Shared/AppConfiguration.swift`）。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** libbox 认得 `aggregate` 出站类型，并交给 Parallux 的构造函数；合法的两线路主备配置通过 CheckConfig。
  - 检：test `TestLibboxResolvesTheAggregateOutboundTypeToParallux`
- **D2** `aggregate` 拒绝空的 links 和未知的 mode，错误里写明字段或取值。
  - 检：test `TestAggregateRejects`
- **D3** 没有 Team 前缀的 App Group（不签名构建）解析为「无」。
  - 检：test `aGroupWithoutATeamPrefixMeansNoGroup`
- **D4** 生成的 entitlements 与 Info.plist 含签名运行所需的键：App 有 system-extension.install、networkextension、application-groups；扩展有 app-sandbox、networkextension、application-groups，`CFBundlePackageType` 为 `SYSX`，`NEMachServiceName` 以 App Group 开头并带版本后缀。检查器先故意违规一次确认会红。
  - 检：cmd `scripts/check-apple-config.sh`
- **D5** Go 输入（go.mod、go.sum、core 下的 .go、build-core.sh、go 版本）不变时不重编 Libbox.xcframework；内核版本号随输入哈希变化，不再烧进 git describe。
  - 检：cmd `scripts/build-core.sh --check-fresh`
- **D6** PLAN 写入决策 10–13（fork、XPC 通路、root 辅助服务、聚合出站模型），修正主备「不断开」的目标措辞；`research-sysext-ipc` 改成复现 SFM 做法的卡；新增网口绑定实验卡。
  - 检：grep `| 13 |`
- **D7** gate 全绿；不弱化既有测试。
  - 检：cmd `keel gate`
- **D8** 作者手测：面板里的设置按钮能把设置窗口打开到最前；右键菜单有「设置…」。
  - 检：author 运行 App 点面板齿轮与右键菜单

## 设计

- **钩子**（fork 里唯一的提交）：`include.RegisterOutboundExtension / RegisterInboundExtension / RegisterEndpointExtension`，在对应 `*Registry()` 返回前调用。`core/aggregate` 在 `init` 里注册，gomobile 把它和 libbox 绑进同一个框架，所以 App 与扩展都能用。
- **聚合出站模型**：每条线路是一个 `direct` + `bind_interface` 出站；`aggregate` 出站带 `mode`（balance / bond / failover）和 `links`；节点用 `detour` 指向它。界面上的全局三选一只是改写这些出站的 mode 的预设。本卡只建选项与校验，构造函数对未实现的模式返回明确错误之外不做转发（转发是 M3）。
  - 否决：节点 × 线路展开成多个出站（节点数乘以线路数，污染分组与连接界面）。
- **IPC**：照 SFM：扩展在版本化的 `NEMachServiceName` 上开 NSXPCListener，App 请求后扩展把 command.sock 的文件描述符经 XPC 传回；libbox `SetXPCDialer` 原生支持。App Group 直连不可行：系统扩展以 root 运行，容器在 root 家目录（Apple DTS，developer.apple.com/forums/thread/800887）。
- **构建**：`build-core.sh` 先算输入哈希，与 `.build/core.stamp` 相同就跳过；默认只出 arm64（`ARCHS=all` 出双架构供发布）；gomobile 的冗长输出进 `.build/logs/`。
- **生成物**：Info.plist 与 entitlements 都由 `project.yml` 生成、不入库；XcodeGen 钉进 `mise.toml`。
- **签名**：NE 权限值走 xcconfig 变量 `PARALLUX_NE_PROVIDER`，默认 `packet-tunnel-provider-systemextension`（Developer ID / SFM 同款）；用 Apple Development 证书调试时在 Local.xcconfig 改成 `packet-tunnel-provider`。

## 验证命令

```bash
keel verify-red docs/tasks/refactor-m1-foundations.md
keel gate --record docs/tasks/refactor-m1-foundations.md
```

## 证据

RED: e967634 -run ^(TestLibboxResolvesTheAggregateOutboundTypeToParallux|TestAggregateRejects) ./core/aggregate/  # D1, D2
RED(swift): e967634 aGroupWithoutATeamPrefixMeansNoGroup  # D3

- D4 检查器演示（2026-11-18）：删掉生成的 `PacketTunnel/Info.plist` 里的 `CFBundlePackageType` 后，`scripts/check-apple-config.sh` 退出 1，`FAIL PacketTunnel/Info.plist: missing CFBundlePackageType`；重新生成后退出 0。
- D5：`scripts/build-core.sh --check-fresh` 构建后退出 0；只 `touch` 源文件仍为 fresh；改一行内容后退出 1（stale）；复原后退出 0。
- D6：PLAN 决策 10–13 已写入；`research-sysext-ipc` 由 `feat-sysext-xpc` 取代；新增 `research-sysext-bind-interface`。
GATE: 63ab03ec8d4b+dirty ok tree:63f0fc6cf046 build=0 vet=0 test=0[7p/0f] fmt=0 swift-test=0[8p/0f] apple-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-18)

## 交接

- 做了什么：fork `visual-z/sing-box` 分支 `parallux/v1.14.4`（钩子提交 78a5638）；`core/aggregate` 注册 aggregate 出站（分流 / 主备做最基础的按连接选线，叠加明确报未实现）；entitlements 与 Info.plist 改由 project.yml 生成并有检查器；Mach 服务名带版本；内核构建按内容哈希缓存、默认只出 arm64（128 MB）；PLAN 决策 10–13。
- 卡在哪：等作者手测 D8。
- 下一步：M1 先做 `research-sysext-bind-interface`，再做 `feat-sysext-xpc`；两者都要签名构建（Local.xcconfig 填 Team ID）。

## 修订

（无）
