import SwiftUI
import AppearanceKit

/// 玻璃质感背景辅助：材质打底 + 主题染色盖在材质之上（ZStack 前层）。
///
/// 注意 SwiftUI 的 `.background(A).background(B)` 顺序是反直觉的：
/// B 垫在 A 底下——染色会被材质模糊掉（主题发白的根因）。
/// 用 ZStack { 材质; 染色 } 让染色在材质之上、内容之下，
/// 主题色真实呈现，材质只在染色未覆盖的透明度里微微透光。
/// （AnyShapeStyle 不是 View，要用 Rectangle().fill() 包一层才能进 ZStack。）
extension View {
    /// 镀铬层（侧栏 / 标签栏 / 工具栏 / 路径栏 / 状态栏）。
    func glassChrome(_ theme: any AppearanceTheme) -> some View {
        background(ZStack {
            Rectangle().fill(theme.sidebarBackground)
            Rectangle().fill(theme.chromeTint)
        })
    }

    /// 表格区。
    func glassPane(_ theme: any AppearanceTheme) -> some View {
        background(ZStack {
            Rectangle().fill(theme.paneBackground)
            Rectangle().fill(theme.paneTint)
        })
    }
}
