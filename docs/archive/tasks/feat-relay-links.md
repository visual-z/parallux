---
type: feat
status: awaiting-author        # todo | doing | blocked | awaiting-author | done
weight: full
created: 2026-11-20
baseline: 348886f9b2e8
---

# 局域网里的中继主机各算一条线路，分流把连接分给它们

## 来源

作者 2026-11-20 给了两张草图。B：叠加 + 公网 VPS（已实现）。D：办公网按设备限速，Mac 的有线口到集群节点是 604 Mbps 的内网；每台节点跑一个小的转发服务，App 把它当成一条额外的线路，分流把连接轮流分给 Mac 自己的两个出口和这几台节点，每台节点各占一份配额（作者实测 4 台同时 53–77 Mbps）。作者要求实现 D，并问 B 里的 VPS 能否用我们自己的软件代替；后者的结论在 `docs/research/bond-without-vps-2026-11-20.md`（不能，重组点必须在瓶颈之后）。

这是新功能，不是缺陷。

## 范围

- **独占：** `core/aggregate/relay.go` 及其测试；`server/cmd/parallux-server/relay.go` 及其测试；`apple/ParalluxKit/Sources/ParalluxKit/Relay/`；`apple/Parallux/Links/Relay*.swift`；`docs/research/relay-link.md`、`docs/research/bond-without-vps-2026-11-20.md`。
- **范围外的顺带改动：** `core/internal/redact`（`Text` 认 `parallux://` 链接，`psk` 记为敏感参数）。检查中继链接会不会进日志时发现的，聚合服务器链接原来也有同样的问题。
- **接缝（改动尽量小）：** `core/aggregate/register.go`（`Options.Relays`、两处拨号、探测器改由 `probers.go` 共享）、`health.go`（往返探测）、`stats.go`（包计数）、`local.go`（拆出本地目标判定）；`ProfileComposer.swift`；`AggregationServer.bond`；`LinkInventory.swift`（`LinkKind.relay`）；`AppModel`、线路页、面板、流向图里列线路的地方；`server/install.sh`、`main.go`。
- **不碰：** multipath 协议与两条线路段的限制；物理线路的选线、健康判据与计数（既有测试原样通过；探测器的归属改了，判据没改）；聚合服务器链接格式 v1；探测目标与探测间隔的取值。

## 不变量

- INV-14（开卡时编号 INV-12，合并进 main 时改号，见修订）：目标在局域网时，拨号顺序等于完整选线顺序去掉中继线路；其他目标就是完整顺序 — 检查方式：property。
- INV-5（扩充）：带中继线路时，出站之间的引用不成环 — 检查方式：property。

## 观测面

- 内核：用假的线路出站记录 TCP 拨号与 UDP 监听次数；`Snapshot()` 的计数；`healthSnapshot()`；纯函数 `relayOrder`、`relayDialFailure`、`probeOnce` 的返回值。
- 服务端：`RelayConfig` 的输出交给 `libbox.CheckConfig`；回环上真的起一个中继和一个客户端，经它回显 4 个字节；`run` 的返回值与写到 `stdout` 的链接。
- Swift：解析结果与错误值；`UserDefaults` 里落盘的字节；组合后 JSON 里每个出站的字段。
- GREEN 可能被截断的方式与挡法：
  - 局域网目标的测试如果轮转恰好没轮到中继，会假绿：每个目标拨两遍，并断言物理线路的拨号次数等于总次数。
  - 往返探测的测试如果连接本身失败，会把「不健康」误当成通过：同一个假拨号器在 `roundTrip=false` 时必须判健康。
  - 组合的 property 如果生成器很少产出可用的中继，证明不了什么：断言至少 50 轮里有中继出站。
  - 重复 tag 会让字典构造崩溃而不是断言失败：用不崩溃的构造，再断言数量。

## 环境假设

2026-11-20 在本机对拍（临时测试，未入库；现在的 `TestARelayCarriesAConnectionForTheOutboundTheAppComposes` 固化了前三条）：

