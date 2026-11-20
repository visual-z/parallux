---
type: feat
status: awaiting-author
weight: full
created: 2026-11-18
baseline: 16e6f1e7529e (gate: test 8p/0f, swift-test 23p/0f)
---

# 配置可以本地、iCloud 云盘、远程订阅三种方式添加、选用、编辑和自动更新

## 来源

PLAN M2「配置（本地 / iCloud / 远程订阅）」；设计稿 v0.2「配置」页与功能对照表（本地、iCloud、远程订阅（自动更新与间隔）、从文件或链接导入、二维码分享与扫描、编辑 JSON）；决策 14 允许在 M1 等手测时推进。SFM 同功能：`Library/Database/Profile.swift`、`ApplicationLibrary/Views/Profile/*`。

## 范围

- **独占：** `apple/ParalluxKit/Sources/ParalluxKit/Profiles/`、对应测试、`apple/Parallux/Profiles/`、主窗口「配置」页、面板开关改用选中的配置。
- **不碰：** 扩展；XPC 协议；`core/`。

## 不变量

- INV-1：配置库的选中项要么为空，要么是库里某个配置的 id；任何操作序列之后都成立 — 检查方式：代码断言（`ProfileStore.checkInvariants`）+ property `anyOperationSequenceKeepsTheSelectionValid`。

## 观测面

- `ProfileStore` 的公开状态（配置列表、顺序、选中项）与磁盘上的 `index.json`；重新打开同一目录后的状态。
- GREEN 被截断的方式：保存失败被吞掉导致「重开」读回的其实是内存里的旧对象——测试每次都新建 store 从磁盘读；删除只改内存不删文件——测试断言内容文件不存在。

## 环境假设

- App 不在沙盒里（project.yml 只开 hardened runtime，2026-11-18 读生成的 entitlements 确认没有 `app-sandbox`），所以 iCloud 云盘里的文件可以直接按路径读，不需要 iCloud 能力或 ubiquity 容器；读时用 `NSFileCoordinator` 触发按需下载。待手测：一个只在云端、本地未下载的文件能读到。
- 远程订阅的内容就是一份 sing-box JSON 配置（SFM 同假设），用 libbox `CheckConfig` 校验后才替换旧内容。
- SFM 的导入链接格式 `sing-box://import-remote-profile?url=…#name` 由 libbox `ParseRemoteProfileImportLink` / `GenerateRemoteProfileImportLink` 生成与解析（libbox 1.14.4 头文件已确认导出）。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** 配置库落盘后重新打开，配置、顺序、种类、远程地址、更新间隔、上次更新时间与选中项都一致。
  - 检：test `aStoreReopensWithTheSameProfilesAndSelection`
- **D2** 删除配置同时删除它的内容文件；删除选中的配置后选中下一个（没有下一个就选上一个，库空则为空）。
  - 检：test `deletingTheSelectedProfileSelectsANeighbour`
- **D3** INV-1 对任意操作序列成立（添加、删除、移动、选中、改名，固定种子 500 轮）。
  - 检：property `anyOperationSequenceKeepsTheSelectionValid`
- **D4** 移动一个配置不改变其他配置的相对顺序。
  - 检：property `movingAProfileKeepsEveryOtherInOrder`
- **D5** 远程订阅只在开启自动更新且距上次更新至少一个间隔时才到期；间隔下限 15 分钟、上限 7 天，越界取边界。
  - 检：test `remoteUpdateIsDueOnlyAfterItsInterval`
- **D6** 远程下载超过大小上限时失败，不写入内容。
  - 检：test `aDownloadLargerThanTheCapIsRejected`
- **D7** 计数只因本卡新测试增加；不弱化既有测试；gate 全绿。
  - 检：cmd `keel gate`
- **D8** 作者手测：主窗口「配置」页能新建本地配置、从文件导入、从链接导入远程订阅、选 iCloud 云盘里的文件；能编辑 JSON 并保存（无效 JSON 有提示且不保存）；能「立即更新」远程订阅；能拷贝导入链接并显示二维码；面板开关用选中的配置连接。
  - 检：author 按「验证命令」里的手测步骤操作

