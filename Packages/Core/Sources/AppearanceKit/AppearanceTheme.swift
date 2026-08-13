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

    /// 非焦点窗格里已选中行的颜色（Finder 语义：失焦变灰）。
    var rowSelectedInactive: Color { get }
    /// 叠加在镀铬层（侧栏/工具栏/标签栏等材质背景）之上的染色，默认无色。
    var chromeTint: Color { get }
    /// 叠加在表格区材质背景之上的染色，默认无色。
    var paneTint: Color { get }

    var primaryText: Color { get }
    var secondaryText: Color { get }
    var accent: Color { get }

    /// 设置页预览色板（材质无法在小预览里正确呈现，用等效纯色）。
    var previewSidebar: Color { get }
    var previewPane: Color { get }

    var rowHeight: CGFloat { get }
    var cornerRadius: CGFloat { get }
    var bodyFontSize: CGFloat { get }
    var captionFontSize: CGFloat { get }
}

public extension AppearanceTheme {
    var rowSelectedInactive: Color { Color.gray.opacity(0.18) }
    var chromeTint: Color { .clear }
    var paneTint: Color { .clear }
    var previewSidebar: Color { Color(nsColor: .windowBackgroundColor) }
    var previewPane: Color { Color(nsColor: .textBackgroundColor) }
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