- sing-box 的 shadowsocks 2022（`2022-blake3-aes-128-gcm`）只接受带填充的标准 base64、16 字节的 key。去掉填充报 `illegal base64 data at input byte 20`，URL 安全字母表报 `illegal base64 data at input byte 0`。所以不能沿用 install.sh 给聚合服务器生成 psk 的写法（base64url、无填充、32 字节）。
- 经中继拨一个关着的端口：拨号**成功**（0.2 ms），随后读到 EOF。shadowsocks 的握手是惰性的，中继连不上目标只表现为连接被关掉。所以健康检查必须有一次真实往返，物理线路「拨通即可达」的判据对中继不成立。
- sing-box 拒绝 `detour` 指向一个没有任何选项的 `direct`（`detour to an empty direct outbound makes no sense`）。线路出站总带 `bind_interface`，不受影响。
- `223.5.5.5:53` 接受 TCP 上的 DNS 查询（`dig +tcp . NS @223.5.5.5`，NOERROR，160 ms），在 1 秒的探测超时之内。**这次对拍只说明这台服务器会回答**：当时本机的默认路由在 `utun4`（另一个 VPN 开着），查询没有经过办公网出口。
- **未证实，手测前先查（`docs/MANUAL-TEST.md` 3.4 的第一步）：** 办公网出口放行节点到 `223.5.5.5` 的 TCP 53。不放行的话，每条中继线路都会一直显示「不可用」，分流永远不选它们。探测目标的取值在本卡的「不碰」里，要改得作者定。
- **未证实，留给作者手测（D19）：** 网络扩展接管默认路由后，绑在承载线路网口上的 socket 能到达同网段或经该网口网关可达的中继主机。这和 PLAN §4「未证实的前提」是同一个前提（`research-sysext-bind-interface`）；Apple 论坛的说法是绑了网口的 socket 优先于路由表（forums/thread/94430），但没有 macOS 系统扩展的专门答复。
- **未证实：** Mac 与中继主机的时钟相差不超过 30 秒（shadowsocks 2022 的重放窗口）。不满足时握手被拒，表现为中继线路不可用。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** 中继线路不承载局域网目标（私有、环回、链路本地地址与本地名，判定沿用 feat-bond-direct 的本地目标规则），TCP 与 UDP 都一样；公网目标照常在全部线路间轮转；全部线路都是中继时，局域网目标直接报错，不拨号。
  - 检：test `TestRelayLinksNeverCarryLocalDestinations`
  - 检：test `TestALocalDestinationWithOnlyRelaysFailsWithoutDialing`
- **D2** INV-12。
  - 检：property `TestLocalDialOrderDropsOnlyRelaysAndKeepsTheRest`
- **D3** 中继线路拨号失败（包括连接被拒）时换下一条线路，并立即把它标为不健康；物理线路上的连接被拒仍然是目标的回答，不重试；调用方取消不算证据。
  - 检：test `TestARelayThatRefusesIsSkippedAndMarkedDown`
- **D4** 中继线路只有在探测得到对端的回答时才算健康：上游立刻断开或一直不回答都判不健康，且不超过探测超时；物理线路的判据不变；没有 53 端口的探测目标时退回只看连接。
  - 检：test `TestARelayIsHealthyOnlyWhenARoundTripComesBack`
- **D5** 经中继线路的 UDP 包计入该线路的上下行与活动连接数，关闭两次只减一次；物理线路的包连接原样交出。
  - 检：test `TestRelayPacketsAreCounted`
- **D6** `relays` 里不在 `links` 中的 tag 被拒绝，错误信息指出它。
  - 检：test `TestAggregateRejectsARelayThatIsNotALink`
- **D7** 中继角色的配置能通过 libbox 校验；生成的 key 是 16 字节随机数的带填充标准 base64；无填充、URL 安全、长度不对、空的 key 与端口 0 被拒绝，端口 1 与 65535 被接受。
  - 检：test `TestTheRelayConfigurationIsAValidShadowsocksServer`
  - 检：test `TestARelayKeyIsSixteenRandomBytesInStandardBase64`
- **D8** 回环上：按 App 组合出的出站形状（shadowsocks + `detour` 到绑定网口的 direct）经一个真实的中继能回显数据。
  - 检：test `TestARelayCarriesAConnectionForTheOutboundTheAppComposes`
- **D9** 服务端生成的导入链接符合 `docs/research/relay-link.md`（保留字符全部百分号编码，字段不多不少）；`-generate-key` 只在文件不存在时生成、权限 0600；`-link` 缺 `-host` 时报错；key 不出现在错误信息里；未知角色被拒绝。
  - 检：test `TestTheRelayLinkRoundTripsItsFields`
  - 检：test `TestRelayModeGeneratesAKeyOnceAndPrintsTheLink`
