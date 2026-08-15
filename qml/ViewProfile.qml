import QtQuick
import ptest
import QtQuick.Controls
import QtQuick.Layouts

// 产品配置 —— 多产品支持的落点。一份 profile = 一款产品。
// 勾选在这里定"本产品该测什么",运行时再与设备位图求交集。
Item {
    RowLayout {
        anchors.fill: parent
        anchors.margins: Theme.s5
        spacing: Theme.s4

        Card {
            title: "产品 profile"
            titleIcon: Icons.navProduct
            Layout.preferredWidth: 300
            Layout.fillHeight: true

            ColumnLayout {
                anchors { left: parent.left; right: parent.right; top: parent.top }
                spacing: Theme.s3

                Repeater {
                    model: [
                        { n: "CS7GV1.0", d: "低功耗电池 IPC", p: "5KHBENFCX2", cur: true },
                        { n: "CS6GV2.0", d: "低功耗电池 IPC", p: "（待建模）",  cur: false },
                        { n: "＋ 新增产品", d: "",            p: "",           cur: false }
                    ]

                    Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        height: 62
                        radius: Theme.radius
                        color: modelData.cur ? Theme.surfaceAlt : "transparent"
                        border.width: 1
                        border.color: modelData.cur ? Theme.accentDim : Theme.border

                        Column {
                            anchors {
                                left: parent.left; verticalCenter: parent.verticalCenter
                                leftMargin: Theme.s4
                            }
                            spacing: 2
                            Row {
                                spacing: Theme.s2
                                Text {
                                    text: modelData.n
                                    color: modelData.cur ? Theme.textPrimary : Theme.textSecondary
                                    font.family: TypeScale.family
                                    font.pointSize: TypeScale.body
                                    font.weight: TypeScale.weightBold
                                }
                                Text {
                                    text: modelData.d
                                    color: Theme.textDim
                                    font.family: TypeScale.family
                                    font.pointSize: TypeScale.caption
                                    anchors.baseline: parent.children[0].baseline
                                }
                            }
                            Text {
                                visible: modelData.p.length > 0
                                text: "ProductId  " + modelData.p
                                color: Theme.textDim
                                font.family: "Consolas"
                                font.pointSize: TypeScale.caption
                            }
                        }

                        Rectangle {
                            visible: modelData.cur
                            width: 3; radius: 2
                            color: Theme.accent
                            anchors {
                                left: parent.left; top: parent.top; bottom: parent.bottom
                                topMargin: Theme.s3; bottomMargin: Theme.s3
                            }
                        }
                    }
                }

                Item { Layout.fillHeight: true }
            }
        }

        Card {
            title: "本产品测试项  ·  勾选决定下发范围"
                titleIcon: Icons.navFinished
            Layout.fillWidth: true
            Layout.fillHeight: true

            ColumnLayout {
                anchors.fill: parent
                spacing: Theme.s3

                Text {
                    Layout.fillWidth: true
                    text: "勾选 = 本产品要测。实际下发 = 勾选 ∩ 设备上报的 SupportedItems。"
                        + "若勾了而设备未上报该能力，运行时会标红提示检查接线，而不是静默跳过。"
                    color: Theme.textSecondary
                    font.family: TypeScale.family
                    font.pointSize: TypeScale.body
                    wrapMode: Text.WordWrap
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 2
                    model: MockData.items
                    ScrollBar.vertical: ScrollBar {}

                    delegate: Rectangle {
                        required property var modelData
                        width: ListView.view.width
                        height: Theme.hit
                        radius: Theme.radius
                        color: hh.hovered ? Theme.surfaceAlt : "transparent"
                        HoverHandler { id: hh }
                        Behavior on color { ColorAnimation { duration: Theme.durFast } }

                        CheckBox {
                            id: cb
                            checked: modelData.state !== 4
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.s3
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        // 不显示 bit 序号 —— 那是内部实现细节,产线看项名就够。
                        // 位图整值仍在成品页顶部给出,诊断时够用。
                        Rectangle {
                            id: chip
                            width: 30; height: 30
                            radius: Theme.radius
                            color: Qt.rgba(1, 1, 1, 0.04)
                            anchors.left: cb.right
                            anchors.leftMargin: Theme.s2
                            anchors.verticalCenter: parent.verticalCenter
                            Icon {
                                anchors.centerIn: parent
                                text: Icons.forItem(modelData.item)
                                size: 15
                                color: (MockData.supportedItems & (1 << modelData.item))
                                       ? Theme.textSecondary : Theme.textDim
                            }
                        }

                        Text {
                            text: modelData.name
                            color: Theme.textPrimary
                            font.family: TypeScale.family
                            font.pointSize: TypeScale.body
                            anchors.left: chip.right
                            anchors.leftMargin: Theme.s3
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text: (MockData.supportedItems & (1 << modelData.item))
                                  ? "设备支持" : "设备未上报"
                            color: (MockData.supportedItems & (1 << modelData.item))
                                   ? Theme.pass : Theme.textDim
                            font.family: TypeScale.family
                            font.pointSize: TypeScale.caption
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.s4
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }
            }
        }
    }
}
