import QtQuick
import ptest

// 左侧工位导航。Wayfinding:工人永远知道自己在哪个工位。
// 图标 + 文字双编码 —— 图标给快速识别，文字消除歧义。
Rectangle {
    id: rail

    property int currentIndex: 0
    readonly property var entries: [
        { key: "调焦",   sub: "工位 1", icon: Icons.navFocus },
        { key: "准成品", sub: "工位 2", icon: Icons.navSemi },
        { key: "成品",   sub: "工位 2", icon: Icons.navFinished },
        { key: "检查",   sub: "工位 3", icon: Icons.navInspect },
        { key: "维修",   sub: "按需",   icon: Icons.navRepair },
        { key: "产品",   sub: "配置",   icon: Icons.navProduct },
        { key: "关于",   sub: "版本",   icon: Icons.navAbout }
    ]

    color: Theme.bgDeep

    Rectangle {
        width: 1
        color: Theme.border
        anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
    }

    // 品牌 logo 置顶。产线电脑上常同时开好几个工具，一眼认出是哪个。
    Image {
        id: brandMark
        source: "logo.png"
        sourceSize.width: rail.width - Theme.s4 * 2
        fillMode: Image.PreserveAspectFit
        smooth: true
        anchors {
            horizontalCenter: parent.horizontalCenter
            top: parent.top
            topMargin: Theme.s5
        }
    }

    Column {
        anchors {
            left: parent.left; right: parent.right
            top: brandMark.bottom; topMargin: Theme.s6
        }
        spacing: Theme.s1

        Repeater {
            model: rail.entries

            Item {
                id: cell
                required property int index
                required property var modelData

                readonly property bool active: index === rail.currentIndex

                width: parent.width
                height: 62

                // 选中态用品牌色低透明度垫底，不用实心块 —— 实心块会跟
                // 右侧结果爆点抢注意力。
                Rectangle {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.s2
                    anchors.rightMargin: Theme.s2
                    radius: Theme.radius
                    color: cell.active ? Theme.brandWash
                           : (hh.hovered ? Qt.rgba(1, 1, 1, 0.04) : "transparent")
                    Behavior on color { ColorAnimation { duration: Theme.durFast } }
                }

                HoverHandler { id: hh }
                TapHandler { onTapped: rail.currentIndex = cell.index }

                // 选中指示条:滑动而非跳变
                Rectangle {
                    width: 3
                    height: cell.active ? 26 : 0
                    radius: 2
                    color: Theme.brand
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    Behavior on height {
                        NumberAnimation { duration: Theme.durMed; easing.type: Easing.OutCubic }
                    }
                }

                Column {
                    anchors.centerIn: parent
                    spacing: 3

                    Icon {
                        text: cell.modelData.icon
                        size: 20
                        color: cell.active ? Theme.brand : Theme.textSecondary
                        anchors.horizontalCenter: parent.horizontalCenter
                        Behavior on color { ColorAnimation { duration: Theme.durFast } }
                    }

                    Text {
                        text: cell.modelData.key
                        color: cell.active ? Theme.textPrimary : Theme.textSecondary
                        font.family: TypeScale.family
                        font.pointSize: TypeScale.caption
                        font.weight: cell.active ? TypeScale.weightBold : TypeScale.weightRegular
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
            }
        }
    }

    // 底部版本号。小字弱化，但随时可查。
    Text {
        text: typeof appVersion !== "undefined" ? "v" + appVersion : "dev"
        color: Theme.textDim
        font.family: "Consolas"
        font.pointSize: TypeScale.caption
        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: parent.bottom
            bottomMargin: Theme.s4
        }
    }
}
