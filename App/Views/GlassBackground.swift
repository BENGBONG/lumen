import SwiftUI
import AppearanceKit

/// 主题背景辅助，两层叠放：不透明底色 + 主题染色。
///
/// 为什么不用 SwiftUI Material（玻璃材质）：
/// Material 在真机上走 WindowServer 的「窗口后混合」——它会直接采样
/// 桌面壁纸并**覆盖**同窗口内它下面的所有层（包括垫的底色）。
/// ultraThinMaterial 尤其透，浅色壁纸会渗上来形成脏色块（2026-08-13
/// 深色模式翻车事件）。底色挡不住它，因为它不是普通合成。
/// 真要玻璃感，得用 NSVisualEffectView 且 blendingMode = .withinWindow——
/// 那是另一个工程，先保证颜色正确。
extension View {
    /// 镀铬层（侧栏 / 标签栏 / 工具栏 / 路径栏 / 状态栏）。
    func glassChrome(_ theme: any AppearanceTheme) -> some View {
        background(ZStack {
            Rectangle().fill(theme.chromeBase)
            Rectangle().fill(theme.chromeTint)
        })
    }

    /// 表格区。
    func glassPane(_ theme: any AppearanceTheme) -> some View {
        background(ZStack {
            Rectangle().fill(theme.paneBase)
            Rectangle().fill(theme.paneTint)
        })
    }
}
