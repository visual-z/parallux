---
type: fix
status: awaiting-author
weight: light
created: 2026-11-20
baseline: bb72642b6ae1（Go 594，Swift 145）
---

# 用错相标志本身表达菜单栏状态

## 问题

作者在 C 分层定稿后指出，18 pt 菜单栏的外置箭头和叹号抢走了两枚半圆的空间。本卡重画菜单栏的现有 20 种状态。Dock 的分层文稿和运行状态的判断沿用上张卡。

## 参考与设计

- Apple 演示了按符号内已有的层改变局部强调程度，填充变体也可以表达选中状态。[WWDC 的 SF Symbols 示例](https://developer.apple.com/videos/play/wwdc2022/10157/) · [Apple 的符号变体](https://developer.apple.com/documentation/uikit/configuring-and-displaying-symbol-images-in-your-ui)
- Caffeine 在同一个杯子里切换空与满。Tunnelblick 用隧道本身的明暗表达 VPN 连接状态。两个实现都保留应用原有的识别物。[Caffeine](https://www.caffeine-app.net/) · [Tunnelblick](https://www.tunnelblick.net/cIconAnimation.html)
- Bjango 的圆形菜单栏图标以约 16 pt 可见面积为参照，分别检查 1× 和 2×。Parallux 继续用 18 pt 画布，让两枚半圆占据中央，交由系统为模板着色。[Bjango 的菜单栏绘图实践](https://bjango.com/articles/designingmenubarextras/)
- 代理开启时填实上半片。下半片的开口、轮廓、大小与对齐方式表示聚合。异常从上半片的右端平切一小段，露出垂直于斜缝的截面。连接过程也只使用这两枚半圆。

## 环境假设

现有 AppKit 模板可在测试进程按 1×、2× 光栅化，起点全量检查已覆盖原 20 枚模板。评审图取自菜单栏调用的同一个绘图入口。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** 可切代理的相同运行方式在代理开启时只填入原图的内部。每一种可以发生异常的状态都只从原有图形减去墨色。1×、2× 均成立。
  - 检：property `turningOnTheProxyFillsOnlyAnEnclosedPartOfTheMark`
  - 检：property `aFaultOnlyRemovesInkFromTheHealthyMark`
- **D2** 现有 20 个状态的映射、中文说明及两种比例的独立轮廓全部通过测试。评审图展示所有组合和原大样本。
  - 检：test `theIconFollowsTheEffectiveModeAndDisplayedSwitches`
  - 检：test `thePhaseIconsRetainDistinctInkAtBothMenuBarScales`
  - 检：author 逐个比较上、下半片和弧边缺口，确认实际菜单栏浅色、深色及选中背景的辨识度。
- **D3** 全量检查及防弱化检查通过。
  - 检：cmd `keel gate --record docs/tasks/fix-menu-icon-silhouettes.md`

## 证据

RED(swift): b687bb2 MenuBarSilhouetteTests # D1

原实现选中 2 个测试，2 个失败，退出 1。代理箭头落在原轮廓的外部，异常叹号给健康蒙版新增了像素。

- `keel verify-red docs/tasks/fix-menu-icon-silhouettes.md` 退出 0，改前 2 个测试全部失败，改后 2 个全部通过。
- 从 AppKit 导出 20 枚模板，在 1× 和 2× 各得到 20 个不同的蒙版。以半透明为阈值计算八邻域，两个比例下每枚图标都恰有两个独立的墨色区域，包括代理开启且异常的状态。
GATE: b687bb24fd90+dirty ok tree:d2b72b90b376 build=0 vet=0 test=0[594p/0f] fmt=0 swift-test=0[147p/0f] apple-build=0 server-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-20)

## 交接

菜单栏已按作者反馈改为两枚半圆。上片填实表示代理，右端截短表示异常。下片的外弧、空心、错开、缩小、对齐分别表示仅代理、聚合待命、分流、主备和叠加。已提供 20 种状态的原大交互预览，待作者目测真实菜单栏。
