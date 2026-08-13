import SwiftUI
import AppKit
import QuickLookUI   // QLPreviewPanel, QLPreviewPanelDataSource/Delegate
import FileSystemKit
import AppearanceKit

/// NSTableView-backed file list. We use this instead of SwiftUI `Table` because:
///
///  * `Table` on macOS 14+ commits selection only on mouse-up (worse: can be
///    delayed up to ~250ms when `primaryAction:` is set, while AppKit
///    arbitrates click vs double-click). NSTableView commits on mouse-down.
///  * Space-bar key handling in SwiftUI Table is unreliable — NSTableView
///    swallows the keyDown before SwiftUI's `.onKeyPress` sees it.
///  * Native NSTableView gives us double-click via `doubleAction`, sort via
///    `sortDescriptors`, and proper drag/drop integration.
struct NativeFileTable: NSViewRepresentable {
    let items: [FileItem]
    @Binding var selection: Set<FileItem.ID>
    @Binding var sortKey: PaneViewModel.SortKey
    @Binding var sortAscending: Bool

    let theme: any AppearanceTheme

    let onOpen: (FileItem) -> Void
    let onSpace: ([FileItem]) -> Void
    let onBackspace: () -> Void
    let onEscape: () -> Void
    /// The URL of the directory currently displayed in this pane.
    /// Used as the default drop destination when files are dropped onto the table
    /// background (not onto a specific directory row).
    let currentDirectory: URL
    /// Called when files are dropped.
    /// - Parameters:
    ///   - urls: source file URLs
    ///   - destination: target directory URL (the pane's current dir, or a sub-folder row)
    ///   - isMove: true → move; false → copy
    let onDropFiles: ([URL], URL, Bool) -> Bool
    let onContextMenu: ([FileItem]) -> NSMenu?
    let onRename: (FileItem, String) -> Void
    /// 请求对某个 item 发起内联重命名（新建文件后 / F2 / 右键菜单）。
    /// 消费后通过 onRenameRequestConsumed 通知清除。
    let renameRequestID: FileItem.ID?
    let onRenameRequestConsumed: () -> Void
    /// 所属窗格是否为焦点窗格——决定选中行用 accent 还是灰色（Finder 语义）。
    let isPaneFocused: Bool
    /// 表格内任何 mouseDown（行/空白都算）——用于把焦点切到所属窗格。
    /// 走 NSTableView 自身的 mouseDown 覆盖，不参与手势仲裁，零延迟。
    let onTableInteraction: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSScrollView {
        let table = ForkLiftTableView()
        table.style = .inset
        table.allowsMultipleSelection = true
        table.allowsEmptySelection = true
        table.allowsColumnSelection = false
        table.usesAlternatingRowBackgroundColors = false
        table.rowHeight = 24
        table.intercellSpacing = NSSize(width: 8, height: 4)
        table.gridStyleMask = []
        table.headerView = NSTableHeaderView()
        table.selectionHighlightStyle = .regular   // 自定义 ThemedRowView 绘制

        // Columns -----------------------------------------------------------
        let nameCol = NSTableColumn(identifier: .init("name"))
        nameCol.title = "名称"
        nameCol.minWidth = 180
        nameCol.width = 320
        nameCol.sortDescriptorPrototype = NSSortDescriptor(key: "name", ascending: true)
        table.addTableColumn(nameCol)

        let sizeCol = NSTableColumn(identifier: .init("size"))
        sizeCol.title = "大小"
        sizeCol.minWidth = 60
        sizeCol.width = 90
        sizeCol.maxWidth = 140
        sizeCol.sortDescriptorPrototype = NSSortDescriptor(key: "size", ascending: false)
        table.addTableColumn(sizeCol)

        let dateCol = NSTableColumn(identifier: .init("date"))
        dateCol.title = "修改时间"
        dateCol.minWidth = 130
        dateCol.width = 160
        dateCol.maxWidth = 220
        dateCol.sortDescriptorPrototype = NSSortDescriptor(key: "date", ascending: false)
        table.addTableColumn(dateCol)

        // Wire up coordinator
        let coord = context.coordinator
        coord.tableView = table
        table.dataSource = coord
        table.delegate = coord
        table.target = coord
        table.doubleAction = #selector(Coordinator.tableDoubleClicked(_:))
        table.keyDownHandler = { [weak coord] event in coord?.handleKeyDown(event) ?? false }
        table.menuProvider = { [weak coord] event in coord?.makeContextMenu(for: event) }
        table.mouseDownHandler = { [weak coord] in coord?.parent.onTableInteraction() }

        // Drag SOURCE: manual initiation via mouseDragged override in ForkLiftTableView.
        // The NSDraggingSource conformance on ForkLiftTableView sets operation masks.
        // We still register these as a fallback for NSTableView's native detection.
        table.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        table.setDraggingSourceOperationMask(.copy, forLocal: false)
        table.dragURLProvider = { [weak coord] rows in
            rows.compactMap { idx in
                guard let coord, idx < coord.items.count else { return nil }
                return coord.items[idx].url
            }
        }

        // Drop destination — accepts file-URL drops from any source.
        table.registerForDraggedTypes([.fileURL])

        // Initial sort descriptors
        table.sortDescriptors = [NSSortDescriptor(key: sortKey.rawValue, ascending: sortAscending)]

        // Scroll view --------------------------------------------------------
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true

        // Initial data
        coord.items = items
        // 自愈：首次布局可能与数据装配存在时序竞争（标签页切换/重建后
        // 曾出现"有数据但零行"），下一 runloop 兜底 reload 一次。
        DispatchQueue.main.async { [weak table] in table?.reloadData() }
        return scroll
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let table = scrollView.documentView as? ForkLiftTableView else { return }
        let coord = context.coordinator
        coord.parent = self

        // Detect items change by id sequence (cheap; avoids full reload on
        // selection/sort updates that don't actually change the data).
        let oldIDs = coord.items.map(\.id)
        let newIDs = items.map(\.id)
        let itemsChanged = oldIDs != newIDs
        coord.items = items
        // numberOfRows 对账：任何遗漏的 reload 都在此自愈（防空白表格）
        if itemsChanged || table.numberOfRows != items.count { table.reloadData() }

        // 焦点变化 → 行选中色 accent/灰 切换，需要重建 row views
        if coord.lastIsPaneFocused != isPaneFocused {
            coord.lastIsPaneFocused = isPaneFocused
            table.reloadData()
        }

        // Sync sort indicator (avoid retriggering the sortDescriptorsDidChange
        // delegate by suppressing during the assignment).
        let descriptor = NSSortDescriptor(key: sortKey.rawValue, ascending: sortAscending)
        if !descriptorsEqual(table.sortDescriptors, [descriptor]) {
            coord.suppressSortFeedback = true
            table.sortDescriptors = [descriptor]
            coord.suppressSortFeedback = false
        }

        // Sync selection — only push down if it differs, so user clicks don't
        // re-loop through SwiftUI.
        let desired = IndexSet(items.enumerated().compactMap { idx, item in
            selection.contains(item.id) ? idx : nil
        })
        if table.selectedRowIndexes != desired {
            coord.suppressSelectionFeedback = true
            table.selectRowIndexes(desired, byExtendingSelection: false)
            coord.suppressSelectionFeedback = false
        }

        // Consume an inline-rename request (new file / F2 / context menu).
        // Runs after items+selection sync so the target row is already visible.
        if let requestID = renameRequestID {
            if let row = items.firstIndex(where: { $0.id == requestID }) {
                coord.startRename(row: row)
            }
            onRenameRequestConsumed()
        }
    }

