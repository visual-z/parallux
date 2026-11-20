---
type: chore
status: done        # todo | doing | blocked | awaiting-author | done
weight: full
created: 2026-11-20
baseline: 7bb05c121690
---

# 仓库可以公开：有许可证全文，没有指向不存在的任务卡的引用

## 来源

作者 2026-11-20 决定把仓库开源，并选定：保留提交历史；此前的任务卡与进度记录不进公开仓库（留在私有存档）；公开仓库从这次整理之后照常用任务卡开发。

历史任务卡拿掉之后，代码注释、脚本和文档里还留着一百九十多处对它们的引用（`docs/tasks/….md` 路径和卡名），读的人顺着找不到东西。另外仓库一直没有 `LICENSE` 文件，README 只有一句「GPLv3」。

## 范围

- **独占：** `LICENSE`；`scripts/check-card-refs.sh`；本卡。
- **只改注释与文字：** `core/`、`apple/`、`server/`、`scripts/`、`keel.toml`、`apple/project.yml` 里提到旧卡的注释；`PLAN.md`、`docs/MANUAL-TEST.md`、`docs/RELEASE.md`、`docs/research/` 里提到旧卡的句子；`README.md` 的许可证一节；删掉只为进度记录服务的 `.gitattributes`。
- **不碰：** 任何产品行为、测试断言、常量、配置格式；PLAN 的决策内容（只去掉卡名，决策与理由原样）。

## 观测面

- `scripts/check-card-refs.sh` 的退出码：被跟踪的文件里每个 `docs/tasks/<type>-<slug>.md` 路径都指向存在的文件。
- gate 的测试计数：注释改动不应让任何测试增减或变红。
- GREEN 可能被截断的方式：检查脚本一个路径都没匹配到也会退出 0。挡法：先故意加一处指向不存在的卡的引用，确认它退出 1 并指出文件（见证据）；并且本卡自己的路径会被它扫到。

## 环境假设

无。只改文本，不依赖外部系统。GPLv3 全文取自 <https://www.gnu.org/licenses/gpl-3.0.txt>（674 行）。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** 仓库根目录有 GPLv3 全文，README 链到它，并写明内核所基于的 sing-box 的附加条款。
  - 检：grep `GNU GENERAL PUBLIC LICENSE` in `LICENSE`
  - 检：grep `\[GPLv3\]\(LICENSE\)` in `README.md`
- **D2** 被跟踪的文件里，每个写成路径的任务卡引用都指向存在的卡。
  - 检：cmd `scripts/check-card-refs.sh`
- **D3** 产品行为不变：gate 全绿，测试计数不变（Go 625、Swift 176）。
  - 检：cmd `keel gate`
- **D4** 不弱化既有测试（测试文件里只动了注释）。
  - 检：cmd `keel assert-guard --card docs/tasks/chore-public-release.md`

## 设计

- **注释不留悬空的出处。** 原来的注释用「（某张卡）」交代理由的来处。卡不在了，就把括号去掉；注释里本来写着的理由、实测数字和 PLAN 决策号都留着。只剩一个卡名、没有别的内容的注释行整行删掉。
- **PLAN 只去卡名。** 决策表的「理由与证据」一栏里引用旧卡的地方去掉卡名；提到网口绑定实验的四处改为指向仍然在库里的 `docs/research/sysext-bind-interface.md`。
- **手测清单去掉「卡」一栏。** 那一栏把每一步对应到旧卡的完成定义编号，现在没有对应物。步骤和期望不变。
- **加一个检查而不是只清一次。** 以后的卡也会被注释引用、也会被改名或删除。`scripts/check-card-refs.sh` 只查写成路径的引用：裸的卡名（`feat-…`）和普通词分不开，查不了。它没有接进 gate：本卡用它验收；要不要每次都跑由作者定。
- 否决：把旧卡脱敏后留下。作者选的是不进公开仓库。

## 验证命令

```bash
scripts/check-card-refs.sh
keel gate --record docs/tasks/chore-public-release.md
```

## 证据

RED: none 只改注释、文档与许可证，没有行为改动可以先红后绿

检查器先红过一次：往 `core/tools.go` 加一行注释，指向 `docs/tasks/` 下一张不存在的 fix 卡，`scripts/check-card-refs.sh` 退出 1，打印 `FAIL core/tools.go names …, which does not exist`；撤掉后退出 0。（这里不写出那个路径：检查器也扫本卡，它第一次跑就因为本卡原样引用了那个路径而红了一次。）
GATE: 943e63cb670c+dirty ok tree:ef896d554d55 build=0 vet=0 test=0[625p/0f] fmt=0 swift-test=0[176p/0f] apple-build=0 server-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-20)

## 修订

## 交接

- 做了什么：补了 `LICENSE` 与 README 的许可证一节；代码注释、脚本、PLAN、手测清单与调研笔记里对旧任务卡的引用都去掉了，理由、实测数字与决策号保留；加了 `scripts/check-card-refs.sh`。gate 全绿，测试计数未变。
- 卡在哪：无。
- 下一步：`scripts/check-card-refs.sh` 要不要接进 gate 由作者定；裸的卡名引用它查不了。
