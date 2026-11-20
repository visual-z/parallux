---
type: feat
status: awaiting-author        # todo | doing | blocked | awaiting-author | done
weight: full
created: 2026-11-20
baseline: b1639bd0b668
---

# 叠加时直连流量也经聚合服务器（局域网与服务器自身除外）

## 来源

作者 2026-11-20：「直连流量也要能聚合」。我列出了代价：国内网站看到的是 VPS 的 IP，VPS 在境外时国内网站会变慢；叠加只合并 TCP。作者选了「直连也全部走叠加」；同一轮问到主备，作者选了「保留主备」。

这推翻了 fix-aggregate-routing 的第 2 条（叠加时直连不进聚合服务器）。当时的两条理由，今天重新判断：
- 「叠加协议不加密」：直连流量本来就明文经过运营商，叠加并没有让它暴露得更多；聚合服务器是作者自己的。
- 「设计稿把直连画成单独的出口」：保留，流向图里直连仍是单独的出口。

## 范围

- **独占：** `core/aggregate/local.go` 及其测试；`core/aggregate/register.go` 的 Options 与 DialContext；`ProfileComposer.swift`；`AggregationServer.swift`（取服务器地址）；`AppModel.effectiveMode`；`ConnectionSwitches.swift` 的 AggregationNotice；`ExplainView.swift` 的线路说明；`PLAN.md` 决策表。
- **不碰：** multipath 协议；主备与分流的行为；UDP（照旧按线路走）。

## 观测面

- 哪些目标可以走叠加：纯函数 `bondEligible(destination, bypass)`，表驱动测试。
- 拨号：用假的线路出站和假的 bond 出站记录各自的拨号次数，确认局域网目标根本不碰 bond。
- 组合后的配置：解析 JSON，检查每个聚合出站的 `mode`、`bond` 与 `bond_bypass`。

## 环境假设

- sing-box 的 tun 入站开启 sniff 后，目标可能是域名而不是 IP（`route.rules` 里有 sniff）。局域网主机名（`nas.local`、单标签名）要按名字判断，不能只看 IP。
- multipath 出站拨聚合服务器时直接用线路出站（`outbounds: [link-en0, link-en7]`），不经过 aggregate，所以不会出现环路；`bond_bypass` 只是让「访问服务器本身」的连接不绕一圈。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** `bondEligible`：
  - 不走叠加：私有地址（10/8、172.16/12、192.168/16、fc00::/7）、环回、链路本地（169.254/16、fe80::/10）、CGNAT（100.64/10）、组播、未指定地址；以 `.local`、`.lan`、`.home.arpa`、`.internal` 结尾或不含点的域名；`bypass` 里列出的主机（不区分大小写）。
  - 走叠加：其余公网 IP 与域名。
  - 检：test `TestLocalDestinationsNeverGoThroughTheBond`
- **D2** 叠加方式下，聚合出站拨局域网目标或 bypass 主机时不拨 bond，直接走线路；拨公网目标时先拨 bond。
  - 检：test `TestBondSkipsLocalDestinations`
- **D3** 组合：叠加且有服务器时，替换用户 `direct` 的聚合出站和 `parallux-links` 一样，`mode` 为 bond、`bond` 为 multipath 的 tag、`bond_bypass` 含服务器地址；没有服务器时都是主备、不带 bond。
  - 检：test `bondModeCarriesDirectTrafficToo`
- **D4** 只开聚合、选了叠加、有服务器时，`AggregationNotice` 不给提示（真的在叠加）；没有服务器时仍提示「尚未设置聚合服务器，暂按主备运行」。
  - 检：test `aggregationOnlyBondRunsAsBond`
- **D5** 计数只因本卡新测试增加；除下方 WEAKEN-OK 列出的、因本决策改变契约的断言外，不弱化既有测试；gate 全绿。
  - 检：cmd `keel gate`
- **D6** 作者手测：有聚合服务器时选叠加，国内网站的连接也经服务器（连接页的出站链里有 parallux-bond），NAS 和打印机这类局域网设备照常访问。
  - 检：author 统一手测

