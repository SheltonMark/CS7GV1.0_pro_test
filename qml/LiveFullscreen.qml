import QtQuick
import ptest
import QtQuick.Controls

// 拉流全屏层。覆盖整个窗口（含侧边栏），Esc 或双击退出。
//
// 放在 Main 顶层而不是各页面内部：全屏必须盖住导航栏，
// 页面内部的层级盖不住。各页面通过 Main 的 liveFull.open(标题, 预览项) 唤起。
//
// 画面来源 = 把页面里正在播的那个 LivePreview 整体重挂(reparent)进来，
// 关闭时挂回原位 —— 不是开第二路拉流。同一路 RTSP 会话、同一个解码器，
// 全屏与小窗零延迟同步，LIVE 徽标/建联提示/诊断信息原样跟随。
// （此前这里放的是独立 LivePreview 实例，sourceUrl 没接 —— 全屏永远黑屏。）
Item {
    id: root
    anchors.fill: parent
    visible: opacity > 0
    opacity: 0
    z: 900        // 在页面之上、确认弹窗(ConfirmDialog)之下

    property string caption: ""

    // 被托管的预览项及其原父项（关闭时挂回去）。
    // 预览项自身写 anchors.fill: parent —— 挂进来自动铺满,挂回去自动填槽位。
    property Item hosted: null
    property Item homeParent: null

    function open(text, item) {
        if (!item) return;
        if (hosted === item) {    // 全屏里再双击同一预览 = 退出
            close();
            return;
        }
        caption = text || "";
        hosted = item;
        homeParent = item.parent;
        item.parent = stage;
        item.fullscreenHosted = true;
        opacity = 1;
        hintShown = true;
        hintTimer.restart();
        focusScope.forceActiveFocus();
    }
    function close() {
        if (hosted) {
            hosted.fullscreenHosted = false;
            if (homeParent) hosted.parent = homeParent;
            hosted = null;
            homeParent = null;
        }
        opacity = 0;
    }

    Behavior on opacity { NumberAnimation { duration: Theme.durSlow } }

    // 挡住底层的鼠标事件，否则全屏时还能点到下面的按钮。
    // 双击退出主要由托管预览自己的双击处理（fullscreenRequested →
    // open() 判定同项 → close），这层只兜预览没盖到的边缘。
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

        // 托管容器：open() 把页面预览挂到这里
        Item {
            id: stage
            anchors.fill: parent
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
