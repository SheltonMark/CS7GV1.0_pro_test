pragma Singleton
import QtQuick

// 模块化字号阶:base 11pt,比例 ~1.333(Perfect Fourth,强对比,适合仪表类)。
// 用 pointSize 而非 pixelSize —— 尊重系统 DPI 缩放。
// 单屏最多用 3-4 个阶,超过就是视觉噪音。
QtObject {
    readonly property int caption: 8    // 元数据/单位
    readonly property int body:    11   // 正文 base
    readonly property int heading: 15   // 区块标题
    readonly property int title:   20   // 页标题
    readonly property int display: 26   // 关键读数
    readonly property int hero:    35   // 设备 SN
    readonly property int giant:   46   // PASS / FAIL,一米可辨

    readonly property string family: "Segoe UI Variable"

    readonly property int weightRegular: Font.Normal
    readonly property int weightMedium:  Font.Medium
    readonly property int weightBold:    Font.DemiBold
}
