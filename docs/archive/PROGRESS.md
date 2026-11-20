# PROGRESS

项目级记录：里程碑、跨卡的结论。最新的在最上；只写结论，命令输出与日志不入库。
会话交接不写这里，写在当前卡的 `## 交接`（`keel status` 会显示）：每个分支都往同一个文件顶部追加，并行时几乎每次合并都冲突。

## 2026-11-19（M3–M6 代码完成）

- 做了什么：作者要求先把功能全部做完再统一手测（决策 16–19）。M3 选线、健康检查、逐线路统计、配置组合器与线路界面；M4 移植 singbox-multipath 为 `core/bond`、聚合服务器与一键安装脚本、叠加接入与测速；辅助服务；M5 小组件、控制中心、快捷指令、URL scheme、远程控制、SFM 对照剩余项；M6 发布脚本与 Sparkle。gate 全绿（Go 587、Swift 94）。
- 卡在哪：所有隧道相关的功能都没在签名构建里跑过，19 张卡在 awaiting-author。作者在 Xcode 重新登录后，签名构建（App、系统扩展、小组件、辅助服务）已装到 /Applications，深度校验通过。
- 下一步：作者按 `docs/MANUAL-TEST.md` 顺序手测；1.4 的线路绑定结论决定 M3 是否要改线路出站的实现。

## 2026-11-19（M1 通路与 M2 并行）

- 做了什么：Apple Development 签名打通（决策 15）；扩展跑 libbox 并经 XPC 交出 command.sock（`feat-sysext-xpc`）；线路探针三组对照（`research-sysext-bind-interface`、`feat-probe-arms`）；按决策 14 并行做了 M2 的配置、内核会话四页、界面（面板、右键菜单、概览、设置六页、菜单栏模板图标）；审查后修了三处签名运行隐患（`fix-signed-run-hazards`）与规则命中截断（`fix-rule-hit-truncation`）；`sfm-parity.md` 按新代码重判。
- 卡在哪：所有隧道相关功能都没在签名构建里跑过。七张卡在 awaiting-author；手测顺序见 `feat-sysext-xpc` 的交接。
- 下一步：作者手测；结果出来后写研究结论，再决定 M3 的分流与主备怎么实现，并开辅助服务卡。

## 2026-11-18（架构审计）

- 做了什么：按 Fable 审计重做地基（`refactor-m1-foundations`）：sing-box fork 加注册钩子、aggregate 出站、XPC 通路与辅助服务定为决策 11、12，聚合模型定为决策 13；生成物（Info.plist、entitlements）不入库并加检查器；内核构建按内容缓存。
- 卡在哪：两张卡等作者手测（M0 的 D6、本次的 D8）；M1 需要签名环境。
- 下一步：`research-sysext-bind-interface` 先证实扩展内能绑非默认网口，它决定分流与主备怎么实现。

## 2026-11-18

- 做了什么：用 keel 1.3.0 模板初始化；填好 PLAN（决策 1–9、里程碑 M0–M6）与词表；M0 骨架完成：Go 内核绑成 Libbox.xcframework（sing-box 1.14.4，86 秒），App 与系统扩展不签名可编译。
- 卡在哪：M0 等作者手测（`chore-m0-skeleton` D6）；M1 需要 Developer ID 账号才能安装系统扩展。
- 下一步：`research-sysext-ipc`：App 直连扩展里的 command server，还是像 SFM 一样经 XPC 中转。
