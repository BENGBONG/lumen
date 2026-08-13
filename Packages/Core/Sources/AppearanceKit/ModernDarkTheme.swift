import SwiftUI

public struct ModernDarkTheme: AppearanceTheme {
    public let id = "modern-dark"
    public let displayName = "现代深色"

    public init() {}

    public var windowBackground: AnyShapeStyle {
        AnyShapeStyle(Color(red: 0.055, green: 0.067, blue: 0.086))
    }
    // 玻璃材质 + 深蓝染色叠层（chromeTint / paneTint 在视图中叠加）
    public var sidebarBackground: AnyShapeStyle {
        AnyShapeStyle(.ultraThinMaterial)
    }
    public var paneBackground: AnyShapeStyle {
        AnyShapeStyle(.thinMaterial)
    }
    public var chromeTint: Color { Color(red: 0.094, green: 0.106, blue: 0.133).opacity(0.88) }
    public var paneTint: Color { Color(red: 0.071, green: 0.082, blue: 0.106).opacity(0.93) }
    public var chromeBase: Color { Color(red: 0.094, green: 0.106, blue: 0.133) }
    public var paneBase: Color { Color(red: 0.071, green: 0.082, blue: 0.106) }

    public var rowSelected: Color { Color(red: 0.227, green: 0.357, blue: 0.706).opacity(0.38) }
    public var rowSelectedInactive: Color { Color.white.opacity(0.10) }
    public var rowHover: Color { Color.white.opacity(0.06) }
    public var separator: Color { Color.white.opacity(0.09) }

    public var primaryText: Color { Color.white.opacity(0.94) }
    public var secondaryText: Color { Color.white.opacity(0.58) }
    public var accent: Color { Color(red: 0.404, green: 0.671, blue: 0.988) }

    public let rowHeight: CGFloat = 24
    public let cornerRadius: CGFloat = 5
    public let bodyFontSize: CGFloat = 12.5
    public let captionFontSize: CGFloat = 10.5

    public var previewSidebar: Color { Color(red: 0.094, green: 0.106, blue: 0.133) }
    public var previewPane: Color { Color(red: 0.071, green: 0.082, blue: 0.106) }
}