    private func descriptorsEqual(_ a: [NSSortDescriptor], _ b: [NSSortDescriptor]) -> Bool {
        guard a.count == b.count else { return false }
        return zip(a, b).allSatisfy { $0.key == $1.key && $0.ascending == $1.ascending }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: NativeFileTable
        var items: [FileItem] = []
        var suppressSelectionFeedback = false
        var suppressSortFeedback = false
        var lastIsPaneFocused: Bool
        weak var tableView: NSTableView?

        // Inline rename state
        private var editingOverlay: InlineEditTextField?
        private var editingRow: Int?

        private static let dateFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateStyle = .short
            f.timeStyle = .short
            return f
        }()

        init(parent: NativeFileTable) {
            self.parent = parent
            self.lastIsPaneFocused = parent.isPaneFocused
        }

        // MARK: NSTableViewDataSource

        func numberOfRows(in tableView: NSTableView) -> Int { items.count }

        /// 自定义行视图：焦点窗格选中行用 accent，非焦点用灰（Finder 语义）。
        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            let rowView = ThemedRowView()
            rowView.fillColor = NSColor(parent.isPaneFocused
                                        ? parent.theme.rowSelected
                                        : parent.theme.rowSelectedInactive)
            return rowView
        }

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard !suppressSortFeedback,
                  let descriptor = tableView.sortDescriptors.first,
                  let key = descriptor.key,
                  let parsed = PaneViewModel.SortKey(rawValue: key) else { return }
            let ascending = descriptor.ascending
            DispatchQueue.main.async {
                self.parent.sortKey = parsed
                self.parent.sortAscending = ascending
            }
        }

        // Drag source -----------------------------------------------------------

        /// Provide a pasteboard writer for each row so rows can be dragged out.
        func tableView(_ tableView: NSTableView,
                       pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
            guard row < items.count else { return nil }
            return items[row].url as NSURL
        }

        // Drop ------------------------------------------------------------------

        func tableView(_ tableView: NSTableView,
                       validateDrop info: NSDraggingInfo,
                       proposedRow row: Int,
                       proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
            let srcTable   = info.draggingSource as? ForkLiftTableView
            let isSamePane = srcTable === tableView
            let mask       = info.draggingSourceOperationMask

            // Drop ON a directory row — any source including same pane.
            // IMPORTANT: do NOT read the pasteboard here; validateDrop is called
            // 30+ times/sec during hover and pasteboard deserialization is slow.
            // The "drop folder into itself" guard runs once in acceptDrop instead.
            if dropOperation == .on,
               row >= 0, row < items.count,
               items[row].isDirectory, !items[row].isPackage {
                return mask.contains(.move) ? .move : .copy
            }

            // Background drop into same pane: files already live here — no-op.
            if isSamePane { return [] }

            // Another pane or external app: whole-table drop.
            tableView.setDropRow(-1, dropOperation: .above)
            guard srcTable == nil else {
                return mask.contains(.move) ? .move : .copy   // other pane
            }
            return .copy                                        // Finder / external
        }

        func tableView(_ tableView: NSTableView,
                       acceptDrop info: NSDraggingInfo,
                       row: Int,
                       dropOperation: NSTableView.DropOperation) -> Bool {
            let pb = info.draggingPasteboard
            guard let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
                  !urls.isEmpty else { return false }

            // Destination: a sub-folder row, or the pane's current directory.
            let destURL: URL
            if dropOperation == .on, row >= 0, row < items.count, items[row].isDirectory {
                destURL = items[row].url
                // Guard: never drop a folder into itself.
                if urls.contains(destURL) { return false }
            } else {
                destURL = parent.currentDirectory
            }

            let isMove = info.draggingSourceOperationMask.contains(.move)
                      && info.draggingSource is ForkLiftTableView
            return parent.onDropFiles(urls, destURL, isMove)
        }

        // MARK: NSTableViewDelegate

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < items.count, let column = tableColumn else { return nil }
            let item = items[row]
            switch column.identifier.rawValue {
            case "name":
                let id = NSUserInterfaceItemIdentifier("nameCell")
                let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? NameCellView) ?? NameCellView()
                cell.identifier = id
                cell.configure(with: item, theme: parent.theme)
                return cell
            case "size":
                return makeTextCell(
                    in: tableView, identifier: "sizeCell",
                    text: item.isDirectory ? "—" : ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file),
                    monospacedDigits: true
                )
            case "date":
                let txt = item.modifiedAt.map { Self.dateFormatter.string(from: $0) } ?? "—"
                return makeTextCell(in: tableView, identifier: "dateCell", text: txt, monospacedDigits: false)
            default:
                return nil
            }
        }

        private func makeTextCell(in tableView: NSTableView, identifier: String, text: String, monospacedDigits: Bool) -> NSView {
            let id = NSUserInterfaceItemIdentifier(identifier)
            let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? PlainTextCellView) ?? PlainTextCellView()
            cell.identifier = id
            cell.configure(text: text, monospacedDigits: monospacedDigits)
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !suppressSelectionFeedback,
                  let table = notification.object as? NSTableView else { return }
            let selectedItems = table.selectedRowIndexes.compactMap { idx -> FileItem? in
                idx >= 0 && idx < items.count ? items[idx] : nil
            }
            let ids  = Set(selectedItems.map(\.id))
            let urls = selectedItems.map(\.url)

            // Sync QuickLook URLs synchronously so the next Space keystroke
            // sees the latest selection even before the SwiftUI binding
            // propagates (which happens one runloop tick later).
            //
            // Primary: store on ForkLiftTableView itself — it's the first
            // responder, so QLPreviewPanel finds it immediately.
            if let flTable = table as? ForkLiftTableView {
                flTable.quickLookURLs = urls
            }
            // Fallback: AppDelegate (reached when the table lost first-responder).
            AppDelegate.shared?.quickLookURLs = urls

            // Mirror to SwiftUI binding on the next runloop tick (cannot write
            // @Observable state inside a delegate callback without triggering
            // "modifying state during view update" warnings).
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.parent.selection != ids { self.parent.selection = ids }
            }
        }

        // Double-click ---------------------------------------------------------

        @objc func tableDoubleClicked(_ sender: AnyObject) {
            guard let table = sender as? NSTableView else { return }
            let row = table.clickedRow
            guard row >= 0, row < items.count else { return }
            parent.onOpen(items[row])
        }

        // Keyboard -------------------------------------------------------------

        // Type-to-select 缓冲（1 秒内连续输入累积成前缀）
        private var typeBuffer = ""
        private var typeResetTask: Task<Void, Never>?

        /// 累积输入字符并选中第一个前缀匹配的行。返回是否命中。
        private func typeSelect(matching char: String) -> Bool {
            guard let table = tableView, !items.isEmpty else { return false }
            typeResetTask?.cancel()
            typeResetTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                self?.typeBuffer = ""
            }
            let lower = char.lowercased()
            let candidate = typeBuffer + lower
            // 先按累积缓冲匹配；失配则回退到单字符重新起跳（Finder 行为）
            for query in [candidate, lower] {
                if let row = items.firstIndex(where: {
                    $0.name.lowercased().hasPrefix(query)
                }) {
                    typeBuffer = query
                    table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                    table.scrollRowToVisible(row)
                    return true
                }
            }
            typeBuffer = ""
            return false
        }

        func handleKeyDown(_ event: NSEvent) -> Bool {
            guard let chars = event.charactersIgnoringModifiers, chars.count == 1 else { return false }
            let scalar = chars.unicodeScalars.first!.value

            // Type-to-select：无修饰键的可打印字符 → 按名称前缀跳选（Finder 基础能力）。
            // 空格（QuickLook）、Backspace（上级）、Escape 等控制键不进跳选。
            if event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
               scalar > 0x20, scalar != 0x7F, scalar != 0x1B,
               !(scalar >= 0xF700 && scalar <= 0xF8FF),   // 功能键区
               typeSelect(matching: chars) {
                return true
            }

            // Read selection from the live NSTableView — the SwiftUI binding
            // may be one runloop tick behind because we dispatch its update
            // async (see tableViewSelectionDidChange).
            let liveSelected: [FileItem] = {
                guard let table = tableView else { return [] }
                return table.selectedRowIndexes.compactMap { idx in
                    idx >= 0 && idx < items.count ? items[idx] : nil
                }
            }()

            switch scalar {
            case 0x20: // Space → QuickLook preview
                guard !liveSelected.isEmpty else { return false }
                // Refresh the table's URL list directly — no async path needed.
                let urls = liveSelected.map(\.url)
                if let flTable = tableView as? ForkLiftTableView {
                    flTable.quickLookURLs = urls
                }
                AppDelegate.shared?.quickLookURLs = urls
                // Show or refresh the panel.  ForkLiftTableView is the first
                // responder, so QLPreviewPanel's responder-chain walk finds it
                // first and calls beginPreviewPanelControl immediately.
                if let panel = QLPreviewPanel.shared() {
                    panel.isVisible ? panel.reloadData() : panel.makeKeyAndOrderFront(nil)
                }
                return true

            case 0x7F: // Backspace → go up
                parent.onBackspace()
                return true

            case 0x1B: // Escape
                parent.onEscape()
                return true

            case 0x0D, 0x03: // Return / Enter → open
                guard !liveSelected.isEmpty else { return false }
                for item in liveSelected { parent.onOpen(item) }
                return true

            default:
                return false
            }
        }

        // Right-click ----------------------------------------------------------

        func makeContextMenu(for event: NSEvent) -> NSMenu? {
            guard let table = event.window?.contentView?.hitTest(
                event.window?.contentView?.convert(event.locationInWindow, from: nil) ?? .zero
            ) as? NSTableView ?? findTableView(under: event) else {
                return parent.onContextMenu([])
            }
            let pt = table.convert(event.locationInWindow, from: nil)
            let row = table.row(at: pt)
            if row >= 0 && row < items.count {
                // If clicked row isn't part of selection, replace selection.
                if !table.selectedRowIndexes.contains(row) {
                    table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                }
                let selectedItems = items.filter { parent.selection.contains($0.id) }
                let target = selectedItems.isEmpty ? [items[row]] : selectedItems
                return parent.onContextMenu(target)
            } else {
                return parent.onContextMenu([])
            }
        }

        // MARK: - Inline rename ------------------------------------------------

        func startRename(row: Int) {
            guard let table = tableView,
                  row >= 0, row < items.count,
                  editingOverlay == nil else { return }

            let item = items[row]
            table.scrollRowToVisible(row)

            // Position the overlay over the name label portion of the cell.
            // Icon (18px) + leading pad (4px) + gap (6px) = 28px offset.
            let cellRect = table.frameOfCell(atColumn: 0, row: row)
            let iconOffset: CGFloat = 28
            let overlayRect = NSRect(
                x: cellRect.minX + iconOffset,
                y: cellRect.minY + 2,
                width: max(cellRect.width - iconOffset - 8, 40),
                height: cellRect.height - 4
            )

            let field = InlineEditTextField(frame: overlayRect)
            field.stringValue = item.name
            field.onCommit = { [weak self] newName in self?.finishRename(newName: newName, item: item) }
            field.onCancel = { [weak self] in self?.finishRename(newName: nil, item: item) }

            table.addSubview(field)
            table.window?.makeFirstResponder(field)
            field.selectText(nil)
            // Finder 行为：文件只预选主体名（不含扩展名），目录全选
            if !item.isDirectory {
                let nsName = item.name as NSString
                let stemLength = (nsName.deletingPathExtension as NSString).length  // UTF-16 长度
                if stemLength > 0, stemLength < nsName.length {
                    field.currentEditor()?.selectedRange = NSRange(location: 0, length: stemLength)
                }
            }

            editingRow     = row
            editingOverlay = field
        }

        private func finishRename(newName: String?, item: FileItem) {
            editingOverlay?.removeFromSuperview()
            editingOverlay = nil
            editingRow     = nil
            // Return keyboard focus to the table so arrow keys work immediately.
            tableView?.window?.makeFirstResponder(tableView)

            guard let name = newName?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty, name != item.name else { return }
            parent.onRename(item, name)
        }

        private func findTableView(under event: NSEvent) -> NSTableView? {
            // Walk the subview tree if hitTest didn't directly return the table.
            guard let root = event.window?.contentView else { return nil }
            return findTable(in: root)
        }

        private func findTable(in view: NSView) -> NSTableView? {
            if let t = view as? NSTableView { return t }
            for sub in view.subviews {
                if let t = findTable(in: sub) { return t }
            }
            return nil
        }
    }
}

