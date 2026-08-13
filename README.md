# ForkLiftClone

类 ForkLift 的 Mac 本地文件管理器，SwiftUI + SwiftPM 构建，目标 macOS 14+。

> 详细方案见 `~/.claude/plans/mac-forklift-silly-whistle.md`。

## 已交付（阶段 1 + 阶段 2）

- ✅ NavigationSplitView：左侧 **Sidebar 收藏夹** + 右侧 HSplitView 双窗格
- ✅ **每个 Pane 多 Tab**（Cmd+T 复制当前 Tab，× 关闭）
- ✅ Pane 工具栏：后退/前进/上级/刷新/隐藏文件 toggle/**当前目录搜索**
- ✅ 路径栏面包屑、Table 列表（图标/大小/时间），点列头排序
- ✅ 右键菜单：打开 / 在新标签页打开 / Finder 显示 / 复制路径 / 移到废纸篓
- ✅ 空格 QuickLook、Cmd+I (待) 等键盘交互
- ✅ **F5 / F6** 复制/移动到对侧 Pane（NSEvent local monitor）
- ✅ Cmd+Shift+C / Cmd+Shift+X 备用快捷键
- ✅ Cmd+[ / Cmd+] / Cmd+↑ / Cmd+R 导航
- ✅ Cmd+Return 重命名对话框
- ✅ Cmd+D 把当前目录加入收藏（持久化到 `~/Library/Application Support/ForkLiftClone/bookmarks.json`）
- ✅ **Pane 之间拖拽**复制（走 TransferQueue）
- ✅ **传输队列 Inspector**（工具栏图标切换），实时进度、状态、清空已完成
- ✅ **三套主题**（macOS 原生 / 现代深色 / 轻量明亮），Cmd+, 设置里切换，UserDefaults 持久化
- ✅ DirectoryWatcher：在 Finder 改文件，对应 Pane 自动刷新
- ✅ 状态栏：选中数 + 总大小 + loading + 错误
- ✅ 15 个 Core 单测全绿

## 项目结构

```
类forklift-项目/
├── Package.swift                     ← 顶层 SwiftPM，executable target
├── App/                              ← App 源码（path: "App"）
│   ├── Info.plist
│   ├── ForkLiftCloneApp.swift        @main + 命令菜单 + F5/F6 NSEvent
│   ├── Services/
│   │   ├── BookmarksStore.swift      Sidebar 收藏的 JSON 持久化
│   │   └── ThemeStore.swift          主题切换 + UserDefaults
│   ├── ViewModels/
│   │   ├── PaneTabsViewModel.swift   单边的 Tab 容器
│   │   └── PaneViewModel.swift       单 Tab 的状态
│   └── Views/
│       ├── MainWindowView.swift      NavigationSplitView + HSplitView + Inspector
│       ├── PaneView.swift            TabBar + Toolbar + PathBar + Table + StatusBar
│       ├── TabBarView.swift
│       ├── PaneToolbarView.swift     后退/前进/上级/刷新/隐藏/搜索
│       ├── PathBarView.swift
│       ├── FileTableView.swift       Table + 右键菜单 + 拖拽 + QuickLook
│       ├── StatusBarView.swift
│       ├── TransferInspectorView.swift 队列侧栏
│       ├── Sidebar/SidebarView.swift   收藏列表
│       └── Settings/SettingsView.swift 主题切换面板
├── Packages/Core/                    ← 内部 SwiftPM
│   ├── Package.swift
│   ├── Sources/
│   │   ├── FileSystemKit/            FileItem / FileProvider / LocalFileProvider / DirectoryWatcher
│   │   ├── TransferEngine/           TransferTask / ConflictResolver / TransferQueue
│   │   ├── PreviewKit/               QuickLookView
│   │   └── AppearanceKit/            AppearanceTheme + 三套主题
│   └── Tests/                        15 个单测
└── scripts/
    └── build-app.sh                  一键构建 ForkLiftClone.app
```

## 日常使用

### 跑 App

一行命令构建并启动：

```bash
./scripts/build-app.sh
open build/ForkLiftClone.app
```

或者开发期直接 `swift run`（启动会快一点，但没有完整 .app bundle 行为）：

```bash
swift run ForkLiftClone
```

### 跑测试

```bash
cd Packages/Core
swift test
```

预期：15 个用例全绿（FileSystemKit 8 + TransferEngine 7）。

### 在 Xcode 里开发

直接用 Xcode 打开顶层 `Package.swift`：

```bash
open Package.swift
```

Xcode 会把这个 SwiftPM 当成一个项目，可以直接 Cmd+R / Cmd+U。不需要 `.xcodeproj`。

### 装到 /Applications

```bash
./scripts/build-app.sh
cp -R build/ForkLiftClone.app /Applications/
```

## 阶段 2 验收清单

构建/测试已通过。下面是手动验证清单：

- [ ] Sidebar 显示 5 个默认收藏（主目录/桌面/下载/文档/应用程序），点击跳转
- [ ] Cmd+D 把当前目录加入收藏；右键 → 「从收藏中移除」
- [ ] Cmd+T 在当前 Pane 复制一个 Tab；点 × 关闭；点 + 也能新建
- [ ] PaneToolbar 搜索框输入关键字，列表实时过滤
- [ ] 隐藏文件 toggle 切换显示 dot 文件
- [ ] F5 把选中文件复制到对侧 Pane（看 Inspector 进度条）
- [ ] F6 把选中文件移动到对侧
- [ ] Cmd+[ / Cmd+] 走导航历史；Cmd+↑ 上级；Cmd+R 刷新
- [ ] Cmd+Return 弹重命名对话框
- [ ] 选中文件，从一个 Pane 拖到另一个 Pane → 走传输队列复制
- [ ] 工具栏右上角的「传输」按钮切出 Inspector，能看到任务进度 + 清空已完成
- [ ] Cmd+, 打开设置，切换三套主题，所有界面颜色/字号/圆角立刻变；重启后保留
- [ ] 在 Finder 改一个目录里的文件，对应 Pane 自动刷新

## 阶段 3（待做）

- SFTP / S3 / WebDAV 远程协议
- 归档（zip/tar）压缩 + 解压 + 虚拟目录浏览
- 传输冲突弹窗（覆盖/跳过/重命名/合并）
- 大文件并发分片传输

## 已知技术点

- **Swift 6 actor 隔离**：`@MainActor` 类不能在 `deinit` 里访问自己的 isolated 属性。`PaneViewModel` 提供 `stopObserving()` 公开方法供 View 在 `.onDisappear` 调用。
- **`swift build` 的 build.db SQLite 警告**：返回 exit 1 但产物正常。`build-app.sh` 用「检查产物存在」绕过。
- **App Sandbox**：未启用（无 entitlements 文件），所以可以访问任意路径。后续若上架 MAS，再切到 Security-Scoped Bookmarks。
- **Code signing**：ad-hoc 签名（`codesign --sign -`），自己用没问题。要分发给别人才需要 Developer ID 签名 + 公证。
