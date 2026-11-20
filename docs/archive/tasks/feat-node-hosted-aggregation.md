---
type: feat
status: awaiting-author        # todo | doing | blocked | awaiting-author | done
weight: full
created: 2026-11-20
baseline: 07170123a2a2
---

# 聚合服务器装在代理节点的机器上也能用，同机节点的连接照样叠加

## 来源

作者 2026-11-20：三项待定里选了第一项「节点自带聚合」（代理节点是自己的机器时，把聚合服务器装在节点上，不必另备 VPS），并要求先看竞品、避开边界问题。调研与对拍在 `docs/research/node-hosted-aggregation-2026-11-20.md`，决策 25。

这不是纯新功能：对拍发现现状里同机部署有两处是坏的，都是一直就有的（`feat-bond`、`feat-bond-direct` 起）。
- 聚合服务器到达同机节点只能拨自己的公网地址；这条路不通时客户端不回退，节点整个断。
- 节点带 `domain_resolver`、链接里写 IP 时，节点的连接被「不把去聚合服务器的连接送进叠加」的排除挡在叠加之外。

## 范围

- **独占：** `server/cmd/parallux-server/self.go` 及其测试；`server/cmd/parallux-server/main.go` 的 `Config`；`server/install.sh` 的聚合服务器部分；`docs/research/node-hosted-aggregation-2026-11-20.md`。
- **新增检查：** `scripts/test-install.sh`（由 `scripts/build-server.sh` 调用，即 gate 的 server-build 步）。
- **接缝：** `ProfileComposer.swift` 给节点用的聚合出站写不写 `bond_bypass`（作者 2026-11-20 确认后改的）；聚合服务器页的说明文字；`docs/research/aggregation-server-link.md`、`docs/MANUAL-TEST.md` 第 4 节。
- **不碰：** multipath 协议；`core/aggregate` 的拨号与 `bond_bypass` 字段本身；中继角色；链接格式 v1；直连流量用的聚合出站的排除规则。

## 观测面

- 真实的三个 sing-box 实例跑在回环上：客户端（节点出站 → 聚合出站 → multipath）、`Config` 生成的聚合服务器、一个 shadowsocks 入站充当同机节点；看回显是否回来、聚合出站的逐线路计数是否为零。
- 计数的回环监听器：服务器替客户端连了环回，它的接受数就不是零。
- 纯逻辑 `selfDelivery.DialContext`：注入拨号函数，记录拨了哪些地址、按什么顺序。
- `Config` 输出的 JSON：路由规则的顺序与内容，交给 `libbox.CheckConfig`。
- GREEN 可能被截断的方式与挡法：
  - 节点地址若是本机或局域网地址，客户端的聚合出站本来就不送进叠加，测试会空过：节点的 `server` 用 TEST-NET-2 地址（`198.51.100.7`），既不可路由也不是本地目标。
  - 叠加拨号在服务器动手之前就报成功：所有判定都以回显读回来为准，不以拨号成功为准。
  - 「拒绝环回」若只看读失败，分不清是被拒还是端口没人听：监听器真的在听，并数接受数。
  - 拒绝规则若排在本机投递后面，会把同机节点一起拒掉：同一个测试里，同一个监听器经公网地址必须能通。

## 环境假设

对拍结果见调研笔记「本机对拍」四条，都已固化成本卡的测试。另外：

- sing-box 1.14.4 的路由动作 `resolve`、`reject` 与规则项 `ip_is_private`、`ip_cidr`、`domain` 对 multipath 入站交给路由器的连接生效（回环对拍，四种规则组合）。
- 路由器解析出地址后，对不实现并行拨号接口的出站逐个地址调用 `DialContext`（`route/conn.go` 的 `DialSerialNetwork`），所以本机投递的出站收到的是 IP。
- **未证实，留给作者在真实 VPS 上测（D12）：** 公网 IP 不在网卡上的云主机里，连「本机发包用的地址:节点端口」能到节点。依据是这类云把公网地址 1:1 映射到那个私网地址；节点若只监听别的地址，本机投递会被拒绝，随后按原地址拨（与现状相同）。
- **未证实：** 各家云上虚拟机能否连自己的公网 IP（调研笔记）。本卡的设计不依赖它，它只决定回退那一步有没有用。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** 同机节点的整条链路在回环上走通：节点出站的 `server` 是这台机器的公网地址，经节点用的聚合出站（叠加、不带排除）、multipath、`Config` 生成的聚合服务器，到同一台机器上的节点入站，数据回显回来；聚合出站的逐线路计数为零（没有绕开叠加）。
  - 检：test `TestANodeOnTheAggregationServersOwnMachineIsReachedThroughTheBond`
