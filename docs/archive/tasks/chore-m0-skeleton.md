---
type: chore
status: awaiting-author
weight: full
created: 2026-11-18
baseline: none
---

# 仓库能从源码编出带 Go 内核的 App 和系统扩展，gate 全绿

## 来源

PLAN 里程碑 M0。作者在 2026-11-18 确认项目名 Parallux、Swift 原生界面 + Go 内核、只支持 macOS 26+（PLAN 决策 2–9），要求先把项目初始化好。

## 范围

- **独占：** 全仓库（首张卡）。
- **不碰：** `sing-box-mygo` 旧仓库（只读，只拷贝 `docs/LICENSES.md` 登记的文件）。

## 观测面

- Go：`go test -json` 的事件计数；Swift：`swift test` 写出的 JUnit 报告计数。
- 编译链接：`scripts/build-apple.sh` 的退出码；系统扩展是否进了 App 包、Info.plist 键是否正确，用 `plutil` 读产物。
- GREEN 可能被截断的方式：Swift 步骤选中 0 个测试（keel 的 junit runner 判失败）；xcframework 是旧的（`build-apple.sh` 比较时间戳后重编）。

## 环境假设

- Xcode 27.2（`/Applications/Xcode.app`，macOS SDK 27.2）可以把部署目标设为 macOS 26.0。对拍：2026-11-18 不签名编译通过。
- sagernet/gomobile v0.1.12 能为 `-target macos -macosversion=26.0` 绑定 sing-box v1.14.4 的 libbox。对拍：2026-11-18 构建成功，86 秒。
- Libbox 静态库在 App 与扩展里额外依赖 libresolv、libbsm、AppKit、ApplicationServices、CoreText、IOUSBHost、SystemConfiguration、Network。对拍：逐个按链接错误补齐，2026-11-18 链接通过。
- 本机没有 Developer ID，系统扩展的安装与运行留给 M1。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** gate 每一步退出码为 0，包括 Go 测试、Swift 测试与不签名的 App/扩展编译。
  - 检：cmd `keel gate`
- **D2** 边界规则「core 不启动子进程」能抓住违规：在 `core/` 下引入 `os/exec` 时 `keel check-boundaries` 失败。
  - 检：cmd `keel check-boundaries`
- **D3** ParalluxKit 的 Swift 测试至少执行 7 个，全部通过。
  - 检：test `ParalluxKitTests`
- **D4** 编出的 App 包内含系统扩展，扩展 Info.plist 的 packet-tunnel 提供者指向 `PacketTunnel.PacketTunnelProvider`。
  - 检：cmd `plutil -extract NetworkExtension.NEProviderClasses.com\.apple\.networkextension\.packet-tunnel raw .build/xcode/Build/Products/Debug/Parallux.app/Contents/Library/SystemExtensions/io.github.visual-z.parallux.tunnel.systemextension/Contents/Info.plist`
- **D5** 不弱化既有测试。
  - 检：cmd `keel assert-guard`
- **D6** 作者运行 App：菜单栏出现图标；左键打开面板（总开关、聚合方式三选一、打开主窗口）；右键出现原生菜单；主窗口侧栏按三组列出九项；⌘, 打开设置窗口，「内核」页显示 `sing-box 1.14.4`。
  - 检：author 运行 `.build/xcode/Build/Products/Debug/Parallux.app` 逐项查看

## 设计

- Go 模块在仓库根，代码在 `core/`。`core/pxbridge` 是唯一给 Swift 的 Go API；libbox 与 gomobile 经 `core/tools.go`（`tools` 构建标签）钉进 go.mod。
- `scripts/build-core.sh` 照搬 sing-box v1.14.4 的 Apple 构建标签与链接参数，只出 macOS 切片。
- Swift 侧三块：`ParalluxKit`（SwiftPM，纯逻辑，`swift test`）、`Parallux`（App）、`PacketTunnel`（系统扩展）。工程用 XcodeGen 生成。
- 菜单栏状态项用 AppKit 而非 MenuBarExtra，因为要区分左右键（决策 7）。
- 否决：独立进程 + daemon gRPC（决策 4）；把 .xcodeproj 入库（决策 8）。

## 验证命令

```bash
keel gate --record docs/tasks/chore-m0-skeleton.md
```

## 证据

RED: none — 骨架卡，没有要修回的既有行为；D2 的边界规则单独演示过会红（见下）。

- D2 演示（2026-11-18）：在 `core/zz/x.go` 写 `import _ "os/exec"`，`keel check-boundaries` 退出 1，`FAIL core/zz/x.go:3: [core 不启动子进程]`；在 `apple/Parallux/Zz.swift` 写 `PacketTunnelProvider`，退出 1，`[app 不引用扩展源码]`。删掉后退出 0。
- D4：`plutil -extract …packet-tunnel raw …/Info.plist` 退出 0，输出 `PacketTunnel.PacketTunnelProvider`。
GATE: a0af4b9f4d72 ok tree:1ad79025c31f build=0 vet=0 test=0[4p/0f] fmt=0 swift-test=0[7p/0f] apple-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-18)

## 交接

- 做了什么：仓库初始化；Go 内核、Libbox.xcframework、ParalluxKit、App 与系统扩展都能从源码编出；gate 回执已记录。
- 卡在哪：等作者手测 D6（`scripts/build-apple.sh` 后运行 `.build/xcode/Build/Products/Debug/Parallux.app`）。
- 下一步：作者确认 D6 后改 done；然后开 `research-sysext-ipc`，它需要 Developer ID 账号。

## 修订

（无）