- **D10** App 按 v1 解析中继链接：字段、缺省名、`+` 不当空格；不认识的版本与加密方式、缺字段、重复字段、坏端口、坏 key 各有明确的错误；多行粘贴逐行解析，坏的那一行报出行号。
  - 检：test `relayLinksParseByTheV1Spec`
  - 检：test `severalRelayLinksPasteAtOnce`
- **D11** 中继线路的 key 只进 SecretStore，不落进 UserDefaults；重启后列表、承载线路与名字都在；同一主机与端口再次添加是替换；删除时一并删 key；数量到上限后拒绝新增（0、1、上限、上限 + 1）。
  - 检：test `aRelayStoreKeepsKeysOutOfDefaultsAndSurvivesAReload`
  - 检：test `aRelayStoreStopsAtItsLimit`
- **D12** 组合：每条可用的中继线路是一个 shadowsocks 出站，`detour` 指向承载线路的线路出站，不指向聚合出站；它的 tag 按调用方给的优先级列进每个聚合出站的 `links`，并列进 `relays`；承载线路不在启用线路里、或没有对应描述的中继被整条去掉（包括从 `backup` 里）；一条物理线路加一条中继就能聚合，可用线路不足两条时配置原样返回；中继永远不是叠加的线路段，只有一条物理线路时叠加退回主备。
  - 检：test `aRelayIsALinkNamedAfterItsHost`
  - 检：test `relaysJoinEveryAggregateAndDialThroughTheirCarrier`
  - 检：test `aRelayWithoutItsCarrierIsLeftOut`
  - 检：test `onePhysicalLinkAndARelayAreEnoughToAggregate`
  - 检：test `relaysAreNeverLegsOfTheBond`
- **D13** INV-5 扩充。
  - 检：property `composingWithRelaysKeepsEveryTagAndNeverLoops`
- **D14** 速率归属：中继线路的速率取内核的计数；承载线路显示网口速率减去它承载的中继，不为负；物理线路仍用网口速率。
  - 检：test `relayRatesComeFromTheCoreAndLeaveTheCarrier`
- **D15** 带中继的组合结果固化成夹具，libbox（聚合与 multipath 都注册时）接受它，组合器持续产出同一份。
  - 检：test `TestTheComposedRelayProfilePassesLibboxCheckConfig`
  - 检：test `composedRelayFixtureMatchesTheGenerator`
- **D16** `install.sh --relay` 语法与 shellcheck 通过，服务端可交叉编译。
  - 检：cmd `scripts/build-server.sh`
- **D17** 计数：Go 596、Swift 147 只因本卡的新测试增加；gate 全绿。
  - 检：cmd `keel gate`
- **D18** 不弱化既有测试。
  - 检：cmd `keel assert-guard --card docs/tasks/feat-relay-links.md`
- **D19** 作者手测（真实节点）：在至少两台节点上 `install.sh --relay`，把链接粘进线路页；选分流、开多线程下载，合计速率超过单台设备的配额；停掉一台节点的服务，2 秒内它显示「不可用」，新连接不再分给它；NAS、打印机这类局域网设备照常访问。
  - 检：author `docs/MANUAL-TEST.md` 3.4–3.6
- **D20** 作者手测（界面）：线路页列出中继线路（名字、经哪条线路、速率、状态），能添加、停用、移除；面板与概览的流向图里有它们。
  - 检：author `docs/MANUAL-TEST.md` 3.4

- **D21** 引用了导入链接的日志或错误信息里看不到 key（中继链接的 `key`、聚合服务器链接的 `psk`）。
  - 检：test `TestARelayImportLinkLosesItsKey`
- **D22** 承载线路是按调用方给的顺序、第一个绑定后能连上中继主机端口的网口；网口不存在、端口没人监听、列表为空时没有结果；主机名先解析。缺 key、没有承载线路、承载线路未启用各有明确的原因，缺 key 优先。
  - 检：test `theCarrierIsTheFirstInterfaceThatReachesTheRelay`
  - 检：test `aRelayIsBlockedWithoutItsKeyOrItsCarrier`
- **D23** 选了叠加但只有一条物理线路时，提示说的是「叠加需要两条物理线路」，不是「尚未设置聚合服务器」。
  - 检：test `bondOverOnePhysicalLinkSaysWhyItRunsAsFailover`
