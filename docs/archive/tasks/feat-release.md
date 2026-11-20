---
type: feat
status: awaiting-author
weight: full
created: 2026-11-19
baseline: a562c88 (gate: test 586p/0f, swift-test 80p/0f)
---

# 发布：Developer ID 签名、公证、DMG 打包脚本，与 Sparkle 自动更新

## 来源

PLAN M6「Developer ID 签名、公证、自动更新；首个公开版本」，决策 19（作者选定：脚本写好、凭据之后配；自动更新用 Sparkle；不推送、不发布）与决策 16（不等手测）。设计稿设置 › 通用的「自动检查更新」「更新通道」（词表禁用「通道」，代码与界面用「更新渠道」）。

## 范围

- **独占：** `scripts/release.sh`、`scripts/check-release.sh`、`scripts/fetch-sparkle.sh`、`docs/RELEASE.md`、`apple/Parallux/Update/`、`apple/Parallux/Settings/UpdateSection.swift`、`apple/ParalluxKit/Sources/ParalluxKit/Update/` 与测试；`apple/project.yml` 中 Sparkle 框架依赖与 Info 键；`apple/Config/Base.xcconfig` 的更新变量；`scripts/build-apple.sh`、`scripts/build-signed.sh` 各加一行调用 `fetch-sparkle.sh`；`keel.toml` 一个 `tier = "release"` 步骤；`docs/LICENSES.md` 追加两行。
- **不碰：** `core/`、`server/`、`AppDelegate.swift`；`SettingsView.swift` 只加 `UpdateSection()` 一行、删「自动更新在 M6 提供」一行；小组件与快捷指令（并行卡）。

## 观测面

- `UpdateFeed.resolve` 的返回值（哪个 feed，或「未配置」）。
- `scripts/check-release.sh <app>` 的退出码与每条 FAIL 行。
- `scripts/release.sh --dry-run` 的退出码与产物（`.build/release/<版本>/Parallux.dmg`）。
- GREEN 被截断的方式：检查器遇到第一个问题就退出、漏掉其余包——检查器累计全部失败再退出，演示时断言多条 FAIL 同时出现；release.sh 缺凭据时静默跳过公证——缺凭据退出 2 并打印要运行的命令，只有 `--dry-run` 才跳过。

## 环境假设

- Sparkle 2.10.1（2026-10-25 发布，距今 25 天，满足「至少两周」；`gh api repos/sparkle-project/Sparkle/releases` 2026-11-19 查得的最新稳定版）。MIT。
- Sparkle 替换含系统扩展的 App：Sparkle 只替换 .app 包本身；系统扩展由系统从 App 里拷出并独立运行，App 被替换后要再提交一次激活请求，系统按版本号替换扩展。先例：coder/coder-desktop-macos（AGPL-3.0，`Coder-Desktop/Info.plist` 同时有 `SUFeedURL` 与 `NEMachServiceName`，`UpdaterService.swift` 用 `SPUStandardUpdaterController`），betafish-inc/adblock-mac-vpn-release（`AppDelegate.swift` 同时 import Sparkle 与 SystemExtensions，启动时提交激活请求），2026-11-19 读源码确认。Parallux 的 `SystemExtensionInstaller` 在版本变化时 `.replace`，连接前未就绪会激活。待手测：更新后第一次连接触发扩展替换。
- 公证凭据：本机钥匙串里没有 notarytool 档案（`xcrun notarytool history --keychain-profile parallux` 2026-11-19 报 No Keychain password item），由作者之后配置。
- Developer ID 描述文件：NE 权限值 `packet-tunnel-provider-systemextension` 在 Developer ID 下需要 Developer ID 描述文件（Apple 论坛 thread 737894）。本机没有 Parallux 的 Developer ID 描述文件。决策 15 只授权了 Apple Development 的自动注册，所以脚本**不**用 `-allowProvisioningUpdates` 去创建 Developer ID 描述文件；`--dry-run` 在没有 Developer ID 描述文件时改用 Apple Development 构建，只验证打包流程，并明确打印这一降级。
- Sparkle 的 EdDSA 私钥在登录钥匙串，`generate_appcast` 默认从钥匙串读（Sparkle 文档 Publishing an update）。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** 更新源解析：稳定渠道用稳定 feed；测试渠道用测试 feed，没有测试 feed 时退回稳定 feed；稳定 feed 或公钥为空、变量未展开、或不是 https 时为「未配置」，更新器不启动。
  - 检：test `updateFeedsResolveByChannel`
