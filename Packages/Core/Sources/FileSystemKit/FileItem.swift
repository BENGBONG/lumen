import Foundation

public struct FileItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let url: URL
    public let name: String
    public let isDirectory: Bool
    public let isPackage: Bool
    public let isHidden: Bool
    public let isSymlink: Bool
    public let size: Int64
    public let modifiedAt: Date?
    public let createdAt: Date?
    public let typeIdentifier: String?

    public init(
        id: String,
        url: URL,
        name: String,
        isDirectory: Bool,
        isPackage: Bool = false,
        isHidden: Bool = false,
        isSymlink: Bool = false,
        size: Int64 = -1,
        modifiedAt: Date? = nil,
        createdAt: Date? = nil,
        typeIdentifier: String? = nil
    ) {
        self.id = id
        self.url = url
        self.name = name
        self.isDirectory = isDirectory
        self.isPackage = isPackage
        self.isHidden = isHidden
        self.isSymlink = isSymlink
        self.size = size
        self.modifiedAt = modifiedAt
        self.createdAt = createdAt
        self.typeIdentifier = typeIdentifier
    }
}
