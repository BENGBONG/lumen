# Lumen 项目长期记忆

> 策展后的长期事实。每日流水在 `YYYY-MM-DD.md`。

## 项目是什么

**Lumen** —— macOS 双窗格文件管理器 + AI（File Chat / AI 搜索 / AI 批量操作）。SwiftUI+AppKit，SwiftPM，macOS 14+。仓库 2026-08-13 从大 monorepo 独立出来（此前两个月工作差点丢失）。可执行产物名仍为 ForkLiftClone，Bundle ID `com.panglin.forkliftclone`（不能改，会丢 Keychain AI key）。

## 当前功能水位（2026-08-13 收盘）

文件管理：双窗格多标签、拖拽/剪贴板/F5-F6、内联重命名（无弹窗）、传输队列+冲突弹窗、**Cmd+Z 批次撤回**、Cmd+Backspace 删除、type-to-select、收藏闭环（右键添加/拖入/排序）、**归档虚拟目录浏览**（zip/tar/tgz/tar.gz，只读，临时缓存支撑预览拷出）、**新建文件 6 种模板**（txt/md/py + 运行时生成 docx/xlsx/pptx）、**8 套玻璃主题**（原生/明亮/现代深色/深海/琥珀/抹茶/蔷薇/水墨）、会话状态完整持久化（多标签+焦点）。
AI：File Chat（**能读 docx/xlsx/pptx 正文**，图片自动≤1568px）、AI 搜索、AI 批量操作（预览确认+失败报告+重命名可撤回）。多 provider（Claude/OpenAI/OpenRouter/自定义），Keychain 存 key。

测试：**60 个单测全绿**（FileSystemKit/TransferEngine/AIKit）。

## 关键约定（改动前必读）

1. 构建必须 `set -o pipefail && swift build --disable-sandbox ...`，且看到 "Build of product complete" 才算成；**构建-重启链路禁用 `;`**。
2. 更多坑（背景叠层顺序、NavigationSplitView 列宽、菜单 placement、type-check 超时等 13 条）见 `.workbuddy/skills/lumen-dev-workflow/SKILL.md`——**改代码前先读它**。
3. 通知机制：跨层通信用 `.fl*` NotificationCenter（定义在 ForkLiftCloneApp.swift 末尾）。
4. 归档语义：RoutedFileProvider 路径与本地完全一致（providerID="local"），穿过归档文件即虚拟目录、内部只读。

## 路线图剩余

目录合并（.merge 已预留入口）、归档内写入（StoredZipWriter 有底子）、SFTP/S3/WebDAV、大文件分片、redo（Cmd+Shift+Z）、重命名/新建的撤回、废纸篓放回原处。

## 用户偏好

- 不要弹窗，要内联（重命名案例）
- 焦点/选中状态要明显（描边、灰选中行、跨窗格选中互斥）
- 主题要有质感、融合要深（不接受发白的假玻璃）
- 交互惯例对齐 macOS/Finder（Cmd+Z、Cmd+Backspace、字母跳选）
- 直接规划直接干，不走 COLLAB 角色制（2026-08-13 起）
