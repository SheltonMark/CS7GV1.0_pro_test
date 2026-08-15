import QtQuick
import ptest

// 顶栏:产品 / 设备 SN(大) / 连接态。工人一眼确认"手上这台就是屏幕上这台"。
Rectangle {
    property string station: ""
    // 只有真正的工位页才带"工位"后缀,关于页不是工位
    property bool isStation: true
    property bool online: true
    // 设备上报 ProductId 与会话产品不符(规则5)
    property bool mismatch: false

    color: Theme.bg

    Rectangle {
        height: 1
        color: Theme.border
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
    }

    Column {
        anchors {
            left: parent.left; leftMargin: Theme.s6
            verticalCenter: parent.verticalCenter
        }
        spacing: 2

        Row {
            spacing: Theme.s2
            Text {
                text: station
                color: Theme.textPrimary
                font.family: TypeScale.family
                font.pointSize: TypeScale.title
                font.weight: TypeScale.weightBold
            }
            Text {
                visible: isStation
                text: "工位"
                color: Theme.textDim
                font.family: TypeScale.family
                font.pointSize: TypeScale.body
                anchors.baseline: parent.children[0].baseline
            }
        }
        Text {
            // 工具版本挂在这里：产线出批量误判要能追溯是哪个版本干的。
            // 将来每条产测记录也要带上同一个值。
            text: Session.profile
                  ? Session.profile.name + "  " + Session.profile.desc
                    + "  ·  " + Session.profile.productId
                    + "      工具 v" + (typeof appVersion !== "undefined" ? appVersion : "dev")
                  : ""
            color: Theme.textSecondary
            font.family: TypeScale.family
            font.pointSize: TypeScale.caption
        }
    }

    Row {
        spacing: Theme.s5
        anchors {
            right: parent.right; rightMargin: Theme.s6
            verticalCenter: parent.verticalCenter
        }

        // 型号不符红警(规则5):禁用工位操作的原因必须让工人一眼看到
        Row {
            visible: mismatch
            spacing: Theme.s2
            anchors.verticalCenter: parent.verticalCenter
            Icon {
                text: Icons.warning
                size: 15
                color: Theme.fail
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: "设备型号与当前产品不符 · 工位操作已禁用"
                color: Theme.fail
                font.family: TypeScale.family
                font.pointSize: TypeScale.body
                font.weight: TypeScale.weightBold
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // 设备 SN 用 hero 字号 —— 产线核对最频繁的字段
        // (切换产品是会话级低频动作,放导航栏底部;顶栏右侧只留设备状态,
        //  高频瞟一眼的信息不和动作按钮混排 —— 混排迟早误触)
        Column {
            spacing: 0
            Text {
                text: "设备 SN"
                color: Theme.textDim
                font.family: TypeScale.family
                font.pointSize: TypeScale.caption
                horizontalAlignment: Text.AlignRight
                width: parent.width
            }
            // 型号段与流水号段分色显示。分隔符是"排版"不是"数据" ——
            // SN 原文仍是 CS7G2608150042(无分隔符),扫码/入库用 MockData.sn。
            Row {
                spacing: 0
                Text {
                    text: MockData.snModel
                    color: Theme.textSecondary
                    font.family: "Consolas"
                    font.pointSize: TypeScale.heading
                    font.weight: TypeScale.weightBold
                }
                Text {
                    text: "-"
                    color: Theme.textDim
                    font.family: "Consolas"
                    font.pointSize: TypeScale.heading
                    font.weight: TypeScale.weightBold
                    leftPadding: 3
                    rightPadding: 3
                }
                Text {
                    text: MockData.snSerial
                    color: Theme.textPrimary
                    font.family: "Consolas"
                    font.pointSize: TypeScale.heading
                    font.weight: TypeScale.weightBold
                }
            }
        }

        Rectangle {
            width: 1
            height: 32
            color: Theme.border
            anchors.verticalCenter: parent.verticalCenter
        }

        Row {
            spacing: Theme.s2
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
                width: 8; height: 8; radius: 4
                color: online ? Theme.pass : Theme.fail
                anchors.verticalCenter: parent.verticalCenter

                SequentialAnimation on opacity {
                    running: online
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.35; duration: 1100 }
                    NumberAnimation { to: 1.0;  duration: 1100 }
                }
            }
            Text {
                text: online ? "在线" : "离线"
                color: online ? Theme.pass : Theme.fail
                font.family: TypeScale.family
                font.pointSize: TypeScale.body
                font.weight: TypeScale.weightMedium
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
}