// MARK: - Custom NSTableView

/// 主题化行视图：自绘选中背景（圆角横条），颜色由焦点状态决定。
private final class ThemedRowView: NSTableRowView {
    var fillColor: NSColor = .clear

    override func drawSelection(in dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 4, dy: 1)
        fillColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
    }
}

/// NSTableView subclass that also acts as the primary QLPreviewPanel
/// controller.  Because it is the first responder after any row click,
/// QLPreviewPanel's responder-chain walk finds it immediately — no need
/// to rely on AppDelegate (which is further up the chain).
final class ForkLiftTableView: NSTableView {
    var keyDownHandler: ((NSEvent) -> Bool)?
    var menuProvider:   ((NSEvent) -> NSMenu?)?
    /// 任意 mouseDown 触发（行/空白区域都会），用于窗格焦点切换。
    var mouseDownHandler: (() -> Void)?

    /// Preview URLs — set synchronously in `tableViewSelectionDidChange`
    /// so they are always current when Space is pressed.
    var quickLookURLs: [URL] = []

    /// Closure called in mouseDragged to obtain file URLs for the dragged rows.
    /// Bypasses NSTableView's internal drag detection, which is unreliable on
    /// macOS 26 with the .inset style.
    var dragURLProvider: ((IndexSet) -> [URL])?

