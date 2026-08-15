pragma Singleton
import QtQuick

// 产线深色主题 token。深色优先:工人一个班次盯 8 小时。
QtObject {
    // ---- 品牌 ----
    // 取自 logo.png 实测主色 #EC6C00。
    readonly property color brand:      "#EC6C00"
    readonly property color brandHover: "#FF7D14"
    readonly property color brandPress: "#C85B00"
    // 品牌色的低透明度垫底,用于选中态/焦点环
    readonly property color brandWash:  Qt.rgba(0.925, 0.424, 0, 0.14)
    readonly property color brandEdge:  Qt.rgba(0.925, 0.424, 0, 0.42)

    // ---- 背景层次:底 → 卡片 → 抬升 ----
    readonly property color bg:         "#14161A"
    readonly property color bgDeep:     "#0F1114"
    readonly property color surface:    "#1C1F26"
    readonly property color surfaceAlt: "#23272F"
    readonly property color border:     "#2C323C"
    readonly property color borderSoft: "#232830"

    // ---- 文字三级 ----
    readonly property color textPrimary:   "#F2F4F8"
    readonly property color textSecondary: "#98A2B3"
    readonly property color textDim:       "#5B6472"

    // 强调色 = 品牌橙。控件(按钮/复选框/滚动条)都跟这个走。
    readonly property color accent:     brand
    readonly property color accentDim:  brandEdge

    // ---- 状态色 ----
    // ⚠️ 强调色已是橙色,所以 warn 不能再用橙 —— 会和普通按钮撞色,
    // 工人分不清"这是警告"还是"这是可点的东西"。warn 改用明黄。
    readonly property color pass:    "#22C55E"
    readonly property color fail:    "#EF4444"
    readonly property color warn:    "#FACC15"
    readonly property color running: "#38BDF8"   // 执行中用蓝,与品牌橙区分
    readonly property color idle:    "#5B6472"

    // ---- 间距阶 ----
    readonly property int s1: 4
    readonly property int s2: 8
    readonly property int s3: 12
    readonly property int s4: 16
    readonly property int s5: 24
    readonly property int s6: 32
    readonly property int s7: 48

    readonly property int radius:    8
    readonly property int radiusLg:  12

    // ---- 动效预算(小 100-150 / 中 200-300 / 全屏 300-400,不超 500) ----
    readonly property int durFast: 120
    readonly property int durMed:  220
    readonly property int durSlow: 320

    // 产线可达性:工人站着操作,命中区不小于 44px
    readonly property int hit: 44

    // 测试项状态 → 颜色/文案。
    // state: 0 待测 1 执行中 2 通过 3 失败 4 设备不支持 5 profile要求但设备缺
    function itemStateColor(s) {
        switch (s) {
        case 1:  return running;
        case 2:  return pass;
        case 3:  return fail;
        case 4:  return idle;
        case 5:  return fail;
        default: return textDim;
        }
    }

    function itemStateText(s) {
        switch (s) {
        case 1:  return "执行中";
        case 2:  return "通过";
        case 3:  return "失败";
        case 4:  return "设备不支持";
        case 5:  return "缺能力";
        default: return "待测";
        }
    }
}
