import Foundation
import Observation
import FileSystemKit

public extension FileItem {
    var sizeForSort: Int64 { isDirectory ? -1 : size }
    var dateForSort: Date { modifiedAt ?? .distantPast }
    var kindForSort: String { typeIdentifier ?? "" }
}

@Observable
@MainActor
public final class PaneViewModel: Identifiable {
    public enum SortKey: String, CaseIterable, Sendable {
        case name, size, date, kind
    }

    public let id: UUID
    public var currentPath: ProviderPath
    public var items: [FileItem] = []
    public var selection: Set<FileItem.ID> = []
    public var isLoading = false
    public var errorMessage: String?
    public var includeHidden = false
    public var searchQuery: String = ""
    /// When non-nil, only files whose names are in this set are shown (AI search result).
    public var aiSearchResults: Set<String>? = nil
    public var sortKey: SortKey = .name {
        didSet { items = applyView(allItems) }
    }
    public var sortAscending: Bool = true {
        didSet { items = applyView(allItems) }
    }

    public let provider: any FileProvider
    private var observationTask: Task<Void, Never>?
    private var history: [ProviderPath] = []
    private var historyIndex = -1
    private var allItems: [FileItem] = []

    public var displayName: String {
        currentPath.components.last ?? "/"
    }

    public var fileCount: Int { allItems.filter { !$0.isDirectory }.count }
    public var dirCount: Int { allItems.filter { $0.isDirectory }.count }
    public var totalCount: Int { allItems.count }
    public var hiddenSuppressedCount: Int {
        // Best-effort: when includeHidden is off we don't know the suppressed count
        // without re-listing; so we just expose 0 here. Real count would need provider.list with hidden=true.
        0
    }

    public init(provider: any FileProvider, initialPath: ProviderPath) {
        self.id = UUID()
        self.provider = provider
        self.currentPath = initialPath
        self.history = [initialPath]
        self.historyIndex = 0
    }

    public var canGoBack: Bool { historyIndex > 0 }
    public var canGoForward: Bool { historyIndex + 1 < history.count }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await provider.list(currentPath, includeHidden: includeHidden)
            allItems = result
            items = applyView(allItems)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            allItems = []
            items = []
        }
        startObserving()
    }

    public func setSearch(_ q: String) {
        searchQuery     = q
        aiSearchResults = nil
        items           = applyView(allItems)
    }

    /// Apply an AI search result: only show files whose names are in `matched`.
    public func setAISearchResults(_ matched: Set<String>) {
        aiSearchResults = matched
        items           = applyView(allItems)
    }

    public func toggleHidden() async {
        includeHidden.toggle()
        await reload()
    }

    private func applyView(_ input: [FileItem]) -> [FileItem] {
        let filtered: [FileItem]
        if let aiSet = aiSearchResults {
            // AI search mode: show only files in the matched set
            filtered = aiSet.isEmpty ? [] : input.filter { aiSet.contains($0.name) }
        } else {
            let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
            filtered = q.isEmpty ? input : input.filter { $0.name.lowercased().contains(q) }
        }
        return sortItems(filtered.filter { $0.isDirectory })
            + sortItems(filtered.filter { !$0.isDirectory })
    }

    private func sortItems(_ list: [FileItem]) -> [FileItem] {
        let asc = sortAscending
        return list.sorted { a, b in
            let result: Bool
            switch sortKey {
            case .name: result = a.name.localizedStandardCompare(b.name) == .orderedAscending
            case .size: result = a.sizeForSort < b.sizeForSort
            case .date: result = a.dateForSort < b.dateForSort
            case .kind:
                let cmp = a.kindForSort.compare(b.kindForSort)
                if cmp == .orderedSame {
                    result = a.name.localizedStandardCompare(b.name) == .orderedAscending
                } else {
                    result = cmp == .orderedAscending
                }
            }
            return asc ? result : !result
        }
    }

    public func navigate(to path: ProviderPath, recordHistory: Bool = true) async {
        if recordHistory {
            history = Array(history.prefix(historyIndex + 1))
            history.append(path)
            historyIndex = history.count - 1
        }
        currentPath = path
        selection.removeAll()
        await load()
    }

    public func goUp() async {
        if let parent = currentPath.parent() {
            await navigate(to: parent)
        }
    }

    public func goBack() async {
        guard historyIndex > 0 else { return }
        historyIndex -= 1
        await navigate(to: history[historyIndex], recordHistory: false)
    }

    public func goForward() async {
        guard historyIndex + 1 < history.count else { return }
        historyIndex += 1
        await navigate(to: history[historyIndex], recordHistory: false)
    }

    private func startObserving() {
        observationTask?.cancel()
        guard provider.supportsObservation else { return }
        let stream = provider.observe(currentPath)
        observationTask = Task { [weak self] in
            // Debounce: coalesce rapid filesystem events (e.g. many files
            // downloading into the watched directory) into a single reload.
            // Without this, each individual DispatchSource event fires a
            // full reloadData() on the NSTableView, causing visible flickering.
            var debounce: Task<Void, Never>?
            for await _ in stream {
                if Task.isCancelled { return }
                debounce?.cancel()
                debounce = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(400))
                    guard !Task.isCancelled else { return }
                    await self?.reload()
                }
            }
        }
    }

    public func reload() async {
        do {
            let result = try await provider.list(currentPath, includeHidden: includeHidden)
            allItems = result
            items = applyView(allItems)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func stopObserving() {
        observationTask?.cancel()
        observationTask = nil
    }
}
