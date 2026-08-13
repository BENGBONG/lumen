import SwiftUI
import AppearanceKit

/// 玻璃质感背景辅助，三层叠放（后→前）：
///   1. 不透明底色（挡住桌面壁纸——材质太透时浅壁纸会渗上来形成脏色块）
///   2. 材质（磨砂纹理）
///   3. 主题染色（决定色调）
///
/// 两个已踩过的坑：
/// - `.background(A).background(B)` 的 B 垫在 A 底下，别用它做叠层；
/// - AnyShapeStyle 不是 View，进 ZStack 要包 Rectangle().fill()。
extension View {
    /// 镀铬层（侧栏 / 标签栏 / 工具栏 / 路径栏 / 状态栏）。
    func glassChrome(_ theme: any AppearanceTheme) -> some View {
        background(ZStack {
            Rectangle().fill(theme.chromeBase)
            Rectangle().fill(theme.sidebarBackground)
            Rectangle().fill(theme.chromeTint)
        })
    }

    /// 表格区。
    func glassPane(_ theme: any AppearanceTheme) -> some View {
        background(ZStack {
            Rectangle().fill(theme.paneBase)
            Rectangle().fill(theme.paneBackground)
            Rectangle().fill(theme.paneTint)
        })
    }
}
