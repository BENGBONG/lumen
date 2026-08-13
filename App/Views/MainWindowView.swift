import SwiftUI
import FileSystemKit
import TransferEngine
import AppearanceKit
import AIKit

struct MainWindowView: View {
    @State private var leftTabs: PaneTabsViewModel
    @State private var rightTabs: PaneTabsViewModel
    @State private var bookmarks = BookmarksStore()
    @State private var focusedSide: PaneSide = .left
    @State private var inspectorVisible = false
    @State private var chatVisible = false
    @State private var chatContextURLs: [URL] = []
    @StateObject private var queue: TransferQueue

    enum PaneSide { case left, right }

    init() {
        // RoutedFileProvider：对外仍是本地路径语义，但路径穿过 .zip 时
        // 自动切换为归档虚拟目录（双击进入浏览、条目可拷出、内部只读）。
        let provider = RoutedFileProvider()
        let home = FileManager.default.homeDirectoryForCurrentUser
        let snapshot = PaneStateStore.load()
        let leftURL = snapshot
            .flatMap { URL(fileURLWithPath: $0.leftPath) }
            .flatMap(Self.directoryOrNil) ?? home
        let rightURL = snapshot
            .flatMap { URL(fileURLWithPath: $0.rightPath) }
            .flatMap(Self.directoryOrNil) ?? URL(fileURLWithPath: "/Applications")
        let leftPath = provider.providerPath(for: leftURL)
        let rightPath = provider.providerPath(for: rightURL)
        _leftTabs = State(wrappedValue: PaneTabsViewModel(provider: provider, initialPath: leftPath))
        _rightTabs = State(wrappedValue: PaneTabsViewModel(provider: provider, initialPath: rightPath))
        _queue = StateObject(wrappedValue: TransferQueue(provider: provider,
                                                         resolver: UserConflictResolver()))
    }

