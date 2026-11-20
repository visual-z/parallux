---
type: fix
status: awaiting-author        # todo | doing | blocked | awaiting-author | done
weight: full
created: 2026-11-19
baseline: d270bf16c965
---

# 隧道能在沙盒里启动；启动失败时如实报错，不再卡在「正在连接」

## 来源

作者 2026-11-19 首次在签名构建上点「启动」：扩展是 `[activated enabled]`，VPN 停在 Connecting，界面一直「正在连接…」。查系统日志和复测，找到四处缺陷。它们一直就有，只是此前没有在签名构建上真正连过：

1. 扩展里 sing-box 启动时拉取远程规则集，DNS 查询失败：`dial udp 223.5.5.5:53: connect: operation not permitted`。
2. 扩展把 gomobile 的错误对象（类 `Universeerror`）交给 `startTunnel` 的 completionHandler。nesessionmanager 解码 `startedWithError:` 时报 `class "Universeerror" not loaded or does not exist` 并丢弃这条消息，会话因此一直停在 connecting。
3. 一大串规则集错误被原样塞进状态行，App 也从不读取启动失败的原因。
4. 装上新构建后点「启动」，扩展没有被替换：`AppModel.connect` 只在没有 VPN 配置时才调用 `install()`，于是系统里一直跑着旧扩展（复测时 `systemextensionsctl list` 仍是旧 build）。旧扩展监听的是旧版本号的 Mach 服务（决策 11），新 App 连不上它。

复测还看到：设置 › 内核里，清单显示「安装系统扩展」，下面却写「已启用 · 0.0.1」。原因是 `installedVersion()` 同时只服务一个调用方，第二个调用方拿到的是 nil（来自 71d6190）。

## 范围

- **独占：** `apple/project.yml` 的 PacketTunnel entitlements；`scripts/check-apple-config.sh`；`apple/PacketTunnel/PacketTunnelProvider.swift` 的 startTunnel 错误出口；`apple/ParalluxKit/Sources/ParalluxKit/Tunnel/ProviderError.swift` 与 `TunnelStartTests.swift`、`ProjectConfigTests.swift`；`SystemExtensionInstaller.swift`（版本查询）；`TunnelController.swift`（启动失败原因、启动时限）；`AppModel.connect` 的安装判断；`SetupView.swift`、`SettingsView.swift` 的内核页。
- **不碰：** App 与 Widget 的 entitlements；ProfileComposer；内核；聚合与代理开关（另开卡）。

## 观测面

- entitlements 由 project.yml 生成，测试解析 project.yml 的 PacketTunnel 块；`check-apple-config.sh` 再检查构建产物。
- 错误出口 `ProviderError.portable`：测试把一个系统不认识的类名（`Universeerror`）编码进去，按 nesessionmanager 的方式安全解码，失败策略设为「出错即返回」，这样解码失败会表现为断言失败而不是崩溃。
- 版本判断 `ExtensionVersion.needsActivation` 是纯函数；App 只负责把 macOS 报告的版本和自带版本交给它。

## 环境假设

- 本机已装的 SFM 系统扩展，签名权限里有 `com.apple.security.network.client` 和 `network.server`（2026-11-19 用 `codesign -d --entitlements -` 查看）。它仓库里的 `SystemExtension.entitlements` 没有这两项（2026-11-19 取 main 分支），是构建时由 Xcode 的沙盒设置注入的。Parallux 的扩展这两项都没有。
- 对拍（2026-11-19）：加上两项后，签名产物里确认有这两个键，但旧扩展没被替换，所以 EPERM 是否就此消失还没验证到；装上本卡的版本判断后再测一次，结果写进证据。如果仍然 EPERM，本卡的第一条前提就不成立，要停下来重新查。
- nesessionmanager 只能解码系统已知的类：日志原文 `Exception caught during decoding of received selector startedWithError: … class "Universeerror" not loaded`（2026-11-19 14:07:16）。
- SFM 判断扩展是否需要重装，是比较 propertiesRequest 返回的 bundleVersion / bundleShortVersion 与 App 自带的版本（SFM `SystemExtension.isInstalled`）。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** 扩展的 entitlements 声明 `com.apple.security.network.client` 与 `com.apple.security.network.server`，构建检查脚本同样要求这两项。
  - 检：test `theSystemExtensionCanOpenNetworkSockets`
