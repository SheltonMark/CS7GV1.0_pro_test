import QtQuick
import ptest
import QtQuick.Controls
import QtQuick.Layouts

// 启动门:软件第一屏 = 选产品。选定后锁定会话(ProductId/测试项集合,
// 真实实现还锁凭证与工装卡校验基准),再进主界面。
// 产品页不再放工位侧边栏 —— 产线一台电脑一个班次只跑一种产品,
// 产品是会话属性不是页面,混在工位流里会被误点。
Item {
    id: gate

    // 开发用:--autoselect 跳过启动门直接进首个可用产品(自动化/联调方便)
    Component.onCompleted: {
        if (Qt.application.arguments.indexOf("--autoselect") >= 0)
            Session.profile = MockData.profiles.find(p => p.enabled) || null
    }

    Rectangle { anchors.fill: parent; color: Theme.bg }

    ColumnLayout {
        anchors.centerIn: parent
        width: 560
        spacing: Theme.s4

        Image {
            source: "logo.png"
            sourceSize.height: 34
            fillMode: Image.PreserveAspectFit
            smooth: true
            Layout.alignment: Qt.AlignHCenter
        }

        Text {
            text: "产测工具"
            color: Theme.textPrimary
            font.family: TypeScale.family
            font.pointSize: TypeScale.display
            font.weight: TypeScale.weightBold
            Layout.alignment: Qt.AlignHCenter
        }

        Text {
            text: "选择产品进入 · 会话将锁定该产品"
            color: Theme.textSecondary
            font.family: TypeScale.family
            font.pointSize: TypeScale.body
            Layout.alignment: Qt.AlignHCenter
            Layout.bottomMargin: Theme.s4
        }

        Repeater {
            model: MockData.profiles

            Rectangle {
                id: card
                required property var modelData
                readonly property bool usable: modelData.enabled

                Layout.fillWidth: true
                height: 86
                radius: Theme.radiusLg
                color: usable && hh.hovered ? Theme.surfaceAlt : Theme.surface
                border.width: 1
                border.color: usable && hh.hovered ? Theme.brandEdge : Theme.borderSoft
                opacity: usable ? 1.0 : 0.45
                Behavior on color { ColorAnimation { duration: Theme.durFast } }
                Behavior on border.color { ColorAnimation { duration: Theme.durFast } }

                HoverHandler { id: hh; enabled: card.usable }
                TapHandler {
                    enabled: card.usable
                    onTapped: Session.profile = card.modelData
                }

                Rectangle {
                    visible: card.usable && hh.hovered
                    width: 3; radius: 2
                    color: Theme.brand
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom
                              topMargin: Theme.s4; bottomMargin: Theme.s4 }
                }

                RowLayout {
                    anchors { fill: parent; leftMargin: Theme.s5; rightMargin: Theme.s5 }
                    spacing: Theme.s4

                    Rectangle {
                        width: 44; height: 44; radius: Theme.radius
                        color: card.usable ? Theme.brandWash : Qt.rgba(1, 1, 1, 0.04)
                        Icon {
                            anchors.centerIn: parent
                            text: Icons.navProduct
                            size: 20
                            color: card.usable ? Theme.brand : Theme.textDim
                        }
                    }

                    ColumnLayout {
                        spacing: 2
                        Layout.fillWidth: true

                        Row {
                            spacing: Theme.s2
                            Text {
                                text: card.modelData.name
                                color: card.usable ? Theme.textPrimary : Theme.textDim
                                font.family: TypeScale.family
                                font.pointSize: TypeScale.heading
                                font.weight: TypeScale.weightBold
                            }
                            Text {
                                text: card.modelData.desc
                                color: Theme.textDim
                                font.family: TypeScale.family
                                font.pointSize: TypeScale.caption
                                anchors.baseline: parent.children[0].baseline
                            }
                        }
                        Text {
                            text: card.usable
                                  ? "ProductId  " + card.modelData.productId
                                    + "   ·   测试项 " + card.modelData.items.length + " 项"
                                  : "ProductId  （待建模）"
                            color: Theme.textDim
                            font.family: "Consolas"
                            font.pointSize: TypeScale.caption
                        }
                    }

                    // 待建模产品可见但置灰(规则6):看得见"它在计划里",选不进坏会话
                    Rectangle {
                        visible: !card.usable
                        width: badge.implicitWidth + Theme.s3
                        height: 24; radius: 12
                        color: Qt.rgba(0.980, 0.800, 0.082, 0.10)
                        border.width: 1
                        border.color: Qt.rgba(0.980, 0.800, 0.082, 0.40)
                        Text {
                            id: badge
                            text: "待建模"
                            color: Theme.warn
                            font.family: TypeScale.family
                            font.pointSize: TypeScale.caption
                            anchors.centerIn: parent
                        }
                    }

                    Icon {
                        visible: card.usable
                        text: Icons.play
                        size: 16
                        color: hh.hovered ? Theme.brand : Theme.textDim
                    }
                }
            }
        }

        // 新增入口:普通工人不可编辑 profile,入口只指路
        Rectangle {
            Layout.fillWidth: true
            height: 52
            radius: Theme.radiusLg
            color: "transparent"
            border.width: 1
            border.color: Theme.borderSoft

            HoverHandler { id: addHover }
            TapHandler { onTapped: addDialog.open() }

            Row {
                anchors.centerIn: parent
                spacing: Theme.s2
                Icon {
                    text: Icons.add
                    size: 14
                    color: addHover.hovered ? Theme.textSecondary : Theme.textDim
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: "新增产品"
                    color: addHover.hovered ? Theme.textSecondary : Theme.textDim
                    font.family: TypeScale.family
                    font.pointSize: TypeScale.body
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        Text {
            text: "工具 " + (typeof appVersion !== "undefined" ? "v" + appVersion : "dev")
            color: Theme.textDim
            font.family: "Consolas"
            font.pointSize: TypeScale.caption
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Theme.s5
        }
    }

    Dialog {
        id: addDialog
        title: "新增产品"
        modal: true
        anchors.centerIn: parent
        standardButtons: Dialog.Ok

        Text {
            width: 360
            text: "产品 profile 随软件发布、由管理员维护：安装目录 profiles/*.json"
                + "（productId / 显示名 / 固定测试项集合 / 工装卡模板）。"
                + "普通工位电脑不提供编辑入口。"
            color: Theme.textPrimary
            font.family: TypeScale.family
            font.pointSize: TypeScale.body
            wrapMode: Text.WordWrap
        }
    }
}
