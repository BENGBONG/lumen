import SwiftUI

public struct LightTheme: AppearanceTheme {
    public let id = "light"
    public let displayName = "轻量明亮"

    public init() {}

    public var windowBackground: AnyShapeStyle {
        AnyShapeStyle(Color(red: 0.992, green: 0.992, blue: 0.992))
    }
    public var sidebarBackground: AnyShapeStyle {
        AnyShapeStyle(Color(red: 0.965, green: 0.967, blue: 0.972))
    }
    public var paneBackground: AnyShapeStyle { AnyShapeStyle(Color.white) }

    public var rowSelected: Color { Color(red: 0.882, green: 0.918, blue: 0.984) }
    public var rowHover: Color { Color(red: 0.949, green: 0.953, blue: 0.961) }
    public var separator: Color { Color(red: 0.882, green: 0.886, blue: 0.898) }

    public var primaryText: Color { Color(red: 0.114, green: 0.122, blue: 0.149) }
    public var secondaryText: Color { Color(red: 0.451, green: 0.467, blue: 0.502) }
    public var accent: Color { Color(red: 0.247, green: 0.439, blue: 0.937) }

    public let rowHeight: CGFloat = 30
    public let cornerRadius: CGFloat = 8
    public let bodyFontSize: CGFloat = 13
    public let captionFontSize: CGFloat = 11
}
