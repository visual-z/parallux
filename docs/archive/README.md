# 存档：仓库公开之前的任务卡与进度记录

这里是只读的历史记录，不是活的任务卡。新的卡写在 [`docs/tasks/`](../tasks/README.md)。

- `tasks/`：仓库公开（2026-11-20）之前写的 53 张任务卡，状态停在当时的样子。其中标着 `awaiting-author` 的，机器能查的部分当时已经通过，只差作者手测；手测步骤在 [`docs/MANUAL-TEST.md`](../MANUAL-TEST.md)，那里的「卡」一栏指的就是这些卡和它们的完成定义编号。
- `PROGRESS.md`：同一时期的里程碑记录。

## 读的时候要知道的

- **证据指向公开之前的历史。** 卡里的 `RED: <commit>` 与 `GATE: <commit>` 是当时的提交。公开的历史换过提交邮箱，提交号全部变了，所以这些提交号在本仓库里查不到，`keel verify-red` 也无法在这里重跑它们。测试本身都在：按卡里写的测试名在 `core/`、`server/`、`apple/ParalluxKit/Tests/` 里能找到，`keel gate` 每次都跑。
- **它们不在 `docs/tasks/` 里，是因为过不了 `keel lint`。** lint 要求每条证据都有本仓库里的验证记录。让它通过只能改卡的状态或删掉证据，那是在弱化证据，所以改为原样存档。
- **卡里的路径是当时的路径。** 卡与卡之间互相引用时写的是 `docs/tasks/<卡名>.md`，对应现在的 `docs/archive/tasks/<卡名>.md`。`scripts/check-card-refs.sh` 不检查这个目录。
- **替换过的个人环境信息**（只有这三样，其余原文未动）：Apple 团队 ID 换成了 `ABCDE12345`；一处本机家目录路径换成了示例路径；一处局域网网关地址换成了 `192.168.1.1`。
- **两处相对链接改了层级**：`feat-phase-icons.md` 与 `research-icon-concepts.md` 里各有一个指向仓库内文件的链接，目录深了一层，链接跟着多了一个 `../`。
- 代码注释里原先指向这些卡的引用，在公开时已经去掉（`docs/tasks/chore-public-release.md`）；想知道某段代码的来由，可以在这里按功能名找对应的卡。

## 第二批：公开之后在私有工作副本里写的卡（2026-11-21 至 11-26）

公开之后有一段时间，工作仍然做在原来的私有工作副本里（18 个提交，含 0.1.1、0.1.2 两次发版），没有进本仓库。2026-11-26 把它们并了进来：

- **提交原样保留，换了身份信息。** 18 个提交的内容与说明按上面同样的三条规则替换过，提交邮箱换成 noreply，接到本仓库里对应的提交上，再用一个合并提交并进 `main`。所以这些提交号和卡里写的提交号对不上。
- **7 张卡放在 `tasks/` 下**：`fix-node-picker-subgroups`、`fix-tunnel-xpc-connection-churn`、`chore-notification-app-icon`、`fix-release-profile-selection`、`fix-sysext-error-text`、`release-sysext-needs-notarization`、`fix-tunnel-xpc-interface-race`。原因和第一批一样：证据指向替换前的提交号，过不了 `keel lint`。手测步骤在 `docs/MANUAL-TEST.md` 第 7 节。
- **不变量改了编号。** 两边各自新登记了 `INV-15`。本仓库原有的（概览卡片分行）保留 15；这批卡里写的 INV-15、INV-16、INV-17，在 `docs/INVARIANTS.md` 里是 INV-16、INV-17、INV-18。

手测通过之后怎么记：不要回头改这里的卡。为那一组手测开一张新卡（`keel new`），在新卡里写明确认了哪些存档卡的哪几条。
