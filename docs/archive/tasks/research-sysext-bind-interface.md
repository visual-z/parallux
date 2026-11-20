---
type: research
status: awaiting-author
weight: full
created: 2026-11-18
baseline: 7bb1fb6 (gate: test 8p/0f, swift-test 17p/0f)
---

# 证实系统扩展在接管默认路由后，仍能把连接绑到非默认的物理网口

## 来源

Fable 审计（2026-11-18）：PLAN §4 的分流与主备都依赖这一点，但没有证据在 macOS 系统扩展里证实过。
- 正面：mqvpn 的 iOS 扩展在 NE 内强制 `IP_BOUND_IF`（`ios/app/PacketTunnel/PathBinder.swift`）。
- 反面：Apple 论坛 thread 692930，隧道起来后绑定 socket 的 connect 返回 `EADDRNOTAVAIL`。
- sing-box 上游只在所选网口不是默认网口时才绑（`common/dialer/default_parallel_interface.go:35-37`）。
- mqvpn 记录的坑：NE 内 `NWPathMonitor` 回调可迟到约 110 秒、单监视器只报首选路径；网口重连后 ifindex 会变；utun 的更具体路由让作用域查找返回 `ENETUNREACH`。

2026-11-18 作者同意：探针不放实验分支，做进主干，作为诊断页逐线路检查的基础；与 `feat-sysext-xpc` 的 D8 同一次手测完成。

## 范围

- **独占：** `apple/ParalluxKit/Sources/ParalluxKit/Links/`、对应测试、`TunnelXPCProtocol.probeLinks`、扩展里的探针调用、主窗口「诊断」页的探针区、`docs/research/sysext-bind-interface.md`。
- **不碰：** `core/aggregate`；sing-box 的 dialer。

## 观测面

- 每个网口一条结果：网口名、ifindex、connect 是否成功、失败的 errno、耗时、对端回显的出口 IP（`http://1.1.1.1/cdn-cgi/trace` 的 `ip=` 行）。
- GREEN 被截断的方式：探针在 `if_nametoindex` 失败时直接返回「成功」或空结果——测试断言不存在的网口得到 `ENXIO`；connect 被拒时吞掉 errno——测试断言回环上关闭的端口得到 `ECONNREFUSED`。

## 环境假设

- 实测需要签名构建、扩展已批准、两条真实线路（Wi‑Fi + USB 网卡或 iPhone USB 共享）。本机当前只有作者能插第二条线路，结论待作者手测后写。
- 系统扩展自己的 socket 不进自己的隧道（NE provider 的流量默认被排除），所以探针反映的是「扩展内绑定物理网口」本身，而不是隧道回环。待实测确认：探针结果里默认网口的出口 IP 应等于不开隧道时的公网 IP。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** 探针对存在的网口建立绑定连接并报告成功；对不存在的网口报告 `ENXIO`；对拒绝连接的端口报告 `ECONNREFUSED`；能从 trace 响应解析出口 IP。
  - 检：test `LinkProbeTests`
- **D2** 候选网口只含 UP、RUNNING、有 IPv4 地址的物理网口，排除回环、utun、ipsec、awdl、llw、bridge、anpi、ap。
  - 检：test `candidateInterfacesExcludeVirtualOnes`
- **D3** 作者手测：隧道连接状态下，在主窗口「诊断」点「检测线路」，把结果（每个网口的成功与否、errno、出口 IP）贴回来；至少两条线路。
  - 检：author 主窗口 › 诊断 › 检测线路
- **D4** 结论文档写明：扩展内对默认网口与第二网口各自建连的结果、出口 IP、errno，以及 M3 线路发现该用的 API；结论只来自 D3 的实测。
  - 检：author 读 `docs/research/sysext-bind-interface.md`
- **D5** 计数只因本卡新测试增加；不弱化既有测试；gate 全绿。
  - 检：cmd `keel gate`

## 设计

- `LinkProbe`（ParalluxKit，纯 POSIX，可在 `swift test` 里用回环测）：`socket` → `setsockopt(IP_BOUND_IF)` → 非阻塞 `connect` + `poll` 超时 → 发一个最小 HTTP 请求读 trace。不用 NWConnection 的 `requiredInterface`：sing-box 的 direct 出站走 `IP_BOUND_IF`，要证实的正是这条路径。
- 候选网口用 `getifaddrs` 列，按名字前缀排除虚拟网口；不用 NWPathMonitor（mqvpn 记录的迟到与只报首选路径）。
- 扩展经 XPC `probeLinks` 跑探针，返回 JSON；App 诊断页显示并可拷贝。
- 否决：在实验分支里做一次性探针（作者同意做进主干，见来源）。

## 验证命令

```bash
scripts/swift-test.sh /tmp/probe.xml LinkProbe
keel verify-red docs/tasks/research-sysext-bind-interface.md
keel gate --record docs/tasks/research-sysext-bind-interface.md
```

## 证据

RED(swift): 33b7d4d LinkProbeTests  # D1
RED(swift): 33b7d4d candidateInterfacesExcludeVirtualOnes  # D2

- RED 时的失败原文：`Expectation failed: result.errno == ENXIO`；`Expectation failed: LinkProbe.parseTrace("fl=1\nip=198.51.100.7\nts=2\n") == "198.51.100.7"`；`Expectation failed: !LinkProbe.isCandidate(name: name, flags: up, hasIPv4: true)`。
- 另加 `probeResultsComeBackOverXPCIntact`：探针结果经真实 XPC 编解码往返。
GATE: 33b7d4d43432+dirty ok tree:c68ae9605dee build=0 vet=0 test=0[8p/0f] fmt=0 swift-test=0[23p/0f] apple-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-18)

## 修订

- D1 开卡时是占位符；改写为 D1–D5，探针做进主干，结论文档改为 D4 的作者检查（作者确认 2026-11-18）
- D2 D3 D4 D5 随 D1 的改写新增（作者确认 2026-11-18）

## 交接

- 做了什么：`LinkProbe`（IP_BOUND_IF + 非阻塞 connect + trace 取出口 IP）进 ParalluxKit；扩展 XPC 新增 `probeLinks`；主窗口「诊断」页可检测并拷贝结果；结论文档骨架在 `docs/research/sysext-bind-interface.md`。
- 卡在哪：等作者在两条真实线路上跑 D3，再据结果写 D4。
- 下一步：拿到结果后写结论；如果绑定失败，按 PLAN §4 重新设计分流与主备并先与作者讨论。
