---
type: feat
status: awaiting-author
weight: full
created: 2026-11-19
baseline: b1008cd (gate: test 586p/0f, swift-test 83p/0f)
---

# 远程控制：查看并控制另一台设备上运行的内核

## 来源

`sfm-parity.md` #94–96；设计稿设置窗口「远程控制」标签（「家里的 Mac mini 192.168.1.20 · 已连接 · 运行 6 天」「添加远程设备…」，「和 SFM 一样，可以查看并控制另一台设备上运行的内核」）。参照 SFM 768b3de `Library/Network/CommandTarget.swift`、`Library/Database/RemoteServer.swift`、`ApplicationLibrary/Views/RemoteControl/`（GPLv3）。

## 范围

- **独占：** `apple/ParalluxKit/Sources/ParalluxKit/Remote/`、对应测试、`apple/Parallux/Remote/`、`CoreSession` 的 client 创建处（本地 / 远程两种）、设置窗口远程控制标签的内容（只改 `SettingsView.swift` 里 `.remoteControl` 一个 case）。
- **不碰：** 扩展；XPC；内核。

## 观测面

- 纯函数：`RemoteServerAddress.normalize` / `connectURL` 的输出；`RemoteServerStore` 的存取（secret 进 SecretStore）。
- 界面：作者手测（需要另一台运行 sing-box 并开了 command server 的设备）。

## 环境假设

- libbox 1.14.4 有 `LibboxNewRemoteCommandClient(handler, options, remoteOptions)` 与 `LibboxNewStandaloneRemoteCommandClient(remoteOptions)`，`LibboxRemoteConnectionOptions` 有 url 与 secret（头文件已确认）。远程端是 SFM 的 tvOS 或开了 `commandServerListenPort` 的 sing-box 客户端。
- 远程模式下本机专属的操作（启停本机隧道、线路、系统代理）不可用，界面停用并说明（SFM 同做法）。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** 地址规范化与 SFM 一致：去首尾空白与末尾斜杠，显示时去掉 `http://`，连接时没有 scheme 补 `http://`，保留 `https://`；空串连接地址为空。
  - 检：test `remoteAddressesNormalizeLikeSFM`
- **D2** 远程设备列表不含 secret；secret 经 SecretStore 存取，删除设备时一并删除。
  - 检：test `remoteServerListsNeverCarryTheSecret`
- **D3** 计数只因本卡新测试增加；不弱化既有测试；gate 全绿。
  - 检：cmd `keel gate`
- **D4** 作者手测：添加一台远程设备，探测可达；切到它后概览、节点、连接、日志、路由模式都显示远端数据并能操作；切回本机恢复。
  - 检：author 统一手测

## 设计

- `CommandTarget`（App）：当前目标为本机或某台远程设备；`CoreSession.Stream` 与 `perform` 按目标建 client（远程用 `LibboxNewRemoteCommandClient` / `LibboxNewStandaloneRemoteCommandClient`）。切换目标时 `CoreSession` 重启所有流。
- 远程模式下：面板与主窗口顶部显示「正在查看 <名称>」，开关与线路停用。
- secret 进钥匙串（复用 `KeychainSecretStore`，换一个 service 名）。

## 验证命令

```bash
scripts/swift-test.sh /tmp/rc.xml Remote
keel verify-red docs/tasks/feat-remote-control.md
keel gate --record docs/tasks/feat-remote-control.md
```

## 证据

RED(swift): edaf1d3 remoteAddressesNormalizeLikeSFM  # D1
RED(swift): edaf1d3 remoteServerListsNeverCarryTheSecret  # D2

- RED 时：冻结提交里 `normalize` / `connectURL` 原样返回、存储不落盘。
- 范围外改动：所有建 command client 的地方（`SpeedTestRunner`、`NetworkToolsRunner`、`CoreSession`）改为经 `CommandTarget`；`KeychainSecretStore` 加 service 参数；`TunnelController` 在远程模式下不随本机隧道启停会话。
GATE: c11a553a2e27+dirty ok tree:aa89c2d4ea96 build=0 vet=0 test=0[587p/0f] fmt=0 swift-test=0[85p/0f] apple-build=0 server-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-19)

## 修订

（无）

## 交接

- 做了什么：远程设备（地址规则同 SFM，密钥进钥匙串）；`CommandTarget` 统一本机与远程的 client；设置 › 远程控制可添加、探测、查看、切回；主窗口与面板显示「正在查看」，本机专属控件停用。
- 卡在哪：等统一手测 D4（需要另一台开了 command server 的设备）。
- 下一步：合入两个并行分支。
