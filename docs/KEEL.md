# keel 手册

`keel` 是工作区的可信内核：它从 git 和真实退出码重新推出卡上的每一条声明，不采信叙述。
它是一个没有运行时依赖的静态二进制，和项目用什么语言无关；技术栈相关的知识全在 `keel.toml` 里。
源码与发布：[github.com/visual-z/keel](https://github.com/visual-z/keel)。

## 安装与版本

每个仓库在 `keel.toml` 里钉住 keel 的版本。PATH 上的 keel 版本与钉住的不同时，它会改为运行钉住的版本，做法同 `GOTOOLCHAIN=auto` 与 bazelisk：先在 `~/.local/share/keel/<版本>/keel` 找，没有就从 GitHub Release 下载，核对 `checksums.txt` 之后再运行。结论只取决于仓库钉住的版本：

```toml
[keel]
version = "1.3.0"
```

- `KEEL_TOOLCHAIN=local`：只用本机已安装的版本，不下载；版本不符时直接拒绝运行。
- `KEEL_HOME`：改变版本的存放目录。

装一个入口（任选一种）：

```bash
mise install                                             # 推荐：mise.toml 里已写好 "github:visual-z/keel"
go install github.com/visual-z/keel/cmd/keel@v1.3.0      # 有 Go 工具链时
# 或从 GitHub Release 下载对应平台的二进制，核对 checksums.txt
```

升级 keel 是一次刻意的改动：改 `keel.toml` 里的版本，跑一遍 `keel gate`，作为一次提交。`mise.toml` 里的版本只决定装哪个入口，不需要跟着改。

## 命令

| 命令 | 做什么 | 失败意味着 |
|---|---|---|
| `init --name N --stack S` | 在空仓库里写入模板、`keel.toml`（预设 S）、`mise.toml`，启用 `.githooks` | — |
| `adopt [--stack S]` | 已有项目接入：只补缺的文件（`keel.toml`、卡模板、hooks），把现存的不合规卡写进存量清单（只写一次） | — |
| `new <type> <slug> [--light]` | 从模板开卡，填好类型、日期和基线 commit | — |
| `status [--all] [--worktrees]` | 按状态列出卡；进行中（doing、blocked）的卡显示其 `## 交接` 的前三行；有别的 worktree 改到同样的文件时各给一行提示。`--worktrees` 列出每个 worktree：领先/落后主干、未提交的路径数、它改动的进行中的卡，并标出已合并且干净、可以删掉的（只列出，从不删除） | — |
| `lint [卡…]` | 卡的结构：front matter、必需的节、每条 `D<n>` 都绑定了检查、状态与证据一致 | 卡的格式不合格，或者声称完成但缺少证据 |
| `freeze-check [卡…]` | 拿当前完成定义和开卡提交（冻结点）比较；存量清单只减不增 | 完成定义被悄悄改动或删除 |
| `verify-red <卡> [--at REV] [--repeat N] [--no-green]` | 在临时 worktree 里重跑每条 `RED:` 和每个 `keel-inject`，必须红；再在工作树里重跑，必须绿。全部通过才在 `refs/keel/verified/` 下留一条验证记录 | 测试不在测它声称的东西 |
| `audit-red [--retain] [--json]` | 所有卡（含存量卡）的 RED commit 都还在，并已钉在保留 ref 下；`--retain` 先校验全部再一次性钉住 | 证据丢了，或声明格式错 |
| `snapshot <路径…>` | 把 HEAD 加上指定文件提交成一个私有快照，不动 index 和分支；输出 sha，供 `RED:` 使用 | — |
| `assert-guard [--base B \| --card 卡]` | 在 diff 里查删掉的断言、新增的 skip/only、测试里的早退出和 `__eq__` 覆盖、被删的测试文件。默认从与 `guard.base` 的合并基点比起；`--card` 从卡的锚点比起（见「锚点」） | 测试被弱化了 |
| `gate [--record 卡] [--staged] [--tier T] [--keep-going] [--only a,b]` | 依次跑 `[[gate.step]]`（keel 自己的快速检查 lint、freeze-check、check-docs、check-boundaries、assert-guard 先跑，回执仍按配置顺序），直接读退出码，解析测试计数，列出失败的测试名，输出一行回执。`--record` 另外从卡的锚点跑 assert-guard（回执里的 `guard`），只记录通过的 gate，并留下记录（见「回执与日志」）；`--staged` 在临时 worktree 里测**恰好是已暂存的那棵树**；`--only` 的结果不能 `--record` | 起点或终点不是绿的 |
| `replay [卡…] [--since REV] [--strict]` | 把每个 `keel-inject` 故障重新打到 HEAD 上，测试必须仍然红。发版前用 `--since <上个 tag>` | 测试已经抓不住它声称能抓的故障 |
| `sync [--remote R] [--push \| --fetch]` | 经远端交换证据（见「团队与多 worktree」）：先 fetch，再为本分支离开主干以来收尾的卡生成收尾记录，再 push。只交换 `refs/keel/` 下可以公开的那几类，从不推本机的 gate 记录 | 远端拒绝创建 `refs/keel/*`，或不可达 |
| `ci [--base REV] [--no-fetch]` | 在 CI 里判定推上来的分支：先取证据，在 HEAD 上跑快速检查（lint、freeze-check、check-docs、check-boundaries、从 REV 起的 assert-guard），再把 REV..HEAD 里每张收尾的卡在它收尾的那个提交上判定一次，规则和 pre-commit hook 相同。不重跑测试 | 某张卡的收尾没有证据、证据过期，或分支合并后超出了文档上限 |
| `check-docs` | AGENTS 行数上限、PLAYBOOK 规则数上限、坏链接与绝对路径链接、地图里的过期路径、决策编号唯一、注册表指向的位置、词表禁词 | 文档和代码脱节了 |
| `check-boundaries` | `[[boundary.rule]]` 定义的正则级架构边界 | 越界依赖或禁用调用 |
| `mutate [--base B]` | 跑配置好的、只针对 diff 的变异测试工具 | 存活的变异体，就是测试分辨不出的改动 |
| `hook pre-commit` / `hook pre-push` / `hook commit-msg <文件>` | git hooks：快速检查（lint、冻结、文档、边界、弱化测试）全部跑完再汇总，判定的是要提交的 index；提交信息须为 Conventional Commits。`.githooks/pre-merge-commit` 让没有冲突的合并也跑同样的检查。`pre-push` 顺带推送本次推送的收尾所需的证据，失败只提示一行，从不阻止推送 | — |

退出码：0 通过，1 检查失败（输出 `FAIL  <原因>`），2 用法错误。

## 卡片格式

````markdown
---
type: fix            # feat fix perf refactor debt docs chore research review release
status: doing        # todo doing blocked awaiting-author done
weight: light        # full | light
created: 2026-01-01
baseline: 1a2b3c4d5e6f
reason: …            # 只有 blocked 时必填
---

## 完成定义（动工前冻结；实现中不得放宽）

- **D1** 一条可检查的判据。
  - 检：test `完整测试名或过滤串`
- **D2** 作者手测的判据。
  - 检：author 打开设置页，切换主题  已确认：2026-01-02

## 证据

RED: 1a2b3c4d5e6f test_name_substring  # D1
RED(web): 9f8e7d6c5b4a formats binary units

```diff keel-inject test_name_substring
--- a/src/calc.py
+++ b/src/calc.py
@@ -2,1 +2,1 @@
-    return a + b
+    return a - b
```

GATE: 9f8e7d6c5b4a+dirty ok build=0 test=0[812p/0f] … (2026-01-02)
````

规则：

- **必需的节。** 完整卡要有 来源 / 范围 / 观测面 / 环境假设 / 完成定义 / 设计 / 验证命令 / 证据；轻量卡要有 问题 / 完成定义 / 证据。
- **检查的 kind。** `test` `property` `inject` `cmd` `grep` `author` `measure`。其中 test、property、cmd、grep 要把目标写在反引号里。
- **占位符。** 模板用 `⟨…⟩` 标占位（不用 `<…>`，因为代码里的泛型合法）。状态离开 todo 后还有占位符，lint 失败。
- **RED 声明的语法是严格的。** 以 `RED:` 或 `RED(<profile>):` 开头的行必须是 `<7–64 位十六进制 commit> <非空过滤串>`；分支名、`HEAD`、占位符、空过滤串都是错误，不会被悄悄忽略。行尾 `# D1, D2`（或 `# D1 D2`）是注释，标出这条声明证明哪几条判据；以 `# D<n>` 开头却解析不了的行尾是错误，不会悄悄变成过滤串的一部分。`RED: none <理由>` 只允许用在非行为卡。
- **RED 的要求。** feat、fix、perf 卡进入 awaiting-author 或 done 时，必须有 `RED:` 或 `keel-inject`。
- **done 的要求。** 需要一行覆盖全部 gate 步骤、且每步退出码为 0 的 `GATE: … ok` 回执，并且所有 author 类检查都带「已确认：日期」。
- **收尾判定（只判一次，在卡收尾的那次提交）。** 卡第一次进入 awaiting-author 或 done 的那次提交要满足：每条 `RED:` 和每个 `keel-inject` 都有 `verify-red` 留下的验证记录（没人复验过的声明不算数）；有一行覆盖全部步骤的 `GATE: … ok` 回执，回执有记录，记录里的树就是这次要提交的树（见「回执与日志」）。awaiting-author 也一样：只剩作者手测，机器能查的证据必须已经齐了。之后不再重判：作者在 awaiting-author 上补「已确认」改成 done，回执和声明都没变，就不重判；卡在分支上已经收尾，合并进主干时也不重判（合并提交的任一父提交里它已是 done）。合并后的主干是否全绿，是下一次会话开始时 `keel gate` 的事。
- **收尾顺序。** 先 `verify-red`，再 `gate --record`，然后把状态改成 done（或 awaiting-author），和实现一起提交。先改状态再跑 `gate --record` 也可以：gate 里的 `keel lint` 步骤知道这张卡的回执正在生成，不会因此失败。
- **gate 层级。** front matter 写 `gate: release`，回执就要包含这个层级的步骤，也就是要用 `keel gate --tier release --record` 来记录。
- **锚点。** 卡的锚点是开卡提交（冻结点）；如果 `baseline:` 写的 commit 更早，就用 `baseline:`。从锚点比起，卡的全部工作都在 diff 里，无论它提交在哪个分支上。在主干上直接提交时，与 `guard.base` 的合并基点就是 HEAD 本身，不传 `--card` 时只比较了未提交的改动。比冻结点晚的 `baseline:` 不起作用：它只能扩大比较范围，不能缩小。
- **卡名。** `<type>-<slug>.md`，slug 是小写 kebab-case，允许点号写版本号（`release-1.2.0`）。
- **不解析的地方。** 代码块和 HTML 注释里的内容不算声明。
- **修订。** `## 修订` 下写「D<n> … 作者确认 YYYY-MM-DD」的条目，`freeze-check` 才放行对应编号的改动。
- **允许弱化。** `WEAKEN-OK: <测试文件> <理由>（作者确认 YYYY-MM-DD）` 让 `assert-guard` 放过那个文件。

## verify-red 判定什么

**红**必须同时满足：
- 没有超时，没有被信号杀死；
- 输出能被解析，并且没有编译错误、加载错误、收集错误、包级失败；
- 过滤器选中并**实际执行**了至少 1 个测试（跳过的、`#[ignore]` 的不算）；
- 至少 1 个测试失败；
- 退出码是该格式表示「有测试失败」的那个码（cargo 101，其余 1）。退出码与报告不一致就不算红。

**绿**必须同时满足：退出码为 0，选中并执行的测试数大于 0，失败数为 0，输出无异常。

**重复。** `[red] repeat = N`（或 `--repeat N`）让每个声明跑 N 次，每次都必须满足判定；偶发的测试证明不了任何东西。

**故障补丁**只能改产品代码：它在目标上实际改动的文件，只要落在 `tests.paths` 里就会被拒绝。补丁先尝试直接打到 HEAD 上（允许零上下文的单行补丁）。打不上时，keel 找到补丁能打上的那个提交（优先用上次验证时保留在 `refs/keel/fault/` 下的版本，其次是最近的一个祖先），在那里提交故障，再用 git 的三方合并带到 HEAD，就像 cherry-pick。文件改了名、上下文挪了位置，都能合并过去。故障所在的代码已经被重写时，合并会冲突，keel 如实报告「无法重放」，不会去猜。主工作区不受影响。

**依赖漂移。** `[red] lockfiles` 列出的文件在快照和工作树之间不一致时，说明链接过去的依赖是为另一份代码装的。keel 会提示这一点。设了 `[red] prepare` 时，改为在临时 worktree 里为快照自己安装依赖，安装失败就不算红。

**保留。** RED 用的 commit 只在验证通过之后钉到 `<ref_prefix><sha>`（默认 `refs/keel/red/`），squash 或 reflog 过期都抹不掉它。已存在的 ref 指向别处、或是符号引用时，keel 拒绝并且不移动它。

## 输出格式（runner）

keel 认的是**输出格式**，不是工具。能用结构化输出就不解析文本：

| runner | 读什么 | 适用 |
|---|---|---|
| `go-json` | `go test -json` 的事件流 | Go |
| `junit` | 命令写到 `{junit}` 的 JUnit XML 报告 | pytest `--junitxml`、vitest/bun `--reporter=junit`、jest-junit、cargo-nextest |
| `cargo` | `test result:` 行（cargo 没有稳定的结构化输出） | `cargo test` |
| `bun` | 恰好一份正常的 bun 摘要 | `bun test` |
| `custom` | `selected_re` / `failed_re` / 可选 `invalid_re` / `red_exit` | 其他 |

JUnit 报告里的 `<error>`（setup、collection 出错）、重复的 testcase、空报告都不算证据；思路参照 [regression-witness](https://github.com/qjf1597300-cloud/regression-witness)。

## keel.toml

```toml
[keel]
version = "1.3.0"             # 必填：钉住的 keel 版本

[gate]
unbound = ["**/*.md"]         # 回执不绑定的路径（默认：测试路径以外的 markdown）
exact_tree = false            # true：分支 rebase 后也要求收尾的树恰好是 gate 测过的树（见「团队与多 worktree」）

[sync]
remote = "origin"             # sync、ci 与 pre-push 交换证据的远端
auto = true                   # false：pre-push 不推证据，只用 keel sync

[[gate.step]]                 # 按顺序执行；第一条失败即停
name = "test"
cmd = ["cargo", "test", "--locked"]
runner = "cargo"              # 可选：解析计数；选中 0 个测试就判失败
cwd = "."                     # 可选：相对仓库根的运行目录
timeout_s = 0                 # 可选：0 = 不限
retries = 0                   # 可选：全量里失败的测试单独重跑几次；每次都过才算偶发（见下）
max_flaky = 3                 # 可选：失败多于这个数就不重跑，直接判失败
profile = ""                  # 可选：单独重跑用哪个 [red.profile]

[[gate.step]]
name = "deny"
cmd = ["cargo", "deny", "check"]
external = true               # 依赖仓库之外的状态（公告库、网络）；见下

[[gate.step]]
name = "eval"
cmd = ["bun", "run", "eval:test"]
tier = "release"              # 只在 gate --tier release 时跑；卡用 `gate: release` 要求它

[red]
runner = "cargo"
command = ["cargo", "test", "--locked", "{args}"]
link = []                     # 链进临时 worktree 的依赖目录，例如 ["node_modules"]
env = { CARGO_TARGET_DIR = "{cache}/cargo-target" }   # 只给临时 worktree；{cache} 指 .keel/cache
timeout_s = 3600
repeat = 1                    # 每个声明跑几次，必须全部一致
ref_prefix = "refs/keel/red/" # 保留 ref 的前缀（已有项目可沿用自己的）
lockfiles = ["Cargo.lock"]    # 快照与工作树的这些文件不一致时提示依赖漂移
prepare = []                  # 设了就在漂移时为快照自己装依赖，例如 ["bun", "install", "--frozen-lockfile"]

[red.profile.web]             # 多套测试命令；未写的字段继承 [red]
runner = "junit"
cwd = "web"
command = ["node_modules/.bin/vitest", "run", "-t", "{filter}", "--reporter=junit", "--outputFile.junit={junit}"]
link = ["web/node_modules"]

[tests]                       # assert-guard 与 keel-inject 用
paths = ["tests/**"]          # 什么是测试文件（故障补丁不得改它们）
inline_paths = ["src/**"]     # 另外要统计断言的位置（Rust 的内联测试和 debug_assert）
inline_marker = '#\[cfg\(test\)\]'  # 可选：inline_paths 里测试区域的起始行；skip 和早退出只在区域内算，断言仍按整个文件算
assert_patterns = ['…']
skip_patterns = ['…']
suspicious_patterns = ['…']   # 早退出、永远相等

[paths]
tasks = "docs/tasks"
legacy_manifest = "docs/tasks/legacy.txt"

[docs]
agents = "AGENTS.md"
agents_max_lines = 150
playbook = "docs/PLAYBOOK.md"
playbook_max_rules = 120
progress = "docs/PROGRESS.md"
plan = "PLAN.md"
decisions_heading = "决策记录"   # 只检查这个标题下表格的编号：唯一；数字编号还须递增
invariants = "docs/INVARIANTS.md"
fixtures = "docs/FIXTURES.md"
glossary = "CONTEXT.md"
glossary_source_dirs = ["src"]
link_exclude = []                # 不做链接检查的 glob
historical = ["docs/research/**"] # 当时的记录：链接目标后来被移动的，经由 git 改名跟过去，不要求改写原文
map_files = []                   # 检查反引号路径的「地图」文件；空 = agents、fixtures、invariants

[[boundary.rule]]
name = "core 不做 I/O"
paths = ["src/core/**"]
except = []
forbid = ['^use std::fs']

[mutate]
command = ["cargo", "mutants", "--in-diff", "{diff}"]   # {diff} 为本分支 diff 文件，{base} 为合并基点
```

未知的键是错误：拼错的键就是一项永远不会运行的检查。

命令里的占位符：

| 占位符 | 替换为 |
|---|---|
| `{filter}` | 声明里的过滤串，作为一个参数 |
| `{args}` | 过滤串按 shell 规则拆成多个参数（`-p server --test ssh_agent live_policy::`） |
| `{junit}` | 本次运行要写的 JUnit 报告路径（也可用在 `env` 的值里） |
| `{existing:a,b}` | 列出的路径中，在运行目录里存在的那些（老快照里可能还没有某个测试目录） |

## 团队与多 worktree

keel 的证据都是 `refs/keel/` 下的 ref。git 默认只推送和拉取分支与标签，所以以前队友的 clone 和 CI 什么都看不到，收尾只在作者本机的 hook 里判定过一次。

- **共享什么。** fetch 取回四类 ref 的全部；push 只推**被推送的卡引用到的**那些（它们 `RED:` 指向的 commit、验证记录、故障来源、回执的收尾记录），所以别的、尚未推送的分支上保留的快照不会跟着出去。四类 ref 是：验证记录（`verified/`，空树加上证明了的声明）、保留的 RED commit、故障的来源 commit（`fault/`），以及**收尾记录**（`closed/`，每张推送出去的收尾一条）。收尾记录是被测的树去掉 gate 运行时恰好未被跟踪的文件（构建产物、草稿），所以推出去的都是项目历史里本来就有的内容。本机的 gate 记录（`gate/`）保留原样的被测树，从不推送。
- **为什么不改默认 refspec。** 那样每次普通的 fetch 都要列出所有证据 ref。共享的 ref 都按内容命名（commit id 或补丁哈希），队友之间不会写出同名不同义的 ref，也就不需要合并；同一个故障在两台机器上首次应用于不同提交时，先到的那条保留，另一条只提示、不覆盖。
- **托管平台。** GitHub 和 Gitea（自 go-gitea/gitea#16705 起）接受任意 `refs/*`；Gerrit 需要管理员在 `refs/keel/*` 上授予 Create Reference；GitLab 与自建服务器要先试推一次（`keel sync`）。推不上去时 pre-push 只提示一行，不阻止推送。从 fork 发起的 PR 推不了上游的 ref，这时在 CI 里直接跑 `keel gate`。
- **CI。** 例如 GitHub Actions：`actions/checkout` 用 `fetch-depth: 0`（`keel ci` 拒绝浅克隆：冻结点和 RED commit 都在历史里），然后 `keel ci --base origin/main`（推到主干时用 `--base ${{ github.event.before }}`）：

  ```yaml
  - uses: actions/checkout@v4
    with: { fetch-depth: 0 }
  - run: go install github.com/visual-z/keel/cmd/keel@v<钉住的版本>   # 或 mise
  - run: keel ci --base origin/${{ github.base_ref || 'main' }}
  ```

  PR 的合并 ref 上跑也可以：合并提交本身不会让卡重新收尾。服务端的记录谁都能推，它证明的是「有人跑过」，不是「CI 跑过」；要后者，就在 CI 里另跑项目自己的测试。
- **rebase 之后。** rebase 和 squash 都不跑 pre-commit，收尾的树也就不再是被测的树。默认判定**改动等价**：分支自离开主干起的 diff，去掉行号和 blob id 之后与 gate 测过的完全相同（`git cherry` 认 rebase 过的提交也是这个思路；空白照算，缩进在 Python、YAML、Makefile 里就是代码），回执就仍然成立。解决过冲突、改过代码、或者主干改到了离你的改动三行以内，改动就不同，需要重跑 gate。**直接在主干上收尾的卡**不适用这一条，仍要求树逐字相同：在主干上，「别人往主干提交了」和「自己又提交了没测过的代码」分不出来。要求处处逐字相同就设 `[gate] exact_tree = true`。CI 以 `--base` 那个提交作为主干：分支合并之后，它的提交也在主干分支上了。
- **交接。** 会话交接写在卡的 `## 交接`（只留最新一条），不写进所有分支都在顶部追加的 `docs/PROGRESS.md`。卡是 markdown，改它不会让回执过期。`keel init` 的 `.gitattributes` 给 `docs/PROGRESS.md` 设了 `merge=union`；已有项目要用，自己加这一行。
- **决策编号。** 新决策用短 slug 当编号（`ref-sync`），只要求唯一；两条分支各加一条不会撞号。已有的数字编号不动，仍须递增。
- **worktree。** 一个 agent 一个 worktree 一个分支；主 checkout 只用来合并。`keel status` 会提示和别的 worktree 改到同一批文件。缓存与依赖由各个项目自己的工具管理，keel 不在 worktree 之间共享它们：不同的锁文件共用一份依赖会装错，cargo 共用 target 目录会互相加锁。合并且干净的 worktree 由 `keel status --worktrees` 列出，删除由人来做。

## 在已有项目中采用

```bash
keel adopt --stack cargo     # 没有 keel.toml 时从预设生成；已有就沿用
# 把 [[gate.step]] 改成这个项目原有的「完成」定义，不放宽任何一条
```

- 存量清单里的卡**豁免**格式检查（lint / freeze-check / 链接检查）；不在清单里的卡必须合规。
- 存量卡里的 `RED:` 行**仍然是声明**，`audit-red` 照样检查它们的语法和 commit。
- 清单**只能缩短**：`freeze-check` 拿当前清单和它第一次提交的版本比较，多出来的名字就失败。迁移一张老卡，就是把它改合规，然后删掉它那一行。清单里列的卡如果已经不存在，lint 失败。
- 文档预算按现状设成**棘轮**：`agents_max_lines`、`playbook_max_rules` 填当前值，只降不升。

## 回执与日志

- `gate` 的完整输出写到 `.keel/logs/`（已被 gitignore，原始日志不入库），卡里只记一行 `GATE:` 回执。
- 回执里的 `+dirty` 表示跑的时候有未提交改动。这是常态：回执通常和实现在同一次提交里写进卡。
- **记录。** `gate --record` 只在 gate 通过时写入。它把被测的树提交到 `refs/keel/gate/<sha>`，提交信息就是回执；回执里的 `tree:<hash>` 指向这棵树。做法同 git-test 按树记录结果。手写的回执没有记录，lint 不认。
- **什么改动会让回执过期。** 回执绑定的是被测的树，但不包括 `[gate] unbound` 里的路径；默认不包括测试路径以外的 markdown。所以跑完 gate 再写证据、写收尾说明、改卡片，都不必重跑。改了代码或测试，回执就过期，lint 会列出改了哪些文件。在 pre-commit hook 里判定的是要提交的 index，不是工作树：没暂存的改动不影响这次提交。
- **共用工作树。** 别的会话没提交的改动也会被 gate 测进去。提交时这些改动不在 index 里，hook 会指出「gate 测了这次提交不包含的改动」。这时先暂存要提交的内容，再跑 `keel gate --staged --record <卡>`：它把 index 检出到临时 worktree（依赖按所有 profile 的 `link` 链过去，构建缓存用 `.keel/cache/`），测的就是要提交的树；工作树和 index 都不会被 stash 或改动。
- **偶发。** 步骤设了 `retries = N` 时，全量运行里失败的测试会被单独重跑 N 次。每次都通过就算偶发：回执记为 `[…/1flaky]`，记录里写出它的名字，不阻塞这次 gate。单独跑也失败的，是真失败。失败数超过 `max_flaky` 时，说明构建坏了，不重跑。keel 无法逐个列出名字的失败（名字数与失败数对不上）也不重跑。偶发不是修复，它的名字留在记录里，供你另开卡去修。默认 `retries = 0`，就是不重跑。
- **外部步骤。** `external = true` 的步骤失败时，`gate --record` 会在卡的锚点上再跑一次这个步骤。锚点也失败，说明不是这张卡造成的：回执记为 `name=1(base)`，不阻塞这张卡，记录里写明两边的退出码。锚点通过而这里失败，就是这张卡的问题，照常阻塞。
