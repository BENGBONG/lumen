import Foundation

public struct PaneStateSnapshot: Codable, Sendable {
    public var leftPath: String
    public var rightPath: String

    public init(leftPath: String, rightPath: String) {
        self.leftPath = leftPath
        self.rightPath = rightPath
    }
}

public enum PaneStateStore {
    private static let key = "ForkLiftClone.paneState"

    public static func load() -> PaneStateSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(PaneStateSnapshot.self, from: data)
    }

    public static func save(_ snapshot: PaneStateSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
