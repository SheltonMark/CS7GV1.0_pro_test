import QtQuick
import ptest

// 图标 = Windows 自带图标字体，不引第三方图标库、不打包 svg。
//
// ⚠️ 字体名必须运行时探测(见 Icons.fontFamily)，不能写死。
//    "Segoe Fluent Icons" 是 Win11 才有的，Win10 只有 "Segoe MDL2 Assets"。
//    写死 Fluent 时 Win10 不会自动退到 MDL2，而是落到默认正文字体 ——
//    那里 E0xx-EAxx 码位没有字形，图标整体消失。
//    (QML font 类型没有 families 回退链，赋 font.families 直接组件加载失败。)
//    实测教训:Win11 上开发看着好，同事 Win10 上图标全没了。
//
// 用到的 38 个码位已用 GlyphTypeface 逐个校验，两种字体里都存在，
// 所以回退到 MDL2 后 Win10 显示一致。
Text {
    // 用 Icons.xxx 里的常量，别直写码位
    property int size: 18

    font.family: Icons.fontFamily
    font.pointSize: size * 0.75
    color: Theme.textSecondary
    renderType: Text.NativeRendering
    verticalAlignment: Text.AlignVCenter
    horizontalAlignment: Text.AlignHCenter
}
