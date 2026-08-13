import Foundation
import Observation
import FileSystemKit

@Observable
@MainActor
public final class PaneTabsViewModel {
    public var tabs: [PaneViewModel] = []
    public var activeID: PaneViewModel.ID

    public let provider: any FileProvider

    public init(provider: any FileProvider, initialPath: ProviderPath) {
        self.provider = provider
        let first = PaneViewModel(provider: provider, initialPath: initialPath)
        self.tabs = [first]
        self.activeID = first.id
    }

    /// 多标签恢复（重启后还原会话）。paths 为空时回退单标签根目录。
    public init(provider: any FileProvider, initialPaths: [ProviderPath], activeIndex: Int) {
        self.provider = provider
        let vms = initialPaths.map { PaneViewModel(provider: provider, initialPath: $0) }
        if vms.isEmpty {
            let first = PaneViewModel(provider: provider, initialPath:
                ProviderPath(providerID: provider.id, components: []))
            self.tabs = [first]
            self.activeID = first.id
        } else {
            self.tabs = vms
            self.activeID = vms[min(max(activeIndex, 0), vms.count - 1)].id
        }
    }

    public var active: PaneViewModel {
        tabs.first(where: { $0.id == activeID }) ?? tabs[0]
    }

    public func newTab(at path: ProviderPath) {
        let tab = PaneViewModel(provider: provider, initialPath: path)
        tabs.append(tab)
        activeID = tab.id
        Task { await tab.load() }
    }

    public func closeTab(_ id: PaneViewModel.ID) {
        guard tabs.count > 1 else { return }
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        let wasActive = tabs[idx].id == activeID
        tabs[idx].stopObserving()
        tabs.remove(at: idx)
        if wasActive {
            let newIdx = max(0, idx - 1)
            activeID = tabs[newIdx].id
        }
    }

    public func activate(_ id: PaneViewModel.ID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeID = id
    }

    public func duplicateActive() {
        newTab(at: active.currentPath)
    }
}
