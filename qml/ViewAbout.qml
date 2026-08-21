import QtQuick
import ptest
import QtQuick.Controls
import QtQuick.Layouts

// 关于。产线出问题时工人要能在 10 秒内找到联系人，所以联系人排在版本号之前。
Item {
    id: root

    Toast { id: upgradeToast }

    // 一键跳企业微信。wxwork:// 协议已注册(实测)，但"直接打开某人会话"
    // 没有稳定的公开 deep-link 格式，各版本行为不一致。
    // 所以：跳转是尽力而为，工号始终摆在旁边可复制 —— 兜底路径必须永远可用。
    function openWeCom(id) {
        Qt.openUrlExternally("wxwork://message?username=" + id);
    }

    // 复制到剪贴板。QML 没有剪贴板 API，标准做法是借隐藏 TextEdit 的 copy()。
    // ⚠️ 隐藏 TextEdit 的 id 不能叫 "clip"：clip 是 Item 自带属性，Repeater
    //    委托里未限定的 "clip" 会先命中按钮自身的 clip(bool) 而非外层 id，
    //    selectAll() 抛 TypeError 且 WIN32 无控制台看不到报错，
    //    表现就是"点了没反应"。委托里只调这个函数，不直接摸 TextEdit。
    function copyText(t) {
        copyHelper.text = t;
        copyHelper.selectAll();
        copyHelper.copy();
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

            // ---- 当前产品(只读,规则3;profile 由管理员维护,此处不给编辑入口) ----
            Card {
                title: "当前产品"
                titleIcon: Icons.navProduct
                fitContent: true
                Layout.fillWidth: true
                Layout.leftMargin: Theme.s5
                Layout.rightMargin: Theme.s5

                ColumnLayout {
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    spacing: Theme.s3

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: Theme.s7
                        rowSpacing: Theme.s3

                        FieldRow {
                            Layout.fillWidth: true
                            label: "产品"
                            value: Session.profile ? Session.profile.name + "  " + Session.profile.desc : ""
                            mono: false
                        }
                        FieldRow {
                            Layout.fillWidth: true
                            label: "ProductId"
                            value: Session.profile ? Session.profile.productId : ""
                        }
                    }

                    // 固定测试项(profile 决定,只读展示)
                    Flow {
                        Layout.fillWidth: true
                        spacing: Theme.s2

                        Repeater {
                            model: Session.profile ? Session.profile.items : []
                            Rectangle {
                                required property var modelData
                                width: chipRow.implicitWidth + Theme.s3
                                height: 24; radius: 12
                                color: Qt.rgba(1, 1, 1, 0.04)
                                border.width: 1
                                border.color: Theme.borderSoft
                                Row {
                                    id: chipRow
                                    anchors.centerIn: parent
                                    spacing: Theme.s1
                                    Icon {
                                        text: Icons.forItem(modelData)
                                        size: 11
                                        color: Theme.textSecondary
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Text {
                                        text: {
                                            const it = MockData.itemByBit(modelData);
                                            return it ? it.name : ("bit" + modelData);
                                        }
                                        color: Theme.textSecondary
                                        font.family: TypeScale.family
                                        font.pointSize: TypeScale.caption
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: "测试项集合由产品 profile 固定（profiles/" 
                              + (Session.profile ? Session.profile.name : "") 
                              + ".json，管理员随软件发布维护）。切换产品用顶栏按钮。"
                        color: Theme.textDim
                        font.family: TypeScale.family
                        font.pointSize: TypeScale.caption
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

            // ---- 在线升级（工厂需求 2026-08-21：不再逐台手工拷包）----
            // ⚠️ 只有 UI，检查/下载/替换还没实现 —— 按钮点了给"暂未开通"提示。
            //    真正的实现要解决三件事：exe 不能覆盖运行中的自己（要独立 updater）、
            //    358MB 全量太重（要按清单差分）、升级包防篡改（要验签）。
            Card {
                title: "在线升级"
                fitContent: true
                Layout.fillWidth: true
                Layout.leftMargin: Theme.s5
                Layout.rightMargin: Theme.s5

                RowLayout {
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    spacing: Theme.s4

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            text: "当前 " + (typeof appVersion !== "undefined"
                                             ? "v" + appVersion : "dev")
                                  + " · 已是最新"
                            color: Theme.textPrimary
                            font.family: TypeScale.family
                            font.pointSize: TypeScale.body
                            font.weight: TypeScale.weightMedium
                        }
                        Text {
                            text: "升级源与自动更新尚未开通 —— 新版本仍由管理员分发"
                            color: Theme.textDim
                            font.family: TypeScale.family
                            font.pointSize: TypeScale.caption
                        }
                    }

                    AppButton {
                        text: "检查更新"
                        glyph: Icons.reset
                        Layout.preferredWidth: 136
                        onClicked: upgradeToast.show("在线升级暂未开通，敬请期待", true)
                    }
                }
            }

            // ---- 负责人 ----
            Card {
                title: "联系人"
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
                                    text: modelData.wecom
                                    color: Theme.textSecondary
                                    font.family: "Consolas"
                                    font.pointSize: TypeScale.caption
                                }
                            }

                            Item { Layout.fillWidth: true }

                            AppButton {
                                text: "企业微信"
                                glyph: Icons.chat
                                kind: "primary"
                                implicitHeight: Theme.hit - 6
                                onClicked: root.openWeCom(modelData.wecom)
                            }

                            AppButton {
                                text: "复制工号"
                                glyph: Icons.copy
                                implicitHeight: Theme.hit - 6
                                onClicked: {
                                    root.copyText(modelData.wecom);
                                    copied.owner = modelData.wecom;
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


                }
            }

            Item { Layout.preferredHeight: Theme.s5 }
        }
    }

    // 复制用的隐藏文本框（仅 copyText() 使用，id 不能叫 clip，见上）。
    TextEdit {
        id: copyHelper
        visible: false
    }
}
