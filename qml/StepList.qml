import QtQuick
import ptest

// 线性步骤条。渐进披露:工人只需盯当前那一步,已完成的收成小圆点。
Column {
    property var steps: []
    spacing: 0

    Repeater {
        model: steps

        Item {
            required property int index
            required property var modelData

            width: parent.width
            height: 34

            readonly property int st: modelData.state
            readonly property bool active: st === 1

            // 连接线
            Rectangle {
                width: 2
                color: st === 2 ? Theme.pass : Theme.border
                x: 8
                y: 17
                height: index === steps.length - 1 ? 0 : 34
                opacity: 0.5
            }

            Rectangle {
                id: dot
                width: active ? 18 : 14
                height: width
                radius: width / 2
                x: 9 - width / 2
                y: 17 - width / 2
                color: st === 2 ? Theme.pass : (active ? Theme.running : "transparent")
                border.width: st === 2 ? 0 : 2
                border.color: active ? Theme.running : Theme.border

                Behavior on width { NumberAnimation { duration: Theme.durMed; easing.type: Easing.OutBack } }

                Text {
                    visible: st === 2
                    text: "✓"
                    color: Theme.bg
                    font.pointSize: TypeScale.caption
                    font.weight: TypeScale.weightBold
                    anchors.centerIn: parent
                }

                SequentialAnimation on scale {
                    running: active
                    loops: Animation.Infinite
                    NumberAnimation { to: 1.15; duration: 620; easing.type: Easing.InOutQuad }
                    NumberAnimation { to: 1.0;  duration: 620; easing.type: Easing.InOutQuad }
                }
            }

            Text {
                text: modelData.name
                color: active ? Theme.textPrimary
                       : (st === 2 ? Theme.textSecondary : Theme.textDim)
                font.family: TypeScale.family
                font.pointSize: TypeScale.body
                font.weight: active ? TypeScale.weightBold : TypeScale.weightRegular
                anchors.left: parent.left
                anchors.leftMargin: 30
                anchors.verticalCenter: dot.verticalCenter
            }
        }
    }
}
