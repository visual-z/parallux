---
type: fix
status: awaiting-author        # todo | doing | blocked | awaiting-author | done
weight: light
created: 2026-11-19
baseline: 2414f6aa84bd
---

# App 更新后，正在运行的旧扩展自动换成新版本，隧道随后重连

## 问题

2026-11-19 复测：隧道已连接时装上新构建（只改了 App 代码），重新打开 App 后状态行显示「已连接，但读不到内核：probe command server … dial xpc … TunnelXPC.DialError error 0」。`systemextensionsctl list` 显示运行中的扩展是 build 20261119062842，App 自带的是 20261119063918。

扩展的 Mach 服务名带构建号（决策 11），新 App 只连自己构建号的服务。fix-tunnel-start-sandbox 只在点「启动」时比对版本，而隧道一直连着，就不会有人点启动。以后每次更新 App（含 Sparkle）都会这样。这个缺陷一直就有。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** 启动时的决定 `LaunchUpgrade.action(signed:status:stale:)`：签名构建、扩展版本不一致、隧道处于已连接 / 连接中 / 重连中 → 替换后重连；版本不一致但未连接 → 只替换；版本一致或未签名 → 不动。每种输入的结果唯一。
  - 检：test `aStaleExtensionIsReplacedOnLaunchAndTheTunnelComesBack`
- **D2** gate 全绿；测试计数只因本卡新增的测试而增加，既有测试没有被弱化。
  - 检：cmd `keel assert-guard --card docs/tasks/fix-stale-extension-on-launch.md`
- **D3** 作者手测：隧道连着时装上新构建，打开 App 后几秒内状态行回到「已连接 · …」，不需要手动断开重连。
  - 检：author 统一手测

## 证据

RED(swift): fe10194 aStaleExtensionIsReplacedOnLaunchAndTheTunnelComesBack  # D1

- 冒烟（2026-11-19 14:43）：隧道连着旧扩展 20261119062842 时装上 build 20261119064200 并打开 App，25 秒后 `systemextensionsctl list` 显示新 build `[activated enabled]`、旧 build `[terminated waiting to uninstall on reboot]`；`scutil --nc list` 显示 Connected；窗口标题「概览 – 已连接 · 主备 · 2 条线路」，没有再出现 XPC 拨号错误。
GATE: 593ecd2208a3+dirty ok tree:c7825dc6f1a9 build=0 vet=0 test=0[590p/0f] fmt=0 swift-test=0[114p/0f] apple-build=0 server-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-19)

## 交接

- 做了什么：App 启动时比对扩展版本，不一致就替换；隧道原本开着的，替换后自动重连。
- 卡在哪：等作者手测 D3。
- 下一步：无。