    private static func directoryOrNil(_ url: URL) -> URL? {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
            ? url : nil
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(store: bookmarks) { bookmark in
                Task { await activeTabs().active.navigate(to: bookmark.providerPath) }
            }
            // 列宽由 NavigationSplitView 托管——在 SidebarView 里手写
            // .frame(maxWidth:) 会导致拖宽列时内容布局坍塌消失
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 340)
        } detail: {
            detailPane
        }
        .task {
            await leftTabs.active.load()
            await rightTabs.active.load()
        }
        .onChange(of: leftTabs.active.currentPath) { _, _ in persistPaneState() }
        .onChange(of: rightTabs.active.currentPath) { _, _ in persistPaneState() }
        .onChange(of: queue.tasks.count) { _, count in
            // Auto-open inspector panel whenever a transfer is enqueued.
            if count > 0 { inspectorVisible = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .flPasteFiles)) { note in
            guard let urls = note.userInfo?["urls"] as? [URL], !urls.isEmpty else { return }
            let isCut = note.userInfo?["isCut"] as? Bool ?? false
            let dest  = activeTabs().active.currentPath
            handleDrop(urls: urls, destination: dest, kind: isCut ? .move : .copy)
        }
        .onReceive(NotificationCenter.default.publisher(for: .flNewFile)) { note in
            guard let raw = note.userInfo?["template"] as? String,
                  let template = NewFileTemplate(rawValue: raw) else { return }
            Task { await newFileInActive(template) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .flBookmarkPaths)) { note in
            guard let paths = note.userInfo?["paths"] as? [String] else { return }
            for p in paths {
                let name = URL(fileURLWithPath: p).lastPathComponent
                bookmarks.add(Bookmark(name: name.isEmpty ? "/" : name, path: p))
            }
        }
        .modifier(NotificationListeners(listeners: notificationListeners))
    }

    private var detailPane: some View {
        // EqualHSplitView: custom NSSplitView wrapper that keeps both panes
        // at the same *proportion* when the window is resized (fixes the
        // imbalance caused by NSSplitView's default last-pane-gets-all-space
        // behaviour). Autosave is disabled so a corrupted position can never
        // collapse a pane to zero on the next launch.
        //
        // The transfer panel is drawn on top via .overlay — it never touches
        // the split view's frame, so there is zero risk of layout corruption.
        HSplitView {
            PaneView(
                tabs: leftTabs,
                isFocused: focusedSide == .left,
                onFocus: { focusedSide = .left },
                onDropFiles: { urls, dest, isMove in
                    handleDrop(urls: urls, destination: dest, kind: isMove ? .move : .copy)
                }
            )
            .background(SplitProportionFixer())   // patches HSplitView's delegate
            PaneView(
                tabs: rightTabs,
                isFocused: focusedSide == .right,
                onFocus: { focusedSide = .right },
                onDropFiles: { urls, dest, isMove in
                    handleDrop(urls: urls, destination: dest, kind: isMove ? .move : .copy)
                }
            )
        }
        .overlay(alignment: .trailing) {
            if chatVisible {
                HStack(spacing: 0) {
                    Divider()
                    FileChatPanel(isPresented: $chatVisible,
                                  contextFiles: chatContextURLs)
                        .frame(width: 300)
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else if inspectorVisible {
                HStack(spacing: 0) {
                    Divider()
                    TransferInspectorView(queue: queue, isPresented: $inspectorVisible)
                        .frame(width: 280)
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: chatVisible)
        .animation(.easeInOut(duration: 0.22), value: inspectorVisible)
        .navigationTitle(activeTabs().active.displayName)
        .navigationSubtitle(activeTabs().active.currentPath.displayString)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    inspectorVisible.toggle()
                } label: {
                    Label("传输", systemImage: "arrow.up.arrow.down.circle")
                }
                .help("显示/隐藏传输队列")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    openAIChat()
                } label: {
                    Label("AI 助手", systemImage: "sparkles")
                }
                .help("AI 文件助手 (⌘I)")
            }
        }
    }

    private func openAIChat() {
        let pane = activeTabs().active
        let selectedURLs = pane.items
            .filter { pane.selection.contains($0.id) }
            .map(\.url)
        chatContextURLs = selectedURLs
        chatVisible     = true
        inspectorVisible = false
    }

    private var notificationListeners: [(Notification.Name, () -> Void)] {
        [
            (.flOpenAIChat,      { openAIChat() }),
            (.flCopyToOtherPane, { Task { await transferToOther(kind: .copy) } }),
            (.flMoveToOtherPane, { Task { await transferToOther(kind: .move) } }),
            (.flAddBookmark, { addCurrentBookmark() }),
            (.flNewTab, { activeTabs().duplicateActive() }),
            (.flGoBack, { Task { await activeTabs().active.goBack() } }),
            (.flGoForward, { Task { await activeTabs().active.goForward() } }),
            (.flGoUp, { Task { await activeTabs().active.goUp() } }),
            (.flReload, { Task { await activeTabs().active.reload() } }),
            (.flRename, { startRename() }),
            (.flFocusLeft, { focusedSide = .left }),
            (.flFocusRight, { focusedSide = .right }),
            (.flMkdir, { Task { await mkdirInActive() } }),
        ]
    }

    private func addCurrentBookmark() {
        let path = activeTabs().active.currentPath
        let name = path.components.last ?? "/"
        bookmarks.add(Bookmark(name: name, path: "/" + path.components.joined(separator: "/")))
    }

    /// 重命名统一走列表内联（NativeFileTable 的 overlay），不再弹 sheet。
    private func startRename() {
        let pane = activeTabs().active
        guard let id = pane.selection.first,
              pane.items.contains(where: { $0.id == id }) else { return }
        pane.pendingRenameID = id
    }

    private func activeTabs() -> PaneTabsViewModel {
        focusedSide == .left ? leftTabs : rightTabs
    }

    private func otherTabs() -> PaneTabsViewModel {
        focusedSide == .left ? rightTabs : leftTabs
    }

    private func persistPaneState() {
        PaneStateStore.save(PaneStateSnapshot(
            leftPath: leftTabs.active.currentPath.displayString,
            rightPath: rightTabs.active.currentPath.displayString
        ))
    }

    private func mkdirInActive() async {
        let pane = activeTabs().active
        var name = "新建文件夹"
        let existing = Set(pane.items.map(\.name))
        if existing.contains(name) {
            var i = 2
            while existing.contains("\(name) \(i)") { i += 1 }
            name = "\(name) \(i)"
        }
        let target = pane.currentPath.appending(name)
        try? await pane.provider.mkdir(target)
        await pane.reload()
    }

    /// 新建文件：模板生成内容 → 唯一命名 → 落盘 → 选中并直接进入重命名。
    private func newFileInActive(_ template: NewFileTemplate) async {
        let pane = activeTabs().active
        let existing = Set(pane.items.map(\.name))
        let stem = template.defaultStem
        let ext  = template.fileExtension
        var name = "\(stem).\(ext)"
        if existing.contains(name) {
            var i = 2
            while existing.contains("\(stem) \(i).\(ext)") { i += 1 }
            name = "\(stem) \(i).\(ext)"
        }
        do {
            try await pane.provider.createFile(pane.currentPath.appending(name),
                                               contents: template.makeData())
        } catch {
            pane.errorMessage = error.localizedDescription
            return
        }
        await pane.reload()
        // 选中新文件并发起内联重命名（编辑框直接出现在列表行上）
        if let item = pane.items.first(where: { $0.name == name }) {
            pane.selection = [item.id]
            pane.pendingRenameID = item.id
        }
    }

    private func handleDrop(urls: [URL], destination: ProviderPath, kind: TransferKind = .copy) {
        let provider = LocalFileProvider()
        for url in urls {
            let srcPath = provider.providerPath(for: url)
            let dstPath = destination.appending(url.lastPathComponent)
            queue.enqueue(TransferTask(
                kind: kind,
                source: srcPath,
                destination: dstPath
            ))
        }
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if leftTabs.active.currentPath == destination { await leftTabs.active.reload() }
            if rightTabs.active.currentPath == destination { await rightTabs.active.reload() }
        }
    }

    private func transferToOther(kind: TransferKind) async {
        let src = activeTabs().active
        let dst = otherTabs().active
        for id in src.selection {
            guard let item = src.items.first(where: { $0.id == id }) else { continue }
            let srcPath = src.currentPath.appending(item.name)
            let dstPath = dst.currentPath.appending(item.name)
            queue.enqueue(TransferTask(
                kind: kind,
                source: srcPath,
                destination: dstPath,
                bytesTotal: item.size
            ))
        }
    }
}

private struct NotificationListeners: ViewModifier {
    let listeners: [(Notification.Name, () -> Void)]
    func body(content: Content) -> some View {
        listeners.reduce(AnyView(content)) { acc, listener in
            AnyView(
                acc.onReceive(NotificationCenter.default.publisher(for: listener.0)) { _ in
                    listener.1()
                }
            )
        }
    }
}