- **D2** 聚合服务器不替客户端连环回或私网目标：`127.0.0.1`、IPv4 映射的 IPv6 写法、解析到环回的名字、`127.0.0.0/8` 里的其他地址、`0.0.0.0` 都到不了一个正在监听的环回端口；同一个端口经这台机器的公网地址能到。
  - 检：test `TestTheServerNeverDialsLoopbackOrPrivateDestinationsForAClient`
- **D3** 配置里路由规则的顺序是契约：先解析名字，再拒绝私网（`ip_is_private`）与 `100.64.0.0/10`，最后才是本机投递（地址与名字各一条）；没有 `-self` 时只剩解析与两条拒绝；带端口、带空格、空的、带协议头的 `-self` 条目与不是地址的 `-self-target` 被拒绝；条目数到上限可以、超过上限被拒绝；两种配置都能通过 libbox 校验。
  - 检：test `TestTheServerConfigurationRefusesPrivateDestinationsBeforeDeliveringToItself`
- **D4** 本机投递的拨号顺序：先连本机发包用的地址（或指定的 `-self-target`），没人监听再按原地址拨；公网地址就在网卡上时只拨一次；不知道源地址时按原地址拨；两次都失败时返回按原地址拨的错误；IPv6 同理；没被解析的名字只有在指定了目标时才先试本机。
  - 检：test `TestSelfDeliveryTriesTheLocalAddressFirstAndFallsBackToTheAddressGiven`
- **D5** 本机投递绝不连聚合服务器自己的监听端口：直接报错，一次都不拨。
  - 检：test `TestSelfDeliveryNeverDialsTheServersOwnListener`
- **D6** 本机那一次尝试有上限（挂住时不超过约 `localDeliveryTimeout`，之后按原地址拨）；调用方取消后不再拨第二次。
  - 检：test `TestSelfDeliveryBoundsTheLocalAttemptAndRespectsTheCaller`
- **D7** `-self` 里的名字在启动时解析一次，解析到的地址也算这台机器：名字保留，新地址去重后追加（IPv4 映射写法按 IPv4 算），解析失败不改变什么，总数不超过上限。
  - 检：test `TestSelfNamesAlsoCoverTheAddressesTheyResolveTo`
- **D8** `-self` 与 `-self-target` 从命令行进到配置；坏条目的报错指出是哪一条。
  - 检：test `TestTheSelfFlagsReachTheConfiguration`
- **D9** `install.sh` 的聚合服务器部分：服务从命令行参数启动（与 `Config` 是同一处构造，不再另写一份 JSON），带 `-self`；psk 只存在 `/etc/parallux-server/psk`（0600），旧安装里 `config.json` 中的 psk 被沿用并迁走；语法与 shellcheck 通过，服务端可交叉编译。
  - 检：cmd `scripts/build-server.sh`
  - 检：grep `ExecStart=\$BIN -port \$PORT -psk-file \$PSK_FILE -self` in `server/install.sh`
- **D10** 计数：Go 613、Swift 162 只因本卡的新测试增加；gate 全绿。
  - 检：cmd `keel gate`
- **D11** 不弱化既有测试（作者确认的改动除外，见修订）。
  - 检：cmd `keel assert-guard --card docs/tasks/feat-node-hosted-aggregation.md`
- **D12** 作者手测（真实 VPS，最好是公网 IP 不在网卡上的云主机）：在自己的节点机器上装聚合服务器；选叠加，经这个节点的单线程下载比最快单线路快；节点机器上只听 127.0.0.1 的面板经叠加访问不到；此前装过的聚合服务器重跑一次 `install.sh`。
  - 检：author `docs/MANUAL-TEST.md` 4.5–4.7
- **D13** 组合：叠加时，节点用的聚合出站（`parallux-links`）不带 `bond_bypass`，无论节点的 `server` 写的是聚合服务器的地址、别的名字还是 IPv6；节点照样 `detour` 到它；直连流量用的聚合出站仍然排除聚合服务器地址；分流与主备下两者都没有排除。
  - 检：test `aNodeOnTheAggregationServersMachineDetoursThroughABondWithoutBypass`
- **D14** `install.sh` 在临时根目录里真的跑通七种情形：全新安装（密钥文件 0600、43 个字符，unit 从参数启动并带 `-self`，密钥不在 unit 里，链接里的密钥与文件一致且只打印一次）、重装沿用密钥、`--new-psk` 更换、旧安装的密钥从 `config.json` 迁到密钥文件且旧文件删除、私网源地址要求 `--host` 且 `--host` 的值进 `-self`、带 shell 字符的 `--host` 被脚本自己拒绝、端口被别的程序占用时拒绝而自己的服务占用时放行、中继角色。
  - 检：cmd `scripts/test-install.sh`
