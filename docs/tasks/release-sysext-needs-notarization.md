---
type: release
status: blocked
reason: 本机没有公证凭据（Apple ID + App 专用密码或 App Store Connect API Key），无法为 Developer ID 版装订票据
weight: light
created: 2026-11-25
---

# Developer ID 版装得上、但系统扩展激活不了（没有公证）

## 问题

0.1.2 的 DMG（Developer ID 签名、未公证）装到 `/Applications` 后，扩展激活失败，界面按当时的错误码表显示
「请将 Parallux 移到「应用程序」文件夹」——位置是对的，真正的原因被那张错表盖住了
（错表已由 `docs/tasks/fix-sysext-error-text.md` 修掉）。

本机证据（2026-11-25 17:44–17:49）：

- `spctl -a -vvv -t exec /Applications/Parallux.app` → `rejected, source=Unnotarized Developer ID`；
  扩展 bundle 同样被拒。
- `syspolicyd`：`looking up ticket: …` → `Error checking with notarization daemon: 3`（查不到公证票据）。
- `sysextd`：`advancing state from staging to validating` → `extension failed to validate! uninstalling...`。
- 应用侧拿到 `OSSystemExtensionErrorDomain` code 8（`CodeSignatureInvalid`，`SystemExtensions.h`）。
- 对照组：同一棵树用 Apple Development 证书签名（`scripts/build-signed.sh --install`），扩展
  `[activated enabled]`，说明 bundle 结构、权限、entitlements 都没问题，差的只是公证。

Apple 的说法（`docs/research` 未收，见 https://developer.apple.com/documentation/driverkit/debugging-and-testing-system-extensions）：
Xcode 的正常开发流程不会公证 App 与系统扩展，所以开发期要关掉校验；反过来说，Developer ID 分发版
必须公证，否则激活时会被 Gatekeeper 的相关检查拒掉。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** 公证凭据存进钥匙串，`xcrun notarytool history` 能列出记录。
  - 检：cmd `xcrun notarytool history --keychain-profile parallux`
- **D2** 重发的 Developer ID 版能通过 Gatekeeper：`spctl -a -vvv -t exec` 对 App 与扩展都返回 accepted。
  - 检：cmd `scripts/release.sh 0.1.3 --dry-run && spctl -a -vvv -t exec .build/release/0.1.3/export/Parallux.app`
- **D3** 装上该版本后扩展 `[activated enabled]`，作者测速/开关一次。
  - 检：cmd `systemextensionsctl list | grep parallux`
  - 检：author

## 证据

RED: none 发版阻塞项：判据是产物与系统状态检查，行为代码不在此卡

## 卡在哪

本机没有公证凭据：

- `xcrun notarytool history --keychain-profile parallux` → `No Keychain password item found for profile: parallux`
- `security find-generic-password -s com.apple.gke.notary.tool` → 找不到
- `~/.appstoreconnect/private_keys` 不存在

作者需要提供一种凭据（Apple ID + App 专用密码，或 App Store Connect API Key `.p8` + issuer/key id），
存进钥匙串后 `scripts/release.sh` 才能公证 + 装订。

## 影响

`v0.1.1`、`v0.1.2` 两个 release 的 DMG 在任何 Mac 上都激活不了系统扩展，等于不可用。在补上公证之前
不要再发新的 Developer ID 版本；本机测试用 `scripts/build-signed.sh --install`（Apple Development）。

## 下一步

1. 作者给出公证凭据 → `xcrun notarytool store-credentials parallux --apple-id … --team-id ABCDE12345`。
2. 补 `scripts/check-release.sh`：Developer ID 版必须能 `spctl -a -t exec` 通过（装订过票据），否则判失败——
   这条检查本身就是「装了也激活不了」的机械判据（待开卡，先确认公证可用，否则检查永远红）。
3. 决定已发的两个 pre-release 是撤回还是留档说明。
