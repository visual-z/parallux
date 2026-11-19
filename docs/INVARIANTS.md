# 不变量登记

不变量是比样例测试更强的规约：它对所有输入成立，而不只是对写下来的那几个输入成立。
优先级：**代码断言**（测试构建里常开，已有的每个测试都会顺带检查它）> **property 测试**（固定种子）> **模型检查**（穷举小状态空间）> 样例测试。

`check-docs` 会检查：编号形如 `INV-<n>` 且唯一；「位置」一栏里反引号中的路径存在，或者符号确实出现在某个源文件里。
检查方式写「计划」的行暂不检查位置。

| ID | 不变量（一句话，对所有输入成立） | 检查方式 | 位置 |
|---|---|---|---|
| INV-1 | 配置库的选中项要么为空，要么是库里某个配置的 id | 代码断言（`checkInvariants`，每次修改后）+ property | `anyOperationSequenceKeepsTheSelectionValid` |
| INV-2 | 日志与速率历史的环形缓冲长度不超过容量，并按到达顺序保留最新的条目 | 代码断言 + property | `aRingBufferKeepsTheNewestEntriesInOrder` |
| INV-3 | 流向图里每个节点高度等于流经它的流带宽度之和，左右两侧总高度相等 | 代码断言 + property | `aSankeyLayoutConservesWidth` |
| INV-4 | 选线顺序是全部线路的排列；有健康的非备用线路时，第一条一定是它 | 代码断言 + property | `TestLinkOrderIsAPermutationThatStartsHealthy` |
| INV-5 | 组合后的配置保留用户的每个出站 tag，且没有 detour、成员或 links 指向不存在的 tag | property | `composingKeepsEveryTagAndNoDanglingDetour` |
| INV-6 | 路由覆盖只改写对应规则的出站，其余规则不变，且不产生指向不存在出站的规则 | property | `overridesOnlyTouchTheirRulesAndNeverDangle` |
| INV-7 | 带量程的流向图里，节点、中柱与流带都不超出绘图高度，同列相邻节点间距不小于最小间距，中柱上的流带首尾相接且总和等于中柱 | 代码断言 + property | `aFlowLayoutWithCapacityIsProportionalAndNeverOverflows` |
| INV-8 | 流向图的粒子数不超过上限，每个粒子都落在一股现存流带的范围内 | property | `flowParticlesStayBoundedAndInsideTheirBands` |
| INV-9 | 流向图交给 GPU 的每片流带网格面积等于厚度 × 宽度，顶点都在绘图范围内，顶点总数不超过上限 | property | `flowMeshCoversEachBandExactly` |
| INV-10 | 流向图与路线图里已经显示的节点只在闲置超过保留时长后才离开，离开之前相对顺序不变，节点数不超过上限 | property | `flowSlotsKeepTheirPlaceWhileTrafficComesAndGoes` |

## 写法提示

- **往返：** `decode(encode(x)) == x`；`apply_all(deltas) == snapshot`。
- **多实现对同一份规约：** 多条路径（快速路径、回退路径、增量路径）都去对照一个参考函数，而不是两两互相比较。
- **状态机：** 每个事件交错下，「一个请求只被结算一次」；用穷举或模型检查覆盖小规模的全部交错。
- **脱敏：** 任意输入下，落盘的字节里都找不到金丝雀秘密。
