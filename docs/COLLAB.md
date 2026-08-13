# COLLAB.md — 多 Agent 协作协议

> **本项目由多个 AI agent 协作开发**——其中一个 agent 担任 **Planner** 角色（拆任务、写 spec、做最终审查），另一个 agent 担任 **Executor** 角色（按 spec 实施、跑 build、回填结果）。具体由哪个 AI（Claude / Codex / Cursor / Aider / Gemini / ChatGPT 等）担任哪个角色，由用户在每次会话里指派——可以两边都换、可以交叉、可以同一 AI 串行扮演两个角色。这份文档是角色之间的"合同"，与具体 AI 无关。Agent 之间不能直接对话，所有协调通过 git 仓库里的文件完成。**任何 agent 在动手前必须读完本文档。**
>
> 项目简介：**Lumen — macOS 双窗格文件管理器，集成 AI 文件对话与自然语言操作**

## 1. 共享假设

| 假设 | 说明 |
|---|---|
| **git 仓库是唯一通信通道** | Agent 之间不共享上下文 / 对话。所有要让对方知道的事，**必须 commit 到仓库**。 |
| **任务文件 = 工作合同** | `tasks/Tnnn-*.md` 是任务的权威定义，包含 spec、状态、回填记录。 |
| **文件协议优先于聊天记忆** | 任何 agent 拿到仓库都应该能凭文件继续工作，不依赖此前的聊天。 |
| **零 push 不算完成** | 在本地 commit 不算交付，必须 push 到远端 main 分支。 |

## 2. 角色与权限

| 角色 | 主职 | 写权区 | 不允许 |
|---|---|---|---|
| **Planner**（任意 AI；由用户在派单会话指派） | 定义任务的**为什么 / 做什么 / 做到什么程度**：场景、目标、期望效果、交付边界、验收标准。**不规定"怎么做"**——技术方案、文件拆分、函数签名、算法选型由 Executor 决定。审查时只对照验收标准与边界，不挑实现风格（除非违反 docs/CONVENTIONS.md 或红线）。 | `tasks/*`、`docs/*`、`README.md`、`AGENTS.md`、planning 类文件（task_plan.md / progress.md / findings.md 如有）、commit message 起草 | 不直接写功能代码；不在 spec 里规定具体函数签名 / 文件拆分 / 算法（除非是项目硬约定） |
| **Executor**（任意 AI；由用户在派单会话指派） | **自主决定技术方案**：读 spec 后选实现路径、拆文件、选库（在 spec 允许的范围内）、写代码、跑 build、回填任务文件。M/L 任务建议先写一段 Approach 大纲再动手（不强制，见 §3）。 | `App/`、`Packages/Core/`、`scripts/`、`Package.swift`（仅 spec 允许新依赖时）、`tasks/Tnnn-*.md` 自己负责那条的「Executor 回填段」 | 不动 `docs/*`、planning 类文件、`tasks/README.md`、`AGENTS.md`；不越 DO NOT TOUCH 边界；不擅自扩大 Acceptance 之外的功能 |
| **User**（人类） | 派单、端到端验证、密钥/.env、对外决策 | `.env*`、外部控制台、最终发布决策 | 不要 force push / 不要绕过审查归档 |

**红线**（任一 agent 都不可越界）：
- 不在客户端代码 import 服务端密钥（service-role / API key / token）
- 不修改已存在的数据库迁移文件（要改 schema → 写新迁移）
- 不 force push 到主分支
- 不把秘钥 / 密码 / PIN 提交进 git
- 项目专属红线见 `docs/CONVENTIONS.md`（如该文件存在）

## 3. 任务文件结构

```
tasks/
  README.md                          # 索引：当前 open 任务清单
  T006-some-feature.md               # 一个任务一个文件
  T007-...
  archive/
    T001-...md                       # 已完成、归档
```

**文件命名**：`T<3 位编号>-<kebab-case 描述>.md`。编号严格递增，不复用。

**任务文件模板**（Planner 负责前半段，Executor 负责后半段）：