- **D24** 同一个内核实例里，挂着同一批线路出站的聚合出站共用每条线路的一个探测器和它的健康状态；另一个实例里同名的线路出站有自己的探测器；最后一个使用者关闭后探测器停止，重复关闭只释放一次。
  - 检：test `TestAggregatesOverTheSameLinksShareOneProberPerLink`
- **D25** 经中继线路的 UDP 在 sing 的包路径（`ReadPacket` / `WritePacket`）上同样计数。
  - 检：test `TestRelayPacketsAreCountedOnSingsPacketPath`
- **D26** 调用方自己的超时或取消不算中继线路的证据：不标记，也不再试后面的线路；同样的错误在调用方还活着时照常算中继线路的故障。
  - 检：test `TestACallersExpiredDeadlineDoesNotMarkRelaysDown`

## 设计

**中继是一条线路，不是一种新机制。** 聚合出站的 `links` 本来就是出站 tag（决策 13），所以中继线路就是另一种出站：`shadowsocks` 加 `detour`。选线、主备、仅备用、计数、健康、流向图都沿用线路已有的那一套；界面上它是 `LinkKind.relay` 的一个 `LinkInterface`。否决：给中继单独做一个「中继组」出站再和线路并列——两套选线逻辑、两套健康状态，而 D 要的恰好是「和 Mac 自己的出口一起轮转」。

**内核只需要知道哪些线路是中继（`relays`），因为它们有三处和物理线路不同：**
1. 不能承载局域网目标：中继主机在另一台机器上，够不着 Mac 这边 Wi‑Fi 网段里的打印机；而且经代理协议拨号时目标不可达不会报成拨号错误，没有重试的机会。判定沿用 feat-bond-direct 的 `local.go`，拆成 `localDestination`，不写第二份。
2. 拨号错误的含义相反：物理线路上 `ECONNREFUSED` 是目标的回答；中继线路上拨号只到中继主机为止，任何错误都是这条线路的问题。
3. 健康要往返：见环境假设第二条。探测向 53 端口的目标发一条 DNS 查询（根的 NS），读到任何回答即可；不解析内容。否决「读到 EOF 才算坏」：上游超时类的故障要等很久才 EOF，会误判健康。

**每条线路一个探测器，聚合出站共用（重构，`probers.go`）。** 组合后的配置里有好几个聚合出站挂着同一批线路（每个用户 direct 一个，加上 `parallux-links`），原来各自探测，同一个问题每秒问几遍；中继线路的每次探测又是一次经中继主机的 DNS 往返，线路数乘以聚合出站数。现在按线路出站对象共享探测器：探测量减到每条线路每秒一次，一个聚合出站看到的拨号失败也成了其他聚合出站的证据。键是出站对象而不是 tag，重载后的新实例不会接到旧实例的探测器。判据、间隔与目标都没动。已知代价：6 条中继线路就是每秒 6 次经办公网出口到 `223.5.5.5` 的 DNS 查询，这是 2 秒内发现故障的价钱；公共 DNS 是否对这个频率限速没有核实，手测时留意中继线路有没有无故闪「不可用」。

**只有中继线路包一层 UDP 计数。** 物理线路的速率在界面上取自网口计数器，它看得到全部字节；给它们的包连接加包装会丢掉 sing 的快路径，却得不到新信息。中继线路的字节混在承载线路的网口里，内核的计数是唯一来源，所以承载线路显示时要减掉它们（`RelayRates.merge`）。

**转发协议：sing-box 自带的 shadowsocks 2022。** PLAN §2 不自己实现协议。办公网是共享网络，转发服务必须认证，否则谁都能用这台机器当跳板：排除无认证的 socks/http；socks 的用户名密码是明文。vless/trojan/anytls 要证书。shadowsocks 2022 一个 key 即可，带认证与防重放，TCP 与 UDP 都转；代价是要求两端时钟相差不超过 30 秒，以及对已加密的代理流量再加密一次（AES-GCM 有硬件加速，单节点 20–30 Mbps 的量级下可忽略）。社区先例：没有找到（调研笔记）。

**承载线路由 App 探测，不写进链接。** 链接由节点上的安装脚本生成，它不知道 Mac 的网口名；网口名也会变（USB 网卡重插）。App 在添加时和线路变化时，逐条物理线路绑定网口去连中继主机的端口，第一条连通的就是承载线路。承载线路被停用时，经它的中继一并停用，而不是悄悄保留一个出站：线路页上「关掉有线」的意思应该是这个网口上不再有流量。

