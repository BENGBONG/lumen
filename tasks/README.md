# Tasks — 工作队列

> 多 agent 协作的任务清单。规则见 [docs/COLLAB.md](../docs/COLLAB.md)。
>
> **同时只允许一个 Status=open / in_progress / review 的任务**。归档的任务在 [archive/](archive/) 里。

## 命名

`T<3 位编号>-<kebab-case 描述>.md`，编号严格递增、不复用。

## 当前 Open / 进行中

| ID | 标题 | Status | Owner | Complexity | 创建时间 |
|----|------|--------|-------|------------|----------|
| _无_ | _等待派单_ | — | — | — | — |

## 最近归档

| ID | 标题 | 归档时间 |
|----|------|----------|
| _空_ | _尚无归档任务_ | — |

## 状态机

```
open ──→ in_progress ──→ review ──→ done（归档到 archive/）
              │             │
              │             └──→ needs_rework ──→ in_progress（重做）
              │
              └──→ needs_human ──→（等用户决策）
```

| Status | 含义 | 谁可以变更下一态 |
|---|---|---|
| `open` | spec 已写好，等 Executor 接 | Executor（→ in_progress）|
| `in_progress` | Executor 实施中 | Executor（→ review）|
| `review` | 等 Planner 审 | Planner（→ done 或 needs_rework）|
| `needs_rework` | 审查未通过，Executor 要改 | Executor（→ in_progress）|
| `needs_human` | 需要用户决策 / 提供输入 | User（→ open 或修改 spec）|
| `done` | 已通过审 + 归档 | _终态_ |

## 工作流提示

- **派单（Planner）**：写新任务文件 → 在上表「当前 Open」追加一行 → commit `task(Tnnn): draft spec` → push
- **接单（Executor）**：从「当前 Open」表选编号最小的一条 → 按 [COLLAB.md §5](../docs/COLLAB.md#5-用户给-executor-的标准-prompt) 流程执行
- **归档（Planner）**：审通过后 → `git mv tasks/Tnnn-*.md tasks/archive/` → 在「最近归档」追加一行 → 从「当前 Open」删行 → commit `verify(Tnnn): pass, archived` → push
