import SwiftUI
import AppearanceKit

struct TabBarView: View {
    @Bindable var tabs: PaneTabsViewModel
    let isFocused: Bool
    @Environment(\.appearanceTheme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 1) {
                    ForEach(tabs.tabs) { tab in
                        TabChip(
                            label: tab.displayName,
                            isActive: tab.id == tabs.activeID,
                            canClose: tabs.tabs.count > 1,
                            onActivate: { tabs.activate(tab.id) },
                            onClose: { tabs.closeTab(tab.id) }
                        )
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 3)
            }
            Divider()
                .frame(height: 16)
                .padding(.horizontal, 2)
            Button {
                tabs.duplicateActive()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: theme.captionFontSize + 1, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
                    .frame(width: 24, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("新建标签页 (⌘T)")
        }
        .frame(height: 30)
        .glassChrome(theme)
        .background(isFocused ? theme.accent.opacity(0.10) : Color.clear)
    }
}

private struct TabChip: View {
    let label: String
    let isActive: Bool
    let canClose: Bool
    let onActivate: () -> Void
    let onClose: () -> Void
    @Environment(\.appearanceTheme) private var theme
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .font(.system(size: theme.captionFontSize))
                .foregroundStyle(isActive ? theme.accent : theme.secondaryText)
            Text(label)
                .font(.system(size: theme.captionFontSize,
                              weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? theme.primaryText : theme.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(minWidth: 60, idealWidth: 120, maxWidth: 160, alignment: .leading)
            if canClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: theme.captionFontSize - 2, weight: .bold))
                        .foregroundStyle(theme.secondaryText.opacity(isHovering || isActive ? 1.0 : 0.0))
                        .frame(width: 12, height: 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 12, height: 12)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isActive
                      ? theme.paneBackground
                      : AnyShapeStyle(isHovering ? theme.rowHover : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(
                    isActive ? theme.separator : Color.clear,
                    lineWidth: 0.5
                )
        )
        .shadow(color: .black.opacity(isActive ? 0.10 : 0), radius: 2, y: 1)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(perform: onActivate)
    }
}