    // Track mouseDown state for our own drag initiation.
    private var mouseDownRow     = -1
    private var mouseDownPt      = NSPoint.zero
    private var didBeginDrag     = false

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        mouseDownHandler?()
        let pt            = convert(event.locationInWindow, from: nil)
        mouseDownRow      = row(at: pt)
        mouseDownPt       = pt
        didBeginDrag      = false
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard !didBeginDrag,
              mouseDownRow >= 0,
              let urlProvider = dragURLProvider else {
            super.mouseDragged(with: event)
            return
        }
        // Wait for the system drag-threshold (~4 pt) before initiating.
        let pt   = convert(event.locationInWindow, from: nil)
        let dist = hypot(pt.x - mouseDownPt.x, pt.y - mouseDownPt.y)
        guard dist > 4 else { super.mouseDragged(with: event); return }

        // Use selected rows; if the clicked row isn't selected, drag just it.
        var rows = selectedRowIndexes
        if rows.isEmpty || !rows.contains(mouseDownRow) {
            rows = IndexSet(integer: mouseDownRow)
        }
        let urls = urlProvider(rows)
        guard !urls.isEmpty else { super.mouseDragged(with: event); return }

        // Build one NSDraggingItem per file.
        var items: [NSDraggingItem] = []
        for (idx, row) in rows.enumerated() {
            let url      = idx < urls.count ? urls[idx] : urls[urls.count - 1]
            let pbItem   = NSPasteboardItem()
            pbItem.setData(url.dataRepresentation, forType: .fileURL)
            let di       = NSDraggingItem(pasteboardWriter: pbItem)
            // Use the file's cached system icon — fast, no layout pass needed.
            let rowRect  = self.rect(ofRow: row)
            let iconRect = NSRect(x: rowRect.minX + 4, y: rowRect.minY + 2,
                                  width: 20, height: 20)
            di.setDraggingFrame(iconRect, contents: dragImage(for: url))
            items.append(di)
        }