- **D2** `scripts/check-release.sh` 对 Apple Development 构建报红（get-task-allow、非 Developer ID、NE 权限值不带 -systemextension、缺 SUFeedURL / SUPublicEDKey），并一次列出全部问题；检查器先故意违规一次确认会红（即对 Apple Development 构建运行）。
  - 检：cmd `scripts/check-release.sh .build/xcode-signed/Build/Products/Debug/Parallux.app`（期望退出 1，见证据）
- **D3** `scripts/release.sh` 缺公证凭据或 Sparkle 私钥时退出 2，并打印要运行的确切命令；`--dry-run` 跑完构建、签名核对、DMG，跳过公证与 appcast。
  - 检：cmd `scripts/release.sh 0.1.0 --dry-run`
- **D4** 不签名的 gate 构建链接 Sparkle 后仍绿；feed 为空时设置里显示「此构建未配置更新源」，更新器不启动。
  - 检：cmd `keel gate`
- **D5** 计数只因本卡新测试增加；不弱化既有测试。
  - 检：cmd `keel assert-guard --card docs/tasks/feat-release.md`
- **D6** 作者手测：配好凭据与 Developer ID 描述文件后，`scripts/release.sh 0.1.0` 产出公证过的 DMG 与 appcast，`check-release.sh` 退出 0；装上旧版、发布新版后，「检查更新」能下载并替换，替换后连接正常（扩展被替换）。
  - 检：author 统一手测，按 `docs/RELEASE.md`

## 设计

- **为什么引入 Sparkle**（AGENTS.md「新增依赖要写为什么需要」）：Developer ID 分发没有 App Store 更新；自己写需要下载、EdDSA 验签、原子替换与重启、权限提升、增量包。Sparkle 是 macOS 独立分发 App 的通行实现（约 8k star，MIT），coder-desktop 与 adblock VPN 都在含网络扩展的 App 里用它。否决：只检查 GitHub Release 并提示下载（作者选了自动安装）。
- **更新源**：xcconfig 变量 `PARALLUX_UPDATE_FEED`、`PARALLUX_UPDATE_BETA_FEED`、`PARALLUX_UPDATE_PUBLIC_KEY` 写进 Info.plist（`SUFeedURL`、`SUPublicEDKey` 与自定义的测试源键）；渠道存在 UserDefaults；`SPUUpdaterDelegate.feedURLString(for:)` 返回 `UpdateFeed.resolve` 的结果。解析为「未配置」时不创建 `SPUStandardUpdaterController`。
- **release.sh**：双架构内核 → `xcodebuild archive`（Release、Developer ID、`PARALLUX_NE_PROVIDER=packet-tunnel-provider-systemextension`、版本号与时间戳构建号）→ `-exportArchive`（developer-id）→ `check-release.sh` → 公证并装订 App → DMG（hdiutil，含 /Applications 链接）→ 公证并装订 DMG → `generate_appcast`。产物在 `.build/release/<版本>/`，`.build/release/latest` 指向它。
- 否决：在 release.sh 里自动创建 Developer ID 描述文件（改动开发者账号，决策 15 未覆盖）；把 Sparkle 私钥放进仓库或环境变量（秘密）。

## 验证命令