**叠加不用中继。** multipath 恰好两条线路段（feat-bond）。组合器保证线路段只取物理线路；只有一条物理线路时叠加退回主备。把中继当线路段（B 与 D 相乘）要先有 N 线路段的传输，见调研笔记结论 5。

**安装：一个二进制，两种角色。** `parallux-server -role relay`；key 的生成和链接的拼装都在 Go 里（可测），install.sh 只负责装服务。中继用独立的 unit（`parallux-relay.service`）和独立的 key 文件，同一台机器可以两种角色都装。中继主机通常是内网地址，所以 `--relay` 不做「地址必须是公网」的检查。

## 验证命令

```bash
go test ./core/aggregate/ -run 'Relay|LocalD' -count=1
go test ./server/... -count=1
scripts/swift-test.sh /tmp/relay.xml Relay
keel verify-red docs/tasks/feat-relay-links.md
keel gate --record docs/tasks/feat-relay-links.md
```

## 证据

RED: bab583a -run ^TestRelayLinksNeverCarryLocalDestinations$ ./core/aggregate/  # D1
RED: bab583a -run ^TestALocalDestinationWithOnlyRelaysFailsWithoutDialing$ ./core/aggregate/  # D1
RED: bab583a -run ^TestLocalDialOrderDropsOnlyRelaysAndKeepsTheRest$ ./core/aggregate/  # D2
RED: bab583a -run ^TestARelayThatRefusesIsSkippedAndMarkedDown$ ./core/aggregate/  # D3
RED: bab583a -run ^TestARelayIsHealthyOnlyWhenARoundTripComesBack$ ./core/aggregate/  # D4
RED: bab583a -run ^TestRelayPacketsAreCounted$ ./core/aggregate/  # D5
RED: bab583a -run ^TestAggregateRejectsARelayThatIsNotALink$ ./core/aggregate/  # D6
RED: bab583a -run ^TestTheRelayConfigurationIsAValidShadowsocksServer$ ./server/cmd/parallux-server/  # D7
RED: bab583a -run ^TestARelayKeyIsSixteenRandomBytesInStandardBase64$ ./server/cmd/parallux-server/  # D7
RED: bab583a -run ^TestARelayCarriesAConnectionForTheOutboundTheAppComposes$ ./server/cmd/parallux-server/  # D8
RED: bab583a -run ^TestTheRelayLinkRoundTripsItsFields$ ./server/cmd/parallux-server/  # D9
RED: bab583a -run ^TestRelayModeGeneratesAKeyOnceAndPrintsTheLink$ ./server/cmd/parallux-server/  # D9
RED(swift): bab583a relayLinksParseByTheV1Spec  # D10
RED(swift): bab583a severalRelayLinksPasteAtOnce  # D10
RED(swift): bab583a aRelayStoreKeepsKeysOutOfDefaultsAndSurvivesAReload  # D11
RED(swift): bab583a aRelayStoreStopsAtItsLimit  # D11
RED(swift): bab583a aRelayIsALinkNamedAfterItsHost  # D12
RED(swift): bab583a relaysJoinEveryAggregateAndDialThroughTheirCarrier  # D12
RED(swift): bab583a aRelayWithoutItsCarrierIsLeftOut  # D12
RED(swift): bab583a onePhysicalLinkAndARelayAreEnoughToAggregate  # D12
RED(swift): bab583a relaysAreNeverLegsOfTheBond  # D12
RED(swift): bab583a composingWithRelaysKeepsEveryTagAndNeverLoops  # D13
RED(swift): bab583a relayRatesComeFromTheCoreAndLeaveTheCarrier  # D14

D8 的测试在收尾时加了两段（经真实中继拨主机名、UDP 回显），冻结点上的 RED 仍然覆盖它。D15、D21–D26 是冻结之后加的，冻结点上没有对应的测试，用故障补丁证明这些测试抓得住它们声称的东西：

```diff keel-inject -run ^TestTheComposedRelayProfilePassesLibboxCheckConfig$ ./core/pxbridge/
--- a/core/aggregate/register.go
+++ b/core/aggregate/register.go
@@ -50 +50 @@
-	Relays []string `json:"relays,omitempty"`
+	Relays []string `json:"relayz,omitempty"`
```

