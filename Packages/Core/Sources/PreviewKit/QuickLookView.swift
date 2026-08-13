import SwiftUI
import QuickLookUI

public struct QuickLookView: NSViewRepresentable {
    public let url: URL?

    public init(url: URL?) {
        self.url = url
    }

    public func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        view.autostarts = true
        view.shouldCloseWithWindow = false
        return view
    }

    public func updateNSView(_ nsView: QLPreviewView, context: Context) {
        nsView.previewItem = url as NSURL?
    }
}
