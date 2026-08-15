import QtQuick
import ptest
import QtQuick.Controls
import QtQuick.Layouts

// 人工判定面板。解决一个正确性问题:
//
// 九项外设里有三项(指示灯/白光/喇叭)设备只回 `ok`,意思是
// "GPIO 拉高了 / 音频送进功放了" —— 灯泡烧了、白光 LED 虚焊、喇叭线没焊上,
// 设备照样回 ok,因为固件感知不到发光和出声。
// 直接把 Code=0 打成绿✓ = 把"指令下发成功"伪装成"硬件合格",
// 灯不亮的机器会一路绿灯走完产测。
//
// 所以:自动项(电池/4G/SD,设备回读数)由 PC 比阈值自动判;
// 人工项在自动流程跑完后集中确认,一屏勾完,工人点过才算通过。
//
// 集中确认(而非逐项弹窗)是刻意的:点击次数一样,但只打断一次,产线节拍更顺。
Card {
    id: panel

    title: "人工判定  ·  目视与听音"
    titleIcon: Icons.whiteLight
    fitContent: true

    // 判定结果:key → true(通过)/false(不通过)/undefined(未判)
    property var verdicts: ({})
    // 是否已具备判定条件(自动项跑完 + 拉流已建立)
    property bool ready: false

    signal allSettled()

    // 六条目视 + 一条听音。指示灯要测四个状态(红/蓝/双色闪烁),
    // 不是一行 —— 评审表 §1.3 逐条下发,判定也应逐条。
    readonly property var checks: [
        { key: "led_red",   group: "指示灯", label: "红灯常亮",        glyph: Icons.light },
        { key: "led_blue",  group: "指示灯", label: "蓝灯常亮",        glyph: Icons.light },
        { key: "led_blink", group: "指示灯", label: "双色闪烁 500ms",  glyph: Icons.light },
        // 无红外灯条目 —— CS7G 是全彩夜视,用白光补光,没有 IR 灯硬件。
        { key: "white",     group: "白光灯", label: "亮度 100 发光",   glyph: Icons.whiteLight },
        { key: "audio",     group: "喇叭 + 咪头", label: "放音后能听到，且对着设备说话也能听到",
          glyph: Icons.speaker, loopback: true }
    ]

    readonly property int settledCount: {
        var n = 0;
        for (var i = 0; i < checks.length; i++)
            if (verdicts[checks[i].key] !== undefined) n++;
        return n;
    }
    readonly property bool allDone: settledCount === checks.length
    readonly property bool anyFail: {
        for (var i = 0; i < checks.length; i++)
            if (verdicts[checks[i].key] === false) return true;
        return false;
    }

    function setVerdict(key, ok) {
        var v = {};
        for (var k in verdicts) v[k] = verdicts[k];
        v[key] = ok;
        verdicts = v;
        if (allDone) allSettled();
    }

    function reset() { verdicts = ({}) }

    ConfirmDialog { id: confirm }

    ColumnLayout {
        anchors { left: parent.left; right: parent.right; top: parent.top }
        spacing: Theme.s2

        Text {
            Layout.fillWidth: true
            text: panel.ready
                  ? "设备已按下列状态动作，逐条确认实际现象。设备回报「指令已执行」不代表硬件正常。"
                  : "自动项完成并拉流后开放判定。"
            color: panel.ready ? Theme.textSecondary : Theme.textDim
            font.family: TypeScale.family
            font.pointSize: TypeScale.body
            wrapMode: Text.WordWrap
        }

        Repeater {
            model: panel.checks

            RowLayout {
                required property var modelData
                readonly property var verdict: panel.verdicts[modelData.key]

                Layout.fillWidth: true
                spacing: Theme.s2
                enabled: panel.ready

                Rectangle {
                    width: 26; height: 26
                    radius: Theme.radius
                    color: verdict === undefined ? Qt.rgba(1, 1, 1, 0.04)
                           : verdict ? Qt.rgba(0.133, 0.773, 0.369, 0.13)
                                     : Qt.rgba(0.937, 0.267, 0.267, 0.13)
                    Behavior on color { ColorAnimation { duration: Theme.durFast } }

                    Icon {
                        anchors.centerIn: parent
                        text: modelData.glyph
                        size: 15
                        color: verdict === undefined ? Theme.textSecondary
                               : verdict ? Theme.pass : Theme.fail
                    }
                }

                ColumnLayout {
                    spacing: 1
                    Layout.fillWidth: true

                    Text {
                        text: modelData.group
                        color: Theme.textPrimary
                        font.family: TypeScale.family
                        font.pointSize: TypeScale.body
                        font.weight: TypeScale.weightMedium
                    }
                    Text {
                        text: modelData.label
                        color: Theme.textSecondary
                        font.family: TypeScale.family
                        font.pointSize: TypeScale.caption
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }

                // 喇叭+咪头一步双验(P10-③):放音听到 = 喇叭✓+咪头✓+音频链路✓
                AppButton {
                    visible: modelData.loopback === true
                    text: "放音"
                    glyph: Icons.speaker
                    implicitHeight: Theme.hit - 8
                    onClicked: { /* 真实实现:Item=7 Op=4 放音 */ }
                }

                AppButton {
                    text: "正常"
                    glyph: Icons.pass
                    kind: verdict === true ? "primary" : "normal"
                    implicitHeight: Theme.hit - 8
                    onClicked: panel.setVerdict(modelData.key, true)
                }

                AppButton {
                    text: "异常"
                    glyph: Icons.fail
                    kind: verdict === false ? "danger" : "normal"
                    implicitHeight: Theme.hit - 8
                    // 判不良是终局结论,要确认
                    onClicked: confirm.ask("判定异常？",
                        modelData.group + "（" + modelData.label + "）将记为不通过，设备转维修。",
                        function () { panel.setVerdict(modelData.key, false) })
                }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderSoft }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.s3

            Text {
                text: "已判定 " + panel.settledCount + " / " + panel.checks.length
                color: panel.allDone ? (panel.anyFail ? Theme.fail : Theme.pass)
                                     : Theme.textSecondary
                font.family: TypeScale.family
                font.pointSize: TypeScale.body
                font.weight: TypeScale.weightMedium
            }

            Item { Layout.fillWidth: true }

            AppButton {
                text: "全部重判"
                glyph: Icons.reset
                implicitHeight: Theme.hit - 8
                visible: panel.settledCount > 0
                onClicked: panel.reset()
            }
        }
    }
}
