# Lumen

macOS 双窗格文件管理器，集成 AI 文件对话与自然语言操作。SwiftUI + AppKit 混合实现，SwiftPM 构建，目标 macOS 14 Sonoma+。

## 功能现状

**文件管理：**
- 双窗格 + 多标签（Cmd+T 复制标签）+ 导航历史（Cmd+[ / Cmd+]）
- 拖拽移动/复制（含跨窗格 + Finder 互操作）
- Cmd+C / Cmd+X / Cmd+V 剪贴板
- F2 内联重命名（编辑框落在列表行上，新建文件后自动进入）
- 传输队列（覆盖式 overlay 面板），实时进度
- 传输冲突弹窗（保留两者 / 覆盖 / 跳过 / 停止，支持"应用到所有冲突"）
- QuickLook（Space）
- 压缩 / 解压
- **归档虚拟目录浏览**（zip / tar / tar.gz / tgz）：双击进入像文件夹一样浏览，条目可预览/拷出，内部只读
- **新建文件**：txt / md / py / docx / xlsx / pptx（右键空白处或文件菜单；Office 模板运行时生成）
- 路径栏直接输入
- Sidebar 收藏（Cmd+D 添加，JSON 持久化）
- 三套主题切换（macOS 原生 / 现代深色 / 轻量明亮），Cmd+, 设置
- DirectoryWatcher：Finder 改动后对应 Pane 自动刷新

**AI 功能：**
- File Chat（Cmd+I）：围绕选中文件/目录与 AI 对话
- AI 自然语言搜索（工具栏 ✦ AI 按钮）
- AI 批量操作（Cmd+Shift+A）
- 支持 Claude / OpenAI / OpenRouter / 自定义 endpoint（MiniMax 等），Keychain 存 key，设置页可测连接

## 构建 / 运行

```bash
# 完整构建（产出 build/Lumen.app）
bash scripts/build-app.sh debug

# 仅编译（不打包）
swift build -c debug --product ForkLiftClone

# 启动
open build/Lumen.app
```

跑测试：

```bash
cd Packages/Core && swift test
```

> 注：某些沙盒环境下 SwiftPM 的 manifest 编译会被 sandbox-exec 拦截，加 `--disable-sandbox` 即可。

**注意事项：**
- Bundle ID 保持 `com.panglin.forkliftclone`（改了会丢 Keychain 里的 AI key）
- 每次 ad-hoc 重签后 macOS 可能要重新授权 Desktop/Documents 访问，可用 `tccutil reset All com.panglin.forkliftclone` 一键重置
- `swift build` 偶尔报 `build.db: disk I/O error`——非致命，可忽略

## 项目结构

```
├── App/                          # 主 App target（SwiftUI 壳）
│   ├── ForkLiftCloneApp.swift    # @main 入口，菜单与快捷键
│   ├── Views/                    # 含 AI/（FileChatPanel 等）与 Settings/
│   ├── ViewModels/               # PaneViewModel / PaneTabsViewModel
│   └── Services/                 # ThemeStore / BookmarksStore / PaneStateStore
├── Packages/Core/                # 内部 SwiftPM，5 个 library targets
│   └── Sources/
│       ├── FileSystemKit/        # FileProvider 协议 + LocalFileProvider + RoutedFileProvider
│       │                         # （归档虚拟目录路由）+ Zip/TarArchiveReader + 新建文件模板
│       ├── TransferEngine/       # 复制/移动队列，进度，冲突解决
│       ├── PreviewKit/           # QuickLook 封装
│       ├── AppearanceKit/        # 三套主题
│       └── AIKit/                # ClaudeClient / KeychainStore / ChatSession / AIProvider
├── scripts/build-app.sh          # swift build → 装配 .app → 拷 icon → ad-hoc 签名
├── docs/                         # 协作协议与项目规范
└── tasks/                        # 多 agent 任务队列（规则见 docs/COLLAB.md）
```

## 待做（候选方向）

- ~~归档（zip/tar）虚拟目录浏览~~ ✅ 已完成（zip / tar / tgz / tar.gz）
- SFTP / S3 / WebDAV 远程协议
- 大文件并发分片传输
- 目录合并（冲突弹窗已预留 .merge，目前返回会报 mergeUnsupported）
- 归档内写入（向 zip 追加/删除条目）
- AI 功能打磨（端到端验证、错误处理、流式体验）

## 已知技术点

- **Swift 6 actor 隔离**：`@MainActor` 类不能在 `deinit` 里访问自己的 isolated 属性。`PaneViewModel` 提供 `stopObserving()` 供 View 在 `.onDisappear` 调用。
- **App Sandbox**：未启用（无 entitlements），可访问任意路径。若上架 MAS 需切 Security-Scoped Bookmarks。
- **Code signing**：ad-hoc 签名（`codesign --sign -`），自用没问题；分发需 Developer ID + 公证。
- **NSSplitView autosave** 会偷偷收起窗格——`EqualHSplitView` 已处理，改动时留意。
