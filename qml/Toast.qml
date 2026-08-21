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
    // ⚠️ 必须不透底。曾用 16% 透明色当底:悬浮位置正压着底部的
    // "流程失败: …"红字,两层文字透叠完全读不清(实测)。
    // 做法同逐项测试的结果气泡:实底 + 低透明度色调罩。
    color: Theme.bgDeep
    border.width: 1
    border.color: root.ok ? Theme.pass : Theme.fail

    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        color: root.ok ? Qt.rgba(0.133, 0.773, 0.369, 0.16)
                       : Qt.rgba(0.937, 0.267, 0.267, 0.16)
    }

    opacity: 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: Theme.durSlow } }

    // 轻微上浮，暗示"刚发生"
    transform: Translate { y: root.opacity > 0 ? 0 : 10 }

    // 本条领到的令牌。被别的 Toast 顶替（token 变大）就自己隐藏 —— 见 ToastBus。
    property int myToken: 0

    // ms 可选：不给就用默认节奏（成功 2.6s；失败 6s —— 工人得有时间读完并决定
    // 下一步）。给了就按指定时长，用于"只是告知一下"的短提示（如起播时闪一下
    // RTSP 地址）。
    function show(text, isOk, ms) {
        message = text;
        ok = isOk === undefined ? true : isOk;
        ToastBus.token = ToastBus.token + 1;
        myToken = ToastBus.token;
        opacity = 1;
        hideTimer.interval = ms !== undefined && ms > 0
                             ? ms
                             : (root.ok ? 2600 : 6000);
        hideTimer.restart();
    }

    // 有别的 Toast 后发先至就让位。用 Connections 而不是绑定 opacity ——
    // opacity 同时被 visible 与 Behavior 引用，直接绑会成绑定环。
    Connections {
        target: ToastBus
        function onTokenChanged() {
            if (root.opacity > 0 && ToastBus.token !== root.myToken) {
                hideTimer.stop();
                root.opacity = 0;
            }
        }
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
