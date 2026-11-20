---
type: fix
status: done
weight: light
created: 2026-11-19
baseline: 32e6eec
---

# 规则命中统计对 4 个以上的 rule_set、protocol 等字段算成 0

## 问题

`RuleSummary.formatItem` 对所有字段超过 3 项就截成 `[a b c...]`，但 sing-box 只有 domain、domain_suffix、domain_keyword、ip_cidr、source_ip_cidr 这几类会截断（`route/rule/rule_item_domain.go`、`rule_item_domain_keyword.go`、`rule_item_cidr.go`，2026-11-19 grep `...]` 确认）；rule_set、protocol 等完整列出（`rule_item_rule_set.go:166`、`rule_item_protocol.go:32`）。于是 `rule_set` 有 4 个以上标签的规则，匹配键与 Connection.rule 对不上，命中数为 0。由 2ee1b07 引入，审查时发现。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** 4 个以上标签的 rule_set 规则按完整列表匹配，命中数正确；domain_suffix 仍按截断格式匹配。
  - 检：test `longRuleSetListsAreMatchedUntruncated`
- **D2** gate 全绿；测试计数只因本卡新增的测试而增加，既有测试没有被弱化。
  - 检：cmd `keel assert-guard --card docs/tasks/fix-rule-hit-truncation.md`

## 证据

RED(swift): 34ca9a8 longRuleSetListsAreMatchedUntruncated  # D1

- RED 时的失败原文：`Expectation failed: hits[0] == 1`。
GATE: 34ca9a8468a8+dirty ok tree:549e32038f87 build=0 vet=0 test=0[8p/0f] fmt=0 swift-test=0[45p/0f] apple-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-19)
GATE: 5ff586844b36+dirty ok tree:c43fe7038765 build=0 vet=0 test=0[577p/0f] fmt=0 swift-test=0[49p/0f] apple-build=0 server-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-19)

## 交接

- 做了什么：只对 sing-box 会截断的五类字段截断匹配键。
- 卡在哪：无。
- 下一步：无。
