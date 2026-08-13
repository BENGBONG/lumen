import SwiftUI
import AppKit
import AppearanceKit
import FileSystemKit

@main
struct ForkLiftCloneApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var themeStore = ThemeStore()
    @State private var keyMonitor: Any?

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environment(\.appearanceTheme, themeStore.theme)
                .frame(minWidth: 1000, minHeight: 600)
                .onAppear { installFunctionKeyMonitor() }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            FileCommands()
        }

        Settings {
            SettingsView(themeStore: themeStore)
                .environment(\.appearanceTheme, themeStore.theme)
        }
    }

    private func installFunctionKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let chars = event.charactersIgnoringModifiers, chars.count == 1 else {
                return event
            }
            // Don't intercept when a text field is the first responder (e.g. rename, search).
            if let resp = NSApp.keyWindow?.firstResponder,
               resp is NSText || resp is NSTextView {
                return event
            }
            // Don't intercept while a sheet (rename dialog etc.) is up.
            if NSApp.modalWindow != nil { return event }

            let scalar = chars.unicodeScalars.first!.value
            switch scalar {
            case 0xF705: // F2 – rename
                NotificationCenter.default.post(name: .flRename, object: nil)
                return nil
            case 0xF708: // F5 – copy to other pane
                NotificationCenter.default.post(name: .flCopyToOtherPane, object: nil)
                return nil
            case 0xF709: // F6 – move to other pane
                NotificationCenter.default.post(name: .flMoveToOtherPane, object: nil)
                return nil
            // Space is handled by ForkLiftTableView.keyDown which updates
            // quickLookURLs from the live NSTableView state before calling
            // QLPreviewPanel — no global override needed.
            default:
                return event
            }
        }
    }
}

struct FileCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("新建标签页") {
                NotificationCenter.default.post(name: .flNewTab, object: nil)
            }
            .keyboardShortcut("t", modifiers: [.command])

            Menu("新建文件") {
                ForEach(NewFileTemplate.allCases, id: \.rawValue) { template in
                    Button(template.displayName) {
                        NotificationCenter.default.post(
                            name: .flNewFile, object: nil,
                            userInfo: ["template": template.rawValue])
                    }
                }
            }
        }
        CommandMenu("导航") {
            Button("后退") {
                NotificationCenter.default.post(name: .flGoBack, object: nil)
            }
            .keyboardShortcut("[", modifiers: [.command])

            Button("前进") {
                NotificationCenter.default.post(name: .flGoForward, object: nil)
            }
            .keyboardShortcut("]", modifiers: [.command])

            Button("上级目录") {
                NotificationCenter.default.post(name: .flGoUp, object: nil)
            }
            .keyboardShortcut(.upArrow, modifiers: [.command])

            Button("刷新") {
                NotificationCenter.default.post(name: .flReload, object: nil)
            }
            .keyboardShortcut("r", modifiers: [.command])

            Divider()
            Button("聚焦左 Pane") {
                NotificationCenter.default.post(name: .flFocusLeft, object: nil)
            }
            .keyboardShortcut("1", modifiers: [.command])

            Button("聚焦右 Pane") {
                NotificationCenter.default.post(name: .flFocusRight, object: nil)
            }
            .keyboardShortcut("2", modifiers: [.command])

            Divider()
            Button("聚焦搜索") {
                NotificationCenter.default.post(name: .flFocusSearch, object: nil)
            }
            .keyboardShortcut("f", modifiers: [.command])

            Button("新建文件夹") {
                NotificationCenter.default.post(name: .flMkdir, object: nil)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
        }
        CommandMenu("传输") {
            Button("复制到对侧 (F5)") {
                NotificationCenter.default.post(name: .flCopyToOtherPane, object: nil)
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])

            Button("移动到对侧 (F6)") {
                NotificationCenter.default.post(name: .flMoveToOtherPane, object: nil)
            }
            .keyboardShortcut("x", modifiers: [.command, .shift])

            Divider()
            Button("将当前目录加入收藏") {
                NotificationCenter.default.post(name: .flAddBookmark, object: nil)
            }
            .keyboardShortcut("d", modifiers: [.command])

            Button("重命名…") {
                NotificationCenter.default.post(name: .flRename, object: nil)
            }
            .keyboardShortcut(.return, modifiers: [.command])
        }
        CommandMenu("AI") {
            Button("打开 AI 助手") {
                NotificationCenter.default.post(name: .flOpenAIChat, object: nil)
            }
            .keyboardShortcut("i", modifiers: [.command])

            Button("AI 批量操作…") {
                NotificationCenter.default.post(name: .flAIBatch, object: nil)
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
        }
    }
}

extension Notification.Name {
    static let flCopyToOtherPane = Notification.Name("flCopyToOtherPane")
    static let flMoveToOtherPane = Notification.Name("flMoveToOtherPane")
    static let flAddBookmark = Notification.Name("flAddBookmark")
    static let flNewTab = Notification.Name("flNewTab")
    static let flGoBack = Notification.Name("flGoBack")
    static let flGoForward = Notification.Name("flGoForward")
    static let flGoUp = Notification.Name("flGoUp")
    static let flReload = Notification.Name("flReload")
    static let flRename = Notification.Name("flRename")
    static let flFocusLeft = Notification.Name("flFocusLeft")
    static let flFocusRight = Notification.Name("flFocusRight")
    static let flFocusSearch = Notification.Name("flFocusSearch")
    static let flMkdir       = Notification.Name("flMkdir")
    /// Open the AI chat panel for the current selection.
    static let flOpenAIChat  = Notification.Name("flOpenAIChat")
    /// Paste files from the system clipboard into the active pane.
    /// userInfo: ["urls": [URL], "isCut": Bool]
    static let flPasteFiles  = Notification.Name("flPasteFiles")
    /// Open the AI batch-operations command bar for the active pane.
    static let flAIBatch     = Notification.Name("flAIBatch")
    /// Create a new file from a template in the active pane.
    /// userInfo: ["template": String]（NewFileTemplate.rawValue）
    static let flNewFile     = Notification.Name("flNewFile")
}
