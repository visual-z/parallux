# 聚合服务器导入链接格式（v1）

`server/install.sh` 安装完成时打印这条链接，App 粘贴它来添加聚合服务器（PLAN 决策 18）。本文是两端唯一的约定；改格式要升 `v`。

## 格式

```
parallux://aggregation-server?v=1&host=<host>&port=<port>&psk=<psk>#<name>
```

| 部分 | 必需 | 取值 | 说明 |
|---|---|---|---|
| scheme | 是 | `parallux` | |
| host（URL 的 host 部分） | 是 | 固定为 `aggregation-server` | 链接的种类；以后别的导入链接用别的 host |
| `v` | 是 | `1` | 格式版本。解析方遇到不认识的版本必须拒绝，不猜 |
| `host` | 是 | IPv4、IPv6 或域名 | 客户端拨号的地址。IPv6 不加方括号，按查询参数规则百分号编码（`:` 编为 `%3A`） |
| `port` | 是 | 1–65535 的十进制整数 | 服务端 multipath 入站的 `listen_port` |
| `psk` | 是 | 至少 16 个字符 | 预共享密钥，与服务端相同。install.sh 生成 32 字节随机数的 base64url（无填充，43 个字符，只含 `A–Z a–z 0–9 - _`），但解析方要按百分号编码解码，不能假设没有特殊字符 |
| fragment `#<name>` | 否 | UTF‑8 文本，百分号编码 | 显示名，例如 `东京%20VPS`；缺省时解析方用 `host` |

- 查询参数的顺序不固定；同名参数出现多次视为无效链接。
- 未知参数忽略（为同一版本内的可选扩展留余地）。
- 编码规则：RFC 3986 查询组件。值里除了非保留字符（`A–Z a–z 0–9 - . _ ~`）以外的字节都要百分号编码；`+` 不表示空格。

## 示例

```
parallux://aggregation-server?v=1&host=203.0.113.24&port=39000&psk=Zq3x0b9Ck2mVv7yQ1nH8sJt4wE6rU5aPxLdFgTiO0Bc#Tokyo%20VPS
parallux://aggregation-server?v=1&host=2001%3Adb8%3A%3A24&port=39000&psk=Zq3x0b9Ck2mVv7yQ1nH8sJt4wE6rU5aPxLdFgTiO0Bc
```

## 生成的 multipath 出站

App 用链接的字段生成客户端出站（字段名照 `core/bond/options.go` 的 `MultipathOutboundOptions`）：

```json
{ "type": "multipath", "tag": "<聚合出站的 tag>", "outbounds": ["<线路出站 tag>", "<线路出站 tag>"],
  "server": "<host>", "server_port": <port>, "psk": "<psk>" }
```

## 安全

- 链接里含 psk，等同口令：install.sh 只在最后一行打印它，不写进日志或别的文件（psk 本身在 `/etc/parallux-server/psk`，权限 0600）。
- multipath 协议本身不加密数据（`core/bond` 上游说明），psk 只用于握手认证与防重放；数据加密靠 leg 上的代理协议或私有链路。
