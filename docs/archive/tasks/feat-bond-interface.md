---
type: feat
status: awaiting-author
weight: full
created: 2026-11-19
baseline: a2f9bda (gate: test 586p/0f, swift-test 60p/0f)
---

# 聚合服务器页：粘贴导入链接添加服务器，叠加经它生效；诊断页单线程下载测速

## 来源

PLAN M4「叠加出站 + 聚合服务器一键部署；两条真实线路上单连接吞吐达到目标」；决策 17、18；设计稿「聚合服务器」页（服务器列表、带宽、重组后的出口、添加服务器）与诊断页「单线程下载测速」。`feat-bond` 提供内核与服务端，链接格式见 `docs/research/aggregation-server-link.md`。

## 范围

- **独占：** `apple/ParalluxKit/Sources/ParalluxKit/Bond/`、对应测试、`apple/Parallux/Bond/`、主窗口的聚合服务器页、`AppModel` 的 `bondProvider` 赋值处、诊断页的测速区。
- **不碰：** `core/`；`server/`；扩展。

## 观测面

- 纯函数：`AggregationServerLink.parse` 的返回值与错误；`AggregationServer.bond(links:)` 生成的出站；`SpeedTest.summary`。
- 钥匙串：psk 只进 Keychain，`UserDefaults` 里的服务器列表不含 psk（测试读回编码后的字节断言）。
- GREEN 被截断的方式：解析器对所有错误返回同一种失败而测试只看「失败了」——测试逐种断言错误类型。

## 环境假设

- 叠加只有两条 leg（`feat-bond` 报告：上游只支持两条）。三条以上启用线路时，叠加取优先级最高的两条，界面写明。
- 单线程测速经扩展内核：用 libbox command client 的 `startNetworkQualityTest`（头文件已确认，参数 configURL、outboundTag、serial、maxRuntimeSeconds、http3）逐出站测，`outboundTag` 依次为每条线路出站与聚合出站；serial 为 true 即单连接。待手测：该接口在 1.14.4 的扩展里可用。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** 导入链接按 v1 规范解析：host（含 IPv6 解码）、port、psk、名称（缺省用 host）；scheme、种类、版本、端口越界、psk 过短、参数重复各报对应错误；未知参数忽略。
  - 检：test `aggregationServerLinksParseByTheV1Spec`
- **D2** 服务器列表编码后不含 psk；psk 读写经可替换的密钥存储，删除服务器时一并删除。
  - 检：test `serverListsNeverCarryThePSK`
- **D3** 由服务器与启用线路生成的 multipath 出站：`outbounds` 是优先级最高的两条线路出站，带 server、server_port、psk；少于两条线路时为 nil。
  - 检：test `theBondOutboundUsesTheTwoTopLinks`
- **D4** 测速汇总：叠加相对最快单线路的倍数，单线路结果缺失时不给倍数；倍数达到 PLAN 目标（1.6）时标注达标。
  - 检：test `speedTestSummaryComparesBondToTheFastestLink`
- **D5** 计数只因本卡新测试增加；不弱化既有测试；gate 全绿。
  - 检：cmd `keel gate`
- **D6** 作者手测：在 VPS 上跑 `server/install.sh` 得到链接；App 聚合服务器页粘贴添加，延迟显示；选叠加后连接经它；诊断页测速给出每条线路与叠加的单连接速度。
  - 检：author 统一手测

## 设计

- **ParalluxKit/Bond**：`AggregationServer`（id、名称、host、port；psk 不在结构里）、`AggregationServerLink.parse`（`URLComponents` 取 percentEncodedQueryItems 后自行解码，避免 `+` 被当空格）、`SecretStore` 协议（Keychain 实现在 App，测试用内存实现）、`AggregationServerStore`（列表进 UserDefaults）、`SpeedTest`（结果与汇总）。
- **App/Bond**：`KeychainSecretStore`（`kSecClassGenericPassword`，service = bundle id + ".aggregation-server"）；`AggregationServersView`（列表：名称、地址、延迟、在用；添加：粘贴链接；删除；设为叠加服务器）与设计稿里的部署说明（显示 `server/install.sh` 的用法，不内置下载地址，M6 发布后才有）。延迟用 TCP 建连时间（App 进程，测的是到服务器的连通）。
- `AppModel.bondProvider` 在启动时赋值：取 `LinkSettings.bondServerID` 对应服务器与 psk，调用 `bond(links:)`。
- 否决：把 psk 放进 UserDefaults（明文落盘，违反 AGENTS.md「秘密」一条）。

## 验证命令

```bash
scripts/swift-test.sh /tmp/bi.xml AggregationServer
keel verify-red docs/tasks/feat-bond-interface.md
keel gate --record docs/tasks/feat-bond-interface.md
```

## 证据

RED(swift): 1fe59e8 aggregationServerLinksParseByTheV1Spec  # D1
RED(swift): 1fe59e8 serverListsNeverCarryThePSK  # D2
RED(swift): 1fe59e8 theBondOutboundUsesTheTwoTopLinks  # D3
RED(swift): 1fe59e8 speedTestSummaryComparesBondToTheFastestLink  # D4

- RED 时：冻结提交里 `parse` 一律抛 `.notAParalluxLink`、存储不落盘、`bond` 返回 nil、`summary` 返回 nil，四条测试全部失败。
- 测速单位：libbox `NetworkQualityResult.downloadCapacity` 是比特每秒（sing-box `cmd_api_networkquality.go` 用 `FormatBitrate` 显示它，2026-11-19 读源码确认），换成字节每秒除以 8。
GATE: 1fe59e864437+dirty ok tree:6695b6cf98f4 build=0 vet=0 test=0[586p/0f] fmt=0 swift-test=0[64p/0f] apple-build=0 server-build=0 boundaries=0 docs=0 cards=0 freeze=0 guard=0 (2026-11-19)

## 修订

（完成定义无改动。）

- 流程记录（2026-11-19）：合入 `feat-bond` 分支后，在 a2f9bda 给 `core/pxbridge/register.go` 加了 `core/bond` 的 import，并加了 `TestTheComposedBondProfilePassesLibboxCheckConfig`。这是行为改动（框架开始认 multipath 类型），但没有先开卡，是流程疏漏；它是本卡叠加接入的前提，归在本卡下。该测试在加 import 之前会因 `unknown outbound type: multipath` 失败（2026-11-19 对拍过，见 `feat-links-aggregate` 证据）。

## 交接

- 做了什么：v1 导入链接解析；服务器列表进 UserDefaults、psk 进钥匙串；叠加出站取优先级最高的两条线路；聚合服务器页（添加、延迟、设为叠加、删除、部署说明）；诊断页单线程测速与达标判断。
- 卡在哪：等统一手测 D6（需要一台 VPS）。
- 下一步：合入辅助服务分支；M5 打磨。
