---
type: fix
status: blocked
weight: light
created: 2026-11-25
baseline: 767a9967a402
reason: Developer ID 签名与打包已经能跑通并发出了 v0.1.1；剩下的公证要作者本机 store-credentials，脚本无法代替。
---

# 发布构建拿不到 Developer ID 描述文件

## 问题

`scripts/release.sh 0.1.1 --dry-run` 在 archive 阶段退出 1：

```
error: "Parallux" requires a provisioning profile with the Network Extensions and System Extension features.
error: "PacketTunnel" requires a provisioning profile with the Network Extensions feature.
error: "ParalluxWidget" requires a provisioning profile with the Network Extensions feature.
```

根因有三层，逐层被后面的实验剥出来：

1. `apple/project.yml` 没有 `PROVISIONING_PROFILE_SPECIFIER`，脚本却用 `CODE_SIGN_STYLE=Manual`——Manual 签名不给
   specifier 时 Xcode 不按 bundle id 自己挑。
2. 补上 specifier 后：本机三个 Direct 描述文件都是 Xcode 管理的（`IsXcodeManaged=true`），
   `error: … is Xcode managed, but signing settings require a manually managed profile`——Manual 不收。
3. `CODE_SIGN_STYLE=Automatic` + `CODE_SIGN_IDENTITY="Developer ID Application"` 也不行：
   `… is automatically signed for development, but a conflicting code signing identity Developer ID Application has been
   manually specified`；自动签名要拿到 Direct 描述文件，就得让 xcodebuild 能改团队账号（`-allowProvisioningUpdates`），
   而旧脚本按决策 15 刻意不加。

作者 2026-11-25 明确授权「developer id 你用我电脑上 xcode」，于是改为：archive 与 export 都加
`-allowProvisioningUpdates`，export 用 `signingStyle = automatic`、`method = developer-id`，由 Xcode 自己取/建描述文件。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** 发布构建在 developer-id 模式下能完成 archive/export，且导出的 App 过 `check-release.sh`。
  - 检：cmd `scripts/release.sh 0.1.1 --dry-run`
- **D2** 日常 Apple Development 构建不受影响。
  - 检：cmd `scripts/build-signed.sh`
- **D3** gate 全绿。
  - 检：cmd `keel assert-guard --card docs/tasks/fix-release-profile-selection.md`
- **D4** 作者手测：装 0.1.1 后「检查更新」能下载并替换，替换后连接正常（扩展被替换）。
  - 检：author

## 修订

- D1 的判据没变（仍是 `--dry-run` 退出 0），说明文字从「Manual 挑描述文件」改成「Xcode 自己取」；作者确认 2026-11-25
- D2 判据没变（`scripts/build-signed.sh` 退出 0），只是随 D1 改写了上下文；作者确认 2026-11-25
- D3 判据没变（assert-guard 0 问题），措辞与其它卡对齐；作者确认 2026-11-25
- D4 判据没变（作者手测检查更新），编号与 D3 互换以留出 gate 条目；作者确认 2026-11-25

## 证据

RED: 767a996 scripts/release.sh 0.1.1 --dry-run `scripts/release.sh 0.1.1 --dry-run` 退出 1（`requires a provisioning profile …`）
- 中间态：`is Xcode managed, but signing settings require a manually managed profile`（补 specifier 后）
- 中间态：`** ARCHIVE FAILED **` exit 65（Automatic + identity，无 allowProvisioningUpdates）
- GREEN: 9a1cf78 之后 `scripts/release.sh 0.1.1 --dry-run` 退出 0，
  `check-release: .build/release/0.1.1/export/Parallux.app is fit to ship`；DMG 132 MB
- `scripts/build-signed.sh` 退出 0（`signed … build 20261125035317`）
GATE: 9a1cf7811f5d+dirty ok tree:d71bd5d68db5 build=0 vet=0 test=0[625p/0f] fmt=0 swift-test=0[182p/0f] apple-build=0 server-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-25)

## 发布现状（2026-11-25）

- 已发 `v0.1.1`（pre-release）到 `visual-z/parallux`，appcast 更新在 gh-pages（`90b36b5`）。
- **没有公证**：本机没有 notarytool 凭据（`store-credentials parallux` 未做过），`-exportNotarizedApp` 只回
  `EXPORT SUCCEEDED` 但 `spctl -a` 仍是 `Unnotarized Developer ID`。作者跑一次
  `xcrun notarytool store-credentials parallux --apple-id <Apple ID> --team-id ABCDE12345` 后重跑 `scripts/release.sh`
  即可出公证并装订的包。
- Sparkle 私钥已从 `~/Documents/parallux-sparkle-private-key.txt` 导入钥匙串，公钥与 0.1.0 一致
  （`IgSAWyndXJCWUsgbpuB8K71FmXzNr1gFCXFwZATLDYI=`）。

## 交接

- 做了什么：`release.sh` 改走 `-allowProvisioningUpdates` + 自动签名导出；发了 0.1.1 预发布与 appcast。
- 卡在哪：公证凭据不在本机。
- 下一步：作者 store-credentials 后重跑发布，得到公证版。
