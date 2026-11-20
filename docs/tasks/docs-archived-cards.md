---
type: docs
status: doing        # todo | doing | blocked | awaiting-author | done
weight: light
created: 2026-11-20
baseline: 853fdb8bdf74
---

# 公开之前的任务卡放进只读存档，手测清单重新对得上卡

## 问题

仓库公开时（`chore-public-release`）没有带上此前的 53 张任务卡和进度记录。作者随后决定它们可以公开，并且要能在同一个仓库里查到：其中四十多张还在等作者手测，手测清单原来按卡名和完成定义编号对应。

它们不能直接放回 `docs/tasks/`。公开的历史是改写过的（换了提交邮箱），卡里的 `RED:` 与 `GATE:` 证据指向的提交和 keel 记录只存在于公开之前的历史里；2026-11-20 试过，53 张卡全部过不了 `keel lint`。让它们通过的办法只有改状态或删证据，那等于伪造或弱化证据，不做。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** 53 张历史卡与进度记录在 `docs/archive/` 下，内容与公开前一致，只替换了个人环境信息（Apple 团队 ID、家目录路径、局域网网关地址）；目录里有一份说明，写清它们是只读的、证据指向哪里、哪些信息被替换过。
  - 检：cmd `test "$(ls docs/archive/tasks/*.md | wc -l)" -eq 53`
  - 检：grep `只读` in `docs/archive/README.md`
- **D2** `docs/tasks/` 里只有活的卡：`keel lint` 不把存档当成卡，卡数只因本卡加一。
  - 检：cmd `keel lint`
- **D3** 手测清单每一步重新标出它确认的存档卡与完成定义编号（公开之后新增的步骤除外）。
  - 检：grep `docs/archive/tasks` in `docs/MANUAL-TEST.md`
- **D4** `scripts/check-card-refs.sh` 不把存档里的旧路径当成悬空引用，对存档之外的文件仍然会红。
  - 检：cmd `scripts/check-card-refs.sh`
- **D5** gate 全绿；测试计数不变，既有测试没有被弱化。
  - 检：cmd `keel assert-guard --card docs/tasks/docs-archived-cards.md`

## 证据

RED: none 只增加文档与调整一个检查脚本的排除路径，没有产品行为改动

## 交接

开卡。下一步：放入存档、恢复手测清单的「卡」一栏、调整检查脚本，跑 `gate --record`。
