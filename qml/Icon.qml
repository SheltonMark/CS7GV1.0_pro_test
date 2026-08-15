import QtQuick
import ptest

// 图标 = Windows 自带的 Segoe Fluent Icons 字体(约 1000 个字形)。
// 不引第三方图标库、不打包 svg —— 少一个依赖，且矢量、跟随 DPI。
// Win10 上该字体不存在，自动退回 Segoe MDL2 Assets(码位基本兼容)。
Text {
    // 用 Icons.xxx 里的常量，别直写码位
    property int size: 18

    font.family: "Segoe Fluent Icons"
    font.pointSize: size * 0.75
    color: Theme.textSecondary
    renderType: Text.NativeRendering
    verticalAlignment: Text.AlignVCenter
    horizontalAlignment: Text.AlignHCenter
}
