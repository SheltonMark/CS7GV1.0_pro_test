import QtQuick
import ptest
import QtQuick.Controls
import QtQuick.Layouts

// 维修工位 —— 唯一有不可逆操作的一屏,设计重心是"防手滑"。
// 清除会擦掉身份+SUID,所以:先存档、再二次确认、危险按钮不做主色。
Item {
    id: root
    property bool archived: false

    RowLayout {
        anchors.fill: parent
        anchors.margins: Theme.s5
        spacing: Theme.s4

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.s4

            Card {
                title: "第 1 步  ·  读产测信息并存档"
                titleIcon: Icons.save
                fitContent: true
                Layout.fillWidth: true

                ColumnLayout {
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    spacing: Theme.s3

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: Theme.s6
                        rowSpacing: Theme.s3

                        FieldRow { Layout.fillWidth: true; label: "SN";   value: MockData.sn }
                        FieldRow { Layout.fillWidth: true; label: "IMEI"; value: MockData.imei }
                        FieldRow { Layout.fillWidth: true; label: "UUID"; value: MockData.uuid }
                        FieldRow { Layout.fillWidth: true; label: "MAC";  value: MockData.mac }
                    }

                    Row {
                        spacing: Theme.s3
                        AppButton {
                            text: root.archived ? "已存档" : "读取并存档"
                            glyph: root.archived ? Icons.pass : Icons.save
                            kind: root.archived ? "normal" : "primary"
                            enabled: !root.archived
                            width: 168
                            onClicked: root.archived = true
                        }
                        Row {
                            visible: root.archived
                            spacing: Theme.s2
                            anchors.verticalCenter: parent.verticalCenter
                            Icon {
                                text: Icons.pass
                                size: 14
                                color: Theme.pass
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: "已写入本地记录"
                                color: Theme.pass
                                font.family: TypeScale.family
                                font.pointSize: TypeScale.body
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                }
            }

            // 危险区:视觉上与正常流程隔开
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: dangerCol.implicitHeight + Theme.s5 * 2
                radius: Theme.radiusLg
                color: Qt.rgba(Theme.fail.r, Theme.fail.g, Theme.fail.b, 0.05)
                border.width: 1
                border.color: Qt.rgba(Theme.fail.r, Theme.fail.g, Theme.fail.b, 0.4)

                ColumnLayout {
                    id: dangerCol
                    anchors {
                        left: parent.left; right: parent.right; top: parent.top
                        margins: Theme.s5
                    }
                    spacing: Theme.s3

                    Text {
                        text: "第 2 步  ·  清除加密分区（不可逆）"
                        color: Theme.fail
                        font.family: TypeScale.family
                        font.pointSize: TypeScale.heading
                        font.weight: TypeScale.weightBold
                    }
                    Text {
                        Layout.fillWidth: true
                        text: "「全部」会清掉阶段标识、身份四元组与 SUID，设备回未测态，需重新完整产测并重新下发 InputData。请先完成上一步存档。"
                        color: Theme.textSecondary
                        font.family: TypeScale.family
                        font.pointSize: TypeScale.body
                        wrapMode: Text.WordWrap
                    }

                    RowLayout {
                        spacing: Theme.s4
                        RadioButton { text: "仅标识（保留身份）"; checked: true }
                        RadioButton { text: "全部" }
                    }

                    Row {
                        spacing: Theme.s3
                        AppButton {
                            text: "清除加密分区"
                            glyph: Icons.erase
                            kind: "danger"
                            enabled: root.archived
                            width: 176
                            onClicked: confirmDialog.open()
                        }
                        Text {
                            visible: !root.archived
                            text: "请先存档"
                            color: Theme.warn
                            font.family: TypeScale.family
                            font.pointSize: TypeScale.body
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }
            }

            Card {
                title: "第 3 步  ·  恢复默认并重启"
                titleIcon: Icons.reboot
                fitContent: true
                Layout.fillWidth: true

                Row {
                    anchors { left: parent.left; top: parent.top }
                    spacing: Theme.s3
                    AppButton { text: "恢复默认配置"; glyph: Icons.reset; width: 168 }
                    AppButton { text: "定时重启"; glyph: Icons.reboot; width: 146; enabled: false }
                    Text {
                        text: "重启须在恢复默认成功之后"
                        color: Theme.textDim
                        font.family: TypeScale.family
                        font.pointSize: TypeScale.caption
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            Item { Layout.fillHeight: true }
        }

        Card {
            title: "指令流水  ·  RequestId 关联"
            Layout.preferredWidth: 340
            Layout.fillHeight: true

            ListView {
                anchors.fill: parent
                clip: true
                spacing: Theme.s1
                model: MockData.log
                ScrollBar.vertical: ScrollBar {}

                delegate: Item {
                    required property var modelData
                    width: ListView.view.width
                    height: 46

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        spacing: 1

                        Row {
                            spacing: Theme.s2
                            Text {
                                text: "#" + modelData.rid
                                color: Theme.accent
                                font.family: "Consolas"
                                font.pointSize: TypeScale.caption
                            }
                            Text {
                                text: modelData.cmd
                                color: Theme.textPrimary
                                font.family: TypeScale.family
                                font.pointSize: TypeScale.caption
                                font.weight: TypeScale.weightMedium
                            }
                            Text {
                                text: modelData.item
                                color: Theme.textDim
                                font.family: TypeScale.family
                                font.pointSize: TypeScale.caption
                            }
                        }
                        Text {
                            text: modelData.detail
                            color: modelData.code === 0 ? Theme.pass
                                   : (modelData.code < 0 ? Theme.running : Theme.fail)
                            font.family: "Consolas"
                            font.pointSize: TypeScale.caption
                            elide: Text.ElideRight
                            width: parent.width
                        }
                    }
                }
            }
        }
    }

    Dialog {
        id: confirmDialog
        title: "确认清除加密分区？"
        modal: true
        anchors.centerIn: parent
        standardButtons: Dialog.Cancel | Dialog.Ok

        Text {
            text: "此操作不可逆。设备 " + MockData.sn + " 的身份信息将被清除。"
            color: Theme.textPrimary
            font.family: TypeScale.family
            font.pointSize: TypeScale.body
            wrapMode: Text.WordWrap
            width: 320
        }
    }
}
