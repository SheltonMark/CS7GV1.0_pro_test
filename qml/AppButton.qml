import QtQuick
import QtQuick.Controls
import ptest

// 按钮:背景和文字颜色全部显式指定，不依赖样式提供。
//
// ⚠️ 为什么不用裸 Button + highlighted:
//    裸 Button 的背景来自当前样式。若 FluentWinUI3 在某些机器上没加载成功
//    （或主题被解析成 Light），背景会变浅，而我们的文字是近白色 #F2F4F8 ——
//    结果是白底白字，按钮完全看不见。
//    实测教训:开发机 Win11 深色模式一切正常，同事 Win10 上"跳过当前项"
//    是白底白字。产线工具不能靠"样式恰好加载成功"来保证可读。
//
// 三种形态:
//   primary  品牌橙实底，一屏最多一个（主操作）
//   normal   深色实底 + 描边（次要操作）
//   danger   红色描边（不可逆操作，如清除分区）
Button {
    id: ctl

    // 不抢键盘焦点 —— 工位页是键盘流(空格/回车/回格驱动),按钮拿了焦点后
    // 空格会变成"再点一次按钮"而不是开始测试(2026-08-17 实测 bug)。
    // 本工具无 Tab 键盘导航需求,产线全是鼠标点按钮+快捷键组合。
    focusPolicy: Qt.NoFocus

    property string kind: "normal"   // primary | normal | danger
    // 不叫 icon —— Button 基类的 icon 是 FINAL 分组属性，同名声明直接组件加载失败
    property string glyph: ""

    readonly property color _base: kind === "primary" ? Theme.brand
                                : kind === "danger"  ? Qt.rgba(0.937, 0.267, 0.267, 0.12)
                                : Theme.surfaceAlt
    readonly property color _hover: kind === "primary" ? Theme.brandHover
                                 : kind === "danger"  ? Qt.rgba(0.937, 0.267, 0.267, 0.22)
                                 : "#2C323C"
    readonly property color _press: kind === "primary" ? Theme.brandPress
                                 : kind === "danger"  ? Qt.rgba(0.937, 0.267, 0.267, 0.30)
                                 : "#22262E"
    readonly property color _edge: kind === "primary" ? Qt.rgba(1, 1, 1, 0.16)
                                : kind === "danger"  ? Qt.rgba(0.937, 0.267, 0.267, 0.55)
                                : Theme.border
    // primary 用白字（橙底上对比最高）；danger 用红字；其余用主文字色
    readonly property color _fg: !enabled ? Theme.textDim
                              : kind === "primary" ? "#FFFFFF"
                              : kind === "danger"  ? Theme.fail
                              : Theme.textPrimary

    implicitHeight: Theme.hit
    // 命中区不小于 44px（工人站着操作），文字两侧留足内距
    implicitWidth: Math.max(Theme.hit, row.implicitWidth + Theme.s5 * 2)

    background: Rectangle {
        radius: Theme.radius
        color: !ctl.enabled ? Qt.rgba(1, 1, 1, 0.03)
               : ctl.pressed ? ctl._press
               : ctl.hovered ? ctl._hover
               : ctl._base
        border.width: 1
        border.color: ctl.enabled ? ctl._edge : Theme.borderSoft
        Behavior on color { ColorAnimation { duration: Theme.durFast } }
    }

    contentItem: Item {
        implicitWidth: row.implicitWidth
        implicitHeight: row.implicitHeight

        Row {
            id: row
            anchors.centerIn: parent
            spacing: Theme.s2

            Icon {
                visible: ctl.glyph.length > 0
                text: ctl.glyph
                size: 15
                color: ctl._fg
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: ctl.text
                color: ctl._fg
                font.family: TypeScale.family
                font.pointSize: TypeScale.body
                font.weight: ctl.kind === "primary" ? TypeScale.weightBold
                                                    : TypeScale.weightRegular
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
}
