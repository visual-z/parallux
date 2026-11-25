---
type: fix
status: doing        # todo | doing | blocked | awaiting-author | done
created: 2026-11-25
weight: light
baseline: HEAD
---

# 系统扩展激活失败时给出误导信息，且本地安装会丢掉可执行位

## 问题

作者装上 0.1.2（Developer ID，未公证）后，界面显示「请将 Parallux 移到「应用程序」文件夹」，但 App 就在
`/Applications` 里。查下来是三件事叠在一起：

1. **错误码表整体错位。** `SystemExtensionErrorText` 的表从 5 开始和 SDK 对不上（`SystemExtensions.h` 里
   5=MissingIdentifier、6=DuplicateIdentifier、7=UnknownCategory、8=CodeSignatureInvalid、9=ValidationFailed、
   10=ForbiddenBySystemPolicy、11=RequestCanceled、12=RequestSuperseded、13=AuthorizationRequired）。
   我们把 8 写成「请将 Parallux 移到「应用程序」文件夹」，而 8 实际是**代码签名无效**；「位置不对」是 3
   （UnsupportedParentBundleLocation）。作者看到的那句是错的，真因被藏起来了。
2. **`build-signed.sh --install` 用 `cp -R` 复制 App**，在当前 umask 077 下把可执行位削成 0700；
   sysextd 日志里出现 `Unexpected value for unix permissions, all executable bits are expected to be set`。
3. 真正的原因见 `docs/tasks/block-dev-release-notarization.md`：Developer ID 签的系统扩展在激活时由
   syspolicyd 查公证票据（`Error checking with notarization daemon: 3`），未公证 → `failed to validate` →
   code 8。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** `SystemExtensionErrorText` 的 1…13 与 SDK 一一对应，8 是「签名无效」、3 是「位置不对」。
  - 检：test `SystemExtensionErrorText` 相关过滤
  - 检：grep `case 8: "代码签名无效"` apple/ParalluxKit/Sources/ParalluxKit/Setup/ActivationMachine.swift
- **D2** `build-signed.sh --install` 复制后主可执行与扩展可执行都是 `0755`（用 `ditto`，保留权限）。
  - 检：cmd `scripts/build-signed.sh --install && ls -l /Applications/Parallux.app/Contents/MacOS/Parallux`
- **D3** gate 全绿。
  - 检：cmd `keel gate`

## 证据

RED: 8cee647 systemExtensionErrorsAreReadable

## 交接

- 做了什么：
- 卡在哪：
- 下一步：
