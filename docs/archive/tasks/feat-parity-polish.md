---
type: feat
status: awaiting-author
weight: full
created: 2026-11-19
baseline: a562c88 (gate: test 586p/0f, swift-test 80p/0f)
---

# 补齐 SFM 对照里配置、节点、连接、日志的待做项

## 来源

`docs/research/sfm-parity.md` 重判（2026-11-19）列为「待做 M5」的项，作者要求在统一手测前全部做完（决策 16）：#5、#10、#21 .bpf 导入导出，#11 编辑元数据，#13 远程配置只读，#18 HTTP Basic 认证，#22 存为 JSON，#38 分组展开折叠，#45 连接按状态过滤，#46 排序，#51 隐藏 DNS 连接，#53 内核日志级别，#56 日志导出（脱敏），#76 禁用弃用警告。

## 范围

- **独占：** `apple/ParalluxKit/Sources/ParalluxKit/Profiles/`（新增文件）、`Session/`（新增文件）、`core/pxbridge/`（新增导出）、`apple/Parallux/Profiles/`、`apple/Parallux/Session/`、对应测试。
- **不碰：** 扩展；XPC；`Settings/`（另两个并行卡在改）；`AppDelegate.swift`、`Intents/`、`Update/`。

## 观测面

- 纯函数：`BasicAuth.request(for:)` 的头部与去掉 userinfo 后的 URL；`ConnectionQuery.apply`（状态、排序、隐藏 DNS）；`LogExport.text`（脱敏后）；`ProfileExport.bpf` 往返。
- Go：`pxbridge.RedactText` 对夹具的输出。
- GREEN 被截断的方式：脱敏在 Swift 侧另写一份而测试只测 Swift 版——导出走 pxbridge 的 Go 实现（`core/internal/redact` 已有测试），Swift 测试断言导出结果里不含金丝雀秘密。

## 环境假设

- libbox `ProfileContent` 的 `encode()` 与 `LibboxDecodeProfileContent` 是 SFM 的 .bpf 格式（SFM `ProfileContent` 导入导出用它，头文件已确认）。
- 内核日志级别可经 command client 运行时修改？libbox 1.14.4 的 `LibboxCommandClientHandler.setDefaultLogLevel` 只是通知。待查：`CommandClient` 没有设级别的方法（头文件里没有）。如果没有，「日志级别」只做界面筛选（已有），在 sfm-parity 写明等价。
- 「禁用弃用警告」：libbox `getDeprecatedNotes` 返回配置里的弃用项（头文件已确认）；SFM 在设置里关掉后不再弹提示。我们在概览显示弃用提示，并提供关闭开关。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** 带 `user:pass@` 的订阅地址：请求不带 userinfo，带 `Authorization: Basic base64(user:pass)`；没有 userinfo 时不加头；百分号编码的用户名密码先解码。
  - 检：test `basicAuthMovesUserinfoIntoAHeader`
- **D2** 连接列表：按活跃 / 已关闭 / 全部过滤；按时间、上行+下行总量、实时速率排序；隐藏 DNS（目标端口 53 或协议 dns）开关；与搜索组合。
  - 检：test `connectionQueryFiltersSortsAndHidesDNS`
- **D3** 日志导出经 Go 的 `redact.Text`：含订阅地址 token、userinfo 的日志行导出后不含这些秘密。
  - 检：test `TestRedactTextRemovesSubscriptionSecrets`
- **D4** 远程配置在编辑器里只读，本地与 iCloud 可编辑。
  - 检：test `onlyRemoteProfilesAreReadOnly`
- **D5** 计数只因本卡新测试增加；不弱化既有测试；gate 全绿。
  - 检：cmd `keel gate`
- **D6** 作者手测：.bpf 导入导出与 SFM 互通；改名与更新间隔可编辑；连接页过滤、排序、隐藏 DNS；节点分组可折叠；日志导出文件里看不到订阅 token；弃用提示可关。
  - 检：author 统一手测

## 设计

- `BasicAuth`（ParalluxKit）纯函数；`ProfileService.download` 用它。
- `ConnectionQuery.apply(rows, state, sort, hideDNS, text)`；`CoreSession` 的连接流改为 `LibboxConnectionStateAll` 并保留已关闭的（数量上限 500，带 why），由页面过滤。
- `pxbridge.RedactText(s)` 导出 Go 的 `redact.Text`；日志页「导出…」写文件前逐行脱敏。
- .bpf：导入用 `LibboxDecodeProfileContent`，导出构造 `LibboxProfileContent` 调 `encode()`。
- 分组展开状态存 `@AppStorage`（每个分组一个键），不调用 libbox `setGroupExpand`（那是给 SFM 自己的界面同步用）。

## 验证命令

```bash
scripts/swift-test.sh /tmp/pp.xml Query
go test -count=1 -run TestRedactText ./core/pxbridge/
keel verify-red docs/tasks/feat-parity-polish.md
keel gate --record docs/tasks/feat-parity-polish.md
```

## 证据

RED(swift): 60a8ef1 basicAuthMovesUserinfoIntoAHeader  # D1
RED(swift): 60a8ef1 connectionQueryFiltersSortsAndHidesDNS  # D2
RED: 60a8ef1 -run ^TestRedactTextRemovesSubscriptionSecrets$ ./core/pxbridge/  # D3
RED(swift): 60a8ef1 onlyRemoteProfilesAreReadOnly  # D4

- RED 时：冻结提交里 `BasicAuth.request` 原样返回、`apply` 原样返回、`RedactText` 原样返回、`isReadOnly` 恒为 false。
- 环境假设对拍（2026-11-19）：libbox 1.14.4 头文件里 command client 没有设置日志级别的方法（只有 handler 回调 `setDefaultLogLevel` 与 server 的 `GetDefaultLogLevel`，后者未导出）。内核日志级别来自配置的 `log.level`；日志页的级别只做界面筛选，sfm-parity #53 记为等价。
GATE: 53760467c2dd+dirty ok tree:f4a8cbd2bcff build=0 vet=0 test=0[587p/0f] fmt=0 swift-test=0[83p/0f] apple-build=0 server-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-19)

## 修订

（完成定义无改动。）

- 范围说明（2026-11-19）：收尾后在 1d992b6 另加了诊断页的网络质量与 STUN（sfm-parity #97、#98）。它没有先开卡，是流程疏漏；改动只有界面与 libbox 调用封装（`apple/Parallux/Bond/NetworkToolsRunner.swift`、`DiagnosticsView.swift`），没有新契约，也没有新测试。手测随本卡 D6 一起：诊断页点「网络质量」「STUN」各一次，有结果或明确的错误。

## 交接

- 做了什么：订阅 Basic 认证；.bpf 导入导出（libbox ProfileContent，与 SFM 互通）；配置改名与更新间隔；远程配置只读；导出 JSON；节点分组折叠；连接按状态、排序、隐藏 DNS（已关闭的最多保留 500 条）；日志导出经 Go `redact.Text`；概览显示弃用提示并可关。
- 卡在哪：等统一手测 D6。
- 下一步：合入系统集成与发布两个并行分支；更新 sfm-parity。
