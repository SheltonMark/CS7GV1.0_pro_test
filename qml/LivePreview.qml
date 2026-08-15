import QtQuick
import ptest
import QtQuick.Controls

// 拉流预览区。真实实现里中间换成 VideoOutput。
//
// 三处复用：调焦页（大窗，构图三分线辅助对中）、准成品/成品页（小窗，
// 只为确认"这台机器的画面确实出来了"）。抽成组件是因为三处的 LIVE 标记、
// 建联中提示、双击全屏行为必须一致 —— 工人换工位时不该重新学一遍。
//
// 双击放大全屏、Esc 退出：产线工位屏常是 1080p 甚至更低，
// 小窗里看不清暗角和脏点，判画面时需要放到满屏。
Rectangle {
    id: root

    property bool showGrid: true       // 三分构图线（调焦要，其它工位不需要）
    property bool compact: false       // 小窗模式：缩小提示文字
    property string hint: "demo 无真实码流"
    // 悬停时的"双击全屏"角标。功能保留，只是不显示提示 ——
    // 准成品/成品工位的小窗上这行字挤在画面里，反而干扰看图。
    property bool showZoomHint: true

    signal fullscreenRequested()

    color: "#0B0D10"
    radius: Theme.radiusLg
    border.width: 1
    border.color: Theme.border
    clip: true

    // 三分法构图辅助线，帮工人把画面对中
    Repeater {
        model: root.showGrid ? 2 : 0
        Rectangle {
            required property int index
            color: Qt.rgba(1, 1, 1, 0.07)
            width: 1
            height: parent.height
            x: parent.width * (index + 1) / 3
        }
    }
    Repeater {
        model: root.showGrid ? 2 : 0
        Rectangle {
            required property int index
            color: Qt.rgba(1, 1, 1, 0.07)
            height: 1
            width: parent.width
            y: parent.height * (index + 1) / 3
        }
    }

    Column {
        anchors.centerIn: parent
        spacing: root.compact ? Theme.s2 : Theme.s3

        BusyIndicator {
            running: root.visible
            implicitWidth: root.compact ? 28 : 44
            implicitHeight: root.compact ? 28 : 44
            anchors.horizontalCenter: parent.horizontalCenter
        }
        Text {
            text: "XP2P 建联中…"
            color: Theme.textSecondary
            font.family: TypeScale.family
            font.pointSize: root.compact ? TypeScale.caption : TypeScale.body
            anchors.horizontalCenter: parent.horizontalCenter
        }
        Text {
            text: root.hint
            visible: root.hint.length > 0
            color: Theme.textDim
            font.family: TypeScale.family
            font.pointSize: TypeScale.caption
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }

    // 左上角实时标记
    Row {
        anchors { left: parent.left; top: parent.top }
        anchors.leftMargin: root.compact ? Theme.s3 : Theme.s4
        anchors.topMargin: root.compact ? Theme.s3 : Theme.s4
        spacing: Theme.s2

        Rectangle {
            width: 8; height: 8; radius: 4
            color: Theme.fail
            anchors.verticalCenter: parent.verticalCenter
            SequentialAnimation on opacity {
                running: root.visible; loops: Animation.Infinite
                NumberAnimation { to: 0.2; duration: 800 }
                NumberAnimation { to: 1.0; duration: 800 }
            }
        }
        Text {
            text: "LIVE"
            color: Theme.textPrimary
            font.family: TypeScale.family
            font.pointSize: TypeScale.caption
            font.weight: TypeScale.weightBold
            font.letterSpacing: 1.5
        }
    }

    // 双击全屏。用 MouseArea 而不是 TapHandler ——
    // TapHandler 的 onDoubleTapped 要求两次 tap 落在同一位置且有手势识别延迟，
    // 在小窗里工人手抖一两个像素就判成两次单击，实测不触发。
    // MouseArea.onDoubleClicked 走系统双击语义，可靠得多。
    MouseArea {
        id: hov
        anchors.fill: parent
        hoverEnabled: true
        onDoubleClicked: root.fullscreenRequested()
    }

    Text {
        anchors { right: parent.right; bottom: parent.bottom; margins: Theme.s3 }
        anchors.rightMargin: Theme.s3
        anchors.bottomMargin: Theme.s3
        visible: hov.containsMouse && root.showZoomHint
        text: "双击全屏"
        color: Theme.textDim
        font.family: TypeScale.family
        font.pointSize: TypeScale.caption
        Behavior on visible { NumberAnimation { duration: Theme.durFast } }
    }
}
