# 第三方出处登记

本项目整体 GPLv3。引用的代码、思路与资产在这里登记（AGENTS.md「Never」最后一条）。

| 出处 | 许可 | 用在哪 | 怎么用的 |
|---|---|---|---|
| sing-box v1.14.4 `experimental/libbox` | GPLv3 | `apple/Frameworks/Libbox.xcframework` | 依赖，gomobile 绑定 |
| sing-box fork `visual-z/sing-box` 分支 `parallux/v1.14.4` | GPLv3 | `go.mod` replace | 上游加一个注册钩子提交（决策 10） |
| `SagerNet/sing-box-for-apple` | GPLv3（附加条款：衍生品不得使用其名称或暗示关联） | `apple/Config/Base.xcconfig` 的版本化 Mach 服务名；计划中的 XPC 通路与辅助服务 | 目前只借鉴做法，未拷代码；拷贝时逐文件登记 |
| sing-box v1.14.4 `cmd/internal/build_libbox` | GPLv3 | `scripts/build-core.sh` | 照搬构建标签与链接参数 |
| `sagernet/gomobile` v0.1.12 | BSD-3-Clause | `scripts/build-core.sh` | 构建工具 |
| `sing-box-mygo`（同一作者的旧 Parallux）`internal/redact` | GPLv3 | `core/internal/redact` | 原样拷贝（2026-11-18） |
| `sing-box-mygo` `reference/` | GPLv3（源自 sing-box） | `reference/` | 原样拷贝：官方 daemon proto 与配置 schema |
| `sing-box-mygo` `docs/research/sfm-feature-matrix.md`、`docs/tasks/parity.md` | GPLv3 | `docs/research/` | 拷贝后加注：状态待重判 |
| `WuSiYu/singbox-multipath` | 待确认（GitHub 未识别许可证） | 计划用于 M4 叠加出站 | 尚未引用；引用前确认许可证 |
