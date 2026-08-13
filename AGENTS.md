# Lumen — Agent 指引

**Lumen** 是一个 macOS 双窗格文件管理器，集成 AI 文件对话与自然语言操作。SwiftUI + AppKit 混合实现，最低 macOS 14 Sonoma。

## 项目结构速览

```
.
├── App/                          # 主 App target（SwiftUI 壳）
│   ├── ForkLiftCloneApp.swift    # @main 入口，菜单与快捷键定义
│   ├── AppDelegate.swift         # QuickLook 等需要 NSAppDelegate 的功能
│   ├── Views/                    # SwiftUI 视图
│   │   ├── MainWindowView.swift
│   │   ├── PaneView.swift
│   │   ├── NativeFileTable.swift # NSTableView wrapper（核心列表）
│   │   ├── EqualHSplitView.swift # 自定义 NSSplitView，保持窗格等比
│   │   ├── AI/                   # FileChatPanel / AIBatchCommandBar / ChatBubble
│   │   ├── Settings/             # 主题 + AI provider 配置
│   │   └── …
│   ├── ViewModels/
│   │   ├── PaneViewModel.swift   # 单窗格状态（@Observable）
│   │   └── PaneTabsViewModel.swift
│   ├── Services/
│   │   ├── ThemeStore.swift
│   │   └── BookmarksStore.swift
│   ├── Info.plist                # CFBundleDisplayName = "Lumen"
│   └── Resources/
├── Packages/Core/                # 内部 SwiftPM
│   ├── Package.swift             # 5 个 library targets
│   └── Sources/
│       ├── FileSystemKit/        # FileProvider 协议 + LocalFileProvider + DirectoryWatcher
│       ├── TransferEngine/       # 复制/移动队列，进度，冲突解决
│       ├── PreviewKit/           # QuickLook 封装
│       ├── AppearanceKit/        # 三套主题：原生 / 现代深色 / 轻量明亮
│       └── AIKit/                # ClaudeClient / KeychainStore / FileContextBuilder / ChatSession / AIProvider
├── Package.swift                 # 外层 SwiftPM（产出 ForkLiftClone executable）
├── scripts/
│   ├── build-app.sh              # swift build → 装配 .app → 拷 icon → ad-hoc codesign
│   └── generate-icon.swift       # Core Graphics 生成 Lumen logo iconset
├── build/                        # 产出 Lumen.app（.gitignore）
├── docs/                         # 协作协议与项目规范
└── tasks/                        # 任务工作队列
```

## 构建 / 运行

```bash
# 完整构建（产出 build/Lumen.app）
bash scripts/build-app.sh debug

# 仅编译（不打包成 .app）
swift build -c debug --product ForkLiftClone

# 启动
open build/Lumen.app
```

**注意事项：**
- `swift build` 偶尔会报 `build.db: disk I/O error`——非致命，可忽略
- Bundle ID 保持 `com.panglin.forkliftclone`（改了会丢 Keychain 里的 AI key）
- 每次 ad-hoc 重签后 macOS 可能要重新授权 Desktop/Documents 访问，可用 `tccutil reset All com.panglin.forkliftclone` 一键重置

## 当前功能现状

**文件管理：**
- 双窗格 + 多标签 + 导航历史（Cmd+[ / Cmd+]）
- 拖拽移动/复制（含跨窗格 + Finder 互操作）
- Cmd+C / Cmd+X / Cmd+V 剪贴板
- F2 内联重命名
- 传输队列（覆盖式 overlay 面板）
- QuickLook（Space）
- 压缩/解压
- 路径栏直接输入
- 三套主题切换

**AI 功能：**
- File Chat（Cmd+I）——支持 Claude / OpenAI / OpenRouter / 自定义 endpoint（MiniMax 等）
- AI 自然语言搜索（工具栏 ✦ AI 按钮）
- AI 批量操作（Cmd+Shift+A）

## 协作模式

本项目由多个 AI agent 协作开发，使用**角色制**协议——具体由哪个 AI（Claude / Codex / Cursor / Aider / Gemini / ChatGPT 等）担任哪个角色，由用户在每次会话指派。详细规则见 [docs/COLLAB.md](docs/COLLAB.md)。**简化版**：

- **如果用户告诉你"你是 Planner"**：拆任务，写 `tasks/Tnnn-*.md` spec，最后审 Executor 的实现。
  - spec **只定义** why（场景）/ what（目标 + 期望效果）/ done（验收标准 + 交付边界）
  - spec **不规定** how（不写函数签名、不指定算法、不强制文件拆分）——把技术方案的发挥空间留给 Executor
- **如果用户告诉你"你是 Executor"**：从 `tasks/README.md` 找 Status: open 的任务，按文件 spec 执行。
  - **技术方案、文件拆分、函数签名、选库都由你自主决定**（除非 spec 的 Constraints 段明确约束）
  - M/L 任务建议先写一段 Approach 大纲再写代码（详见 COLLAB.md §3）
  - 完成后改 Status: review 并 push 等审
- **任何 agent 第一次进仓库**：先读 COLLAB.md 把协议吃透，确认自己的角色，再动手。
- **角色边界严格**：Planner 不直接写功能代码；Executor 不动 docs/* 与 tasks/README.md。
- **正常情况下 Executor 不能自己归档任务**（即不能自己改 Status: done）。Fallback B 例外，见 COLLAB.md §9。

## 文档导航（多 agent 协作相关）

| 想做的事 | 先读 |
|---|---|
| **多 agent 协作机制 / 你被派来执行任务（必读）** | [docs/COLLAB.md](docs/COLLAB.md) |
| **看现在有什么 open 任务** | [tasks/README.md](tasks/README.md) |

## 不要做的事（协作相关）

- **Executor 不要改** `docs/*` / `tasks/README.md` / `AGENTS.md` / planning 类文件（task_plan.md / progress.md / findings.md 如有），那是 Planner 的编辑权区。
- 不要在没有 spec 的情况下做架构改动。
- 不要 force push 到主分支。
- 不要自己改 Status: done（除非 Fallback B 且自审清单全过）。

## 待补充

随项目演进，后续可在此追加：
- 已知技术债务清单
- 易踩的坑（如 NSSplitView autosave 会偷偷收起窗格、macOS 26 keychain TCC 行为差异等）
- 代码风格 / 命名约定（如该项目慢慢形成）
- 第三方依赖详情
