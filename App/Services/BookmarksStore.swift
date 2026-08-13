import Foundation
import Observation
import FileSystemKit

public struct Bookmark: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var path: String
    public var iconSymbol: String

    public init(id: UUID = UUID(), name: String, path: String, iconSymbol: String = "folder") {
        self.id = id
        self.name = name
        self.path = path
        self.iconSymbol = iconSymbol
    }

    public var providerPath: ProviderPath {
        let components = (path as NSString).pathComponents.filter { $0 != "/" }
        return ProviderPath(providerID: "local", components: components)
    }
}

@Observable
@MainActor
public final class BookmarksStore {
    public private(set) var bookmarks: [Bookmark] = []

    private let fileURL: URL
    private static let defaultBookmarks: [Bookmark] = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            .init(name: "主目录", path: home, iconSymbol: "house"),
            .init(name: "桌面", path: "\(home)/Desktop", iconSymbol: "menubar.dock.rectangle"),
            .init(name: "下载", path: "\(home)/Downloads", iconSymbol: "arrow.down.circle"),
            .init(name: "文档", path: "\(home)/Documents", iconSymbol: "doc"),
            .init(name: "应用程序", path: "/Applications", iconSymbol: "app.badge"),
        ]
    }()

    public init() {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let appDir = support.appendingPathComponent("ForkLiftClone", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        self.fileURL = appDir.appendingPathComponent("bookmarks.json")
        load()
    }

    public func add(_ bookmark: Bookmark) {
        guard !bookmarks.contains(where: { $0.path == bookmark.path }) else { return }
        bookmarks.append(bookmark)
        save()
    }

    public func remove(_ id: Bookmark.ID) {
        bookmarks.removeAll { $0.id == id }
        save()
    }

    public func move(from source: IndexSet, to destination: Int) {
        bookmarks.move(fromOffsets: source, toOffset: destination)
        save()
    }

    public func rename(_ id: Bookmark.ID, to name: String) {
        guard let idx = bookmarks.firstIndex(where: { $0.id == id }) else { return }
        bookmarks[idx].name = name
        save()
    }

    private func load() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([Bookmark].self, from: data) {
            bookmarks = decoded
        } else {
            bookmarks = Self.defaultBookmarks
            save()
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(bookmarks) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