- **D15** 真实套接字上：sing-box 建出来的本机投递出站，用它真实的拨号器，把去公网地址的连接送到本机地址上一个真的在听的端口；它不提供包连接；不是地址的目标被拒绝。内核报出的源地址确实是本机的地址，本机地址的源地址是它自己。
  - 检：test `TestTheSelfOutboundDeliversOverRealSockets`
  - 检：test `TestTheSourceAddressIsOneOfThisMachinesOwn`
- **D16** 作者知情并接受本机投递的边界：节点机器上监听所有网卡、安全组不放行的端口，Mac 开着叠加时经公网地址打得开，关掉叠加打不开。
  - 检：author `docs/MANUAL-TEST.md` 4.8

## 设计

**服务端认得自己，先在本机投递，不通再照旧。** 做成一个出站（`parallux-self`），路由规则把「目标是这台机器」的连接交给它。它先连本机发包用的地址上的同一个端口，被拒绝或在 `localDeliveryTimeout` 内没连上，就按原地址拨。

否决的做法：
- 只靠服务器拨自己的公网地址（现状）：通不通取决于云，不通时客户端不回退（对拍 1）。
- 用路由动作直接改写地址（`route-options` 的 `override_address`）：不能回退。链接里的地址是转发机、端口对不上、或节点只监听别的地址时，改写之后就是死路，而且同样不回退到客户端的线路。先试再回退在本机那个端口没人监听时与现状相同（例外见下面的已知限制）。
- 投递到 `127.0.0.1`：会让只听环回的服务（面板、API）对持有密钥的人敞开。连网卡上的地址就够不着它们（调研结论 4）。`-self-target` 留给节点只监听特殊地址的机器，由装的人自己负责。

**本机投递挡不住的东西（已知，如实写）。** 这台机器连自己网卡上的地址，包走的是环回接口：主机防火墙通常放行环回接口，云的安全组根本看不到它。所以监听在 `0.0.0.0`（或网卡地址）上、只靠防火墙或安全组对外关闭的服务，持有密钥的人经聚合服务器是连得上的。这不是本卡带来的：公网 IP 就在网卡上的机器，改动之前也一样（内核直接本机投递）；本卡只是让公网 IP 不在网卡上的云主机也变成这样。挡得住的是三样：只听环回的服务、私网、元数据地址。面板开在所有网卡上、靠安全组挡的机器，要么把面板改成只听 127.0.0.1，要么别把聚合服务器的密钥给别人。

**先试本机不总是无害（已知限制）。** 链接里的地址是一台转发机、而这台机器恰好在同一个端口号上有别的服务时，去「转发机:那个端口」的连接会被本机的服务接走，而不是转发机后面真正的目标。`install.sh` 总是带 `-self`，现在没有关掉的办法；遇到了再加开关。
- 让用户逐个登记「公网地址:端口 → 本机端口」：最精确，但每加一个节点都要重装一次，而且客户端送来的是名字还是 IP 取决于节点配置，两种都得登记。

**默认拒绝私网目标，排在本机投递之前。** 客户端本来就不把本地目标送进叠加（`core/aggregate` 的 `localDestination`），所以服务端合法收到的目标都是公网的；拒绝的是持有密钥的人（或泄露的链接）拿这台机器当跳板。`ip_is_private` 不含 100.64/10，另加一条。名字先解析，解析到私网地址的名字同样被拒。没有做「放行私网」的开关：现在没有人需要，要用的时候再加比现在留一个默认关着的口子安全。

**不连自己的监听端口。** 目标是自己、端口又是 multipath 的监听端口，只可能是环路（engarde 的 README 专门警告过同类问题）。

**服务从参数启动。** `install.sh` 原来用 heredoc 另写一份 JSON，和 `Config` 是两处构造；路由规则只能有一份。psk 改为只放在文件里，`aggregation-server-link.md` 本来就是这么写的。

**客户端：节点用的聚合出站不带排除（作者 2026-11-20 选定）。** 见调研结论 2。节点用的聚合出站（`parallux-links`）只做节点的 `detour`，它见到的目标都是节点的服务器地址；其中等于聚合服务器地址的，按定义就是同机节点，正是要叠加的。所以这个出站上的排除只在出错的时候才起作用。直连流量用的聚合出站不动。这改了 `feat-bond-direct` D3 钉住的一条断言。向作者列了三种改法（只改节点用的、两处都去掉、先不改客户端），作者选了第一种。

