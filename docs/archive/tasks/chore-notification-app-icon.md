---
type: chore
status: awaiting-author  # todo | doing | blocked | awaiting-author | done
weight: light
created: 2026-11-25
baseline: 007d701
---

# 通知横幅里的 App 图标是空白的

## 问题

作者截图（2026-11-24 13:26，0.1.0）：通知中心里「线路已恢复 / 线路不可用」六条横幅，左侧图标都是系统的空白占位块，
不是 Parallux 的图标。

查到的现状（都在本机实测）：

- Bundle 里有两个图标来源：`Contents/Resources/AppIcon.icns`（actool 由 `apple/AppIcon.icon` 生成）与
  `Assets.car` 里的 `AppIcon`。`Assets.car` 的 rendition 齐全（256/512/1024，1024 那份 735 KB），
  `iconutil` 解开 `.icns` 只有 16/32/128/256 四档，**没有 512 与 1024**。
- `.icns` 里那四档不是空白：16→689 B、32→1.6 KB、128→13 KB、256→42 KB，解出来的平均色是暖色（151/125/118）。
- LaunchServices 记录了图标：`iconName: AppIcon`、`icons: Contents/Resources/AppIcon.icns`、
  `supports-asset-catalog`。
- `NSWorkspace.shared.icon(forFile: "/Applications/Parallux.app")` 画到 256 与 1024 都是真图标（平均色 144/117/110），
  不是占位块。

所以空白不是「没有图标文件」，而是通知横幅那条渲染路径拿不到它要的平面图标：Icon Composer 的 `.icon` 只编进
`Assets.car`，旁路的 `.icns` 在 256 px 处截断，而通知服务要更大的平面 rendition 时没有回退，就画占位块。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** 发布出来的 App 里 `AppIcon.icns` 覆盖 16…1024 全部档位。
  - 检：cmd `scripts/release.sh 0.1.2 --dry-run && iconutil -c iconset .build/release/0.1.2/export/Parallux.app/Contents/Resources/AppIcon.icns -o /tmp/iconchk`
- **D2** 换进去的图标确实是 Parallux 的图案（不是系统占位块）：脚本对渲染结果做暖色判定，不符合就退出 1。
  - 检：cmd `scripts/make-appicon-icns.sh .build/xcode/Build/Products/Debug/Parallux.app /tmp/check.icns`
- **D3** gate 全绿。
  - 检：cmd `keel assert-guard --card docs/tasks/chore-notification-app-icon.md`
- **D4** 作者手测：装上 0.1.2 后触发一次线路掉线/恢复的通知，横幅左侧显示 Parallux 图标。
  - 检：author

## 证据

RED: none 非行为卡：改的是打包步骤（`.icns` 的档位），判据是产物检查（见上）
GATE: f47ed5c66e1f+dirty ok tree:2b990baf1e27 build=0 vet=0 test=0[625p/0f] fmt=0 swift-test=0[182p/0f] apple-build=0 server-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-25)

## 交接

- 做了什么：新增 `scripts/make-appicon-icns.sh`（从 bundle 自身解析出的图标重做 16…1024 的 `.icns`，带暖色哨兵）；
  `release.sh` 在 archive 之后、export 之前替换归档里的 `AppIcon.icns`，export 会重新签名。
- 卡在哪：D4 要作者看一次横幅。
- 下一步：0.1.2 已发（`v0.1.2`），已装到 `/Applications`（build 20261125092600）；作者触发一次通知看横幅图标，确认后改 done。
