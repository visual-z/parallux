---
type: research
status: done
weight: full
created: 2026-11-20
baseline: 3de6e75d25fd（Go 593，Swift 141）
---

# Parallux 的应用图标与菜单栏五态选稿

## 来源

作者希望先根据项目做几个有区别的 macOS 应用图标效果图，一起评审菜单栏图标，选定方向之后再用 Icon Composer 定稿。README 里的视差、并行与通量，以及概览中的线路流向图，提供了图形依据。菜单栏沿用 PLAN 决策 7 的模板图标。

## 范围

- **独占：** `docs/design/icon-concepts/` 与本卡。
- **不碰：** 本轮交付评审稿。产品资源接入、Icon Composer 定稿及状态判定留给选稿后。

## 观测面

查看三套并排的应用图标效果图、各自的菜单栏轮廓和小尺寸表现。检查每幅图可加载，五态名称与 `MenuBarIcon.State` 一一对应。

## 环境假设

本机 Xcode 随附的 Icon Composer 版本为 27.2，已通过应用 Info.plist 对拍。苹果的 [Icon Composer 设计流程](https://developer.apple.com/videos/play/wwdc2025/361/)支持分层导入并在工具里调整材质。菜单栏尺寸直接取自项目的 `MenuBarIcon.pointSize`。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** 三个方向各有一张应用图标效果图，形状与配色可并排比较。
  - 检：author 打开评审稿，选择应用图标方向。 已确认：2026-11-20
- **D2** 每个方向有未连接、分流、叠加、主备、线路异常五种单色图形，并可在浅深两种底色按 18 pt 对照。
  - 检：author 在评审稿中比较菜单栏五态，确认偏好的方向。 已确认：2026-11-20
- **D3** 设计稿说明图形和产品的关系，选中的图形可据分层思路进入 Icon Composer。
  - 检：author 评审三个方向的图形说明和分层建议。 已确认：2026-11-20

## 设计

第一轮展示合流、视差 P、飞梭。作者反馈更倾向第二张的风格，要求参考苹果和 X，用简单图形组合重做。第二轮采用同一套朱红和暖白，分别以双轨折返、斜切留白和半圆错位构成标志。评审稿可切换单色轮廓，对照 40 pt、24 pt 应用图标及 18 pt 菜单栏五态。

设计来源及各自启发见[评审稿](../../design/icon-concepts/index.html)的「设计参考」，包括 Apple News、播客、快捷指令、Michael Flarup 在 X 上发布的 Finder 概念图，以及 Parakeet 的图标制作笔记。

## 验证命令

```sh
keel verify-red docs/tasks/research-icon-concepts.md
keel gate --record docs/tasks/research-icon-concepts.md
```

## 证据

设计稿有十五个独立的单色状态。故意让光隙 P 的未连接状态引用其分流图形，以检查两种状态混用时能否报错。失败断言为 `cut uses the same contours for disconnected and balance`。

RED: 03147b2c3b619ebe87fba69ee2fad71bff93846e -run ^TestEveryMenuBarStateResolvesToDistinctArtwork$ ./docs/design/icon-concepts # D2

浏览器在 1120 和 390 逻辑点宽度下核对，横向溢出均为 0。三套图形在 18 × 18 与 36 × 36 像素下每套各有 5 个非空、互异的透明度蒙版；同一状态在浅色和深色栏的蒙版一致。单色切换与图层说明均可打开。
GATE: cfadb8a3bee4+dirty ok tree:43b282393fa8 build=0 vet=0 test=0[594p/0f] fmt=0 swift-test=0[141p/0f] apple-build=0 server-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-20)

## 修订

无。

## 交接

作者选定 C「错相」及其半圆分层，要求扩充菜单栏的代理开关组合，并先用 Icon Composer 做应用图标定稿。