## 设计

- **ParalluxKit/Profiles（纯 Swift，可测）**：`Profile`（id、名称、种类 local / icloud / remote、iCloud 相对路径、远程地址、自动更新、间隔、上次更新）；`ProfileStore`（`@MainActor`，目录 = `~/Library/Application Support/<bundle id>/profiles`，`index.json` + 每个配置一个 `<id>.json`，原子写）；`RemoteUpdate.isDue` 与 `clampInterval` 纯函数；`BoundedDownload.collect` 按字节上限累积（上限常量带 why）。
- **App/Profiles**：`ProfileService` 负责读内容（iCloud 经 `NSFileCoordinator`）、下载远程订阅并用 `LibboxCheckConfig` 校验、到期检查（App 打开期间每 10 分钟查一次）；`ProfilesView` 列表 + 新建表单 + JSON 编辑窗口 + 分享（导入链接、二维码用 CoreImage 生成）。
- 否决：SFM 的 SQLite（GRDB）：配置只有几份，一个 JSON 索引足够且免依赖；iCloud ubiquity 容器：要在开发者账号上新开 iCloud 能力，而非沙盒 App 直接读云盘路径即可。
- 二维码扫描（SFM 有）留到 M5：Mac 上扫码要摄像头权限与 AVFoundation，收益低；`sfm-parity.md` 重判时记一笔。

## 验证命令

```bash
scripts/swift-test.sh /tmp/profiles.xml Profile
keel verify-red docs/tasks/feat-profiles.md
keel gate --record docs/tasks/feat-profiles.md
# 手测（D8）：scripts/build-signed.sh --install 后打开 /Applications/Parallux.app › 主窗口 › 配置
```

## 证据

RED(swift): 6cba9d0 aStoreReopensWithTheSameProfilesAndSelection  # D1
RED(swift): 6cba9d0 deletingTheSelectedProfileSelectsANeighbour  # D2
RED(swift): 6cba9d0 movingAProfileKeepsEveryOtherInOrder  # D4
RED(swift): 6cba9d0 remoteUpdateIsDueOnlyAfterItsInterval  # D5
RED(swift): 6cba9d0 aDownloadLargerThanTheCapIsRejected  # D6

D3 在冻结点上是空 store，不会红；用故障补丁证明：删除选中项时不挪选中、关掉断言，property 必须红。

```diff keel-inject(swift) anyOperationSequenceKeepsTheSelectionValid
--- a/apple/ParalluxKit/Sources/ParalluxKit/Profiles/ProfileStore.swift
+++ b/apple/ParalluxKit/Sources/ParalluxKit/Profiles/ProfileStore.swift
@@ -66 +66 @@
-            selectedID = index < profiles.count ? profiles[index].id : profiles.last?.id
+            _ = index
@@ -112 +112 @@
-        assert(selectedID == nil || profiles.contains { $0.id == selectedID }, "INV-1: selection outside the library")
+        _ = 0
```

- RED 时的失败原文：D1 `Expectation failed: reopened.profiles == [cloud, local, remote]`；D2 `Expectation failed: store.selectedID == c.id`；D4 `Expectation failed: store.profiles.count == 6`；D5 `Expectation failed: RemoteUpdate.isDue(profile, now: now)`；D6 `an error was expected but none was thrown and "0 bytes" was returned`。
GATE: 790fe3f5fa15+dirty ok tree:2341847777a5 build=0 vet=0 test=0[8p/0f] fmt=0 swift-test=0[31p/0f] apple-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-18)

## 修订

（无）

## 交接

- 做了什么：ParalluxKit `ProfileStore`（index.json + 内容文件，INV-1 断言）、到期规则与下载上限；App `ProfileService`（iCloud 协调读取、libbox 校验与格式化、导入链接、10 分钟到期检查）与「配置」页（新建、文件导入、远程订阅、iCloud、编辑 JSON、分享与二维码）；面板开关改用选中的配置。
- 卡在哪：等作者手测 D8。
- 下一步：`feat-core-session`（节点分组、连接、日志、路由模式的数据层）。
