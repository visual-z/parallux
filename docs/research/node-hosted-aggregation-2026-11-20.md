# 聚合服务器装在代理节点上：竞品做法与边界问题（2026-11-20）

## 问题

作者选定做「节点自带聚合」：代理节点是自己的机器时，把聚合服务器装在同一台机器上，不必另备 VPS。作者要求先看竞品怎么做，避开边界问题。答案决定服务端怎样到达同机的节点、默认拒绝哪些目标，以及客户端要不要改。

## 证据

检索日期 2026-11-20。标「未核实」的没有打开一手来源。

**没有找到做法相同的项目**（独立的重组进程，再去拨同机的代理）。相邻的做法：

- OpenMPTCProuter（路由器端约 2.5k star，GPL-3.0；VPS 端 211 star）：没有独立的聚合进程，代理自己终结 MPTCP。Shadowsocks 监听 `0.0.0.0` 并开 `mptcp`，xray 的入站开 `tcpMptcp`：<https://github.com/Ysurac/openmptcprouter-vps/blob/develop/config.json>、<https://github.com/Ysurac/openmptcprouter-vps/blob/develop/xray-server.json>。它从不拨自己的公网 IP。
- engarde（373 star，GPL-2.0）：服务端把同机的 WireGuard 写成 `dstAddr: "127.0.0.1:59301"`，并警告不排除 `wg0` 会成环：<https://github.com/porech/engarde>。这是唯一明确的「同机走本机地址」先例。
- singbox-multipath（我们叠加传输的上游，15 star，GPL-3.0）：服务端「用自己的路由到达目标」，加密是子协议的事，只合并 TCP，恰好两条线路段；没有提同机：<https://github.com/WuSiYu/singbox-multipath>。

**默认拒绝本机与私网目标是通行做法。**

- OpenMPTCProuter 的 xray 路由把 `0.0.0.0/8`、`127.0.0.0/8`、`::1` 和 `localhost` 送进黑洞（同上 xray-server.json）；它的 xray API 监听 127.0.0.1:10086。
- 3x-ui（约 5 万 star）默认模板把 `geoip:private` 送进黑洞，xray API 入站在 127.0.0.1:62789：<https://github.com/MHSanaei/3x-ui/blob/main/internal/web/service/config.json>。一个允许连环回的转发端点够得着这个 API。
- shadowsocks（python）默认 `forbidden_ip` 是 `127.0.0.0/8,::1/128`：<https://github.com/shadowsocks/shadowsocks/blob/master/shadowsocks/shell.py>；shadowsocks-libev 附带 `server_block_local.acl`（私网、链路本地等），是否默认启用未核实：<https://github.com/shadowsocks/shadowsocks-libev/blob/master/acl/server_block_local.acl>；shadowsocks-rust 默认全部放行：<https://github.com/shadowsocks/shadowsocks-rust>。
- Tailscale 的 `autogroup:internet` 不含 10/8、172.16/12、192.168/16、100.64/10、169.254/16：<https://tailscale.com/docs/reference/targets-and-selectors>。
- sing-box 的 `ip_is_private`（源码 `N.IsPublicAddr`，本仓库钉的版本）涵盖私网、环回、组播、链路本地（含 169.254.169.254）、未指定地址；**不含 100.64/10**。阿里云的元数据地址 100.100.100.200 在这个段里（地址本身未核实）。

**虚拟机连自己的公网 IP 没有保证。**

- AWS：实例只知道自己的私网 IP，网关做 1:1 NAT：<https://docs.aws.amazon.com/vpc/latest/userguide/VPC_Internet_Gateway.html>。实例能否连自己的弹性 IP：未核实。
- Azure：只有负载均衡的情形有文档，后端访问自己的前端地址「按设计不支持」：<https://learn.microsoft.com/en-us/troubleshoot/azure/load-balancer/troubleshoot-load-balancer-platform-limitations>。
- 阿里云、腾讯云：公网 IP 默认不在网卡上，各有「网卡可见 / 直通」的可选模式（只看到检索摘要，未核实）。GCP、Oracle：未核实。
- OpenMPTCProuter 把「公网 IP」（向外部服务查询）和「网卡的源地址」分开存：<https://github.com/Ysurac/openmptcprouter-vps/blob/develop/debian9-x86_64.sh>。