```markdown
# T<NNN>: <短描述>

Status: open               # open | in_progress | review | needs_rework | needs_human | done
Owner: executor            # planner | executor | user  （角色名，与具体 AI 无关）
Created: YYYY-MM-DD by <agent-name e.g. claude / codex / cursor>
Complexity: S | M | L      # S=单文件 / 1小时；M=2-4文件；L=跨模块

## Context（应用场景）
[这个需求从哪来？什么场景下用户/系统会触发它？为什么现在做？1-3 句]

## Goal（要解决什么）
[一句话说清成功长什么样。重点描述"结果"而不是"过程"]

## User-Visible Effect（期望效果）
[做完之后，用户/调用方能观察到的变化。可以是：
- 一段交互描述（"点 X 按钮 → 看到 Y"）
- 一个截图/草图链接
- 一个 API 响应样例
- 一段日志/输出格式
让 Executor 看完能脑补出"做完应该是什么样"。]

## Acceptance Criteria（验收标准——这是合同）
- [ ] `<build / test 命令>` 通过
- [ ] <可验证的功能项 1，要能客观打勾，不要"代码优雅"这种模糊项>
- [ ] <功能项 2>
- [ ] <边界 case：异常输入 / 空状态 / 错误处理是否符合期望>

## Delivery Boundaries（交付边界）
**Touch area（建议涉及的范围，非强制清单）**：
- <模块/目录 1，例如 App/Views/>
- <模块/目录 2>
（Executor 可在此范围内自由拆分文件、增减 helper；如需突破此范围，在 Approach 段说明）

**DO NOT TOUCH（强制，越界即 NEEDS_REWORK）**：
- <显式列出不能动的文件/目录，防 scope creep>

## Constraints（硬约束，可选）
[只写**必须遵守**的事，例如：
- 必须沿用现有的 `AppearanceKit` 主题接口
- 必须保持现有快捷键不冲突
- 必须 backward-compatible（不能破老调用方）
没有硬约束就写"无 — 实现方案由 Executor 决定"。**不要写"建议用 X 模式"这种非强制建议**，那是 Executor 的判断范围。]

## Out of Scope（明确不做的事）
- <显式排除，防 Executor 多做>

## Notes / Hints（可选，仅作参考）
[Planner 知道的相关上下文：相似已实现功能位置、已知坑、参考文档链接。
**明确标注"建议而非要求"**，Executor 可以采纳也可以选别的方案。]

## Pre-reading（动手前必读）
- AGENTS.md
- docs/COLLAB.md（本协议）
- docs/CONVENTIONS.md（如有，相关章节）
- <相关源码路径，让 Executor 理解现状>

---
## Executor 回填：Approach（可选，推荐 M/L 任务先写）

[1 段话说清你打算怎么做：
- 选了什么技术方案 / 拆成几个文件
- 关键设计决策（为什么这么选）
- 与 spec 的 Hints 段如有出入，说明理由
然后 commit "wip(Tnnn): approach" 再开始写代码。
S 任务可跳过此段，直接开干。

此段的目的是让用户（不是 Planner）有机会在你写代码前快速 sanity-check 方向，不是审批门。]

---
## Executor 完成后回填

### What I did
（实际改动摘要，3-5 行，描述做了什么、关键决策）

### Build output（最后 10 行）
```
（粘 build/test 末尾）
```

### Diff summary
```
（粘 git diff --stat）
```

### Self-check against Acceptance（逐项勾选）
- [ ] AC 1: ...
- [ ] AC 2: ...
（与 spec 的 Acceptance Criteria 一一对应，没达成的留空并在 Deviations 段说明）

### Deviations / Questions
（如果偏离了 spec 边界、做了 Hints 没提到的设计选择、遇到不清楚的地方，写在这。
正常自主选型不算 deviation，不用写。Deviation 特指：跨了 Touch area、改了 Constraints、漏了某项 AC。
没有就写"无"）

---
## Planner 审查后回填

### Verification
PASS | NEEDS_REWORK

### Notes
[具体哪几项 OK、哪几项不 OK；如果 NEEDS_REWORK 必须列出具体修改要求]

---
## Executor 自审回填（仅在 Fallback B 模式下用，正常审查走 Planner 段）

### Self-Review Checklist
- [ ] git diff --stat 没动 DO NOT TOUCH 列表里的任何文件
- [ ] 没做 Out of Scope 列出的事
- [ ] 没违反 Constraints 段任何条目
- [ ] build/test 通过
- [ ] 红线全检查通过（见 §9 "自审清单"章节）
- [ ] Acceptance Criteria 全部勾选
- [ ] 无未解决的 Questions

### 结论
- 全 PASS 且无偏离 → 自己 mark done 并归档
- 任一不确定 → mark needs_human，push 等用户决策
```

