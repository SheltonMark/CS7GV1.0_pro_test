import QtQuick
import ptest
import QtQuick.Controls
import QtQuick.Layouts

// 调焦工位 —— 画面是主角,占最大面积。无尘室里工人边转镜头边看这一屏。
Item {
    ConfirmDialog { id: confirm }

    RowLayout {
        anchors.fill: parent
        anchors.margins: Theme.s5
        spacing: Theme.s4

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.s4

            // 预览区。真实实现里这里换成 VideoOutput。
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "#0B0D10"
                radius: Theme.radiusLg
                border.width: 1
                border.color: Theme.border

                // 构图辅助线:三分法,帮工人对中
                Repeater {
                    model: 2
                    Rectangle {
                        required property int index
                        color: Qt.rgba(1, 1, 1, 0.07)
                        width: 1
                        height: parent.height
                        x: parent.width * (index + 1) / 3
                    }
                }
                Repeater {
                    model: 2
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
                    spacing: Theme.s3

                    BusyIndicator {
                        running: true
                        implicitWidth: 44
                        implicitHeight: 44
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                    Text {
                        text: "XP2P 建联中…"
                        color: Theme.textSecondary
                        font.family: TypeScale.family
                        font.pointSize: TypeScale.body
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                    Text {
                        text: "demo 无真实码流"
                        color: Theme.textDim
                        font.family: TypeScale.family
                        font.pointSize: TypeScale.caption
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }

                // 左上角实时标记
                Row {
                    anchors { left: parent.left; top: parent.top; margins: Theme.s4 }
                    anchors.leftMargin: Theme.s4
                    anchors.topMargin: Theme.s4
                    spacing: Theme.s2

                    Rectangle {
                        width: 8; height: 8; radius: 4
                        color: Theme.fail
                        anchors.verticalCenter: parent.verticalCenter
                        SequentialAnimation on opacity {
                            running: true; loops: Animation.Infinite
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
                    // 写设备状态 → 必须确认(误触=台账里多一条错误时间戳)
                    onClicked: confirm.ask("写入调焦标识？",
                        "将向设备写入调焦完成时间戳（Stage=1，只增不覆盖）。",
                        function () { /* 真实实现:下发 PtestWriteStage(1) */ })
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
                state_: "idle"
                caption: "等待画面确认"
            }

            Card {
                title: "咪头  ·  人工判定"
                titleIcon: Icons.mic
                fitContent: true
                Layout.fillWidth: true

                Column {
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    spacing: Theme.s3

                    Text {
                        width: parent.width
                        text: "对着设备说话，能从电脑听到声音即通过。"
                        color: Theme.textSecondary
                        font.family: TypeScale.family
                        font.pointSize: TypeScale.body
                        wrapMode: Text.WordWrap
                    }

                    Row {
                        spacing: Theme.s3
                        // 人工判定 → 确认(这一下就是咪头项的最终结论,误触即错判)
                        AppButton {
                            text: "听到了"; glyph: Icons.pass; kind: "primary"; width: 116
                            onClicked: confirm.ask("咪头判定：通过？",
                                "确认从电脑听到了设备咪头采集的声音，该项记为通过。",
                                function () { /* 真实实现:记录咪头=通过 */ })
                        }
                        AppButton {
                            text: "没听到"; glyph: Icons.fail; width: 116
                            onClicked: confirm.ask("咪头判定：不通过？",
                                "该项将记为失败，设备转维修排查咪头。",
                                function () { /* 真实实现:记录咪头=失败 */ })
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
