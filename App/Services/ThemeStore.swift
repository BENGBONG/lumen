import Foundation
import Observation
import AppearanceKit

@Observable
@MainActor
public final class ThemeStore {
    public var theme: any AppearanceTheme {
        didSet { persist() }
    }

    public static let allThemes: [any AppearanceTheme] = [
        NativeTheme(),
        LightTheme(),
        MatchaTheme(),
        RoseTheme(),
        InkTheme(),
        ModernDarkTheme(),
        OceanDepthTheme(),
        AmberDuskTheme(),
    ]

    private static let key = "ForkLiftClone.themeID"

    public init() {
        let id = UserDefaults.standard.string(forKey: Self.key) ?? "native"
        self.theme = Self.allThemes.first(where: { $0.id == id }) ?? NativeTheme()
    }

    public func setTheme(id: String) {
        if let match = Self.allThemes.first(where: { $0.id == id }) {
            theme = match
        }
    }

    private func persist() {
        UserDefaults.standard.set(theme.id, forKey: Self.key)
    }
}
