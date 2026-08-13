import Foundation

public final class DirectoryWatcher: @unchecked Sendable {
    private let url: URL
    private let handler: @Sendable (FileSystemEvent) -> Void
    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1

    public init(url: URL, handler: @escaping @Sendable (FileSystemEvent) -> Void) {
        self.url = url
        self.handler = handler
    }

    public func start() {
        fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let descriptor = fd
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .extend, .attrib],
            queue: .global(qos: .utility)
        )
        let watchedURL = url
        let cb = handler
        src.setEventHandler {
            let path = ProviderPath(
                providerID: "local",
                components: watchedURL.standardizedFileURL.pathComponents.filter { $0 != "/" }
            )
            cb(.changed(path))
        }
        src.setCancelHandler {
            close(descriptor)
        }
        src.resume()
        self.source = src
    }

    public func stop() {
        source?.cancel()
        source = nil
        fd = -1
    }

    deinit { stop() }
}