**安装脚本有了功能测试。** 这次它要把旧安装的密钥从 `config.json` 迁出来，迁错了用户手里的链接就废了，而它此前只有语法检查。`scripts/test-install.sh` 用假的 `systemctl`、`ip`、`ss`、`id` 把脚本真的跑进临时目录，二进制是为本机编出来的真货。加这个检查时先故意改坏了脚本六处（不迁旧密钥、unit 不带 `-self`、不查端口、不删旧配置、不查 `--host`、密钥文件权限 0644），确认每一处都会让它变红；其中「不查 `--host`」第一次没有红（二进制的校验替它兜住了），把断言收紧到脚本自己的报错之后才红。

WEAKEN-OK: apple/ParalluxKit/Tests/ParalluxKitTests/LinkCompositionTests.swift 节点用的聚合出站不再排除聚合服务器地址，`bondModeCarriesDirectTrafficToo` 里对 parallux-links 的断言随之反转，对 direct 的断言不变（作者确认 2026-11-20）

**上限：** `maxSelf` 16 条（一台机器的公网身份：几个地址加一两个名字；名字解析出的地址也算在内）。`localDeliveryTimeout` 1 秒（本机连接要么几毫秒连上，要么立刻被拒；只有防火墙丢包才会挂住）。两个都是假设值。

## 验证命令

```bash
go test ./server/... -count=1
scripts/build-server.sh
keel verify-red docs/tasks/feat-node-hosted-aggregation.md
keel gate --record docs/tasks/feat-node-hosted-aggregation.md
```

## 证据

RED: 455be48 -run ^TestANodeOnTheAggregationServersOwnMachineIsReachedThroughTheBond$ ./server/cmd/parallux-server/  # D1
RED: 455be48 -run ^TestTheServerNeverDialsLoopbackOrPrivateDestinationsForAClient$ ./server/cmd/parallux-server/  # D2
RED: 455be48 -run ^TestTheServerConfigurationRefusesPrivateDestinationsBeforeDeliveringToItself$ ./server/cmd/parallux-server/  # D3
RED: 455be48 -run ^TestSelfDeliveryTriesTheLocalAddressFirstAndFallsBackToTheAddressGiven$ ./server/cmd/parallux-server/  # D4
RED: 455be48 -run ^TestSelfDeliveryNeverDialsTheServersOwnListener$ ./server/cmd/parallux-server/  # D5
RED: 455be48 -run ^TestSelfDeliveryBoundsTheLocalAttemptAndRespectsTheCaller$ ./server/cmd/parallux-server/  # D6
RED: 455be48 -run ^TestSelfNamesAlsoCoverTheAddressesTheyResolveTo$ ./server/cmd/parallux-server/  # D7
RED: 455be48 -run ^TestTheSelfFlagsReachTheConfiguration$ ./server/cmd/parallux-server/  # D8

D13 是作者答复之后加的，冻结点上没有它的测试，用故障补丁证明：让节点用的聚合出站重新带上排除，测试必须红。

```diff keel-inject(swift) aNodeOnTheAggregationServersMachineDetoursThroughABondWithoutBypass
--- a/apple/ParalluxKit/Sources/ParalluxKit/Links/ProfileComposer.swift
+++ b/apple/ParalluxKit/Sources/ParalluxKit/Links/ProfileComposer.swift
@@ -165 +165 @@
-        if !taken.contains(aggregateTag) { added.append(aggregate(tag: aggregateTag, carriesBond: true, bypassesServer: false)) }
+        if !taken.contains(aggregateTag) { added.append(aggregate(tag: aggregateTag, carriesBond: true, bypassesServer: true)) }
```

D15 也是冻结之后加的：跳过本机那一次尝试，真实套接字上的投递必须红；让源地址函数报不出地址，源地址的测试必须红。

```diff keel-inject -run ^TestTheSelfOutboundDeliversOverRealSockets$ ./server/cmd/parallux-server/
--- a/server/cmd/parallux-server/self.go
+++ b/server/cmd/parallux-server/self.go
@@ -84 +84 @@
-	if local, ok := s.local(destination); ok {
+	if local, ok := s.local(destination); ok && destination.Port == 0 {
```

```diff keel-inject -run ^TestTheSourceAddressIsOneOfThisMachinesOwn$ ./server/cmd/parallux-server/
--- a/server/cmd/parallux-server/self.go
+++ b/server/cmd/parallux-server/self.go
@@ -135 +135 @@
-	address, ok := netip.AddrFromSlice(local.IP)
+	address, ok := netip.AddrFromSlice(local.IP[:0])
```

