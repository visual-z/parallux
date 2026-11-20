# Parallux

macOS 26+ 上的多线路聚合代理客户端：Wi‑Fi、网线、iPhone 共享一起用，同时走你的 sing-box 订阅。

- **分流**：不同连接分到不同线路，不需要服务器。
- **叠加**：同一条连接拆到多条线路，在你自己的服务器上重组，单线程下载也能叠速。
- **主备**：只走首选线路，掉线自动切换。
- SFM（sing-box 官方 Mac 客户端）的功能全部覆盖。

Parallax（视差）+ flux（通量）；前半也是 parallel，多条线路并行。

## 开发

需要 Xcode 27+、Go 1.25+、XcodeGen、keel（`mise install`）。

```bash
keel gate                  # 全部检查（首次会编 Go 框架，约 90 秒）
scripts/build-apple.sh     # 不签名编译 App 与系统扩展
keel status                # 任务卡看板
```

签名构建：复制 `apple/Config/Local.xcconfig.example` 为 `Local.xcconfig` 并填 Team ID。

工作方式见 [AGENTS.md](AGENTS.md)，设计与决策见 [PLAN.md](PLAN.md)，手测步骤见 [docs/MANUAL-TEST.md](docs/MANUAL-TEST.md)。

## 许可证

[GPLv3](LICENSE)。内核基于 [sing-box](https://github.com/SagerNet/sing-box)（GPLv3，附加条款：衍生作品不得使用它的名称或暗示与它有关联）；其余第三方代码的出处见 [docs/LICENSES.md](docs/LICENSES.md)。
