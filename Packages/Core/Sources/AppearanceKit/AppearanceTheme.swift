import SwiftUI

public protocol AppearanceTheme: Sendable {
    var id: String { get }
    var displayName: String { get }

    var windowBackground: AnyShapeStyle { get }
    var sidebarBackground: AnyShapeStyle { get }
    var paneBackground: AnyShapeStyle { get }

    var rowSelected: Color { get }
    var rowHover: Color { get }
    var separator: Color { get }

    var primaryText: Color { get }
    var secondaryText: Color { get }
    var accent: Color { get }

    var rowHeight: CGFloat { get }
    var cornerRadius: CGFloat { get }
    var bodyFontSize: CGFloat { get }
    var captionFontSize: CGFloat { get }
}

public struct AppearanceThemeKey: EnvironmentKey {
    public static let defaultValue: any AppearanceTheme = NativeTheme()
}

public extension EnvironmentValues {
    var appearanceTheme: any AppearanceTheme {
        get { self[AppearanceThemeKey.self] }
        set { self[AppearanceThemeKey.self] = newValue }
    }
}
