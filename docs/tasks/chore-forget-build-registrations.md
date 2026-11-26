---
type: chore
status: doing       # todo | doing | blocked | awaiting-author | done
weight: light
created: 2026-11-26
baseline: d66e74f
---

# 构建脚本不再让 LaunchServices 记住构建产物

## 问题

2026-11-26：通知左侧是空白方块，而 `/Applications/Parallux.app`（11-25 17:55 装的）里已经有 1024 px 图标。
LaunchServices 里同一个 bundle ID `io.github.visual-z.parallux` 登记了 27 份：`.build/xcode`、`.build/xcode-signed`、
`.build/xcode-release`、release 的 archive 与 export、旧 worktree 里的同样产物。多数是加大图标之前的构建。
通知中心按 bundle ID 取图标，未必取到 `/Applications` 那份。每次构建都会多登记一份，所以会一直累积。

作者同意：清掉现有登记（已做，见 `docs/tasks/fix-link-alerts-single-line.md` 的证据），并让脚本构建后注销自己的产物。

做法：`scripts/env.sh` 加 `forget_build <路径…>`（`lsregister -u`，不删文件）；`build-apple.sh`、`build-signed.sh`、`release.sh`
在用完产物之后对各自的构建目录调用它。`/Applications` 里的那份照常登记（系统在复制、打开时登记）。

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** 跑完 `scripts/build-apple.sh` 与 `scripts/build-signed.sh` 后，LaunchServices 里该 bundle ID 没有任何 `.build/` 下的路径。
  - 检：cmd `scripts/build-apple.sh && scripts/build-signed.sh && ! lsregister -dump | grep -E '^path:.*/\.build/.*Parallux\.app'`
- **D2** `scripts/release.sh <版本>` 跑完后，`.build/release/<版本>/` 与 `.build/xcode-release/` 下的 App 都不在 LaunchServices 里。
  - 检：cmd `! lsregister -dump | grep -E '^path:.*/\.build/(release|xcode-release)/.*Parallux\.app'`
- **D3** gate 全绿；测试计数不变。
  - 检：cmd `keel assert-guard --card docs/tasks/chore-forget-build-registrations.md`

## 证据

RED: none 构建脚本的清理步骤，判据是系统状态检查，产品行为代码不在此卡

## 交接
