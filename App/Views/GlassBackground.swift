import SwiftUI
import AppearanceKit

/// 玻璃质感背景辅助：材质层 + 主题染色叠层。
/// 原生主题为纯材质（tint 为 clear）；深色/明亮主题在材质上叠一层品牌色，
/// 既有磨砂透光感又保留主题色调。
extension View {
    /// 镀铬层（侧栏 / 标签栏 / 工具栏 / 路径栏 / 状态栏）。
    func glassChrome(_ theme: any AppearanceTheme) -> some View {
        background(theme.sidebarBackground).background(theme.chromeTint)
    }

    /// 表格区。
    func glassPane(_ theme: any AppearanceTheme) -> some View {
        background(theme.paneBackground).background(theme.paneTint)
    }
}