```bash
scripts/swift-test.sh /tmp/up.xml updateFeeds
scripts/check-release.sh .build/xcode-signed/Build/Products/Debug/Parallux.app   # 期望退出 1
scripts/release.sh 0.1.0 --dry-run
keel verify-red docs/tasks/feat-release.md
keel gate --record docs/tasks/feat-release.md
```

## 证据

RED(swift): 63f01fa updateFeedsResolveByChannel  # D1

- RED 时的失败原文：`updateFeedsResolveByChannel() failed after 0.007 seconds with 5 issues`（桩实现一律返回「未配置」，五条期望 `.feed(…)` 的断言失败）。
- D2 检查器演示（2026-11-19）：对 Apple Development 构建 `/Users/someone/Projects/workspace/parallux/.build/xcode-signed/…/Parallux.app` 运行 `scripts/check-release.sh` 退出 1，一次列出 10 条 FAIL（App 与扩展各：非 Developer ID、无安全时间戳、有 get-task-allow、NE 权限值不带 -systemextension；Info.plist 缺 SUFeedURL、SUPublicEDKey）。尚无符合要求的 Developer ID 构建，所以「退出 0」一侧留给 D6。
- D3：`scripts/release.sh 0.1.0`（无凭据）退出 2，打印 `xcrun notarytool store-credentials parallux --apple-id <Apple ID> --team-id ABCDE12345`。`scripts/release.sh 0.1.0 --dry-run` 退出 0：双架构内核、archive、export、check（因为没有 Developer ID 描述文件，降级为 Apple Development 构建，检查器列出 10 条签名与更新源问题，符合预期；导出的 App 没有 get-task-allow）、DMG（UDZO，127 MB，内含 Sparkle.framework），跳过公证与 appcast。
- D4：不签名构建嵌入 `Sparkle.framework`；feed 为空时启动 App 不崩溃（`open` 后进程常驻，Info.plist 的 SUFeedURL 为空）。
- Sparkle 工具：`scripts/fetch-sparkle.sh` 解出的 `.build/sparkle/bin` 含 generate_keys、generate_appcast、sign_update、BinaryDelta。
GATE: 91b5e4d0b5a6+dirty ok tree:b665ef4c9982 build=0 vet=0 test=0[586p/0f] fmt=0 swift-test=0[81p/0f] apple-build=0 server-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-19)

## 修订

（完成定义无改动。）

- 设计改动（2026-11-19）：开卡时打算用 SPM 包依赖引入 Sparkle。实测 xcodebuild 解析 Sparkle 的二进制产物时无限挂起（`Workspace.BinaryArtifactsManager.download`，进程无网络连接，等在 `…Sparkle_for_Swift_Package_Manager_zip.lock` 上，超过 10 分钟；SwiftPM 命令行同样挂起），而 curl 3 秒就下完同一 URL。改为 `scripts/fetch-sparkle.sh` 下载同一个发布资产、核对钉住的 sha256（与 Sparkle 自己 `Package.swift` 里的 checksum 相同：`4c2e48a3…022a`），解出 `Sparkle.xcframework` 放进 `apple/Frameworks/`（与 Libbox 同处，不入库），工具放 `.build/sparkle/bin`；project.yml 以框架依赖嵌入并签名。下载有 120 秒上限，gate 不会再挂住。

## 交接

- 做了什么：`UpdateFeed` 渠道解析；Sparkle 2.10.1 经 `fetch-sparkle.sh`（sha256 钉住）嵌入 App；`UpdaterModel`（只在有 https feed 与公钥时启动）与设置里的更新区；`check-release.sh` 发布检查器；`release.sh`（双架构、archive、export、检查、公证、DMG、appcast；缺凭据退出 2；`--dry-run`）；`docs/RELEASE.md`；`keel.toml` 的 release 层级步骤。
- 卡在哪：等作者配公证凭据、Sparkle 密钥、更新地址与 Developer ID 描述文件后手测 D6。
- 下一步：右键菜单加「检查更新…」一项（`AppDelegate.swift`，不在本卡范围，见报告）。
