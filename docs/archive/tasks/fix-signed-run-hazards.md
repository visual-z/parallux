---
type: fix
status: awaiting-author
weight: full
created: 2026-11-19
baseline: 0d0f282 (gate: test 8p/0f, swift-test 45p/0f)
---

# 第一次签名运行前的三处隐患：重编的扩展不生效、启动可能卡 30 秒、内核流失败不显示

## 来源

2026-11-19 审查（作者手测之前）发现，三处都是 feat-sysext-xpc 与 feat-core-session 引入的：

1. 版本固定为 0.0.1 / 1，`SystemExtensionInstaller` 遇到同版本返回 `.cancel`，Mach 服务名也只带 MARKETING_VERSION。修过扩展后再装，系统仍运行旧扩展，「重新安装」不起作用。
2. `startTunnel` 在完成回调形式里同步调用 `startOrReloadService`，它会回调 `openTun`，而 `openTun` 在信号量上等 `setTunnelNetworkSettings` 的回调。两者若排在同一队列就会等满 30 秒后报超时。SFM 用 async 覆盖，不在 provider 的回调线程上阻塞。
3. `CoreSession.Stream` 的 `connect()` 用 `try?`，`lastError` 没有任何地方显示。XPC 拨号被拒时，界面显示「已连接」而各页为空。

## 范围

- **独占：** `scripts/build-signed.sh`、`apple/Config/Base.xcconfig`、`scripts/check-apple-config.sh`、`apple/PacketTunnel/PacketTunnelProvider.swift`、`apple/Parallux/Session/CoreSession.swift`、`apple/Parallux/AppModel.swift`、`apple/ParalluxKit/Sources/ParalluxKit/Interface/StatusLine.swift` 与测试。
- **不碰：** XPC 协议；扩展替换策略本身（同版本才取消是对的，错在版本不变）。

## 观测面

- 状态行由纯函数 `StatusLine.text` 生成，测试断言内核流报错时不再显示「已连接」。
- 构建：两次 `build-signed.sh` 产出的扩展 `CFBundleVersion` 不同，Mach 服务名随之不同。
- 启动：扩展日志里 `start` 不在 provider 的回调线程上执行（手测看日志）。

## 环境假设

- `OSSystemExtensionRequest` 按 `CFBundleVersion` 与 `CFBundleShortVersionString` 判断是否替换（Apple 文档 `actionForReplacingExtension`；SFM 同判断）。
- `CURRENT_PROJECT_VERSION` 在命令行覆盖后，App 与扩展在同一次 xcodebuild 里取同一值（xcodebuild 命令行设置作用于所有目标）。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** 已连接但内核流报错时，状态行显示该错误而不是「已连接」；没有错误时照常显示。
  - 检：test `aCoreStreamErrorReplacesConnectedInTheStatusLine`
- **D2** 每次签名构建的扩展有唯一的 `CFBundleVersion`，Mach 服务名包含它；配置检查器要求 Mach 服务名带 `$(CURRENT_PROJECT_VERSION)`，并先故意违规一次确认会红。
  - 检：cmd `scripts/build-signed.sh`
- **D3** 扩展的启动在私有串行队列上执行，不在 provider 的回调线程上同步等待。
  - 检：grep `startQueue.async`
- **D4** 计数只因本卡新测试增加；不弱化既有测试；gate 全绿。
  - 检：cmd `keel gate`
- **D5** 作者手测：随 feat-sysext-xpc D8 一起——修改扩展后再次 `build-signed.sh --install`，「重新安装」后运行的是新扩展（`systemextensionsctl list` 版本号变化）；连接在 2 秒内完成。
  - 检：author 同 feat-sysext-xpc D8

## 设计

- 版本：`build-signed.sh` 传 `CURRENT_PROJECT_VERSION=<UTC 时间戳 yyyymmddHHMMSS>`；`PARALLUX_TUNNEL_MACH_SERVICE = $(PARALLUX_APP_GROUP).tunnel.$(MARKETING_VERSION).$(CURRENT_PROJECT_VERSION)`。不签名的 gate 构建保持 1。否决「总是 .replace」：会让每次启动 App 都重装扩展、弹系统提示。
- 启动：`startTunnel` 把 `start` 派到 `startQueue`（串行），完成后再调 completionHandler。
- 错误：`Stream` 捕获 `connect()` 的错误交给 session；`StatusLine.text` 合成状态行（可测），`AppModel.statusLine` 调它。

## 验证命令

```bash
scripts/swift-test.sh /tmp/sl.xml StatusLine
scripts/build-signed.sh && scripts/build-signed.sh
keel verify-red docs/tasks/fix-signed-run-hazards.md
keel gate --record docs/tasks/fix-signed-run-hazards.md
```

## 证据

RED(swift): 50eff84 aCoreStreamErrorReplacesConnectedInTheStatusLine  # D1

- RED 时的失败原文：`Expectation failed: StatusLine.text(setup: .ready, tunnel: .connected, …) == "已连接 · 1 条线路（Wi‑Fi）"`。
- D2：连续两次 `scripts/build-signed.sh` 退出 0，构建号 20261118165831 与 20261118165835，Mach 服务名分别以之结尾；脚本内核对两个 Info.plist 的 CFBundleVersion。检查器演示：把 Base.xcconfig 的 Mach 服务名改回不带构建号，`check-apple-config.sh` 退出 1（`must … contain $(CURRENT_PROJECT_VERSION)`），复原后退出 0。
- 顺带发现并修正：团队签名检查用 `codesign -dv | grep -q`，在 pipefail 下 grep 提前退出使 codesign 收到 SIGPIPE，签名正确的扩展被随机判失败（第二次构建复现）。改为先捕获输出再 grep；ad-hoc 重签的副本仍判失败。
GATE: b60d558ff327+dirty ok tree:5d8955d58163 build=0 vet=0 test=0[8p/0f] fmt=0 swift-test=0[47p/0f] apple-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-19)

## 修订

（无）

## 交接

- 做了什么：签名构建打唯一构建号（两个包与 Mach 服务名）；扩展启动移到私有串行队列；内核流失败显示在状态行并把菜单栏图标切成「线路异常」；修了签名检查的 SIGPIPE 竞态。
- 卡在哪：等作者随 feat-sysext-xpc D8 一起手测 D5。
- 下一步：探针加对照组与 sing-box 路径。