**同机带来的运维问题。**

- 所有连接在节点看来都来自同一个地址，按 IP 限连接数或封禁会一刀切。3x-ui 为此加了白名单：<https://github.com/MHSanaei/3x-ui/issues/5378>。PROXY protocol 只有 xray 的入站认，sing-box 1.6.0 起去掉了：<https://github.com/SagerNet/sing-box/blob/testing/docs/deprecated.md>。
- 端口冲突：OpenMPTCProuter 的 VPS 上，用户自己的服务被它的转发规则占掉 80/443（<https://github.com/Ysurac/openmptcprouter/issues/4356>）；它另有一份保留端口表，因为出站连接的临时端口会撞上入站端口。
- UDP 不合并：OpenMPTCProuter 维护者的说法是「UDP 永远比 TCP 慢」（<https://github.com/Ysurac/openmptcprouter/issues/3067>）；singbox-multipath 同样只合并 TCP。
- 时钟：OpenMPTCProuter 两端相差超过 10 秒会出问题，安装脚本因此装 chrony（<https://github.com/Ysurac/openmptcprouter/issues/1880>）。我们的握手容许 2 分钟（`core/bond` 的 `helloAuthSkew`）。

**本机对拍（2026-11-20，回环，临时测试未入库；结论已固化成本卡的测试）。**

1. 服务器够不着目标（端口没人听、路由规则拒绝）时，客户端的叠加拨号仍然立刻成功，随后读到 EOF。聚合出站只在拨号报错时回退到线路，所以这种情况不会回退。
2. 节点出站经 `detour` 指向聚合出站时，聚合出站收到的目标：节点没设 `domain_resolver` 是域名；设了就是解析后的 IP（`route.default_domain_resolver` 不影响）。
3. sing-box 的路由规则里，`route-options` 改写地址之后的规则看到的是改写后的地址：拒绝私网的规则放在改写后面会把本机投递也拒掉。
4. 现在的聚合服务器会替客户端连它自己的 127.0.0.1（计数的回环监听器收到了连接）。

## 结论

1. **（实测 1 加推断）同机节点不能靠「服务器拨自己的公网地址」。** 在公网 IP 不在网卡上的云上，这条路通不通没有文档保证；一旦不通，客户端不会回退，经这个节点的连接全断。所以服务端要认得自己，先在本机投递。
2. **（实测 2）客户端不能靠比较主机名识别同机节点。** 聚合服务器的链接写 IP、节点写指向它的域名并带 `domain_resolver`，是最常见的组合之一；到达聚合出站的是 IP，正好撞上现在「不把去聚合服务器的连接送进叠加」的排除，同机节点就得不到叠加。修法必须与地址写法无关。
3. **（有来源）拒绝环回、私网、元数据地址应当是默认行为**，并且放在本机投递之前（实测 3）。同机之后这一条更要紧：节点机器上通常有只听环回的面板和 API。
4. **（推断）本机投递连网卡上的本机地址，不连 127.0.0.1。** 云的 1:1 NAT 把公网地址的包送到私网地址上，节点监听的正是那个地址或 `0.0.0.0`；连 127.0.0.1 会让只听环回的服务对持有密钥的人敞开。它挡不住的：本机连自己的网卡地址走环回接口，主机防火墙与云安全组都不经过，所以监听在所有网卡上、只靠防火墙对外关闭的服务仍然连得上。公网 IP 就在网卡上的机器一直如此。
5. **本机没人监听就按原地址拨。** 链接里的地址可能是一台转发机而不是这台机器本身，端口也可能不同；先试本机、不通再照旧，对这种情况没有坏处。
6. **用户要知道的限制**：只合并 TCP，hysteria2、tuic 这类走 UDP 的节点不会变快；节点看到的来源地址是本机，按 IP 限连接数的面板要把它放行；两端时钟相差不能超过 2 分钟。

## 去向

PLAN 决策 25，卡 `feat-node-hosted-aggregation`。结论 2 的修法改动了 `feat-bond-direct` 钉住的一条断言，等作者确认。