## 4. 标准生命周期

```
┌──────────────────────────────────────────────────────────────────┐
│  User → Planner: "做 X"                                          │
│         │                                                        │
│  ┌──────────────┐                                                │
│  │   Planner    │  写 tasks/Tnnn-*.md (Status: open)             │
│  │ (任意 AI)    │  更新 tasks/README.md                          │
│  │              │  commit "task(Tnnn): draft spec" + push        │
│  └──────┬───────┘                                                │
│         ↓ 用户复制 Executor prompt（见 §5）                      │
│  ┌──────────────┐                                                │
│  │  Executor    │  git pull → 读 Tnnn + Pre-reading              │
│  │ (任意 AI)    │  Status: in_progress, commit "wip(Tnnn): start"│
│  │              │  实施 → 跑 build/test                          │
│  │              │  在 Tnnn 底部回填 4 项                          │
│  │              │  Status: review, Owner: planner                │
│  │              │  commit "wip(Tnnn): implementation done"       │
│  │              │  push                                          │
│  └──────┬───────┘                                                │
│         ↓ 用户告诉 Planner："Tnnn done"                          │
│  ┌──────────────┐                                                │
│  │   Planner    │  git pull → 读 Tnnn + git diff                 │
│  │ (任意 AI)    │  跑 build/test                                 │
│  │              │  在 Tnnn 写 Verification 段                    │
│  │              │  ┌─ PASS  → Status: done                       │
│  │              │  │         git mv 到 tasks/archive/            │
│  │              │  │         更新 tasks/README.md                │
│  │              │  │         commit "verify(Tnnn): pass" + push  │
│  │              │  └─ NEEDS_REWORK → Status: needs_rework        │
│  │              │              Owner: executor                   │
│  │              │              列具体修改要求                      │
│  │              │              commit "review(Tnnn): rework"     │
│  │              │              push → 回到 Executor 步骤         │
│  └──────────────┘                                                │
│                                                                  │
│  最后 User: 端到端验证                                            │
└──────────────────────────────────────────────────────────────────┘
```

**关键约束**：
- 同时只允许**一个 open / in_progress / review 任务**（避免分支冲突）
- 任一阶段完成都必须 push
- Executor 完成后**Status 必须是 review**，绝不能自己改成 done（Fallback B 例外，见 §9）

## 5. 用户给 Executor 的标准 prompt

**每次都用这段，只换 `Tnnn` 和仓库路径**：

