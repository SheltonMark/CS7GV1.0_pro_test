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

    // entries 仍含关于页(索引 = stations.length),Main 的页面栈据此路由;
    // 但它渲染在**底部区**而非工位列表里 —— 关于不是工位,不该混在工位流中间
    // 打断"我在第几站"的判断。工位列表只画 stations。
    readonly property var entries: {
        var out = [];
        for (var i = 0; i < stations.length; ++i) {
            var s = stations[i];
            out.push({ key: s.title, sub: s.sub, icon: iconFor(s.key),
                       pending: s.pending === true });
        }
        out.push({ key: "批次文件", sub: "导入/导出", icon: Icons.save, pending: false });
        out.push({ key: "关于", sub: "版本", icon: Icons.navAbout, pending: false });
        out.push({ key: "云调试", sub: "链路", icon: Icons.cloud, pending: false });
        return out;
    }

    // 非工位页索引:批次文件、关于、云调试依次排在工位之后。
    // ⚠️ 这些索引是按位置算的，往 entries 里增删项必须同步改这里和 Main 的挂载条件。
    //
    // 账号管理**不在这里** —— 左侧栏是工位导航，账号不是工位；而且它该在选产品之前
    // 就能用（换批次时顺手加个人），不该等进了工位主界面（2026-08-21 用户定）。
    // 入口在 ProductGate 的"账号管理"。
    readonly property int batchIndex: stations.length
    readonly property int aboutIndex: stations.length + 1
    readonly property int debugIndex: stations.length + 2

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

        // 只画工位(关于页在底部区)
        Repeater {
            model: rail.stations.length

            Item {
                id: cell
                required property int index
                readonly property var modelData: rail.entries[index]

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

        // 批次文件页(导入 InputData1 / 导出 InputData2)。所有角色可用 ——
        // 批次级动作,不属于任何工位,故与关于页一样放底部区。
        Item {
            id: batchCell
            width: parent.width
            height: 50

            readonly property bool active: rail.currentIndex === rail.batchIndex

            Rectangle {
                anchors.fill: parent
                anchors.leftMargin: Theme.s2
                anchors.rightMargin: Theme.s2
                radius: Theme.radius
                color: batchCell.active ? Theme.brandWash
                       : (bfHover.hovered ? Qt.rgba(1, 1, 1, 0.05) : "transparent")
                Behavior on color { ColorAnimation { duration: Theme.durFast } }
            }
            HoverHandler { id: bfHover }
            TapHandler { onTapped: rail.currentIndex = rail.batchIndex }

            Column {
                anchors.centerIn: parent
                spacing: 2
                Icon {
                    text: Icons.save
                    size: 16
                    color: batchCell.active ? Theme.brand
                           : (bfHover.hovered ? Theme.textSecondary : Theme.textDim)
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                Text {
                    text: "批次文件"
                    color: batchCell.active ? Theme.textPrimary
                           : (bfHover.hovered ? Theme.textSecondary : Theme.textDim)
                    font.family: TypeScale.family
                    font.pointSize: TypeScale.caption
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }

        // 关于页。放在切换产品下方 —— 它是页面(有选中态)而不是动作,
        // 所以保留品牌色选中样式,与上面两个纯动作项区分。
        Item {
            id: aboutCell
            width: parent.width
            height: 50

            // ⚠️ 用具名 id 引用，不用 parent.parent —— 后者在 Column 里层级
            // 数错会把样式绑到兄弟项上（表现为"切换产品"被误高亮成选中态）。
            readonly property bool active: rail.currentIndex === rail.aboutIndex

            Rectangle {
                anchors.fill: parent
                anchors.leftMargin: Theme.s2
                anchors.rightMargin: Theme.s2
                radius: Theme.radius
                color: aboutCell.active ? Theme.brandWash
                       : (abHover.hovered ? Qt.rgba(1, 1, 1, 0.05) : "transparent")
                Behavior on color { ColorAnimation { duration: Theme.durFast } }
            }
            HoverHandler { id: abHover }
            TapHandler { onTapped: rail.currentIndex = rail.aboutIndex }

            Column {
                anchors.centerIn: parent
                spacing: 2
                Icon {
                    text: Icons.navAbout
                    size: 16
                    color: aboutCell.active ? Theme.brand
                           : (abHover.hovered ? Theme.textSecondary : Theme.textDim)
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                Text {
                    text: "关于"
                    color: aboutCell.active ? Theme.textPrimary
                           : (abHover.hovered ? Theme.textSecondary : Theme.textDim)
                    font.family: TypeScale.family
                    font.pointSize: TypeScale.caption
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }

        // 云链路调试页(联调用)。与批次文件/关于同为非工位页,放底部区。
        // 只开放给工程师/管理员（Session.canDebugPanel = role !== "tech"）：这页能
        // 直接下发任意物模型 action、手填 DeviceName，产线操作工不该有这个入口。
        // ⚠️ 只控 visible、不从 entries 里去掉：debugIndex = stations.length + 2 是
        //    按位置算的，抽掉一项会把索引算错。
        Item {
            id: debugCell
            visible: Session.canDebugPanel
            width: parent.width
            height: visible ? 50 : 0

            readonly property bool active: rail.currentIndex === rail.debugIndex

            Rectangle {
                anchors.fill: parent
                anchors.leftMargin: Theme.s2
                anchors.rightMargin: Theme.s2
                radius: Theme.radius
                color: debugCell.active ? Theme.brandWash
                       : (dbgHover.hovered ? Qt.rgba(1, 1, 1, 0.05) : "transparent")
                Behavior on color { ColorAnimation { duration: Theme.durFast } }
            }
            HoverHandler { id: dbgHover }
            TapHandler { onTapped: rail.currentIndex = rail.debugIndex }

            Column {
                anchors.centerIn: parent
                spacing: 2
                Icon {
                    text: Icons.cloud
                    size: 16
                    color: debugCell.active ? Theme.brand
                           : (dbgHover.hovered ? Theme.textSecondary : Theme.textDim)
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                Text {
                    text: "云调试"
                    color: debugCell.active ? Theme.textPrimary
                           : (dbgHover.hovered ? Theme.textSecondary : Theme.textDim)
                    font.family: TypeScale.family
                    font.pointSize: TypeScale.caption
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }


        // 退出登录放**最底下**（2026-08-21 用户定）：它是整个侧栏里唯一"离开"
        // 语义的动作，摆在工位项和其他入口中间容易误点；沉到底部与它们区分。
        // 上面再加一条分隔线，明确"以下不是页面"。
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
                    // "退出登录"而不是"切换用户"：本来就没有用户列表可切，两者都是
                    // 回登录页；登录现在是个人腾达云账号，退出登录是更诚实的叫法
                    text: "退出登录"
                    color: suHover.hovered ? Theme.textSecondary : Theme.textDim
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