```diff keel-inject(swift) composedRelayFixtureMatchesTheGenerator
--- a/apple/ParalluxKit/Sources/ParalluxKit/Links/ProfileComposer.swift
+++ b/apple/ParalluxKit/Sources/ParalluxKit/Links/ProfileComposer.swift
@@ -130 +130 @@
-            if !relayTags.isEmpty { outbound["relays"] = relayTags }
+            if relayTags.count > 99 { outbound["relays"] = relayTags }
```

```diff keel-inject -run ^TestARelayImportLinkLosesItsKey$ ./core/internal/redact/
--- a/core/internal/redact/redact.go
+++ b/core/internal/redact/redact.go
@@ -73 +73 @@
-var urlInText = regexp.MustCompile(`(?:https?|parallux)://[^\s"'<>]+`)
+var urlInText = regexp.MustCompile(`(?:https?)://[^\s"'<>]+`)
```

```diff keel-inject(swift) theCarrierIsTheFirstInterfaceThatReachesTheRelay
--- a/apple/ParalluxKit/Sources/ParalluxKit/Relay/RelayCarrier.swift
+++ b/apple/ParalluxKit/Sources/ParalluxKit/Relay/RelayCarrier.swift
@@ -21 +21 @@
-        let addresses = ipv4Addresses(of: host)
+        let addresses: [String] = ipv4Addresses(of: host).filter { _ in false }
```

```diff keel-inject(swift) aRelayIsBlockedWithoutItsKeyOrItsCarrier
--- a/apple/ParalluxKit/Sources/ParalluxKit/Relay/RelayCarrier.swift
+++ b/apple/ParalluxKit/Sources/ParalluxKit/Relay/RelayCarrier.swift
@@ -64 +64 @@
-        guard hasKey else { return .noKey }
+        guard hasKey || carrier != nil else { return .noKey }
```

```diff keel-inject(swift) bondOverOnePhysicalLinkSaysWhyItRunsAsFailover
--- a/apple/ParalluxKit/Sources/ParalluxKit/Interface/ConnectionSwitches.swift
+++ b/apple/ParalluxKit/Sources/ParalluxKit/Interface/ConnectionSwitches.swift
@@ -52 +52 @@
-        if physicalLinks < 2 { return "叠加需要两条物理线路，中继线路不能叠加，暂按主备运行" }
+        if physicalLinks < 0 { return "叠加需要两条物理线路，中继线路不能叠加，暂按主备运行" }
```

```diff keel-inject -run ^TestAggregatesOverTheSameLinksShareOneProberPerLink$ ./core/aggregate/
--- a/core/aggregate/probers.go
+++ b/core/aggregate/probers.go
@@ -55 +55 @@
-	prober := probers[key]
+	prober := (*sharedProber)(nil)
```

```diff keel-inject -run ^TestRelayPacketsAreCountedOnSingsPacketPath$ ./core/aggregate/
--- a/core/aggregate/stats.go
+++ b/core/aggregate/stats.go
@@ -117 +117 @@
-		c.counters.upload.Add(int64(n))
+		c.counters.upload.Add(int64(n) * 0)
```

```diff keel-inject -run ^TestACallersExpiredDeadlineDoesNotMarkRelaysDown$ ./core/aggregate/
--- a/core/aggregate/register.go
+++ b/core/aggregate/register.go
@@ -299 +299 @@
-		if ctx.Err() != nil {
+		if ctx.Err() != nil && index < 0 {
```

探测在取消时立刻结束（D4 的测试里新增的一段）：

```diff keel-inject -run ^TestARelayIsHealthyOnlyWhenARoundTripComesBack$ ./core/aggregate/
--- a/core/aggregate/health.go
+++ b/core/aggregate/health.go
@@ -133 +133 @@
-	stop := context.AfterFunc(ctx, func() { conn.Close() })
+	stop := context.AfterFunc(ctx, func() {})
```

失败断言原文（RED 时，桩实现下）：

- `the relay carried 0 TCP and 12 UDP local destinations, want none`
- `a local destination was dialed although every link is a relay`
- `local order of [1 0] with relays [false true] = [1 0], want [0]`
- `dial with a refusing relay: dial tcp: connection refused, want the next link to carry it`
- `a relay whose upstream closes at once was probed healthy`
- `relay counters = up 0, down 0, active 0; want 5, 5, 1`
- `relay outside links = <nil>, want an error naming link-relay-z`
- `RelayLink() = "", want parallux://relay?…`
- `Expectation failed: one.linkName == "relay-11111111"`
- `Expectation failed: merged["link-relay-a"] == rate(10, 300)`

实机对拍（2026-11-20，临时测试，未入库，需要外网）：一个 sing-box 实例里，聚合出站（分流）下挂一条绑定默认路由网口的线路出站和一条经回环上真实中继的中继线路，向 `1.1.1.1:80` 发 4 个请求。结果：两条线路各承载 2 个连接（下行各 788 字节）；两轮探测之后中继线路仍判健康，即经真实 shadowsocks 中继的 DNS 往返在协议上成立。局限：当时默认路由在 `utun4`（另一个 VPN），所以「物理线路」那一条绑的是隧道网口，流量也没有经过办公网出口；它证明的是选线、计数与往返探测在真实协议栈上能跑通，不是办公网里的可达性。
GATE: 4f64d70cc80a+dirty ok tree:3928a97a1833 build=0 vet=0 test=0[613p/0f] fmt=0 swift-test=0[162p/0f] apple-build=0 server-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-20)

## 修订

- 测试修正（不改判据）：`TestTheRelayLinkRoundTripsItsFields` 原先断言查询串里不含 `=`，而 `v=1` 本身就有，这是测试写错了。改为：查询串不含 `+`、`/`、空格，并且按值断言 key 的百分号编码形式。D9 的文字未动。
- D21–D26 是实现过程中新增的判据（只加严）：D21 来自检查脱敏时发现 `Text` 只认 http(s) 链接；D22、D23 随承载线路探测与提示文案一起加；D24 是把探测器改成按线路共享（见设计）；D25 补上路由器实际走的包路径；D26 来自收尾审查（调用方超时会把中继线路挨个标成不健康）。
- 作者确认 2026-11-20（对「我替你定的，请确认」四项的答复：「可以，全都按你说的来做吧」）：中继协议用 shadowsocks 2022；新增 `relays` 配置字段与导入链接格式 v1；中继线路上限 16 条；范围外的脱敏改动（D21）。D19、D20 的手测不在这次确认里。
- 合并进 main（2026-11-20，作者要求）：main 上的 `fix-overview-layout-and-flow` 已经用了 INV-12，本卡的不变量改号为 INV-14（`docs/INVARIANTS.md`、`relay.go` 与测试里的注释同步）。D2 的原文「INV-12」按冻结规则没有改，它指的就是现在的 INV-14。同一次合并里，`probeOnce` 与 `fix-probe-lost-syn` 的并行拨号加重试合成了一个函数：中继线路的往返算在「拨号是否完成」里，所以往返卡住和连接卡住一样会重试一次。
- 收尾审查后的两处修正：探测的往返在取消时立刻结束（原来要等满探测超时，停止或重载内核时每条不回答的中继线路多等约 1 秒）；`TestARelayCarriesAConnectionForTheOutboundTheAppComposes` 加了主机名目标与 UDP 回显（原来只拨过 IP 字面量，而节点的 `server` 是以主机名到达中继的）。

## 交接

- 做了什么：方案 D 全部实现。内核 `core/aggregate/relay.go`（中继不承载局域网目标、拨号错误归线路、往返健康检查、UDP 计数）与 `probers.go`（每条线路一个探测器，聚合出站共用）；`parallux-server -role relay` 与 `install.sh --relay`；ParalluxKit `Relay/`（链接解析、存储、承载线路探测、速率归属）与组合器；线路页添加与删除中继线路，面板、右键菜单、流向图、诊断测速都列出它们。顺带修了导入链接在日志里不脱敏的问题（D21）。调研结论在 `docs/research/bond-without-vps-2026-11-20.md`。
- 卡在哪：没有在签名构建和真实节点上跑过（D19、D20）。两个未证实的前提：「扩展里绑定承载线路网口的 socket 能到中继主机」（与 `research-sysext-bind-interface` 是同一个）；办公网出口放行节点到 `223.5.5.5` 的 TCP 53（不放行则中继线路永远「不可用」，要换探测目标）。承载线路探测只支持 IPv4（IPv6 地址的中继主机会显示无承载线路）。分支 `feat/relay-links` 在独立 worktree 里，基于 `348886f`（含 feat-bond-direct），未合并。
- 下一步：作者按 `docs/MANUAL-TEST.md` 3.4–3.6 手测；确认决策 24 的协议选型；决定调研笔记结论 3–5（节点自带聚合、托管聚合服务器、N 线路段）要不要做。
