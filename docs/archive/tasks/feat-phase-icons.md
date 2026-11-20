---
type: feat
status: awaiting-author
weight: full
created: 2026-11-20
baseline: 0c5a06f（Go 594，Swift 141）
---

# 错相应用图标和同时表达聚合、代理、异常的菜单栏

## 来源

作者在图标选稿中选择 C「错相」，要求先在 Icon Composer 分层定稿，并把独立的代理开关补入菜单栏标志。此前 `AppModel.menuBarState` 把只开代理和线路不足都归为分流，异常也覆盖了聚合方式。沿用 PLAN 决策 7、21。

## 范围

- **独占：** 应用图标源文稿、XcodeGen 中的主应用资源、菜单栏状态与绘图、相关测试和设计说明。
- **不碰：** 网络扩展、聚合算法、配置和存储格式、发布。

## 不变量

现有开关与有效方式决定图标；断开期间不把保存的代理偏好显示为正在生效。异常保留正在运行的线路形状和代理标记。以穷举输入和运行时的图形蒙版验证。

## 观测面

Icon Composer 中的可编辑图层、原生导出与应用资源目录。菜单栏从 AppModel 进入共享状态映射，以模板图像的尺寸、透明度蒙版、辅助功能标签和人工预览判定。

## 环境假设

本机 Xcode 随附 Icon Composer 27.2。新文稿的画布提供默认、深色、单色及设计代际 26/27；随附 ictool 支持按平台及外观导出。按 [Apple 的流程](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer)使用两个透明 SVG 图层与原生底色。XcodeGen 2.46.0 的打包结果用编译产物核对。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** 错相的两枚半圆可独立编辑，主应用编译正确的 Icon Composer 资产；可导出 macOS 默认、深色和单色系列外观。
  - 检：test `theAppTargetSelectsTheLayeredPhaseIcon`
  - 检：cmd `scripts/build-apple.sh`
  - 检：author 在 Icon Composer 与 Dock 查看定稿的轮廓和材质。
- **D2** 覆盖只开代理、聚合等待足够线路、分流、主备、有效叠加，以及每个运行组合的异常；连接过程与未连接分别表达。关闭代理的叠加选择沿用现有的主备回退。
  - 检：test `eachPhaseIconAnnouncesItsConnectionProxyAndHealthState`
  - 检：property `theIconFollowsTheEffectiveModeAndDisplayedSwitches`
- **D3** 18 pt 单色模板在 1× 和 2× 下有独立非空轮廓，异常与代理可同时辨认；菜单栏与评审图使用相同绘图入口。
  - 检：test `thePhaseIconsRetainDistinctInkAtBothMenuBarScales`
  - 检：author 比较浅色、深色、选中背景上的图标，以及启用速率文字时的显示。
- **D4** 全量检查及防弱化检查通过。
  - 检：cmd `keel gate --record docs/tasks/feat-phase-icons.md`

## 设计

[Icon Composer 文稿](../../../apple/AppIcon.icon)由暖白底色和两枚独立矢量图层组成，右下半圆为赭红，左上半圆为朱红。两条直径平行错开，中间的斜缝在单色外观里仍然可见。

以下是初版菜单栏的绘制记录。作者反馈后的图形与依据见[用错相标志本身表达菜单栏状态](fix-menu-icon-silhouettes.md)。

菜单栏以半圆画当前生效的方式。右上角的箭头表示代理开启，右下角的叹号表示异常，两个标记可以同时出现。

| 当前设置 | 代理关闭 | 代理开启 |
|---|---|---|
| 聚合关闭 | 两个开关都关闭时断开 | 仅代理，使用单枚半圆 |
| 聚合待命 | 空心半圆与两段短线 | 同一形状加箭头 |
| 分流 | 两枚实心半圆错开 | 同一形状加箭头 |
| 主备 | 一枚实心半圆配一条短线 | 同一形状加箭头 |
| 叠加 | 按主备运行，使用主备图标 | 两枚半圆在中央接合，加箭头。缺少可用聚合服务器时显示主备加箭头 |

八种运行组合各有正常、异常两版。其余四枚分别表示未连接、正在连接或重连、正在断开、连接异常。

## 验证命令

```sh
keel verify-red docs/tasks/feat-phase-icons.md
keel gate --record docs/tasks/feat-phase-icons.md
```

## 证据

RED(swift): cc039c85656e PhaseIconTests # D1, D2

旧版的失败断言为 `actual == expected` 与 `app.contains("ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon")`，选中 2 个测试，失败 2 个。

- `keel verify-red docs/tasks/feat-phase-icons.md` 退出 0。旧版选中 2 个测试，全部失败。实现后选中 4 个测试，全部通过。
- 纯状态映射穷举 256 组输入，覆盖 20 种输出。1×、2× 实际模板图像各有 20 个非空且互异的透明度蒙版。
- Icon Composer 随附的 `ictool` 为 macOS 26、27 分别导出默认、深色、浅色着色、深色着色、浅色透明和深色透明外观，12 个导出均成功。`scripts/build-apple.sh` 退出 0。应用的 `CFBundleIconName` 和 `CFBundleIconFile` 均为 `AppIcon`，包内包含 `Assets.car` 和 `AppIcon.icns`。
GATE: cc039c85656e+dirty ok tree:6d2123261ffe build=0 vet=0 test=0[594p/0f] fmt=0 swift-test=0[145p/0f] apple-build=0 server-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-20)

## 修订

无。

## 交接

已制作 C 的原生分层文稿，接入主应用。Dock 的轮廓与材质仍待作者确认。菜单栏已按作者反馈转入[轮廓调整卡](fix-menu-icon-silhouettes.md)验收。