        didBeginDrag = true
        beginDraggingSession(with: items, event: event, source: self)
    }

    /// Light-weight drag image: NSWorkspace icon (cached by the OS, instant).
    private func dragImage(for url: URL) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 32, height: 32)
        return icon
    }

    override func keyDown(with event: NSEvent) {
        if keyDownHandler?(event) == true { return }
        super.keyDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        menuProvider?(event)
    }

    // MARK: Edit-menu clipboard actions

    /// Tracks which URLs are currently "cut" (pending move-on-paste).
    /// We cannot store this state on the system pasteboard without registering
    /// a custom UTI, so we keep it as a process-level set instead.
    /// It's cleared whenever the user copies something else.
    private static var cutURLs: Set<URL> = []

    /// Cmd+C — write selected file URLs to the system clipboard.
    @objc func copy(_ sender: Any?) {
        guard !quickLookURLs.isEmpty else { return }
        Self.cutURLs = []   // any new copy clears the pending cut
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(quickLookURLs as [NSURL])
    }

    /// Cmd+X — write selected file URLs to the clipboard and mark them as "cut".
    /// On paste, the files will be moved instead of copied.
    @objc func cut(_ sender: Any?) {
        guard !quickLookURLs.isEmpty else { return }
        let urls = quickLookURLs
        Self.cutURLs = Set(urls)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(urls as [NSURL])
    }

    /// Cmd+V — paste clipboard files into the active pane (copy or move).
    @objc func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        guard let urls = pb.readObjects(forClasses: [NSURL.self],
                                        options: nil) as? [URL],
              !urls.isEmpty else { return }
        // It's a move-paste only if every pasted URL was previously cut by us.
        let isCut = !Self.cutURLs.isEmpty && Set(urls) == Self.cutURLs
        if isCut { Self.cutURLs = [] }   // consume the cut state
        NotificationCenter.default.post(
            name: .flPasteFiles, object: nil,
            userInfo: ["urls": urls, "isCut": isCut]
        )
    }

    /// Enable/disable Edit-menu items based on current selection and clipboard.
    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(copy(_:)), #selector(cut(_:)):
            return !quickLookURLs.isEmpty
        case #selector(paste(_:)):
            return NSPasteboard.general
                .canReadObject(forClasses: [NSURL.self], options: nil)
        default:
            return super.validateUserInterfaceItem(item)
        }
    }

    // MARK: NSDraggingSource — NSTableView already conforms; override the mask method.

    override func draggingSession(_ session: NSDraggingSession,
                                  sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        // Within the same app: move or copy.  To an external app: copy only.
        return context == .withinApplication ? [.copy, .move] : .copy
    }

    // MARK: QLPreviewPanelController (informal NSObject protocol)

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        !quickLookURLs.isEmpty
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = self
        panel.delegate   = self
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate   = nil
    }
}

