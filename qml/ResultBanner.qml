import QtQuick
import ptest

// 全屏唯一视觉爆点(von Restorff)。一米外一眼可辨 —— 工人手上忙,不会凑近读小字。
// Peak-End:工位的最后一眼就是这里,必须毫不含糊。
Rectangle {
    // "idle" | "running" | "pass" | "fail"
    property string state_: "running"
    property string caption: ""

    readonly property color tone: {
        switch (state_) {
        case "pass": return Theme.pass;
        case "fail": return Theme.fail;
        case "running": return Theme.running;
        default: return Theme.idle;
        }
    }

    radius: Theme.radiusLg
    color: Qt.rgba(tone.r, tone.g, tone.b, state_ === "idle" ? 0.06 : 0.14)
    border.width: 2
    border.color: state_ === "idle" ? Theme.border : tone

    Behavior on color { ColorAnimation { duration: Theme.durMed } }
    Behavior on border.color { ColorAnimation { duration: Theme.durMed } }

    Column {
        anchors.centerIn: parent
        spacing: Theme.s2

        Text {
            text: {
                switch (state_) {
                case "pass": return "PASS";
                case "fail": return "FAIL";
                case "running": return "测试中";
                default: return "待开始";
                }
            }
            color: tone
            font.family: TypeScale.family
            font.pointSize: state_ === "running" || state_ === "idle"
                            ? TypeScale.display : TypeScale.giant
            font.weight: TypeScale.weightBold
            font.letterSpacing: state_ === "pass" || state_ === "fail" ? 4 : 0
            anchors.horizontalCenter: parent.horizontalCenter

            // 执行中做低幅呼吸,让工人确信系统没卡死(Doherty)。
            // 只动 opacity —— GPU 合成,不触发布局。
            SequentialAnimation on opacity {
                running: state_ === "running"
                loops: Animation.Infinite
                NumberAnimation { to: 0.45; duration: 700; easing.type: Easing.InOutQuad }
                NumberAnimation { to: 1.0;  duration: 700; easing.type: Easing.InOutQuad }
            }
        }

        Text {
            visible: caption.length > 0
            text: caption
            color: Theme.textSecondary
            font.family: TypeScale.family
            font.pointSize: TypeScale.body
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }
}
