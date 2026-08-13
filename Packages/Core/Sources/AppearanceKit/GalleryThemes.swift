import SwiftUI

// MARK: - 深海（深色冷调 · 玻璃 + 青色）

public struct OceanDepthTheme: AppearanceTheme {
    public let id = "ocean-depth"
    public var colorSchemeHint: ColorScheme? { .dark }
    public let displayName = "深海"
    public init() {}

    public var windowBackground: AnyShapeStyle { AnyShapeStyle(Color(red: 0.043, green: 0.071, blue: 0.125)) }
    public var sidebarBackground: AnyShapeStyle { AnyShapeStyle(.ultraThinMaterial) }
    public var paneBackground: AnyShapeStyle { AnyShapeStyle(.thinMaterial) }
    public var chromeTint: Color { Color(red: 0.059, green: 0.106, blue: 0.176).opacity(0.88) }
    public var paneTint: Color { Color(red: 0.043, green: 0.078, blue: 0.141).opacity(0.93) }
    public var chromeBase: Color { Color(red: 0.059, green: 0.106, blue: 0.176) }
    public var paneBase: Color { Color(red: 0.043, green: 0.078, blue: 0.141) }

    public var rowSelected: Color { Color(red: 0.133, green: 0.827, blue: 0.933).opacity(0.30) }
    public var rowSelectedInactive: Color { Color.white.opacity(0.10) }
    public var rowHover: Color { Color.white.opacity(0.06) }
    public var separator: Color { Color(red: 0.55, green: 0.71, blue: 0.85).opacity(0.14) }

    public var primaryText: Color { Color.white.opacity(0.94) }
    public var secondaryText: Color { Color(red: 0.62, green: 0.72, blue: 0.83).opacity(0.75) }
    public var accent: Color { Color(red: 0.133, green: 0.827, blue: 0.933) }   // 青 #22D3EE

    public let rowHeight: CGFloat = 26
    public let cornerRadius: CGFloat = 8
    public let bodyFontSize: CGFloat = 13
    public let captionFontSize: CGFloat = 11

    public var previewSidebar: Color { Color(red: 0.059, green: 0.106, blue: 0.176) }
    public var previewPane: Color { Color(red: 0.043, green: 0.078, blue: 0.141) }
}

// MARK: - 琥珀（深色暖调 · 熔岩琥珀）

public struct AmberDuskTheme: AppearanceTheme {
    public let id = "amber-dusk"
    public var colorSchemeHint: ColorScheme? { .dark }
    public let displayName = "琥珀"
    public init() {}

    public var windowBackground: AnyShapeStyle { AnyShapeStyle(Color(red: 0.086, green: 0.067, blue: 0.051)) }
    public var sidebarBackground: AnyShapeStyle { AnyShapeStyle(.ultraThinMaterial) }
    public var paneBackground: AnyShapeStyle { AnyShapeStyle(.thinMaterial) }
    public var chromeTint: Color { Color(red: 0.129, green: 0.094, blue: 0.071).opacity(0.88) }
    public var paneTint: Color { Color(red: 0.098, green: 0.075, blue: 0.059).opacity(0.93) }
    public var chromeBase: Color { Color(red: 0.129, green: 0.094, blue: 0.071) }
    public var paneBase: Color { Color(red: 0.098, green: 0.075, blue: 0.059) }

    public var rowSelected: Color { Color(red: 0.961, green: 0.647, blue: 0.141).opacity(0.32) }
    public var rowSelectedInactive: Color { Color.white.opacity(0.10) }
    public var rowHover: Color { Color(red: 1, green: 0.9, blue: 0.75).opacity(0.06) }
    public var separator: Color { Color(red: 0.85, green: 0.70, blue: 0.50).opacity(0.14) }

    public var primaryText: Color { Color(red: 0.97, green: 0.94, blue: 0.90).opacity(0.95) }
    public var secondaryText: Color { Color(red: 0.76, green: 0.68, blue: 0.59).opacity(0.75) }
    public var accent: Color { Color(red: 0.961, green: 0.647, blue: 0.141) }   // 琥珀 #F5A524

    public let rowHeight: CGFloat = 26
    public let cornerRadius: CGFloat = 8
    public let bodyFontSize: CGFloat = 13
    public let captionFontSize: CGFloat = 11

    public var previewSidebar: Color { Color(red: 0.129, green: 0.094, blue: 0.071) }
    public var previewPane: Color { Color(red: 0.098, green: 0.075, blue: 0.059) }
}

// MARK: - 抹茶（浅色暖绿 · 奶油纸感）

public struct MatchaTheme: AppearanceTheme {
    public let id = "matcha"
    public var colorSchemeHint: ColorScheme? { .light }
    public let displayName = "抹茶"
    public init() {}

    public var windowBackground: AnyShapeStyle { AnyShapeStyle(Color(red: 0.965, green: 0.961, blue: 0.929)) }
    public var sidebarBackground: AnyShapeStyle { AnyShapeStyle(.ultraThinMaterial) }
    public var paneBackground: AnyShapeStyle { AnyShapeStyle(.thinMaterial) }
    public var chromeTint: Color { Color(red: 0.929, green: 0.925, blue: 0.878).opacity(0.85) }
    public var paneTint: Color { Color(red: 0.984, green: 0.980, blue: 0.957).opacity(0.93) }
    public var chromeBase: Color { Color(red: 0.929, green: 0.925, blue: 0.878) }
    public var paneBase: Color { Color(red: 0.984, green: 0.980, blue: 0.957) }

