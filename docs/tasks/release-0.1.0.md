---
type: release
status: doing        # todo | doing | blocked | awaiting-author | done
weight: full
gate: release
created: 2026-11-20
baseline: d63daf464b7b
---

# 0.1.0 作为第一个预发布版公开，之后的版本能经 Sparkle 更新到它上面

## 来源

作者 2026-11-20：看看 Sparkle 更新有没有接好，接好就发布第一个版本，并把发布版装到作者的电脑上。同一天作者选定：公证用钥匙串里已有的 `horizyn-releases` 凭据；Developer ID 描述文件让 Xcode 自动创建；版本号 0.1.0，在 GitHub 上标为预发布。

检查的结果是 App 里的接线是好的（`UpdaterModel`：构建带了 https 更新源和公钥就启用），发布这一侧从来没有真正跑通过，有四处要改：

1. Developer ID 模式下脚本要求手工建描述文件，并用手动签名却没有指定描述文件，跑不起来。
2. 检查 Sparkle 密钥时不看账户名，会把钥匙串里别的项目的密钥当成自己的；生成 appcast 时也没指定账户。
3. 更新源和公钥只能写在不入库的 `Local.xcconfig` 里，换一台机器就发不出同样的包。
4. appcast 里的下载地址指向 appcast 同目录，而安装包实际放在 GitHub Releases。

## 范围

- **独占：** `scripts/release.sh`；`docs/RELEASE.md`；本卡；PLAN 决策 26。
- **不碰：** App 里的更新逻辑（`UpdaterModel`、`UpdateFeed`）；`scripts/check-release.sh` 的判据；日常的 `build-signed.sh`；Sparkle 的版本。

## 观测面

- `scripts/release.sh 0.1.0` 的退出码；`scripts/check-release.sh` 对导出的 App 的退出码（gate 的 release 层）。
- `spctl` 对 App 与 DMG 的判定；`xcrun stapler validate` 的退出码。
- appcast 的内容（版本、下载地址、签名）与公开地址的 HTTP 状态码。
- 本机：`/Applications/Parallux.app` 的版本与签名，`systemextensionsctl list`，连通性。
- GREEN 可能被截断的方式：脚本在缺凭据时提前退出 2，容易被当成「没出错」——只认退出 0 加上产物逐项核对。appcast 生成工具找不到密钥时也可能生成没有签名的条目——单独断言 `sparkle:edSignature` 存在，并用公钥验签。

## 环境假设

2026-11-20 在本机对拍：

- Xcode 27.2 的 `xcodebuild -exportArchive`（`method = developer-id`、`signingStyle = automatic`、`-allowProvisioningUpdates`）对一份用开发签名归档的包：导出成功；App、系统扩展、小组件、辅助服务都是 `Developer ID Application` 签名；三处网络扩展权限都被改写成 `packet-tunnel-provider-systemextension`；签名里有 `application-identifier` 与 `team-identifier`；Sparkle 的框架、两个 XPC 服务、Autoupdate、Updater.app 都带硬化运行时与安全时间戳；`check-release.sh` 只剩更新源与公钥两条（那份归档本来就没带）。Apple 工程师的说法是 Xcode 26 及更早不会改写这个权限（developer.apple.com/forums/thread/737894），所以脚本靠导出后的 `check-release.sh` 把关，不假设 Xcode 版本。
- `xcrun notarytool history --keychain-profile horizyn-releases` 退出 0。它与签名证书是否同一个团队没有单独核对；不是同一个团队时公证会失败，脚本会报出来。
- `generate_keys --account <账户>`、`generate_appcast --account … --download-url-prefix …` 的参数名取自工具的 `--help` 与 Sparkle 2.x 源码。
- **未证实：**
  - 已装着开发签名版本的机器换成 Developer ID 版本后，系统扩展是否需要在系统设置里重新批准。D6 在本机实测。
  - Sparkle 从 0.1.0 更新到下一个版本的全过程。只有一个版本时测不了；要等 0.1.1。
  - 没有在一台没装过 Parallux 的机器上从 DMG 安装过。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** `scripts/release.sh 0.1.0` 退出 0：双架构、Developer ID 签名、App 与 DMG 都已公证并装订；`check-release.sh` 通过。
  - 检：cmd `keel gate --tier release`
- **D2** Gatekeeper 接受：App 判为 `Notarized Developer ID`，DMG 的装订票据有效。
  - 检：cmd `spctl -a -vv -t exec .build/release/0.1.0/export/Parallux.app`
  - 检：cmd `xcrun stapler validate .build/release/0.1.0/Parallux-0.1.0.dmg`
- **D3** appcast 里 0.1.0 的条目带 `sparkle:edSignature`，下载地址是 GitHub Releases 上 v0.1.0 的 DMG；用 Parallux 自己的公钥对 DMG 验签通过，而且这把公钥就是 App 的 `SUPublicEDKey`。
  - 检：cmd `.build/sparkle/bin/sign_update --verify`（参数见验证命令）
- **D4** 公开可取：GitHub 上有标为预发布的 v0.1.0 与 DMG；App 里写的更新源地址返回 200，内容就是 D3 的 appcast；appcast 里的下载地址返回 200。
  - 检：cmd `curl -fsSIL`（参数见验证命令）
