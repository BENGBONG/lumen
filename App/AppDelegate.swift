import AppKit
import QuickLook
import Quartz

/// Application delegate.
///
/// NOTE: NOT `@MainActor` — the ObjC runtime invokes QLPreviewPanel delegate
/// methods on the main thread, and `@MainActor` isolation can break the
/// responder-chain bridging on some macOS versions.
///
/// Primary QuickLook handling is now in `ForkLiftTableView` (the first
/// responder after a click), so QuickLook finds the controller immediately
/// without needing to walk the full chain up to AppDelegate.  AppDelegate
/// remains as a *fallback* for cases where the table is not first responder
/// (e.g. a toolbar button was last clicked).
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Shared instance — set in `init` so callers don't need to cast
    /// `NSApp.delegate`, which can return a wrapper object in some SwiftUI
    /// configurations.
    nonisolated(unsafe) static weak var shared: AppDelegate?

    /// URLs to preview. Kept in sync by `ForkLiftTableView.Coordinator`
    /// (synchronously on every selection change).
    var quickLookURLs: [URL] = []

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    // MARK: - QLPreviewPanelController fallback (responder-chain)
    //
    // These are only reached when ForkLiftTableView is NOT the first
    // responder and therefore didn't claim the panel first.

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

extension AppDelegate: QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        quickLookURLs.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        guard index >= 0, index < quickLookURLs.count else { return nil }
        return quickLookURLs[index] as NSURL
    }

    func previewPanel(_ panel: QLPreviewPanel!,
                      sourceFrameOnScreenFor item: (any QLPreviewItem)!) -> NSRect {
        let p = NSEvent.mouseLocation
        return NSRect(x: p.x - 1, y: p.y - 1, width: 2, height: 2)
    }
}
