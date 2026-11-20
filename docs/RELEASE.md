# 发布

PLAN 决策 19 与 26：签名、公证、打包与 appcast 由 `scripts/release.sh` 完成；**脚本从不上传、不发布**，上传是手动的一步。

## 一次性准备

1. **Developer ID 证书**：Xcode › Settings › Accounts › Manage Certificates 里要有 `Developer ID Application`。
2. **公证凭据**：在 appleid.apple.com 生成 App 专用密码，然后：
   ```bash
   xcrun notarytool store-credentials parallux --apple-id <Apple ID> --team-id <团队 ID>
   ```
   已经有别的档案可用时，用 `PARALLUX_NOTARY_PROFILE=<名字>` 告诉脚本。
3. **Sparkle 密钥**：`scripts/fetch-sparkle.sh`（每次构建都会跑）把 Sparkle 2.10.1 的工具放在 `.build/sparkle/bin`，运行
   ```bash
   .build/sparkle/bin/generate_keys --account io.github.visual-z.parallux
   ```
   私钥存进登录钥匙串。脚本只认这个账户下的密钥（钥匙串里别的 App 的 Sparkle 密钥不算），发布时从它读出公钥写进 App，所以包里的公钥和签 appcast 的私钥总是一对。**把私钥备份到仓库之外的安全地方**（`generate_keys --account … -x <文件>`）：丢了它，已经装出去的版本就再也收不到更新。
4. **描述文件不用手工建。** 归档用 Apple Development 签名，导出时由 Xcode 换成 Developer ID 签名、把网络扩展权限改成 `-systemextension` 的写法，并在团队账号里创建它托管的 Developer ID 描述文件（App、系统扩展、小组件各一份；决策 26）。这需要 Xcode 27 或更新；更早的 Xcode 不会改写权限，脚本会在 `check-release.sh` 一步失败。

更新源地址与下载地址是脚本里的默认值（GitHub Pages 与 GitHub Releases），需要时用环境变量改，见 `scripts/release.sh` 开头。它们会写进 App，所以属于发布本身，不放在不入库的 `Local.xcconfig` 里。

## 每次发布

```bash
scripts/release.sh 0.2.0 --dry-run   # 先演练：构建、签名核对、DMG，不公证
scripts/release.sh 0.2.0             # 正式：公证并装订 App 与 DMG，生成 appcast
```

产物在 `.build/release/<版本>/`（`.build/release/latest` 指向最近一次）：

- `Parallux-<版本>.dmg`：已公证、已装订，可以直接分发。
- `appcast/appcast.xml`：Sparkle 读取的更新源，条目已用上面的密钥签名，下载地址指向 GitHub Releases 上这个版本的 DMG。
- `export/Parallux.app`：`scripts/check-release.sh` 核对过的 App。

缺凭据时脚本退出 2，并打印要运行的命令。发布门：`keel gate --tier release` 会对 `.build/release/latest/Parallux.app` 跑 `check-release.sh`。

## 上传（手动）

脚本从不上传。顺序不能反：先有 Release，再更新 appcast，否则更新源里的下载地址会有一段时间是 404。

1. 打标签并推送：`git tag v0.2.0 && git push origin v0.2.0`。
2. 发 Release：`gh release create v0.2.0 .build/release/0.2.0/Parallux-0.2.0.dmg --title "Parallux 0.2.0" --notes-file <说明>`（预发布加 `--prerelease`）。
3. 更新 appcast：把 `.build/release/0.2.0/appcast/appcast.xml` 提交到 `gh-pages` 分支的根目录并推送；GitHub Pages 从这个分支发布，地址是 `https://visual-z.github.io/parallux/appcast.xml`。
4. 测试版：流程相同，appcast 提交为 `appcast-beta.xml`。稳定版发布时也把同一份内容写进 `appcast-beta.xml`，免得选了测试版渠道的人落在旧版本上。
5. 核对：`curl -fsSIL` 更新源地址与 appcast 里的下载地址，两个都要是 200。

`generate_appcast` 每次只写当前这个版本的条目。Sparkle 只需要最新的一条，所以更新源里不保留旧版本。

## 更新与系统扩展

Sparkle 只替换 `Parallux.app`。系统扩展由系统独立运行；新版 App 下次连接时提交激活请求，`SystemExtensionInstaller` 在版本号变化时替换扩展（构建号每次都不同）。辅助服务在新版 App 里重新注册。