- **D5** 脚本不再把别的项目的 Sparkle 密钥当成自己的：指定账户下没有密钥时退出 2 并说明要运行什么。
  - 检：cmd `PARALLUX_SPARKLE_ACCOUNT=no-such-account scripts/release.sh 0.1.0`（期望退出 2）
- **D6** 作者的电脑上装的是 0.1.0 发布版：`/Applications/Parallux.app` 版本 0.1.0、Developer ID、已公证；系统扩展是同一个构建并已启用；能上网。
  - 检：cmd `spctl -a -vv -t exec /Applications/Parallux.app`
  - 检：author 设置 › 通用 › 更新：显示更新渠道，点「检查更新」提示已是最新
- **D8** 公证的提交没有完成（上传中断、等待超时）时脚本重试，最多 3 次，两次之间停顿；公证服务给出结论（非 Accepted）时不重试，报出结论；3 次都没完成时退出并说明；每次提交的输出都留在日志里。
  - 检：cmd `scripts/test-release-notarize.sh`
- **D7** gate 全绿，测试计数不变（Go 625、Swift 179）。
  - 检：cmd `keel gate --tier release`

## 设计

- **归档用开发签名，导出时换成 Developer ID。** 这是 Apple 给系统扩展定的流程；Xcode 27 的导出会自己改写权限后缀并创建它托管的描述文件。否决：手工建描述文件再手动签名（原脚本的路，要作者每次换机器都去网站操作）；归档后自己逐个重签（Xcode 26 时代的做法，七八条 codesign，顺序错一处就公证失败）。`check-release.sh` 在导出后把关，所以换到不改写后缀的旧 Xcode 上会明确失败，而不是发出一个装不上的包。
- **更新源与公钥在发布时由脚本传给构建，不靠 `Local.xcconfig`。** 更新源是脚本里的默认值（可用环境变量覆盖），公钥在发布时从钥匙串按账户读出来。这样公钥永远和签 appcast 的私钥是一对，不会出现「包里的公钥是旧的」。日常的开发构建仍然两者皆空，不检查更新。
- **Sparkle 密钥按账户取。** 账户名用 bundle id（`io.github.visual-z.parallux`）。Sparkle 的文档说一把密钥可以给所有 App 用；分开的理由是一把密钥泄露或丢失时只影响一个 App。
- **appcast 放 GitHub Pages，安装包放 GitHub Releases。** `generate_appcast --download-url-prefix` 指向该版本的 Release。先发 Release 再推 appcast，否则更新源里的下载地址会有一段时间是 404（Ice、Maccy 等项目的通行做法；MacPacker 踩过这个顺序的坑）。测试版更新源（`appcast-beta.xml`）这次放同一份内容，免得切到测试版渠道的人拿到 404。
- **上传仍然不在脚本里**（决策 19）：这次由我按 `docs/RELEASE.md` 的步骤手工执行，作者已要求发布。
- **预发布**：GitHub 上标 Pre-release，发布说明写明哪些功能还没有在真实线路上测过。

## 验证命令

```bash
PARALLUX_NOTARY_PROFILE=horizyn-releases scripts/release.sh 0.1.0
spctl -a -vv -t exec .build/release/0.1.0/export/Parallux.app
xcrun stapler validate .build/release/0.1.0/Parallux-0.1.0.dmg
.build/sparkle/bin/sign_update --verify --account io.github.visual-z.parallux .build/release/0.1.0/Parallux-0.1.0.dmg "<appcast 里的 edSignature>"
curl -fsSIL https://visual-z.github.io/parallux/appcast.xml
keel gate --tier release --record docs/tasks/release-0.1.0.md
```

## 证据

RED: none 发布卡：改的是发布脚本与文档，判据是真实跑出来的产物

## 修订

- D8（冻结之后加的判据，只加严）：第二次正式构建（2026-11-20）里 App 公证通过，DMG 的上传在 `HTTPClientError.connectTimeout` 上中断，脚本退出 1，前面二十多分钟的构建作废。这是传输失败，不是公证服务的结论。改为有上限的重试（3 次、间隔 20 秒、每次等待最多 30 分钟，都是假设值，理由写在脚本里），结论不重试。`scripts/test-release-notarize.sh` 把脚本里的函数原样切出来，用假的 notarytool 跑七种情形；加它时先把函数改坏四处（不重试、对结论也重试、有结论就算通过、不停顿），四次它都红。它没有接进 gate，由作者定。
- D7 里的测试计数「Go 625、Swift 179」是开卡时的数。开卡之后 `fix-route-modes` 与 `fix-overview-responsive` 两张卡各自加了测试，现在是 Go 627、Swift 191；本卡自己没有增减测试。按冻结规则 D7 的文字没有改。
- 第一次正式构建（提交 `24eef98`）全程通过，但它不含之后的修复，没有发布；那次的产物已被第二次覆盖。

## 交接

开卡。下一步：改 `scripts/release.sh`，跑正式发布，核对产物，发布到 GitHub，装到本机。