// MARK: - NSDraggingSource override (NSTableView already conforms; we just tune the mask)

// MARK: - QLPreviewPanel data source / delegate

extension ForkLiftTableView: QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        quickLookURLs.count
    }

    func previewPanel(_ panel: QLPreviewPanel!,
                      previewItemAt index: Int) -> (any QLPreviewItem)! {
        guard index >= 0, index < quickLookURLs.count else { return nil }
        return quickLookURLs[index] as NSURL
    }

    func previewPanel(_ panel: QLPreviewPanel!,
                      sourceFrameOnScreenFor item: (any QLPreviewItem)!) -> NSRect {
        // Genie animation originates near the cursor.
        let p = NSEvent.mouseLocation
        return NSRect(x: p.x - 1, y: p.y - 1, width: 2, height: 2)
    }
}

// MARK: - Inline rename text field

/// A floating NSTextField overlaid on a table row for F2-style inline rename.
/// Sets itself as its own delegate so it can intercept Escape and commit via Return.
private final class InlineEditTextField: NSTextField, NSTextFieldDelegate {
    var onCommit: ((String) -> Void)?
    var onCancel: (() -> Void)?
    private var cancelled = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.delegate       = self
        self.isEditable     = true
        self.isBordered     = true
        self.bezelStyle     = .squareBezel
        self.backgroundColor = .textBackgroundColor
        self.focusRingType  = .exterior
        self.font           = .systemFont(ofSize: 13)
        self.lineBreakMode  = .byTruncatingTail
    }
    required init?(coder: NSCoder) { fatalError() }

    // Escape key — cancel without committing.
    override func cancelOperation(_ sender: Any?) {
        cancelled = true
        onCancel?()
    }

    // Fires when the field loses focus for any reason (Return, Tab, click-away).
    // After cancelOperation we guard with `cancelled` to avoid a double-fire.
    func controlTextDidEndEditing(_ obj: Notification) {
        guard !cancelled else { return }
        onCommit?(stringValue)
    }
}

