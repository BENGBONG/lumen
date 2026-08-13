---
name: lumen-dev-workflow
description: Lumen（类forklift-项目）macOS 文件管理器的日常开发流程——构建/测试/打包/重启/验证的正确命令与已踩过的坑。改动这个项目代码时使用。
---

# Lumen 开发工作流

项目：`/Users/admin/Desktop/AI code/按项目工作/类forklift-项目`（独立 git 仓库，main 分支）。

## 构建 / 测试 / 打包（命令必须长这样）

```bash
# 编译（本会话环境必须 --disable-sandbox，否则 sandbox-exec 被拦；
#        必须 pipefail，否则编译错误被管道吞掉、打包包旧二进制！）
set -o pipefail && swift build --disable-sandbox -c debug --product ForkLiftClone 2>&1 | tail -5

# 测试（Core 包 56+ 单测）
cd Packages/Core && swift test --disable-sandbox

# 打包 + 重启
bash scripts/build-app.sh debug && pkill -x ForkLiftClone; sleep 1; open build/Lumen.app
```

**血泪教训**：`swift build | tail` 的退出码是 tail 的——编译失败也会继续执行 `&&` 后面的打包，
导致用户拿到旧二进制（2026-08-13 撤回功能"没反应"就是这个原因）。
确认构建成功要看输出里有 `Build of product 'ForkLiftClone' complete!`。

## 已踩过的坑（改相关代码前必读）

1. **CommandGroupPlacement 没有 `.undo`**——自定义撤回菜单用 `CommandGroup(before: .pasteboard)`（编辑菜单顶部）。
2. **NavigationSplitView 侧栏**：列宽只用 `.navigationSplitViewColumnWidth(min:ideal:max:)`；侧栏内容绝不手写 `.frame(maxWidth:)`（会把内容挤出可视区）。
3. **Swift 独占性**：`data.withUnsafeBytes` 闭包内不能同时 mutate 外层 var——拆成"闭包返回 produced 计数 + 外部 append"。
4. **局部变量遮蔽同名方法**：`let archive = ...` 后 `archive(for:)` 方法就调不到了——局部命名用 `archiveURL`。
5. **updateNSView 里写 @Observable 状态** 触发 "modifying state during view update"——用 `DispatchQueue.main.async` 推迟。
6. **NSTableView + .id 重建可能漏 reload**——NativeFileTable 已有自愈：`table.numberOfRows != items.count` 对账补 reload。改动数据流时保持这个不变式。
7. **NSMenu 子菜单项**不进 `menu.items` 顶层循环，target 要单独挂；representedObject 被占用时另传值。
8. **TCC**：ad-hoc 重签后 Desktop/Documents 权限可能重置，`tccutil reset All com.panglin.forkliftclone`；Bundle ID 不能改（会丢 Keychain 里的 AI key）。

## 架构速查

- **FileProvider 协议**（FileSystemKit）是一切的抽象：LocalFileProvider（本地）、RoutedFileProvider（路由：路径穿过 zip/tar 即归档虚拟目录，providerID 恒为 "local"）。
- **TransferQueue**（@MainActor）：enqueue([TransferTask]) 批量入队共享 batchID；冲突走 ConflictResolver（UI=UserConflictResolver NSAlert）；成功记录逆操作进 undoStack（Cmd+Z 撤回批次）。
- **重命名**：PaneViewModel.pendingRenameID → NativeFileTable 内联 overlay（不是弹窗）。
- **焦点**：focusedSide 切换时清空对侧 selection；ThemedRowView 自绘选中条（焦点 accent/非焦点灰）。
- **主题**：AppearanceKit 三主题，材质+染色叠层（`glassChrome`/`glassPane` View 扩展）。
- **通知**：跨层通信用 NotificationCenter（.fl* 系列，定义在 ForkLiftCloneApp.swift 末尾）。

## 提交规范

`feat:` / `fix:` / `docs:` / `chore:` 前缀 + 中文描述；功能 commit 前必须 测试全绿 + pipefail 构建通过。
