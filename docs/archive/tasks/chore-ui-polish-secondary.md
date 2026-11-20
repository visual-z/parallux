---
type: chore
status: awaiting-author
weight: light
created: 2026-11-19
baseline: 0c7dbbd
---

# 面板、设置与次级页面的文案改用竞品用词，收紧留白，补空态与窄窗口布局

## 问题

2026-11-19 作者反馈：很多地方界面与文案不符合苹果设计规范、跟设计稿不一致，每个页面留白很大；文案要参照竞品，不要自己写。依据 `docs/design/copy-and-style.md`（SFM zh-Hans、Clash Verge Rev zh、LetsMove zh_CN、设计稿 v0.2）。本卡覆盖面板、右键菜单、设置七个标签、配置、线路、聚合服务器、诊断、远程控制、端点、移到「应用程序」提示、小组件；路由、概览、连接、日志由另一张卡处理。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** 上述页面里的中文界面文案只来自 SFM、Clash Verge Rev、LetsMove、设计稿或 `CONTEXT.md` 词表；找不到出处的说明段落删去而不是改写。
  - 检：author 对照设计稿与 `docs/design/copy-and-style.md` 逐页看
- **D2** 没有开发者向的文字（里程碑、研究卡、内部字段名作说明）出现在这些页面。
  - 检：grep `研究卡`
- **D3** gate 全绿；测试计数不变，既有测试没有被弱化。
  - 检：cmd `keel assert-guard --card docs/tasks/chore-ui-polish-secondary.md`

## 证据

RED: none 界面与文案调整，无行为改动

- 没有改 ParalluxKit 的字符串，也没有改任何测试。
- 屏幕截图核对没做成：手测期间显示器休眠后锁屏，`screencapture` 只拿到锁屏画面；只确认了不签名构建通过、Swift 102 个测试全绿。
GATE: 10808823a13e+dirty ok tree:c39387f70390 build=0 vet=0 test=0[590p/0f] fmt=0 swift-test=0[102p/0f] apple-build=0 server-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-19)

## 交接

- 做了什么：面板、右键菜单、设置七个标签、配置、线路、聚合服务器、诊断、远程控制、端点、移到「应用程序」提示、小组件的文案改用 SFM / Clash Verge Rev / LetsMove / 设计稿用词，删去自写说明段落；设置标签高度跟随内容；线路行窄窗口时地址叠到名称下方；空态用竞品用词并给主操作。
- 卡在哪：作者逐页看（D1）；截图没做成，见证据。
- 下一步：合入主干后与路由、概览、连接、日志的那张卡一起看。