```
请按以下流程执行 tasks/Tnnn-<...>.md：

1. cd <repo-path> && git pull
2. 完整读 tasks/Tnnn-*.md 的 spec（重点：Context / Goal / User-Visible Effect / Acceptance Criteria / Boundaries / Constraints）
3. 按 Pre-reading 顺序读完所有前置文档（AGENTS.md 与 docs/COLLAB.md 必读）
4. 把任务文件 Status 改为 in_progress, Owner: executor，
   commit "wip(Tnnn): start" 并 push
   （commit author 会标明你是哪个 AI，role 字段保持角色名）

5. 【方案设计——你的发挥空间】
   spec 只规定"做什么 / 做到什么程度 / 不能碰什么"，**不规定怎么做**。
   技术方案、文件拆分、函数签名、算法选型、helper 抽不抽——你自己决定。
   Notes/Hints 段（如有）只是参考，不是要求。
   
   - S 任务：可以直接动手
   - M/L 任务：建议先在任务文件「Executor 回填：Approach」段写 1 段方案大纲，
     commit "wip(Tnnn): approach" 后再写代码。这不是审批门，是给用户一个 sanity-check 的机会。

6. 实施。硬约束：
   - 不越 DO NOT TOUCH 边界（越了就是 NEEDS_REWORK）
   - 不做 Out of Scope 列出的事
   - 遵守 Constraints 段所有条目
   - Touch area 是"建议范围"，确有必要可超出，但要在 Deviations 说明

7. 跑项目的 build / test 命令必须通过

8. 在任务文件「Executor 完成后回填」段填写：
   - What I did（含关键设计决策的 1 行解释）
   - Build output
   - Diff summary
   - Self-check against Acceptance（逐项勾选）
   - Deviations（仅指：越界 / 改 Constraints / 漏 AC；正常自主选型不算）

9. 把 Status 改为 review, Owner: planner
10. git add -A && git commit -m "wip(Tnnn): implementation done"
11. git push
12. 回报「Tnnn done, pushed」

【什么时候停下来问】
- Acceptance Criteria 内部矛盾 / 模糊到没法判断是否达标
- User-Visible Effect 描述与现有代码行为有冲突，不知道哪个对
- 发现要破坏 Constraints 才能完成 Acceptance
- 发现完成 Acceptance 必须越 DO NOT TOUCH 边界
→ 在文件底部新增 "Questions" 段，写具体问题
→ Status 改为 needs_human, Owner: user
→ commit "wip(Tnnn): blocked on questions" && push
→ 回报「Tnnn blocked」

【不需要问、自己判断就行】
- 用什么库、什么模式、怎么拆文件、起什么名字
- 加不加 helper、抽不抽组件
- 错误处理用 throw 还是返回 Result——选你认为最合适的
（Planner 不会因为这些挑你毛病，除非违反 CONVENTIONS.md）

【硬性禁止】
- 装新依赖（除非 spec 明确允许）
- 改 docs/* / tasks/README.md / AGENTS.md / planning 类文件
- 改既有数据库迁移文件
- 改 .env*
- 自己 mark done（必须 Planner 审）
```

## 6. 用户开新 Planner 会话的标准 prompt

**当本对话 context 满了、想换 AI 当 Planner、或想新开会话续作时用**：

```
我们在做这个项目：<repo-path>
你将担任 Planner 角色（拆任务、写 spec、审查 Executor 实现），不直接写代码。

请先读：
1. AGENTS.md
2. docs/COLLAB.md（多 agent 协作协议 — 你的角色契约）
3. tasks/README.md（当前 open 任务）
4. （如有）docs/CONVENTIONS.md、task_plan.md、progress.md 末尾 1-2 节

读完后告诉我当前进度，然后等我派单。
```

> 同样地，要换 Executor 时只需把同款 prompt 改成 "你将担任 Executor 角色，按 tasks/Tnnn-*.md 的 spec 实施"，再贴 §5 的标准 Executor prompt 即可。

## 7. Commit message 规范

| 前缀 | 谁用 | 何时用 |
|---|---|---|
| `task(Tnnn):` | Planner | 起草 / 修改任务 spec |
| `wip(Tnnn):` | Executor | 实施中、实施完成（等审） |
| `review(Tnnn):` | Planner | 审查结果（pass / needs_rework）|
| `verify(Tnnn):` | Planner | 审通过 + 归档 |
| `self-verify(Tnnn):` | Executor（仅 Fallback B） | Executor 自审通过 |
| `feat:` / `fix:` / `chore:` / `docs:` / `refactor:` | 任意 | 非任务流的临时小改 |

**禁用**：`update`、`改了一下`、单字描述。

## 8. 冲突解决

- **同一时间只允许一个开放任务** → 理论上不会冲突
- 真出现 git merge 冲突时：
  - 优先权归 **Planner**（任何 agent 拉到冲突 → 停下，告诉用户）
  - 用户找一个 agent（推荐 Planner）来解决
  - 不允许 Executor 自己解 conflict

## 9. Fallback：Planner agent 不可用时

### Fallback A：当前 Planner 会话失效

**症状**：Planner 那侧的 AI 会话变慢 / 拒绝继续 / 用户主动 `/clear` / context 满了。

