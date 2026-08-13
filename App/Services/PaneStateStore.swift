import Foundation

/// 窗格状态快照：每侧的全部标签页路径 + 活跃标签 + 焦点侧。
/// 兼容 v1 旧格式（仅 leftPath/rightPath）。
public struct PaneStateSnapshot: Codable, Sendable {
    public var leftTabs: [String]
    public var rightTabs: [String]
    public var leftActive: Int
    public var rightActive: Int
    public var focusedLeft: Bool

    public init(leftTabs: [String], rightTabs: [String],
                leftActive: Int, rightActive: Int, focusedLeft: Bool) {
        self.leftTabs = leftTabs
        self.rightTabs = rightTabs
        self.leftActive = leftActive
        self.rightActive = rightActive
        self.focusedLeft = focusedLeft
    }

    private enum CodingKeys: String, CodingKey {
        case leftTabs, rightTabs, leftActive, rightActive, focusedLeft
        case leftPath, rightPath   // v1 旧字段
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let lt = try c.decodeIfPresent([String].self, forKey: .leftTabs) {
            leftTabs = lt
            rightTabs = try c.decodeIfPresent([String].self, forKey: .rightTabs) ?? []
            leftActive = try c.decodeIfPresent(Int.self, forKey: .leftActive) ?? 0
            rightActive = try c.decodeIfPresent(Int.self, forKey: .rightActive) ?? 0
            focusedLeft = try c.decodeIfPresent(Bool.self, forKey: .focusedLeft) ?? true
        } else {
            // v1 迁移：单路径 → 单标签
            leftTabs = [try c.decode(String.self, forKey: .leftPath)]
            rightTabs = [try c.decode(String.self, forKey: .rightPath)]
            leftActive = 0
            rightActive = 0
            focusedLeft = true
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(leftTabs, forKey: .leftTabs)
        try c.encode(rightTabs, forKey: .rightTabs)
        try c.encode(leftActive, forKey: .leftActive)
        try c.encode(rightActive, forKey: .rightActive)
        try c.encode(focusedLeft, forKey: .focusedLeft)
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