D2 再用故障补丁压一次：把拒绝私网的规则换成一条无关的规则，正在监听的环回端口必须收到连接。

```diff keel-inject -run ^TestTheServerNeverDialsLoopbackOrPrivateDestinationsForAClient$ ./server/cmd/parallux-server/
--- a/server/cmd/parallux-server/main.go
+++ b/server/cmd/parallux-server/main.go
@@ -262 +262 @@
-		map[string]any{"ip_is_private": true, "action": "reject"},
+		map[string]any{"ip_cidr": []string{"192.0.2.0/24"}, "action": "reject"},
```

失败断言原文（RED 时，桩实现下）：

- `a connection through the node on the server's own machine: read tcp …: i/o timeout`
- `127.0.0.1:…: the server relayed a client to its own loopback`；`the loopback listener accepted 4 connections relayed for a client, want 0`
- `route rules = [], want 5`
- `a node listening locally is reached without leaving the machine: dialed [203.0.113.10:443], want [10.0.0.5:443]`
- `dialing the server's own listener through itself: err = <nil>, want a refusal that says so`
- `dialed [203.0.113.10:443], want the local address then the address as given`
- `expandSelf = [203.0.113.10 vps.example.com gone.example.com], want […  2001:db8::10]`
- `a -self entry with a port: err = <nil>, want it named`
GATE: 15ed93e3394f+dirty ok tree:8808326288bc build=0 vet=0 test=0[623p/0f] fmt=0 swift-test=0[163p/0f] apple-build=0 server-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-20)

## 修订

- 作者确认 2026-11-20（对「同机节点要想叠加，客户端得改一条现有规则，你选哪种改法」的答复：「只改节点用的那个」）：节点用的聚合出站不再排除聚合服务器地址。由此加了 D13，并改了 `LinkCompositionTests.bondModeCarriesDirectTrafficToo` 里对 parallux-links 的一条断言（见 WEAKEN-OK）；`core/aggregate/testdata/composed-bond.json` 用生成器重生成，diff 是 parallux-links 少了三行 `bond_bypass`。
- D13、D14、D15、D16 是冻结之后加的判据（只加严）。
- D12 里「只听 127.0.0.1 的面板经叠加访问不到」这一句手测测不出东西：Mac 从不把 127.0.0.1 送进叠加，而只听环回的端口在本机投递和按原地址拨两步上都会被拒绝，服务端做什么它都通过。真正的证据是 D2 的自动测试。这一句是我开卡时写的，没有作者确认不能删，留着；建议作者确认后删掉。
- 决策 25 里有两件事由实现提出、作者尚未单独确认：服务端默认拒绝私网目标；以及本机投递挡不住「监听在所有网卡上、只靠防火墙或安全组对外关闭」的服务（见设计）。

## 交接

- 做了什么：聚合服务器可以装在代理节点的机器上。服务端 `self.go`（本机投递：先连网卡上的本机地址，没人监听再按原地址拨；不连自己的监听端口）；`Config` 的路由规则（先解析，再拒绝环回、私网、链路本地与 100.64/10，最后本机投递）；`-self` / `-self-target`，名字在启动时解析一次；`install.sh` 改为从参数启动、密钥只放文件、旧密钥迁移、端口占用检查，并有了功能测试 `scripts/test-install.sh`。客户端：节点用的聚合出站不带排除。聚合服务器页加了一句说明。调研在 `docs/research/node-hosted-aggregation-2026-11-20.md`。
- 卡在哪：没在真实 VPS 上跑过（D12）；服务端二进制与安装脚本都只在 macOS 上跑过（安装脚本用的是假的 systemctl、ip、ss），从没在 Linux 上执行。未证实的前提：公网 IP 不在网卡上的云主机里，连「本机发包用的地址:节点端口」能到节点；到不了时会按原地址拨，与改动前相同。回环测试里本机投递的目标是用 `-self-target 127.0.0.1` 指定的，「自动取源地址」那条路只有纯逻辑测试，没有真实网卡上的测试。
- 下一步：作者按 `docs/MANUAL-TEST.md` 4.5–4.7 手测；确认「默认拒绝私网目标」。三项待定里的另外两项（由我们托管聚合服务器、把叠加扩成 N 条线路段让中继线路也能当线路段）没有动；后者要重做 `core/bond` 的调度与恢复（到处是按两条线路段写死的结构），属于改协议，要先出设计再定。