**应对**：用户开一个新的 Planner 会话（可以是同款 AI 也可以换一家），复制 §6 的 prompt。新 Planner 从文件接上下文，**协议无变化**。

### Fallback B：Planner 角色完全不可用（额度耗尽 / 服务故障 / 用户暂时没法找另一个 AI 顶上）

**症状**：短时间内没有任何 AI 可以填 Planner 这个角色。

**应对**：Executor 接管 Planner 职能，但**受限模式**。

**Executor 可独立做**：
- 任何 Complexity: S 的任务（单文件、≤1 小时、孤立模块）
- Bug 修复（症状清楚、有重现路径）
- 文档同步
- 自己起草 spec → 自己实施 → 走自审清单

**Executor 不应独自做**：
- Complexity: M 或 L 的任务
- 任何架构改动（新表、改 schema、改鉴权模型）
- 任何会动 `docs/CONVENTIONS.md` 红线条目的事
- 任何要装新依赖的事

**Executor 自审清单**（替代 Planner 审查）：

```markdown
## Self-Review（仅 Fallback B 模式）

### 边界核对
- [ ] git diff --stat 没动 DO NOT TOUCH 列出的任何文件
- [ ] 没做 Out of Scope 列出的任何事
- [ ] 没违反 Constraints 段任何条目
- [ ] Touch area 之外的改动（如有）已在 Deviations 段说明理由

### 构建 / 测试
- [ ] build/test 通过（粘最后 10 行到 Build output 段）
- [ ] 没新增 lint warning

### 红线检查（任一失败 → 立刻 STOP，标 needs_human）
- [ ] 没在客户端代码 import 服务端密钥
- [ ] 没在密钥访问规约外用 service-role / API key
- [ ] 没把秘钥 / 密码 / token 写进任何被 git track 的文件
- [ ] 没改既有数据库迁移文件
- [ ] 所有新增鉴权敏感入口都有权限校验
- [ ] 新增 env 已同步 .env.example（如该文件存在）
- [ ] 没装 spec 未授权的新依赖
- [ ] 没改 docs/* / tasks/README.md / AGENTS.md / planning 类文件（除非 spec 明确要求）
- [ ] 项目专属红线全过（见 docs/CONVENTIONS.md，如该文件存在）

### Acceptance Criteria
（逐项打勾，未达成的项不能自己归档）

### 偏离 / 不确定
（如有 → Status: needs_human，push 等用户决策；不要硬归档）

### 结论
- ✅ 全 PASS 且 Deviations="无" → 可以自己归档（Status: done）+ 更新 tasks/README.md
- ❌ 否则 → Status: needs_human, Owner: user, push
```

**Fallback B 模式下，Executor 必须**：
- commit message 用 `task(Tnnn)` + `wip(Tnnn)` + `self-verify(Tnnn)` 三段（最后一段标明 self-verify 而非 verify）
- 在 progress.md（如该文件存在）追加一节，说明是 Fallback B 模式独立完成的
- 不允许动 docs/* 任何架构相关文档（防架构漂移）

## 10. 紧急停止 / Rollback

**何时触发**：
- 发现严重 bug 影响线上用户
- 任一 agent 误改了关键文件
- 测试发现整体功能不可用

**步骤**：
1. 立刻停掉所有 in-flight 任务（任何 Status: in_progress 的 task 都中止）
2. `git log --oneline -10` 找最后一个已知好的 commit
3. **不要 reset --hard**。用 `git revert <commit>` 创建反向 commit，保留历史
4. 重新 push，部署系统自动重部
5. 在 progress.md（如有）追加 `🚨 Emergency Rollback` 段，说明触发原因 + 回滚到哪个 commit

## 11. 这份文档的修改

**谁能改 COLLAB.md**：仅 Planner 角色。
**何时改**：发现协议漏洞、加新 fallback 场景、修改红线。
**改完做什么**：
1. commit `docs(collab): <什么改动>`
2. push
3. 在 progress.md（如有）追加一行说明变更原因

任何 agent 读到 COLLAB.md 与既有 commit 不一致时，**信文件，不信记忆**。
