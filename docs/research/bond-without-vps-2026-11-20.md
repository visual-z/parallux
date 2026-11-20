# 叠加能不能不要公网 VPS（2026-11-20）

## 问题

作者的两张草图：B（叠加 + 公网 VPS）要用户自己有一台 VPS；D（集群节点当出口中继）只要在局域网的机器上跑我们的转发服务。问题是 B 里重组数据的那一端，能不能换成「我们自己的软件或服务」，不再要求用户准备 VPS。答案决定叠加的服务器形态，以及 D 的范围。

## 证据

检索日期 2026-11-20。标「未核实」的只有二手来源或没有打开原文。

**判据（推断，不依赖来源）。** 把一条连接拆到几条路径上，重组点必须在限制每条路径的那个瓶颈**之后**。办公网按设备限速，瓶颈在办公网出口；集群节点在瓶颈之前。在节点上重组，重组后的那一条连接仍然从一台设备出去，只有一份配额。

**系统与语言层面没有现成的多路径可用。**
- Go 的 MPTCP 只在 Linux 上实现，其他系统是空实现，退回普通 TCP：<https://github.com/golang/go/blob/master/src/net/mptcpsock_stub.go>、<https://pkg.go.dev/net#Dialer.SetMultipathTCP>。sing-box 的 `tcp_multi_path` 只是调用它：<https://sing-box.sagernet.org/configuration/shared/dial/>。
- Apple：`NWParameters.multipathServiceType` 在 macOS 上有声明，但对应的 entitlement 只列了 iOS、iPadOS、visionOS：<https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.multipath>；`URLSessionConfiguration.multipathServiceType` 不支持 macOS，聚合模式标注为仅供实验：<https://developer.apple.com/documentation/foundation/urlsessionconfiguration/multipathservicetype-swift.enum/aggregate>。macOS 上聚合模式实际是否生效：未核实。无论如何 MPTCP 要求对端也支持：<https://developer.apple.com/forums/thread/734359>。
- Network.framework 的 QUIC 选项里没有多路径；`NERelay`、`ProxyConfiguration` 不能指定网口，也不做聚合：<https://developer.apple.com/documentation/network/nwprotocolquic/options>、<https://developer.apple.com/documentation/networkextension/nerelay>。
- 多路径 QUIC：quic-go 的需求自 2022 年起未实现：<https://github.com/quic-go/quic-go/issues/3343>；Xray 把链路聚合的需求关闭为不做：<https://github.com/XTLS/Xray-core/issues/1263>。标准化进度与编号：未核实。

**做聚合的产品都有一个远端重组点。**
- Speedify 在它自己托管的服务器上重组：<https://speedify.com/features/channel-bonding/>。
- OpenMPTCProuter：「The VPS is needed to combine links」：<https://github.com/Ysurac/openmptcprouter/wiki/Technologies>；它把 Shadowsocks、V2Ray 和聚合放在同一台 VPS 上：<https://www.openmptcprouter.com/>。
- engarde 是每条线路都发一份（冗余），不是聚合，也需要服务端：<https://github.com/porech/engarde>（373 star，GPL-2.0）。glorytun 是客户端加服务端：<https://github.com/angt/glorytun>（770 star，BSD-2，2022 年后无更新）。

**不要服务器的做法只对多连接有效。** aria2 的 `--multiple-interface`：<https://aria2.github.io/manual/en/html/aria2c.html>；dispatch-proxy（约 3.5k star，已归档）：<https://github.com/alexkirsz/dispatch-proxy>。它们把不同的连接分到不同网口，和我们的「分流」是一回事，单条连接不会变快。

**可替换的 N 线路段传输。** 没有找到维护中的 Go 实现：getlantern/multipath（60 star，Apache-2.0，2023 年后无更新）偏向选最快的一条；mqvpn（147 star，Apache-2.0）是 C 写的。star 数与日期来自一次检索，未逐项复核。

**用局域网里别的机器当出口。** 没有检索到讨论这个做法的 Reddit 或 Hacker News 帖子（Reddit 当次检索没有取回内容），所以中继主机上跑什么转发软件没有社区先例可引。最接近的是 Speedify 的 Pair & Share：借用附近设备的连接，但仍在它的服务器上重组：<https://speedify.com/features/pair-and-share/>。

## 结论

1. **（推断，由判据得出）集群节点不能代替 B 里的 VPS。** 它们能做的是 D：每台节点各占一份配额，按连接分流。
2. **（有来源）没有不需要对端配合的单连接聚合。** 系统 API、Go、现有代理协议都给不出来；所有产品都靠远端重组点。
3. **不需要「额外」一台 VPS 的情形只有一种**：代理节点是用户自己的机器时，把 `parallux-server` 装在节点上，节点同时做聚合服务器（OpenMPTCProuter 的做法）。用的是机场节点时做不到。
4. **由我们托管聚合服务器**（Speedify 的模式）技术上可行，但要运营带宽、账号与计费，并且用户的流量经过我们的机器，这和 PLAN 的「零遥测」与开源自托管的定位不是一回事。属于改目标，需要作者决定，本次不做。
5. **B 与 D 可以叠起来，但要先有 N 线路段的传输**：有公网重组点时，每台中继主机都可以当一条线路段，单条连接约等于 Wi‑Fi 加 N 份配额。现在的 multipath 只有两条线路段，且没有现成的 Go 实现可换，要自己把两段扩成 N 段。

## 去向

- PLAN 决策 24：实现 D；中继线路不做叠加的线路段（结论 5 留待以后）。
- 结论 3、4、5 没有落成决策，等作者选。
