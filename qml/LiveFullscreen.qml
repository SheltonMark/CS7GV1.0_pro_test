import QtQuick
import ptest
import QtQuick.Controls

// 拉流全屏层。覆盖整个窗口（含侧边栏），Esc 或双击退出。
//
// 放在 Main 顶层而不是各页面内部：全屏必须盖住导航栏，
// 页面内部的层级盖不住。各页面通过 Main 的 liveFull.open() 唤起。
Item {
    id: root
    anchors.fill: parent
    visible: opacity > 0
    opacity: 0
    z: 900        // 在页面之上、确认弹窗(ConfirmDialog)之下

    property string caption: ""

    function open(text) {
        caption = text || "";
        opacity = 1;
        hintShown = true;
        hintTimer.restart();
        focusScope.forceActiveFocus();
    }
    function close() { opacity = 0; }

    Behavior on opacity { NumberAnimation { duration: Theme.durSlow } }

    // 挡住底层的鼠标事件，否则全屏时还能点到下面的按钮
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        onDoubleClicked: root.close()
    }

    Rectangle {
        anchors.fill: parent
        color: "#05070A"
    }

    FocusScope {
        id: focusScope
        anchors.fill: parent

        Keys.onEscapePressed: root.close()

        LivePreview {
            anchors.fill: parent
            anchors.margins: 0
            radius: 0
            border.width: 0
            showGrid: true
            hint: "demo 无真实码流"
            onFullscreenRequested: root.close()   // 全屏里再双击 = 退出
        }
    }

    // 退出提示。只在进入后短暂出现（3 秒淡出）——
    // 全屏的要求是"除画面外不留其它元素"，但完全不提示工人会不知道怎么退。
    // 折中：告知一次就消失，之后画面是干净的。
    Rectangle {
        anchors { horizontalCenter: parent.horizontalCenter; top: parent.top }
        anchors.topMargin: Theme.s5
        width: hintText.implicitWidth + Theme.s5 * 2
        height: 34
        radius: 17
        color: Qt.rgba(0, 0, 0, 0.6)
        opacity: hintShown ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Theme.durSlow } }

        Text {
            id: hintText
            anchors.centerIn: parent
            text: (root.caption.length > 0 ? root.caption + "   ·   " : "")
                  + "Esc 或双击退出全屏"
            color: Theme.textSecondary
            font.family: TypeScale.family
            font.pointSize: TypeScale.caption
        }
    }

    property bool hintShown: false
    Timer {
        id: hintTimer
        interval: 3000
        onTriggered: root.hintShown = false
    }
}