    public var rowSelected: Color { Color(red: 0.42, green: 0.557, blue: 0.306).opacity(0.22) }
    public var rowSelectedInactive: Color { Color(red: 0.35, green: 0.36, blue: 0.32).opacity(0.14) }
    public var rowHover: Color { Color(red: 0.35, green: 0.38, blue: 0.28).opacity(0.06) }
    public var separator: Color { Color(red: 0.55, green: 0.56, blue: 0.47).opacity(0.22) }

    public var primaryText: Color { Color(red: 0.18, green: 0.20, blue: 0.153) }
    public var secondaryText: Color { Color(red: 0.478, green: 0.506, blue: 0.439) }
    public var accent: Color { Color(red: 0.42, green: 0.557, blue: 0.306) }   // 抹茶 #6B8E4E

    public let rowHeight: CGFloat = 26
    public let cornerRadius: CGFloat = 8
    public let bodyFontSize: CGFloat = 13
    public let captionFontSize: CGFloat = 11

    public var previewSidebar: Color { Color(red: 0.929, green: 0.925, blue: 0.878) }
    public var previewPane: Color { Color(red: 0.984, green: 0.980, blue: 0.957) }
}

// MARK: - 蔷薇（浅色粉调 · 柔和玫瑰）

public struct RoseTheme: AppearanceTheme {
    public let id = "rose"
    public var colorSchemeHint: ColorScheme? { .light }
    public let displayName = "蔷薇"
    public init() {}

    public var windowBackground: AnyShapeStyle { AnyShapeStyle(Color(red: 0.976, green: 0.949, blue: 0.957)) }
    public var sidebarBackground: AnyShapeStyle { AnyShapeStyle(.ultraThinMaterial) }
    public var paneBackground: AnyShapeStyle { AnyShapeStyle(.thinMaterial) }
    public var chromeTint: Color { Color(red: 0.961, green: 0.918, blue: 0.929).opacity(0.85) }
    public var paneTint: Color { Color(red: 0.992, green: 0.973, blue: 0.976).opacity(0.93) }
    public var chromeBase: Color { Color(red: 0.961, green: 0.918, blue: 0.929) }
    public var paneBase: Color { Color(red: 0.992, green: 0.973, blue: 0.976) }

    public var rowSelected: Color { Color(red: 0.839, green: 0.325, blue: 0.427).opacity(0.20) }
    public var rowSelectedInactive: Color { Color(red: 0.42, green: 0.36, blue: 0.38).opacity(0.13) }
    public var rowHover: Color { Color(red: 0.65, green: 0.35, blue: 0.42).opacity(0.06) }
    public var separator: Color { Color(red: 0.72, green: 0.52, blue: 0.58).opacity(0.20) }

    public var primaryText: Color { Color(red: 0.20, green: 0.145, blue: 0.165) }
    public var secondaryText: Color { Color(red: 0.545, green: 0.455, blue: 0.486) }
    public var accent: Color { Color(red: 0.839, green: 0.325, blue: 0.427) }   // 蔷薇 #D6536D

    public let rowHeight: CGFloat = 26
    public let cornerRadius: CGFloat = 8
    public let bodyFontSize: CGFloat = 13
    public let captionFontSize: CGFloat = 11

    public var previewSidebar: Color { Color(red: 0.961, green: 0.918, blue: 0.929) }
    public var previewPane: Color { Color(red: 0.992, green: 0.973, blue: 0.976) }
}

// MARK: - 水墨（黑白极简 · 锐利小圆角）

public struct InkTheme: AppearanceTheme {
    public let id = "ink"
    public var colorSchemeHint: ColorScheme? { .light }
    public let displayName = "水墨"
    public init() {}

    public var windowBackground: AnyShapeStyle { AnyShapeStyle(Color.white) }
    public var sidebarBackground: AnyShapeStyle { AnyShapeStyle(.ultraThinMaterial) }
    public var paneBackground: AnyShapeStyle { AnyShapeStyle(.thinMaterial) }
    public var chromeTint: Color { Color(red: 0.955, green: 0.955, blue: 0.949).opacity(0.87) }
    public var paneTint: Color { Color.white.opacity(0.94) }
    public var chromeBase: Color { Color(red: 0.955, green: 0.955, blue: 0.949) }
    public var paneBase: Color { Color.white }

    public var rowSelected: Color { Color.black.opacity(0.14) }
    public var rowSelectedInactive: Color { Color.black.opacity(0.07) }
    public var rowHover: Color { Color.black.opacity(0.045) }
    public var separator: Color { Color.black.opacity(0.12) }

    public var primaryText: Color { Color(red: 0.067, green: 0.067, blue: 0.067) }
    public var secondaryText: Color { Color(red: 0.42, green: 0.42, blue: 0.42) }
    public var accent: Color { Color(red: 0.10, green: 0.10, blue: 0.10) }   // 墨色——克制的单色

    public let rowHeight: CGFloat = 24
    public let cornerRadius: CGFloat = 4    // 锐利，极简
    public let bodyFontSize: CGFloat = 13
    public let captionFontSize: CGFloat = 11

    public var previewSidebar: Color { Color(red: 0.955, green: 0.955, blue: 0.949) }
    public var previewPane: Color { Color.white }
}
