# 发布

PLAN 决策 19：签名、公证、打包与 appcast 由 `scripts/release.sh` 完成；**脚本从不上传、不发布**，上传是作者手动的一步。

## 一次性准备

1. **公证凭据**：在 appleid.apple.com 生成 App 专用密码，然后：
   ```bash
   xcrun notarytool store-credentials parallux --apple-id <Apple ID> --team-id ABCDE12345
   ```
   档案名可改，用 `PARALLUX_NOTARY_PROFILE=<名字>` 告诉脚本。
2. **Sparkle 密钥**：`scripts/fetch-sparkle.sh`（每次构建都会跑）把 Sparkle 2.10.1 的工具放在 `.build/sparkle/bin`，运行
   ```bash
   .build/sparkle/bin/generate_keys
   ```
   私钥存进登录钥匙串（不要导出到仓库或环境变量），它打印的公钥填进第 3 步。
3. **更新源**：在 `apple/Config/Local.xcconfig`（不入库）里加
   ```
   PARALLUX_UPDATE_FEED = https:/$()/visual-z.github.io/parallux/appcast.xml
   PARALLUX_UPDATE_BETA_FEED = https:/$()/visual-z.github.io/parallux/appcast-beta.xml
   PARALLUX_UPDATE_PUBLIC_KEY = <generate_keys 打印的公钥>
   ```
   （xcconfig 里 `//` 是注释，所以 URL 要写成 `https:/$()/…`。）只能用 https；地址是建议，见下文「上传」。
4. **Developer ID 描述文件**：系统扩展的 `packet-tunnel-provider-systemextension` 权限在 Developer ID 下需要描述文件。在 developer.apple.com › Certificates, IDs & Profiles › Profiles 新建 **Developer ID**（Distribution）描述文件，App ID 分别选 `io.github.visual-z.parallux` 与 `io.github.visual-z.parallux.tunnel`（辅助服务不需要），再在 Xcode › Settings › Accounts 下载。脚本不会替你创建它（会改动团队账号，决策 15 只授权了 Apple Development）。

## 每次发布

```bash
scripts/release.sh 0.2.0 --dry-run   # 先演练：构建、签名核对、DMG，不公证
scripts/release.sh 0.2.0             # 正式：公证并装订 App 与 DMG，生成 appcast
```

产物在 `.build/release/<版本>/`（`.build/release/latest` 指向最近一次）：

- `Parallux-<版本>.dmg`：已公证、已装订，可以直接分发。
- `appcast/appcast.xml` 与同目录的 DMG：Sparkle 读取的更新源。
- `export/Parallux.app`：`scripts/check-release.sh` 核对过的 App。

缺凭据或描述文件时脚本退出 2，并打印要运行的命令。发布门：`keel gate --tier release` 会对 `.build/release/latest/Parallux.app` 跑 `check-release.sh`。

## 上传（手动，建议做法）

- DMG：上传到 GitHub Releases（`gh release create v0.2.0 .build/release/0.2.0/Parallux-0.2.0.dmg`）。
- appcast：放在 GitHub Pages（`gh-pages` 分支的 `appcast.xml`），地址与第 3 步一致。`generate_appcast` 生成的下载链接指向 appcast 同目录；改用 Releases 时，用 `--download-url-prefix https://github.com/visual-z/parallux/releases/download/v<版本>/` 重新生成。
- 测试版：同样的流程，appcast 写到 `appcast-beta.xml`。

## 更新与系统扩展

Sparkle 只替换 `Parallux.app`。系统扩展由系统独立运行；新版 App 下次连接时提交激活请求，`SystemExtensionInstaller` 在版本号变化时替换扩展（构建号每次都不同）。辅助服务在新版 App 里重新注册。
