import SwiftUI
import FileSystemKit
import AppearanceKit

struct PaneView: View {
    @Bindable var tabs: PaneTabsViewModel
    let isFocused: Bool
    let onFocus: () -> Void
    let onDropFiles: ([URL], ProviderPath, Bool) -> Void   // Bool = isMove
    @Environment(\.appearanceTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            // Top accent strip — 3px when focused, 1px separator otherwise.
            // A short downward gradient under the strip gives the focused pane
            // a clearly readable glow without visual noise.
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(isFocused ? theme.accent : theme.separator)
                    .frame(height: isFocused ? 3 : 1)
                if isFocused {
                    LinearGradient(
                        colors: [theme.accent.opacity(0.22), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 16)
                    .offset(y: 3)
                    .allowsHitTesting(false)
                }
            }
            .frame(height: 3)

            TabBarView(tabs: tabs, isFocused: isFocused)
                .contentShape(Rectangle())
                .onTapGesture { onFocus() }
            Divider()
            PaneToolbarView(vm: tabs.active, isActive: isFocused)
                .contentShape(Rectangle())
                .onTapGesture { onFocus() }
            Divider()
            PathBarView(path: tabs.active.currentPath, isFocused: isFocused) { newPath in
                Task { await tabs.active.navigate(to: newPath) }
            }
            .contentShape(Rectangle())
            .onTapGesture { onFocus() }
            Divider()
            FileTableView(
                vm: tabs.active,
                isPaneFocused: isFocused,
                onOpenInNewTab: { path in tabs.newTab(at: path) },
                onDropFiles: { urls, destPath, isMove in onDropFiles(urls, destPath, isMove) },
                onUserInteraction: onFocus
            )
            .id(tabs.active.id)
            Divider()
            StatusBarView(vm: tabs.active)
        }
        .glassPane(theme)
        // 焦点窗格：accent 内描边，一眼看出当前操作的是哪一侧
        .overlay(
            Rectangle()
                .strokeBorder(theme.accent.opacity(isFocused ? 0.45 : 0), lineWidth: 1.5)
                .allowsHitTesting(false)
        )
        .animation(.easeInOut(duration: 0.18), value: isFocused)
        .frame(minWidth: 360)
        // Deliberately NOT putting any gesture on the whole pane: any gesture
        // recognizer above the Table participates in AppKit's gesture
        // arbitration and visibly delays NSTableView's mouse-down selection.
        // Focus follows table interaction (via FileTableView.onUserInteraction)
        // and explicit clicks on tab/toolbar/path bars.
    }
}