## 设计

- 局域网判断放在内核的 aggregate 里，不放在 ProfileComposer 的路由规则里。规则方案要在用户的规则前面插一条 `ip_is_private`，会改变用户规则的语义，而且挡不住 sniff 出来的局域网域名；内核拨号时手里正好有最终目标。
- `bond_bypass` 由组合器从 multipath 片段的 `server` 字段填入。内核不去反查 multipath 出站的配置，免得 aggregate 依赖 bond 包的内部结构。
- 被改变的既有断言（作者 2026-11-20 的决定改了契约，不是为了让测试通过）：
  - `LinkCompositionTests.bondModeKeepsDirectTrafficOffTheServer`：断言直连不带 bond，改为本卡 D3 的相反断言。
  - `LinkViewTests.aggregationOnlyBondSaysItRunsAsFailover`（feat-link-view D5）：断言只聚合时提示「按主备运行」，改为 D4。

WEAKEN-OK: apple/ParalluxKit/Tests/ParalluxKitTests/LinkCompositionTests.swift 叠加时直连也走服务器，直连不带 bond 的断言随契约反转（作者确认 2026-11-20）
WEAKEN-OK: apple/ParalluxKit/Tests/ParalluxKitTests/LinkViewTests.swift 只聚合时叠加真的生效，不再提示按主备运行（作者确认 2026-11-20）

## 验证命令

```bash
(cd core && go test ./aggregate -run 'TestLocalDestinations|TestBondSkips' -count=1)
scripts/swift-test.sh /tmp/t.xml bondModeCarriesDirectTrafficToo
keel verify-red docs/tasks/feat-bond-direct.md
keel gate --record docs/tasks/feat-bond-direct.md
```

## 证据

RED: d72941e -run ^TestLocalDestinationsNeverGoThroughTheBond$ ./core/aggregate/  # D1
RED: d72941e -run ^TestBondSkipsLocalDestinations$ ./core/aggregate/  # D2
RED(swift): d72941e bondModeCarriesDirectTrafficToo  # D3
RED(swift): d72941e aggregationOnlyBondRunsAsBond  # D4

- 快照用生成器重生成（`PARALLUX_WRITE_FIXTURES=1`），只有 `composed-bond.json` 变了：`direct` 由 failover 改为 bond，带上 `bond: parallux-bond`，两个聚合出站都带上 `bond_bypass: ["203.0.113.10"]`；`TestComposedFixturesPassLibboxCheckConfig` 通过，libbox 接受新字段。
- 回归冒烟（2026-11-20，签名构建，分流，无聚合服务器）：
  - google 200，baidu 200；10 个并发国内下载 en0 +78 MB、en7 +68 MB。
  - 局域网网关 192.168.1.1：经隧道 TCP 22 成功 10/10，TCP 80 成功 5/10；不经隧道、直接绑 en0 与 en7 拨 80 端口，同样都是 5/10，是路由器自己的问题，不是隧道造成的。
- 叠加的端到端还没测：需要聚合服务器（D6）。
GATE: f57bb971ee1c+dirty ok tree:863b5d91b041 build=0 vet=0 test=0[596p/0f] fmt=0 swift-test=0[147p/0f] apple-build=0 server-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-20)

## 修订
- D3 里「`parallux-links` 的 `bond_bypass` 含服务器地址」一条由决策 25 修订：节点用的聚合出站不再带排除，直连流量用的不变（作者确认 2026-11-20，见 `feat-node-hosted-aggregation` 的修订与 WEAKEN-OK）。

## 交接

- 做了什么：内核加 bondEligible，局域网目标与服务器自身不走 bond；组合器让直连替换出站也带 bond 与 bond_bypass；effectiveMode 和提示不再因为代理关着而退回主备；记为 PLAN 决策 23。
- 卡在哪：等作者提供聚合服务器，端到端测 D6。
- 下一步：拿到服务器链接后，在连接页确认国内连接的出站链里有 parallux-bond，并在局域网访问 NAS 或路由器。