// MARK: - Cell views

final class NameCellView: NSTableCellView {
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        icon.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)
        addSubview(label)
        textField = label
        imageView = icon

        label.font = .systemFont(ofSize: 13)
        label.lineBreakMode = .byTruncatingMiddle
        label.allowsDefaultTighteningForTruncation = true
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func configure(with item: FileItem, theme: any AppearanceTheme) {
        label.stringValue = item.name
        let spec = NameCellView.iconSpec(for: item, theme: theme)
        icon.image = NSImage(systemSymbolName: spec.symbol, accessibilityDescription: nil)
        icon.contentTintColor = spec.tint
        // 隐藏文件（dot 文件）整体变淡，与普通文件一眼区分
        icon.alphaValue  = item.isHidden ? 0.45 : 1.0
        label.alphaValue = item.isHidden ? 0.55 : 1.0
    }

    private static func iconSpec(for item: FileItem,
                                 theme: any AppearanceTheme) -> (symbol: String, tint: NSColor) {
        let accent = NSColor(theme.accent)
        let secondary = NSColor.secondaryLabelColor
        if item.isPackage { return ("shippingbox.fill", accent) }
        if item.isDirectory { return ("folder.fill", accent) }
        if item.isSymlink { return ("link", secondary) }
        let ext = (item.name as NSString).pathExtension.lowercased()
        guard !ext.isEmpty else { return ("doc", secondary) }
        switch ext {
        // Office 三件套：贴近平台习惯的彩色图标
        case "xls", "xlsx", "csv", "tsv", "numbers": return ("tablecells", .systemGreen)
        case "doc", "docx", "pages":                 return ("doc.text", .systemBlue)
        case "ppt", "pptx", "key":                   return ("play.rectangle", .systemOrange)
        case "png", "jpg", "jpeg", "gif", "heic", "tiff", "bmp", "webp": return ("photo", secondary)
        case "mov", "mp4", "m4v", "avi", "mkv": return ("film", secondary)
        case "mp3", "wav", "flac", "aac", "m4a": return ("waveform", secondary)
        case "pdf": return ("doc.richtext", secondary)
        case "zip", "tar", "gz", "bz2", "7z", "rar": return ("archivebox", secondary)
        case "swift", "py", "js", "ts", "rb", "go", "rs", "java", "c", "cpp", "h", "m":
            return ("chevron.left.forwardslash.chevron.right", secondary)
        case "txt", "md", "rtf": return ("doc.text", secondary)
        default: return ("doc", secondary)
        }
    }
}

final class PlainTextCellView: NSTableCellView {
    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
        textField = label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func configure(text: String, monospacedDigits: Bool) {
        label.stringValue = text
        label.font = monospacedDigits
            ? .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            : .systemFont(ofSize: 11)
    }
}
