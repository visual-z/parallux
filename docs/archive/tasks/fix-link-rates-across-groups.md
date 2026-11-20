---
type: fix
status: awaiting-author        # todo | doing | blocked | awaiting-author | done
weight: light
created: 2026-11-19
baseline: d022e684979d
---

# 每条线路的速率是所有聚合出站之和，与组的顺序无关

## 问题

2026-11-19 冒烟（feat-split-switches）：分流方式下，日志里新连接在 `link-en0` 与 `link-en7` 之间轮流，流向图却显示一条线路有流量、另一条 0 bps；上一轮是有线有流量、Wi-Fi 为 0，正好反过来。

组合后的配置里有不止一个聚合出站：用户的 `direct` 换成的聚合出站，加上节点 detour 用的 `parallux-links`，每个都有自己的每线路计数。`LinkRates.rates` 只按线路标签做键，后一个组覆盖前一个组；内核的 `Snapshot` 又用 `sync.Map` 遍历，顺序随机，于是前后两次快照可能拿不同组的计数相减，被截成 0。这个缺陷一直就有，只要配置里有 direct 出站就会触发。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** 速率按（组，线路）各自求差，再按线路标签相加；组在快照里的顺序不影响结果；某个组只出现在一次快照里时，它的这一份记为 0；计数归零时不出现负数。
  - 检：test `linkRatesSumEveryGroupWhateverTheOrder`
- **D2** gate 全绿；测试计数只因本卡新增的测试而增加，既有测试没有被弱化。
  - 检：cmd `keel assert-guard --card docs/tasks/fix-link-rates-across-groups.md`
- **D3** 作者手测：分流方式下有多条连接时，流向图两条线路都显示速率。
  - 检：author 统一手测

## 证据

RED(swift): 806d7e2 linkRatesSumEveryGroupWhateverTheOrder  # D1

- 实机（2026-11-19 15:10，只聚合，分流）：修复后流向图两条线路都出现过速率（Wi-Fi 65 Kbps / 有线 0，另一次 有线 19 Kbps / Wi-Fi 0）。只发两条下载连接时，按连接轮转可能正好都分到同一条线路，所以这次冒烟不能证明 D3。
- 排除过的另一种怀疑：sing 的拷贝路径（`bufio.CopyWithIncreateBuffer`）会绕过 `countedConn`。写临时测试实测，经 sing 拷贝 4 MiB，计数正好 4194304；该临时测试未提交。
- 吞吐对拍：只聚合经隧道 0.33–2.25 MB/s，同时段绕过隧道走 en0 0.26–4.35 MB/s，波动来自国内直连 Cloudflare 本身，看不出隧道带来的退化。
GATE: 28b110d9f1fd+dirty ok tree:d0137d7d9003 build=0 vet=0 test=0[590p/0f] fmt=0 swift-test=0[118p/0f] apple-build=0 server-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-19)

## 交接

- 做了什么：速率按（组，线路）求差后再按线路相加。
- 卡在哪：等作者手测 D3（多开几个下载，看两条线路是否都有速率）。
- 下一步：`LinkStatsPoller.link(_:)` 取的是随机排在最前的组的健康状态，可能闪烁；内核的 `Snapshot` 可以按 tag 排序。另开卡处理，带测试。
