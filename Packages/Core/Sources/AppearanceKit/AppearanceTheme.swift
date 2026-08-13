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
    /// 镀铬层材质底下的不透明底色——挡住桌面壁纸渗透（深色模式下
    /// ultraThinMaterial 太透，浅壁纸会透上来形成脏色块）。
    var chromeBase: Color { get }
    /// 表格区材质底下的不透明底色。
    var paneBase: Color { get }

    var primaryText: Color { get }
    var secondaryText: Color { get }
    var accent: Color { get }

    /// 设置页预览色板（材质无法在小预览里正确呈现，用等效纯色）。
    var previewSidebar: Color { get }
    var previewPane: Color { get }

    /// 主题的外观倾向：深色主题 .dark、浅色主题 .light、跟随系统（原生）nil。
    /// 应用据此设置 NSApp.appearance——否则 SwiftUI 主题色与 AppKit 控件
    /// （表格/表头跟随系统外观）各画各的：浅色主题在深色系统下会出现
    /// "浅栏深表"的拼接怪相（2026-08-13 水墨主题事故）。
    var colorSchemeHint: ColorScheme? { get }

    var rowHeight: CGFloat { get }
    var cornerRadius: CGFloat { get }
    var bodyFontSize: CGFloat { get }
    var captionFontSize: CGFloat { get }
}

public extension AppearanceTheme {
    var rowSelectedInactive: Color { Color.gray.opacity(0.18) }
    var chromeTint: Color { .clear }
    var paneTint: Color { .clear }
    // 默认跟随系统深浅的不透明底色（NSColor 动态色，dark/light 自适应）
    var chromeBase: Color { Color(nsColor: .windowBackgroundColor) }
    var paneBase: Color { Color(nsColor: .textBackgroundColor) }
    var previewSidebar: Color { Color(nsColor: .windowBackgroundColor) }
    var previewPane: Color { Color(nsColor: .textBackgroundColor) }
    var colorSchemeHint: ColorScheme? { nil }
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
