import AppKit
import SwiftUI

/// A zero-size NSViewRepresentable that locates the enclosing NSSplitView
/// (the one created by SwiftUI's HSplitView) and patches its delegate so that
/// both panes resize proportionally when the window is resized.
///
/// Usage: attach as a .background() to one of the HSplitView's children.
struct SplitProportionFixer: NSViewRepresentable {

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        v.isHidden = true          // invisible — we only use it to walk the hierarchy
        context.coordinator.probe = v
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Walk up on the next runloop tick (the HSplitView's NSSplitView is a
        // few levels above us in the AppKit tree).
        DispatchQueue.main.async { [weak coord = context.coordinator] in
            coord?.attach(from: nsView)
        }
    }

    // MARK: - Coordinator / delegate

    final class Coordinator: NSObject, NSSplitViewDelegate {

        weak var probe: NSView?
        weak var splitView: NSSplitView?
        private let minWidth: CGFloat = 360

        /// Walk the superview chain until we find an NSSplitView with exactly
        /// two vertical subviews, then install ourselves as its delegate.
        func attach(from start: NSView) {
            var current: NSView? = start.superview
            while let v = current {
                if let sv = v as? NSSplitView,
                   sv.isVertical,
                   sv.subviews.count == 2,
                   sv !== splitView {
                    splitView = sv
                    sv.delegate = self
                    return
                }
                current = v.superview
            }
        }

        // MARK: NSSplitViewDelegate

        /// Called whenever the split view's frame changes.  We scale both panes
        /// by the same ratio so neither one takes all the extra/missing space.
        func splitView(_ sv: NSSplitView,
                       resizeSubviewsWithOldSize oldSize: NSSize) {
            guard sv.subviews.count == 2 else { sv.adjustSubviews(); return }

            let div       = sv.dividerThickness
            let oldUsable = oldSize.width - div
            let newUsable = sv.frame.width  - div
            guard newUsable > 0 else { return }
            let h = sv.frame.height

            // First layout (oldUsable ≈ 0): split evenly.
            guard oldUsable > 1 else {
                let half = (newUsable / 2).rounded(.towardZero)
                sv.subviews[0].frame = NSRect(x: 0,           y: 0, width: half,             height: h)
                sv.subviews[1].frame = NSRect(x: half + div,  y: 0, width: newUsable - half,  height: h)
                return
            }

            // Proportional scale.
            var w0 = (sv.subviews[0].frame.width / oldUsable * newUsable).rounded(.towardZero)
            var w1 = newUsable - w0
            let mn = minWidth
            if w0 < mn { w0 = mn; w1 = max(newUsable - mn, mn) }
            if w1 < mn { w1 = mn; w0 = max(newUsable - mn, mn) }

            sv.subviews[0].frame = NSRect(x: 0,        y: 0, width: w0, height: h)
            sv.subviews[1].frame = NSRect(x: w0 + div, y: 0, width: w1, height: h)
        }

        func splitView(_ sv: NSSplitView,
                       constrainMinCoordinate _: CGFloat,
                       ofSubviewAt _: Int) -> CGFloat { minWidth }

        func splitView(_ sv: NSSplitView,
                       constrainMaxCoordinate _: CGFloat,
                       ofSubviewAt _: Int) -> CGFloat {
            sv.frame.width - sv.dividerThickness - minWidth
        }
    }
}
