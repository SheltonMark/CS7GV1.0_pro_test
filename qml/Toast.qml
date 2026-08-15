import QtQuick
import ptest

// 轻量结果反馈。写标识这类"一次性、不可撤销"的动作必须有明确回执 ——
// 工人点完按钮如果界面毫无变化，会怀疑没写上而重复点。
//
// 为什么不用弹窗：弹窗要再点一次"确定"才能继续，一条线上几百台机器
// 就是几百次多余点击。Toast 给了确认又不打断流程。
// 失败则停留更久（工人必须看到），并保留红色语义。
Rectangle {
    id: root

    property string message: ""
    property bool ok: true

    // 悬浮在页面底部中央
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Theme.s6
    z: 800

    width: row.implicitWidth + Theme.s5 * 2
    height: 46
    radius: 23
    color: root.ok ? Qt.rgba(0.133, 0.773, 0.369, 0.16)
                   : Qt.rgba(0.937, 0.267, 0.267, 0.16)
    border.width: 1
    border.color: root.ok ? Theme.pass : Theme.fail

    opacity: 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: Theme.durSlow } }

    // 轻微上浮，暗示"刚发生"
    transform: Translate { y: root.opacity > 0 ? 0 : 10 }

    function show(text, isOk) {
        message = text;
        ok = isOk === undefined ? true : isOk;
        opacity = 1;
        // 失败停 6 秒：工人得有时间读完并决定下一步
        hideTimer.interval = root.ok ? 2600 : 6000;
        hideTimer.restart();
    }

    Timer {
        id: hideTimer
        onTriggered: root.opacity = 0
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Theme.s3

        Icon {
            text: root.ok ? Icons.pass : Icons.fail
            size: 17
            color: root.ok ? Theme.pass : Theme.fail
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            text: root.message
            color: Theme.textPrimary
            font.family: TypeScale.family
            font.pointSize: TypeScale.body
            font.weight: TypeScale.weightMedium
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    // 点一下就收起，不想等的工人可以手动关
    MouseArea {
        anchors.fill: parent
        onClicked: root.opacity = 0
    }
}
