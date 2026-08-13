import SwiftUI
import FileSystemKit
import AppearanceKit

struct SidebarView: View {
    @Bindable var store: BookmarksStore
    let onSelect: (Bookmark) -> Void
    @Environment(\.appearanceTheme) private var theme
    @State private var dropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("收藏")
                    .font(.system(size: theme.captionFontSize, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
                    .textCase(.uppercase)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 8)

            List {
                ForEach(store.bookmarks) { bookmark in
                    BookmarkRow(bookmark: bookmark)
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect(bookmark) }
                        .contextMenu {
                            Button("打开") { onSelect(bookmark) }
                            Divider()
                            Button("从收藏中移除", role: .destructive) {
                                store.remove(bookmark.id)
                            }
                        }
                }
                .onMove { source, destination in
                    store.move(from: source, to: destination)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .overlay(alignment: .bottom) {
                if dropTargeted {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(theme.accent)
                        Text("拖入此处加入收藏")
                            .font(.system(size: theme.captionFontSize))
                            .foregroundStyle(theme.primaryText)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity)
                    .background(theme.accent.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 0)
                            .stroke(theme.accent.opacity(0.5), lineWidth: 1.5)
                    )
                    .transition(.opacity)
                }
            }
        }
        .background(theme.sidebarBackground)
        .frame(minWidth: 180, idealWidth: 200, maxWidth: 280)
        .dropDestination(for: URL.self, action: { urls, _ in
            for url in urls {
                let name = url.lastPathComponent.isEmpty ? "/" : url.lastPathComponent
                store.add(Bookmark(name: name, path: url.path, iconSymbol: "folder"))
            }
            return !urls.isEmpty
        }, isTargeted: { dropTargeted = $0 })
        .animation(.easeOut(duration: 0.12), value: dropTargeted)
    }
}

private struct BookmarkRow: View {
    let bookmark: Bookmark
    @Environment(\.appearanceTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: bookmark.iconSymbol)
                .foregroundStyle(theme.accent)
                .frame(width: 16)
            Text(bookmark.name)
                .font(.system(size: theme.bodyFontSize))
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 1)
    }
}
