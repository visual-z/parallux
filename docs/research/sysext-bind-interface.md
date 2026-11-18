# 系统扩展内绑定非默认网口：实测

卡：`docs/tasks/research-sysext-bind-interface.md`。本文的结论只来自作者在真实线路上跑出的探针结果；实测之前不写结论。

## 方法

- 签名构建装到 /Applications，隧道用示例配置连接（tun 接管默认路由）。
- 主窗口 › 诊断 › 检测线路：扩展经 XPC `probeLinks` 对 `getifaddrs` 列出的每个物理网口（UP、RUNNING、有 IPv4，排除 lo/utun/ipsec/awdl/llw/bridge/anpi/ap/gif/stf）各建一条 TCP：`socket` → `setsockopt(IP_BOUND_IF)` → `connect 1.1.1.1:80`（3 秒上限）→ `GET /cdn-cgi/trace` 取 `ip=`。
- 扩展日志：`log stream --predicate 'subsystem == "io.github.visual-z.parallux.tunnel" AND category == "xpc"'`，每个网口一行 `probe …`。

## 结果

（待作者实测：至少两条线路，贴「拷贝结果」的 JSON 或日志行。）

## 结论

（待实测。）
