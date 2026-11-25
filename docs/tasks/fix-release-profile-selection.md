---
type: fix
status: blocked       # todo | doing | blocked | awaiting-author | done
reason: the Developer ID profiles on this Mac are Xcode managed, which manual signing refuses; notary credentials and the Sparkle private key are not on this Mac either. See 卡在哪.
weight: light
created: 2026-11-25
baseline: 767a9967a402
---

# 发布构建选不到 Developer ID 描述文件

## 问题

`scripts/release.sh 0.1.1 --dry-run`（本机，2026-11-24 14:21）在 archive 阶段退出 1：

```
error: "Parallux" requires a provisioning profile with the Network Extensions and System Extension features.
error: "PacketTunnel" requires a provisioning profile with the Network Extensions feature.
error: "ParalluxWidget" requires a provisioning profile with the Network Extensions feature.
```

三个 App ID 的 Direct 描述文件本机都在，缺的是把描述文件交给 xcodebuild：
`apple/project.yml` 没有 `PROVISIONING_PROFILE_SPECIFIER`，`scripts/release.sh` 的 developer-id 分支只给了
`CODE_SIGN_STYLE=Manual` 与 `CODE_SIGN_IDENTITY`——Manual 签名不给 specifier 时 Xcode 不按 bundle id 自己挑。

补上 specifier 后**暴露出真正的原因**（14:48）：

```
error: Provisioning profile "Mac Team Direct Provisioning Profile: io.github.visual-z.parallux" is Xcode managed,
       but signing settings require a manually managed profile.
```

本机这三个 Direct 描述文件都是 Xcode 自动创建的（`IsXcodeManaged=true`，2026-11-20 09:26），
而 Manual 签名只接受 developer.apple.com 下载的、非 Xcode 管理的描述文件。
`CODE_SIGN_STYLE=Automatic` 也走不通：identity 换成 Developer ID 时报
`Parallux is automatically signed for development, but a conflicting code signing identity Developer ID Application
has been manually specified`——自动签名要拿到 Direct 描述文件，就得让 Xcode 去改团队账号（`-allowProvisioningUpdates`），
决策 15 没授权，脚本也刻意不加。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** 发布构建在 developer-id 模式下能完成 archive/export，且导出的 App 过 `check-release.sh`。
  - 检：cmd `scripts/release.sh 0.1.1 --dry-run`（退出 0；developer-id 模式下 check 失败会让脚本退出 1，所以退出 0 即表示检查通过）
- **D2** 日常 Apple Development 构建不受影响：三个 specifier 变量为空时等于没有设置。
  - 检：cmd `scripts/build-signed.sh`（退出 0）
- **D3** gate 全绿；测试计数只因本卡新增的测试而增加，既有测试没有被弱化。
  - 检：cmd `keel assert-guard --card docs/tasks/fix-release-profile-selection.md`
- **D4** 作者手测：配好凭据后 `scripts/release.sh 0.1.1` 产出公证并装订的 DMG 与 appcast，发布后「检查更新」可用。
  - 检：author

## 证据

- RED: 767a996 `scripts/release.sh 0.1.1 --dry-run` 退出 1，`error: "Parallux" requires a provisioning profile …`
- 实现后（未绿）：退出 1，`is Xcode managed, but signing settings require a manually managed profile`
- 自动签名分支（手工 xcodebuild）：`exit=65`，`** ARCHIVE FAILED **`，四条 `conflicting provisioning settings`

## 卡在哪

描述文件是 Xcode 管理的，Manual 签名不收；只有作者能做的那一件事能解开：

1. developer.apple.com › Profiles 新建 **Developer ID**（Distribution）描述文件，App ID 选
   `io.github.visual-z.parallux`、`.widget`、`.tunnel`，下载后在 Xcode 里导入（这样 `IsXcodeManaged` 为假）；
2. 或者明确授权 `scripts/release.sh` 用 `-allowProvisioningUpdates` 让 Xcode 自己创建（会改团队账号，决策 15 未授权）；
3. 另外两项凭据也不在本机：`xcrun notarytool store-credentials parallux --apple-id <Apple ID> --team-id ABCDE12345`；
   Sparkle 私钥（0.1.0 的公钥是 `IgSAWyndXJCWUsgbpuB8K71FmXzNr1gFCXFwZATLDYI=`，私钥不在本机钥匙串，只有 `dev.horizyn.app` 那条）。

## 交接

- 做了什么：`project.yml` 三个 target 加 `PROVISIONING_PROFILE_SPECIFIER`（取自 `Base.xcconfig` 的三个空变量），
  `release.sh` 按 bundle id 从本机挑 Direct 描述文件并传进去；`Local.xcconfig` 补了 feed 与 0.1.0 的公钥。
- 卡在哪：本机描述文件都是 Xcode 管理的，Manual 签名拒收；公证凭据与 Sparkle 私钥也不在本机。
- 下一步：作者做上面 1（或 2）+ 3，然后跑 D1、D4，发布 0.1.1。
