import QtQuick
import ptest
import QtQuick.Controls
import QtQuick.Layouts

// 关于。产线出问题时工人要能在 10 秒内找到"该找谁"，所以联系人比版本号更靠前。
Item {
    id: root

    // 一键跳企业微信。wxwork:// 协议已注册(实测)，但"直接打开某人会话"
    // 没有稳定的公开 deep-link 格式，各版本行为不一致。
    // 所以：跳转是尽力而为，工号始终摆在旁边可复制 —— 兜底路径必须永远可用。
    function openWeCom(id) {
        Qt.openUrlExternally("wxwork://message?username=" + id);
    }

    ScrollView {
        anchors.fill: parent
        contentWidth: availableWidth
        clip: true

        ColumnLayout {
            width: root.width
            spacing: Theme.s4

            Item { Layout.preferredHeight: Theme.s2 }

            // ---- 品牌头 ----
            Card {
                fitContent: true
                Layout.fillWidth: true
                Layout.leftMargin: Theme.s5
                Layout.rightMargin: Theme.s5
                pad: Theme.s6

                ColumnLayout {
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    spacing: Theme.s4

                    Image {
                        source: "logo.png"
                        sourceSize.height: 38
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                    }

                    Text {
                        text: "产测工具"
                        color: Theme.textPrimary
                        font.family: TypeScale.family
                        font.pointSize: TypeScale.display
                        font.weight: TypeScale.weightBold
                    }

                    Text {
                        Layout.fillWidth: true
                        text: "低功耗电池 IPC 产线产测软件。覆盖调焦、准成品、成品三个工位，"
                            + "以及维修工位的信息存档与分区清除。"
                        color: Theme.textSecondary
                        font.family: TypeScale.family
                        font.pointSize: TypeScale.body
                        wrapMode: Text.WordWrap
                    }
                }
            }

            // ---- 版本 ----
            Card {
                title: "版本"
                fitContent: true
                Layout.fillWidth: true
                Layout.leftMargin: Theme.s5
                Layout.rightMargin: Theme.s5

                GridLayout {
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    columns: 2
                    columnSpacing: Theme.s7
                    rowSpacing: Theme.s3

                    FieldRow {
                        Layout.fillWidth: true
                        label: "工具版本"
                        value: typeof appVersion !== "undefined" ? "v" + appVersion : "dev"
                        valueColor: Theme.brand
                    }
                    FieldRow {
                        Layout.fillWidth: true
                        label: "构建日期"
                        value: typeof buildDate !== "undefined" ? buildDate : "—"
                    }
                    FieldRow {
                        Layout.fillWidth: true
                        label: "Qt 版本"
                        value: typeof qtVersion !== "undefined" ? qtVersion : "—"
                    }
                    FieldRow {
                        Layout.fillWidth: true
                        label: "构建类型"
                        value: typeof buildType !== "undefined" ? buildType : "—"
                    }
                }
            }

            // ---- 负责人 ----
            Card {
                title: "找谁"
                fitContent: true
                Layout.fillWidth: true
                Layout.leftMargin: Theme.s5
                Layout.rightMargin: Theme.s5

                ColumnLayout {
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    spacing: Theme.s3

                    Repeater {
                        model: MockData.owners

                        RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: Theme.s3

                            Rectangle {
                                width: 38; height: 38; radius: 19
                                color: Theme.brandWash
                                border.width: 1
                                border.color: Theme.brandEdge
                                Icon {
                                    anchors.centerIn: parent
                                    text: Icons.person
                                    size: 17
                                    color: Theme.brand
                                }
                            }

                            ColumnLayout {
                                spacing: 1
                                Text {
                                    text: modelData.name
                                    color: Theme.textPrimary
                                    font.family: TypeScale.family
                                    font.pointSize: TypeScale.body
                                    font.weight: TypeScale.weightBold
                                }
                                Text {
                                    text: modelData.role + "   ·   " + modelData.wecom
                                    color: Theme.textSecondary
                                    font.family: TypeScale.family
                                    font.pointSize: TypeScale.caption
                                }
                            }

                            Item { Layout.fillWidth: true }

                            Button {
                                implicitHeight: Theme.hit - 6
                                onClicked: root.openWeCom(modelData.wecom)
                                contentItem: RowLayout {
                                    spacing: Theme.s2
                                    Icon {
                                        text: Icons.chat
                                        size: 14
                                        color: Theme.textPrimary
                                    }
                                    Text {
                                        text: "企业微信"
                                        color: Theme.textPrimary
                                        font.family: TypeScale.family
                                        font.pointSize: TypeScale.body
                                    }
                                }
                            }

                            Button {
                                implicitHeight: Theme.hit - 6
                                implicitWidth: Theme.hit - 6
                                ToolTip.visible: hovered
                                ToolTip.text: "复制工号"
                                onClicked: {
                                    clip.text = modelData.wecom;
                                    clip.selectAll();
                                    clip.copy();
                                    copied.owner = modelData.wecom;
                                }
                                contentItem: Icon {
                                    text: Icons.copy
                                    size: 14
                                    color: Theme.textSecondary
                                }
                            }
                        }
                    }

                    Text {
                        id: copied
                        property string owner: ""
                        visible: owner.length > 0
                        text: "已复制 " + owner
                        color: Theme.pass
                        font.family: TypeScale.family
                        font.pointSize: TypeScale.caption
                        onOwnerChanged: if (owner.length > 0) clearTimer.restart()
                        Timer {
                            id: clearTimer
                            interval: 2200
                            onTriggered: copied.owner = ""
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: "跳转依赖本机已登录企业微信。若没反应，用右侧按钮复制工号手动搜索。"
                        color: Theme.textDim
                        font.family: TypeScale.family
                        font.pointSize: TypeScale.caption
                        wrapMode: Text.WordWrap
                    }
                }
            }

            Item { Layout.preferredHeight: Theme.s5 }
        }
    }

    // 复制用的隐藏文本框。QML 没有直接的剪贴板 API，
    // 标准做法是借 TextEdit 的 copy()。
    TextEdit {
        id: clip
        visible: false
    }
}
