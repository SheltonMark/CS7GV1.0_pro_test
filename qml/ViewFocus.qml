import QtQuick
import ptest
import QtQuick.Controls
import QtQuick.Layouts

// 调焦工位 —— 画面是主角,占最大面积。无尘室里工人边转镜头边看这一屏。
Item {
    id: root

    // 画面人工判定:undefined 未判 / true 清晰 / false 不合格。
    // 写标识按钮以此为门 —— 没判过不许写(否则等于没测就盖章)。
    property var imageOk: undefined

    ConfirmDialog { id: confirm }

    // 写调焦标识 + 结果回执。设备回包才算成功;写完把时间戳显示出来,
    // 工人能核对实际写进去的值,而不是只看一句"成功"。
    property string writtenStamp: ""

    function doWriteStage() { writeTimer.restart() }

    Timer {
        id: writeTimer
        interval: 700               // demo:模拟 PC→云端→设备 往返
        onTriggered: {
            var d = new Date();
            function p2(n) { return n < 10 ? "0" + n : "" + n; }
            root.writtenStamp = "" + d.getFullYear() + p2(d.getMonth() + 1)
                + p2(d.getDate()) + p2(d.getHours()) + p2(d.getMinutes())
                + p2(d.getSeconds());
            toast.show("调焦标识写入成功  " + root.writtenStamp, true);
        }
    }

    Toast { id: toast }

    RowLayout {
        anchors.fill: parent
        anchors.margins: Theme.s5
        spacing: Theme.s4

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.s4

            // 预览区。真实实现里 LivePreview 内部换成 VideoOutput。
            // 双击 → 全屏（Main 顶层的 liveFull 层，Esc 退出）。
            LivePreview {
                Layout.fillWidth: true
                Layout.fillHeight: true
                showGrid: true
                onFullscreenRequested: liveFull.open("调焦 · 实时画面")
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.s3

                AppButton {
                    text: "开始拉流"
                    glyph: Icons.play
                    kind: "primary"
                    Layout.preferredWidth: 158
                }
                AppButton {
                    text: "停止"
                    glyph: Icons.stop
                    Layout.preferredWidth: 118
                }

                Item { Layout.fillWidth: true }

                AppButton {
                    text: "调焦完成，写标识"
                    glyph: Icons.save
                    kind: "primary"
                    Layout.preferredWidth: 204
                    // 画面未判定或判为不合格 → 不许写标识
                    enabled: root.imageOk === true
                    // 写设备状态 → 必须确认(误触=台账里多一条错误时间戳)
                    onClicked: confirm.ask("写入调焦标识？",
                        "将向设备写入调焦完成时间戳（Stage=1，只增不覆盖）。",
                        function () { root.doWriteStage() })
                }
            }
        }

        // 右栏:极简 —— 调焦工位工人手在转镜头,不该被信息干扰
        ColumnLayout {
            Layout.preferredWidth: 300
            Layout.fillWidth: false
            Layout.fillHeight: true
            spacing: Theme.s4

            ResultBanner {
                Layout.fillWidth: true
                Layout.preferredHeight: 160
                state_: root.imageOk === undefined ? "idle"
                        : (root.imageOk ? "pass" : "fail")
                caption: root.imageOk === undefined ? "等待画面确认"
                         : (root.imageOk ? "画面清晰，可写标识" : "画面不合格，转返修")
            }

            // 调焦工位的核心判定就是"画面清不清晰",而这只能人工看。
            // 咪头判定已移到成品页与喇叭合并(一步双验) —— 咪头和喇叭同工位
            // 才能一个动作验完两项;且无尘室噪音大,声音判定不宜放这里。
            Card {
                title: "画面  ·  人工判定"
                titleIcon: Icons.navFocus
                fitContent: true
                Layout.fillWidth: true

                Column {
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    spacing: Theme.s3

                    Text {
                        width: parent.width
                        text: "转动镜头至画面最清晰，确认无偏色、无暗角、无异物后判定。"
                        color: Theme.textSecondary
                        font.family: TypeScale.family
                        font.pointSize: TypeScale.body
                        wrapMode: Text.WordWrap
                    }

                    Row {
                        spacing: Theme.s3
                        // 人工判定 = 终局结论,两个方向都要确认
                        AppButton {
                            text: "清晰"
                            glyph: Icons.pass
                            kind: root.imageOk === true ? "primary" : "normal"
                            width: 116
                            onClicked: confirm.ask("画面判定：清晰？",
                                "确认画面已调至最清晰，该工位可写调焦标识。",
                                function () { root.imageOk = true })
                        }
                        AppButton {
                            text: "不合格"
                            glyph: Icons.fail
                            kind: root.imageOk === false ? "danger" : "normal"
                            width: 116
                            onClicked: confirm.ask("画面判定：不合格？",
                                "该设备记为调焦不合格并转返修。",
                                function () { root.imageOk = false })
                        }
                    }
                }
            }

            Card {
                title: "工位流程"
                titleIcon: Icons.navFocus
                Layout.fillWidth: true
                Layout.fillHeight: true

                StepList {
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    steps: [
                        { name: "设备上云建连", state: 2 },
                        { name: "时间同步",     state: 2 },
                        { name: "读产测信息",   state: 2 },
                        { name: "拉流调焦",     state: 1 },
                        { name: "写调焦标识",   state: 0 },
                        { name: "停止拉流",     state: 0 }
                    ]
                }
            }
        }
    }
}
