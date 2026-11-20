---
type: research
status: awaiting-author
weight: full
created: 2026-11-19
baseline: 0ce58a5
---

# 路由页重新设计：把「节点」与「规则」合成从流量出发的「路由」

## 来源

2026-11-19 作者反馈（附现状截图）：节点页把十几个分组平铺成卡片墙，分组套分组，选中的节点要一层层点开；折叠后的色点看不出含义；规则页看不出某条规则的流量最终路由到哪里；设置不直观。要求先出设计稿、参考社区做法、大胆革新。

社区参考（2026-11-19 搜索）：Surge Mac 6.9 新增 `rule explain`，逐步说明请求命中的规则、每个策略组的决策与原因、最终代理链（[Surge Changelog](https://t.me/s/SurgeChangelog?q=#Release&before=2269)、[Surge Manual: CLI](https://manual.nssurge.com/tools/cli.html)）；Surge 与 Stash 的请求列表显示每条连接命中的规则与策略（[Understanding Surge](https://manual.nssurge.com/book/understanding-surge/en/)、[Stash](https://apps.apple.com/us/app/stash-rule-based-proxy/id1596063349)）。没有找到把规则、分组、节点画成一张图的客户端。

## 范围

- **独占：** `docs/design/routing-v0.3.html`。
- **不碰：** 代码；在作者确认设计与三个决定之前不动界面。

## 观测面

设计稿本身（浏览器打开，可交互：点流量类别、点出口、试一下的示例域名）。

## 环境假设

- libbox 1.14.4 没有「给定目标，解释按当前配置会命中哪条规则」的接口（2026-11-19 grep 头文件确认）；sing-box router 有未导出的 `matchRule`（`route/route.go:620`）。实现「试一下」需要在 pxbridge 加导出，拿到扩展里运行中的 router。可行性待实现卡对拍。
- 「改走」需要新的覆盖层存储；改配置格式与存储属于 AGENTS.md「Ask first」。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** 设计稿覆盖：路线图（流量类别 → 出口 → 节点，宽度为速率，可点选高亮）、试一下（逐步解释）、出口分组的节点选择器（地区筛选、延迟排序与分布、子分组展平、自动分组说明）、v0.2 → v0.3 对照、待确认的决定。
  - 检：author 打开 `docs/design/routing-v0.3.html` 评审
- **D2** 作者对三个决定（侧栏改八项、「改走」覆盖层、流量类别命名）给出结论。
  - 检：author 回复

## 设计

见设计稿。要点：
- 合并节点与规则为「路由」，从流量出发：左列是由规则推出的流量类别（按流量排序，前 12 类，其余折叠），中间连线宽度 = 实时速率，右列是出口，每个出口一行展平的链（proxy › DE Auto › DE‑1 AnyTLS）。
- 检查器：选中出口的节点选择器，替代卡片墙。
- 试一下：域名 / IP / App → 规则 → 分组 → 节点 → 线路，每步写「为什么」。
- 延迟颜色改为三档（<400 绿、<800 橙、≥800 红），v0.2 的 150 ms 一刀切在代理场景下几乎全红。
- 否决：继续改良卡片墙（加搜索、加折叠）——不解决「流量去哪了」这个核心问题。

## 验证命令

```bash
open docs/design/routing-v0.3.html
```

## 证据

RED: none 设计稿，不是行为改动
GATE: e0de526b888d+dirty ok tree:5a49ea499e4d build=0 vet=0 test=0[589p/0f] fmt=0 swift-test=0[96p/0f] apple-build=0 server-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-19)

## 修订

（无）

## 交接

- 做了什么：设计稿 v0.3（路由页），可交互。
- 卡在哪：等作者评审与三个决定。
- 下一步：作者确认后开实现卡：pxbridge 规则解释导出、路由页、节点选择器、覆盖层。
