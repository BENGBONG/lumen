import SwiftUI
import AppKit
import QuickLookUI
import FileSystemKit
import AppearanceKit
import AIKit

struct FileTableView: View {
    @Bindable var vm: PaneViewModel
    /// 所属窗格是否为焦点窗格（透传给表格决定选中行颜色）。
    var isPaneFocused: Bool = false
    let onOpenInNewTab: (ProviderPath) -> Void
    let onDropFiles: ([URL], ProviderPath, Bool) -> Void   // (urls, destination, isMove)
    let onUserInteraction: () -> Void
    @Environment(\.appearanceTheme) private var theme
    @State private var batchBarVisible = false

    var body: some View {
        // No `.onChange(of: vm.selection)` here — that observation would force
        // FileTableView body to re-evaluate on every click, which rebuilds
        // NativeFileTable's struct and re-runs updateNSView. Selection is
        // mirrored to AppDelegate (for QuickLook) directly inside the
        // Coordinator's tableViewSelectionDidChange — synchronously and
        // without going through SwiftUI's observation system.
        ZStack {
            NativeFileTable(
                items: vm.items,
                selection: $vm.selection,
                sortKey: $vm.sortKey,
                sortAscending: $vm.sortAscending,
                theme: theme,
                onOpen: { item in openOne(item) },
                onSpace: { items in previewItems(items) },
                onBackspace: { Task { await vm.goUp() } },
                onEscape: {
                    if !vm.searchQuery.isEmpty {
                        vm.setSearch("")
                    } else {
                        vm.selection.removeAll()
                    }
                },
                currentDirectory: URL(fileURLWithPath: vm.currentPath.displayString),
                onDropFiles: { urls, destDirURL, isMove in
                    // Convert destination URL → ProviderPath.
                    let destComponents = destDirURL.standardizedFileURL
                        .pathComponents.filter { $0 != "/" && !$0.isEmpty }
                    let destPath = ProviderPath(providerID: vm.provider.id,
                                               components: destComponents)
                    // Skip files that are already in the destination directory.
                    let destStd = destDirURL.standardizedFileURL.path
                    let filtered = urls.filter { url in
                        url.deletingLastPathComponent().standardizedFileURL.path != destStd
                    }
                    guard !filtered.isEmpty else { return false }
                    onDropFiles(filtered, destPath, isMove)
                    return true
                },
                onContextMenu: { itemsForMenu in
                    onUserInteraction()
                    return buildContextMenu(items: itemsForMenu)
                },
                onRename: { item, newName in
                    Task {
                        try? await vm.provider.rename(
                            vm.currentPath.appending(item.name), to: newName)
                        await vm.reload()
                    }
                },
                renameRequestID: vm.pendingRenameID,
                onRenameRequestConsumed: {
                    // 延迟到下一 runloop 清状态，避免在 view update 中写 @Observable
                    DispatchQueue.main.async { vm.pendingRenameID = nil }
                },
                isPaneFocused: isPaneFocused,
                onTableInteraction: onUserInteraction
            )

            stateOverlay
                .allowsHitTesting(false)

            // AI Batch command bar — slides up from the bottom
            if batchBarVisible {
                VStack {
                    Spacer()
                    AIBatchCommandBar(
                        isPresented: $batchBarVisible,
                        items: vm.items,
                        currentPath: vm.currentPath,
                        provider: vm.provider,
                        onReload: { Task { await vm.reload() } }
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(duration: 0.28), value: batchBarVisible)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .flAIBatch)) { _ in
            withAnimation { batchBarVisible.toggle() }
        }
    }

    @ViewBuilder
    private var stateOverlay: some View {
        if let err = vm.errorMessage {
            VStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 30))
                    .foregroundStyle(.red.opacity(0.7))
                Text(err)
                    .font(.system(size: theme.bodyFontSize))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
            }
            .padding(40)
        } else if vm.items.isEmpty && !vm.isLoading {
            VStack(spacing: 6) {
                Image(systemName: vm.searchQuery.isEmpty ? "tray" : "magnifyingglass")
                    .font(.system(size: 30))
                    .foregroundStyle(theme.secondaryText.opacity(0.5))
                Text(emptyMessage)
                    .font(.system(size: theme.captionFontSize))
                    .foregroundStyle(theme.secondaryText)
            }
        }
    }

    private var emptyMessage: String {
        if !vm.searchQuery.isEmpty { return "没有匹配「\(vm.searchQuery)」的项目" }
        if vm.totalCount == 0 { return "空目录" }
        return ""
    }

    // MARK: - Context menu (built lazily by NativeFileTable on right-click)

    private func buildContextMenu(items targetItems: [FileItem]) -> NSMenu? {
        let insideArchive = (vm.provider as? RoutedFileProvider)?
            .isInsideArchive(vm.currentPath) ?? false

        let menu = NSMenu()
        if targetItems.isEmpty {
            // 归档内部是只读虚拟目录，空白处不提供任何创建/管理操作
            if insideArchive { return nil }
            menu.addItem(item("新建文件夹", #selector(MenuActions.mkdir)))
            let newFileMenu = NSMenu()
            for template in NewFileTemplate.allCases {
                let mi = NSMenuItem(title: template.displayName,
                                    action: #selector(MenuActions.newFile(_:)),
                                    keyEquivalent: "")
                mi.representedObject = template.rawValue
                newFileMenu.addItem(mi)
            }
            let newFileItem = NSMenuItem(title: "新建文件", action: nil, keyEquivalent: "")
            newFileItem.submenu = newFileMenu
            menu.addItem(newFileItem)
            menu.addItem(item("用 Finder 显示当前目录", #selector(MenuActions.revealCurrentDir)))
        } else {
            menu.addItem(item("打开", #selector(MenuActions.openSelected)))
            // 单选普通文件时提供「打开方式」子菜单（归档虚拟目录内没有真实路径，跳过）
            if !insideArchive,
               targetItems.count == 1,
               let file = targetItems.first,
               !file.isDirectory {
                let openWithItem = NSMenuItem(title: "打开方式", action: nil, keyEquivalent: "")
                openWithItem.submenu = buildOpenWithMenu(for: file)
                menu.addItem(openWithItem)
            }
            let openInTab = item("在新标签页打开", #selector(MenuActions.openInNewTab))
            openInTab.isEnabled = targetItems.contains(where: { $0.isDirectory })
            menu.addItem(openInTab)
            let addBookmark = item("添加到收藏", #selector(MenuActions.addToBookmarks))
            addBookmark.isEnabled = targetItems.contains(where: { $0.isDirectory && !$0.isPackage })
            menu.addItem(addBookmark)
            if !insideArchive {
                menu.addItem(item("用 Finder 显示", #selector(MenuActions.revealSelected)))
            }
            menu.addItem(.separator())
            menu.addItem(item("复制路径", #selector(MenuActions.copyPaths)))
            if !insideArchive {
                menu.addItem(item("重命名…", #selector(MenuActions.rename)))
                menu.addItem(.separator())
                menu.addItem(item("压缩为 ZIP", #selector(MenuActions.compressToZip)))
                // "解压到此处" only appears when a single archive file is selected.
                let archiveExts: Set<String> = ["zip", "tar", "gz", "bz2", "tgz", "7z", "rar"]
                if targetItems.count == 1,
                   let ext = targetItems[0].name.split(separator: ".").last.map(String.init)?.lowercased(),
                   archiveExts.contains(ext) {
                    menu.addItem(item("解压到此处", #selector(MenuActions.extractHere)))
                }
                menu.addItem(.separator())
                let trash = item("移到废纸篓", #selector(MenuActions.trash))
                trash.attributedTitle = NSAttributedString(
                    string: "移到废纸篓",
                    attributes: [.foregroundColor: NSColor.systemRed]
                )
                menu.addItem(trash)
            }
        }
        // Bind the closures into MenuActions object via representedObject
        let actions = MenuActions(
            items: targetItems,
            currentPath: vm.currentPath,
            provider: vm.provider,
            insideArchive: insideArchive,
            openOne: { self.openOne($0) },
            openInTabFor: { self.onOpenInNewTab($0) },
            reload: { Task { await vm.reload() } }
        )
        for menuItem in menu.items where menuItem.action != nil {
            menuItem.target = actions
            menuItem.representedObject = actions
        }
        // 子菜单项不进上面的循环：单独挂 target。
        // - 新建文件模板项：representedObject 已被占用为模板类型标识
        // - 打开方式项：representedObject 已被占用为目标应用 URL
        for subItem in menu.items where subItem.submenu != nil {
            for mi in subItem.submenu?.items ?? [] where mi.action != nil {
                mi.target = actions
            }
        }
        // Keep the actions alive for the menu's lifetime via associated object on the menu.
        objc_setAssociatedObject(menu, &MenuActions.assocKey, actions, .OBJC_ASSOCIATION_RETAIN)
        return menu
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        NSMenuItem(title: title, action: action, keyEquivalent: "")
    }

    /// 「打开方式」子菜单：默认应用置顶带勾 + 其他候选（带应用图标）+「其他…」。
    /// target 由 buildContextMenu 底部循环统一挂到 MenuActions。
    private func buildOpenWithMenu(for file: FileItem) -> NSMenu {
        let submenu = NSMenu()
        let url = file.url

        let defaultApp = NSWorkspace.shared.urlForApplication(toOpen: url)
        var candidates = NSWorkspace.shared.urlsForApplications(toOpen: url)

        // 默认应用提到最前（与 Finder 语义一致）
        if let def = defaultApp {
            candidates.removeAll { $0 == def }
            candidates.insert(def, at: 0)
        }

        for appURL in candidates {
            let mi = NSMenuItem(title: appName(for: appURL),
                                action: #selector(MenuActions.openWith(_:)),
                                keyEquivalent: "")
            mi.representedObject = appURL
            if appURL == defaultApp { mi.state = .on }
            let icon = NSWorkspace.shared.icon(forFile: appURL.path)
            icon.size = NSSize(width: 16, height: 16)
            mi.image = icon
            submenu.addItem(mi)
        }

        if !candidates.isEmpty { submenu.addItem(.separator()) }
        let other = NSMenuItem(title: "其他…",
                               action: #selector(MenuActions.openWithOther),
                               keyEquivalent: "")
        submenu.addItem(other)
        return submenu
    }

    private func appName(for bundleURL: URL) -> String {
        if let bundle = Bundle(url: bundleURL) {
            if let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String),
               !name.isEmpty {
                return name
            }
        }
        return bundleURL.deletingPathExtension().lastPathComponent
    }

    // MARK: - Actions

    private func openOne(_ item: FileItem) {
        if item.isDirectory && !item.isPackage {
            Task { await vm.navigate(to: vm.currentPath.appending(item.name)) }
        } else if RoutedFileProvider.isBrowsableArchive(name: item.name) {
            // 双击归档（zip/tar/tgz/tar.gz）：进入虚拟目录浏览
            Task { await vm.navigate(to: vm.currentPath.appending(item.name)) }
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }

    private func previewItems(_ items: [FileItem]) {
        // NativeFileTable.handleKeyDown now handles Space directly via
        // ForkLiftTableView (first-responder QLPreviewPanel controller).
        // This method stays as a programmatic fallback for other callers.
        let urls = items.map(\.url)
        AppDelegate.shared?.quickLookURLs = urls
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.isVisible ? panel.reloadData() : panel.makeKeyAndOrderFront(nil)
    }
}

// MARK: - NSMenu target for context menu

@MainActor
final class MenuActions: NSObject {
    nonisolated(unsafe) static var assocKey: UInt8 = 0

    let items: [FileItem]
    let currentPath: ProviderPath
    let provider: any FileProvider
    let insideArchive: Bool
    let openOne: (FileItem) -> Void
    let openInTabFor: (ProviderPath) -> Void
    let reload: () -> Void

    init(items: [FileItem],
         currentPath: ProviderPath,
         provider: any FileProvider,
         insideArchive: Bool,
         openOne: @escaping (FileItem) -> Void,
         openInTabFor: @escaping (ProviderPath) -> Void,
         reload: @escaping () -> Void) {
        self.items = items
        self.currentPath = currentPath
        self.provider = provider
        self.insideArchive = insideArchive
        self.openOne = openOne
        self.openInTabFor = openInTabFor
        self.reload = reload
    }

    @objc func openSelected() {
        for item in items { openOne(item) }
    }

    /// 用指定应用打开当前选中文件（「打开方式」子菜单）。
    @objc func openWith(_ sender: NSMenuItem) {
        guard let appURL = sender.representedObject as? URL else { return }
        openFiles(with: appURL)
    }

    /// 「其他…」：NSOpenPanel 选任意应用后打开。
    @objc func openWithOther() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        // 只显示 .app（按包判定，与 Finder 一致）
        panel.allowedContentTypes = [.application]
        guard panel.runModal() == .OK, let appURL = panel.url else { return }
        openFiles(with: appURL)
    }

    private func openFiles(with appURL: URL) {
        let urls = items.filter { !$0.isDirectory }.map(\.url)
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.open(urls, withApplicationAt: appURL,
                                configuration: NSWorkspace.OpenConfiguration())
    }

    @objc func openInNewTab() {
        for item in items where item.isDirectory {
            openInTabFor(currentPath.appending(item.name))
        }
    }

    @objc func revealSelected() {
        let urls = items.map(\.url)
        if !urls.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        }
    }

    @objc func revealCurrentDir() {
        NSWorkspace.shared.activateFileViewerSelecting([
            URL(fileURLWithPath: currentPath.displayString)
        ])
    }

    @objc func copyPaths() {
        // 归档内部条目复制虚拟路径（FileItem.id 就是虚拟路径字符串），
        // 本地文件复制真实路径
        let paths = insideArchive ? items.map(\.id) : items.map(\.url.path)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(paths.joined(separator: "\n"), forType: .string)
    }

    @objc func newFile(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        NotificationCenter.default.post(name: .flNewFile, object: nil,
                                        userInfo: ["template": raw])
    }

    @objc func addToBookmarks() {
        let dirs = items.filter { $0.isDirectory && !$0.isPackage }
        // 归档内部条目用虚拟路径（FileItem.id），本地用真实路径
        let paths = dirs.map { insideArchive ? $0.id : $0.url.path }
        guard !paths.isEmpty else { return }
        NotificationCenter.default.post(name: .flBookmarkPaths, object: nil,
                                        userInfo: ["paths": paths])
    }

    @objc func rename() {
        NotificationCenter.default.post(name: .flRename, object: nil)
    }

    @objc func mkdir() {
        NotificationCenter.default.post(name: .flMkdir, object: nil)
    }

    @objc func trash() {
        let snapshot = items
        let provider = self.provider
        let path = currentPath
        let reload = self.reload
        Task { @MainActor in
            for item in snapshot {
                try? await provider.delete(path.appending(item.name), toTrash: true)
            }
            reload()
        }
    }

    // MARK: - Archive operations

    @objc func compressToZip() {
        let snapshot    = items
        let destDirURL  = URL(fileURLWithPath: currentPath.displayString)
        let reload      = self.reload

        // Build a unique archive name.
        let baseName = snapshot.count == 1
            ? (snapshot[0].name as NSString).deletingPathExtension
            : "归档"
        var zipURL   = destDirURL.appendingPathComponent(baseName + ".zip")
        var suffix   = 1
        while FileManager.default.fileExists(atPath: zipURL.path) {
            zipURL = destDirURL.appendingPathComponent("\(baseName) \(suffix).zip")
            suffix += 1
        }

        Task {
            // Run zip on a background thread — `waitUntilExit` is blocking.
            await withCheckedContinuation { cont in
                DispatchQueue.global(qos: .userInitiated).async {
                    let process = Process()
                    process.executableURL     = URL(fileURLWithPath: "/usr/bin/zip")
                    var args: [String]        = ["-r", zipURL.path]
                    args                     += snapshot.map(\.name)
                    process.arguments         = args
                    process.currentDirectoryURL = destDirURL
                    try? process.run()
                    process.waitUntilExit()
                    cont.resume()
                }
            }
            reload()
        }
    }

    @objc func extractHere() {
        guard let archive = items.first else { return }
        let zipURL     = archive.url
        let destDirURL = zipURL.deletingLastPathComponent()
        let reload     = self.reload

        Task {
            await withCheckedContinuation { cont in
                DispatchQueue.global(qos: .userInitiated).async {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                    process.arguments     = ["-o", zipURL.path, "-d", destDirURL.path]
                    try? process.run()
                    process.waitUntilExit()
                    cont.resume()
                }
            }
            reload()
        }
    }
}