- **D2** 交给系统的启动错误是普通 `NSError`：在只允许 `NSError` 的安全解码下能还原，类正好是 `NSError`，保留原文案，不带 underlying error，userInfo 里只有字符串。
  - 检：test `providerErrorsSurviveSecureDecodingAsPlainNSError`
- **D3** 启动错误摘要：保留第一处原因，注明还省略了几处，长度不超过 `summaryLimit`；空串和单条原因原样返回。
  - 检：test `startErrorSummariesKeepTheFirstCauseAndStayShort`
- **D4** 已装扩展的版本与自带版本不同（含没有安装、版本更高）时需要激活，相同时不需要。
  - 检：test `aNewBuildReplacesTheInstalledExtension`
- **D5** 计数：测试数只因本卡新增的测试而增加。
  - 检：cmd `keel gate`
- **D6** 不弱化既有测试。
  - 检：cmd `keel assert-guard --card docs/tasks/fix-tunnel-start-sandbox.md`
- **D7** 作者手测：装上新构建后点「启动」，扩展自动换成新版本并连上；配置有问题时状态行显示错误摘要，不会一直「正在连接」；设置 › 内核里清单与版本状态一致。
  - 检：author 统一手测

## 设计

- 两项权限与 SFM 的实际签名一致。否决只加 client：SFM 两项都有，扩展里 tun 入站和本地 DNS 也需要监听。
- `ProviderError.portable` 把任意错误转成 `NSError(domain: ProviderError.domain, code:, userInfo: [NSLocalizedDescriptionKey: 摘要])`，只在 `startTunnel` 这一个出口转换。否决让 Go 侧返回字符串：gomobile 的 error 绑定本身就会生成 `Universeerror`，那样每个调用点都得改。
- 启动失败原因：`TunnelController` 在状态从 connecting 变为 disconnected 时调用 `fetchLastDisconnectError`，存为 `startError`，AppModel 把它作为状态行的动作错误。再加一个启动时限 `startLimit`：超时仍在 connecting 就主动停止，并报「连接超时」，防的是扩展回调丢失这类情况。
- 安装判断：`AppModel.connect` 每次都先比较版本（`installer.installedVersion` 加上 `ExtensionVersion.needsActivation`），需要时才 `install()`。`installedVersion` 改成多个调用方共享同一次请求，`deactivate` 加上时限。

## 验证命令

```bash
scripts/swift-test.sh /tmp/t.xml ProjectConfig
scripts/swift-test.sh /tmp/t.xml ProviderError
keel verify-red docs/tasks/fix-tunnel-start-sandbox.md
keel gate --record docs/tasks/fix-tunnel-start-sandbox.md
```

## 证据

RED(swift): 97c3656 theSystemExtensionCanOpenNetworkSockets  # D1
RED(swift): 97c3656 providerErrorsSurviveSecureDecodingAsPlainNSError  # D2
RED(swift): 97c3656 startErrorSummariesKeepTheFirstCauseAndStayShort  # D3
RED(swift): 97c3656 aNewBuildReplacesTheInstalledExtension  # D4

- `check-apple-config.sh` 新增的两行先故意违规：去掉 project.yml 里的两个键，输出 `FAIL … missing com\.apple\.security\.network\.client`，`network.server` 同样失败，exit 1；恢复后 exit 0。
- 冒烟对拍（2026-11-19 14:28，签名 build 20261119062842）：
  - 点「启动」后，`systemextensionsctl list` 显示新 build `[activated enabled]`，旧 build `[terminated waiting to uninstall on reboot]`，即版本判断触发了替换，且不需要再次批准。
  - `scutil --nc list` 显示 Parallux `(Connected)`。`route -n get 1.1.1.1` 走 `utun6`。经隧道访问 apple.com 与 google.com 均返回 200。概览显示 59 个连接。
  - 环境假设第 1 条成立：加上权限后不再出现 EPERM。
GATE: 86fad45ea3b1+dirty ok tree:e975f8de3163 build=0 vet=0 test=0[590p/0f] fmt=0 swift-test=0[112p/0f] apple-build=0 server-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-19)

## 修订

## 交接

- 做了什么：补上扩展的网络权限；启动错误转成系统能解码的 NSError，并在状态行显示摘要；加 90 秒启动时限；每次连接都比对扩展版本，不一致就替换；版本查询改为多个调用方共享。签名构建已实测连上。
- 卡在哪：等作者统一手测 D7。
- 下一步：概览的流量图在已连接、有 59 个连接时仍显示「暂无活动连接」，另开卡处理；聚合与代理拆成两个开关，另开卡。
