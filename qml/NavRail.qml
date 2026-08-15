import QtQuick
import ptest

// 左侧工位导航。Wayfinding:工人永远知道自己在哪个工位。
// 图标 + 文字双编码 —— 图标给快速识别，文字消除歧义。
Rectangle {
    id: rail

    property int currentIndex: 0

    // 工位表由当前产品的 profile 决定 —— 不同产品工艺路线不同（射频类产品
    // 多流量/射频/耦合三站且不做调焦）。关于页与工位无关，恒定追加在末尾。
    // 图标按 station.key 查表；pending 站点用统一的"待实现"图标并置灰。
    readonly property var stations: Session.profile && Session.profile.stations
                                    ? Session.profile.stations : []

    readonly property var entries: {
        var out = [];
        for (var i = 0; i < stations.length; ++i) {
            var s = stations[i];
            out.push({ key: s.title, sub: s.sub, icon: iconFor(s.key),
                       pending: s.pending === true });
        }
        out.push({ key: "关于", sub: "版本", icon: Icons.navAbout, pending: false });
        return out;
    }

    // 坑 2:单例属性初始化不能调自定义函数 —— 此处 rail 是普通组件不是单例，
    // 且 entries 是绑定表达式而非单例属性初始化，安全。
    function iconFor(key) {
        switch (key) {
        case "focus":    return Icons.navFocus;
        case "semi":     return Icons.navSemi;
        case "finished": return Icons.navFinished;
        case "inspect":  return Icons.navInspect;
        case "repair":   return Icons.navRepair;
        // flow/rf/coupling 等未实现工位:复用已验证的时钟码位(坑 6 —— 新码位
        // 必须在 MDL2/Fluent 两套字体里都确认过，不新增未验证的)
        default:         return Icons.pending;
        }
    }

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
                        // 未实现工位压到三级灰:导航里看得见(工艺路线确实有这站)
                        // 但一眼可辨"现在还点不出东西"。
                        color: cell.active ? Theme.brand
                               : (cell.modelData.pending ? Theme.textDim
                                                         : Theme.textSecondary)
                        anchors.horizontalCenter: parent.horizontalCenter
                        Behavior on color { ColorAnimation { duration: Theme.durFast } }
                    }

                    Text {
                        text: cell.modelData.key
                        color: cell.active ? Theme.textPrimary
                               : (cell.modelData.pending ? Theme.textDim
                                                         : Theme.textSecondary)
                        font.family: TypeScale.family
                        font.pointSize: TypeScale.caption
                        font.weight: cell.active ? TypeScale.weightBold : TypeScale.weightRegular
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
            }
        }
    }

    // 底部:切换产品(会话级动作,不是页面 —— 用分隔线和暗色与工位项区分;
    // 点击走二次确认,由 Main 处理) + 版本号
    signal switchProduct()
    signal switchUser()

    Column {
        anchors {
            left: parent.left; right: parent.right
            bottom: parent.bottom; bottomMargin: Theme.s3
        }
        spacing: Theme.s3

        Rectangle {
            width: parent.width - Theme.s4 * 2
            height: 1
            color: Theme.borderSoft
            anchors.horizontalCenter: parent.horizontalCenter
        }

        Item {
            width: parent.width
            height: 50

            Rectangle {
                anchors.fill: parent
                anchors.leftMargin: Theme.s2
                anchors.rightMargin: Theme.s2
                radius: Theme.radius
                color: suHover.hovered ? Qt.rgba(1, 1, 1, 0.05) : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.durFast } }
            }
            HoverHandler { id: suHover }
            TapHandler { onTapped: rail.switchUser() }

            Column {
                anchors.centerIn: parent
                spacing: 2
                Icon {
                    text: Icons.person
                    size: 16
                    color: suHover.hovered ? Theme.textSecondary : Theme.textDim
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                Text {
                    text: "切换用户"
                    color: suHover.hovered ? Theme.textSecondary : Theme.textDim
                    font.family: TypeScale.family
                    font.pointSize: TypeScale.caption
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }

        Item {
            width: parent.width
            height: 50

            Rectangle {
                anchors.fill: parent
                anchors.leftMargin: Theme.s2
                anchors.rightMargin: Theme.s2
                radius: Theme.radius
                color: swHover.hovered ? Qt.rgba(1, 1, 1, 0.05) : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.durFast } }
            }
            HoverHandler { id: swHover }
            TapHandler { onTapped: rail.switchProduct() }

            Column {
                anchors.centerIn: parent
                spacing: 2
                Icon {
                    text: Icons.reset
                    size: 16
                    color: swHover.hovered ? Theme.textSecondary : Theme.textDim
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                Text {
                    text: "切换产品"
                    color: swHover.hovered ? Theme.textSecondary : Theme.textDim
                    font.family: TypeScale.family
                    font.pointSize: TypeScale.caption
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }

        Text {
            text: typeof appVersion !== "undefined" ? "v" + appVersion : "dev"
            color: Theme.textDim
            font.family: "Consolas"
            font.pointSize: TypeScale.caption
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }
}
