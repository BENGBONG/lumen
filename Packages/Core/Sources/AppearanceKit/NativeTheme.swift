import SwiftUI

public struct NativeTheme: AppearanceTheme {
    public let id = "native"
    public let displayName = "macOS 原生"

    public init() {}

    public var windowBackground: AnyShapeStyle { AnyShapeStyle(.windowBackground) }
    public var sidebarBackground: AnyShapeStyle { AnyShapeStyle(.thinMaterial) }
    public var paneBackground: AnyShapeStyle { AnyShapeStyle(.background) }

    public var rowSelected: Color { Color.accentColor.opacity(0.18) }
    public var rowHover: Color { Color.primary.opacity(0.04) }
    public var separator: Color { Color.primary.opacity(0.08) }

    public var primaryText: Color { .primary }
    public var secondaryText: Color { .secondary }
    public var accent: Color { .accentColor }

    public let rowHeight: CGFloat = 24
    public let cornerRadius: CGFloat = 6
    public let bodyFontSize: CGFloat = 13
    public let captionFontSize: CGFloat = 11
}
