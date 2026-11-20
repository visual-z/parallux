# 中继线路导入链接格式（v1）

`server/install.sh --relay` 安装完成时打印这条链接，App 在「线路 › 添加中继线路」里粘贴它（PLAN 决策 24）。本文是两端唯一的约定；改格式要升 `v`。写法与 `aggregation-server-link.md` 相同，只列出不同之处。

## 格式

```
parallux://relay?v=1&host=<host>&port=<port>&method=<method>&key=<key>#<name>
```

| 部分 | 必需 | 取值 | 说明 |
|---|---|---|---|
| host（URL 的 host 部分） | 是 | 固定为 `relay` | 链接的种类 |
| `v` | 是 | `1` | 格式版本。不认识的版本必须拒绝 |
| `host` | 是 | IPv4、IPv6 或主机名 | Mac 经承载线路到达中继主机的地址，通常是局域网地址。IPv6 不加方括号，`:` 编为 `%3A` |
| `port` | 是 | 1–65535 | 中继主机上 shadowsocks 入站的端口，默认 39100 |
| `method` | 是 | `2022-blake3-aes-128-gcm` | v1 只有这一种；别的取值必须拒绝，不降级 |
| `key` | 是 | 16 字节随机数的**标准** base64，带填充（24 个字符） | sing-box 的 shadowsocks 2022 只接受这种写法：去掉填充或换成 URL 安全字母表都会被拒绝（2026-11-20 回环对拍）。所以 `+`、`/`、`=` 在链接里要百分号编码 |
| fragment `#<name>` | 否 | UTF‑8 文本，百分号编码 | 显示名；缺省用 `host` |

- 查询参数顺序不固定；同名参数出现多次视为无效；未知参数忽略。
- 编码规则：RFC 3986 查询组件，`+` 不表示空格。
- 链接里没有承载线路：哪条物理线路能到这台主机由 App 自己探测，换了网口也不用重新导入。
- 一次可以粘贴多行，每行一条链接。

## 示例

```
parallux://relay?v=1&host=10.0.0.21&port=39100&method=2022-blake3-aes-128-gcm&key=MDEyMzQ1Njc4OWFiY2RlZg%3D%3D#worker-1
```

（示例里的 key 是 `0123456789abcdef` 的 base64，不是真实密钥。）

## 生成的出站

```json
{ "type": "shadowsocks", "tag": "link-relay-<id 前 8 位>", "server": "<host>", "server_port": <port>,
  "method": "<method>", "password": "<key>", "detour": "link-<承载线路的网口>" }
```

tag 同时列进每个聚合出站的 `links` 与 `relays`（`core/aggregate` 的 `Options`）。

## 安全

- key 等同口令：拿到它的人可以经这台主机向它够得着的任何地址发起连接，包括它所在的内网。`parallux-server` 只从文件读 key（`/etc/parallux-server/relay.key`，0600），不写日志；链接只在安装结束时打印一次。
- shadowsocks 2022 校验时间戳：Mac 与中继主机的时钟相差超过 30 秒时握手会被拒绝，表现为这条中继线路「不可用」。两边都开着 NTP 即可。
- 中继主机看得到它代拨的目标地址。走代理节点的流量在节点协议里已经加密；直连流量的内容和从本机直接出去时一样可见。
