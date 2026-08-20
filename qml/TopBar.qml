import QtQuick
import ptest

// 顶栏:产品 / 设备 SN(大) / 连接态。工人一眼确认"手上这台就是屏幕上这台"。
Rectangle {
    id: bar

    property string station: ""
    // 工位 key（focus/semi/finished/…），给设备浮层判"本工位做完没有"。
    // 与 station 分开：station 是显示用的中文标题，key 才是数据侧的标识。
    property string stationKey: ""
    // 只有真正的工位页才带"工位"后缀,关于页不是工位
    property bool isStation: true
    property bool online: true
    // 设备上报 ProductId 与会话产品不符(规则5)
    property bool mismatch: false

    // 切设备/选到离线设备的提示。顶栏只有 76px，装不下 Toast，交给窗口根层。
    signal deviceMessage(string text, bool ok)

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
            text: (Session.profile
                   ? Session.profile.name + "  " + Session.profile.desc
                     + "  ·  " + Session.profile.productId
                   : "")
                  + (Session.user
                     ? "  ·  " + Session.user.id + "（" + Session.roleLabel() + "）"
                     : "")
                  + "      工具 v" + (typeof appVersion !== "undefined" ? appVersion : "dev")
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

        // 当前工装卡（device_name）+ 下拉切换。
        //
        // 这里原先显示的是 MockData.snModel/snSerial —— demo 期的**假 SN**，与真
        // 设备无关。多设备之后工人要核对的标识是 device_name（SD 工装卡上那串，
        // 一卡一台、下批复用），所以换成它，并就地提供切换入口。
        //
        // 放顶栏而不是单独一条：顶栏本来就占 76px，塞进来不吃额外高度。任何占高度
        // 的东西都会挤到调焦页的画面（Crop 从上下裁，吃掉 OSD 时间戳和 logo）。
        Column {
            spacing: 1
            anchors.verticalCenter: parent.verticalCenter

            // 本批进度：自动跳台之后工人靠这一行知道"这批还剩几台"。
            // ⚠️ 依赖 tick 才会重算 —— stationDoneCount 里调的 StationProgress.isDone
            //    是函数调用，QML 不会因为它内部数据变了就刷新绑定。
            Text {
                id: progressLabel
                property int tick: 0
                Connections {
                    target: StationProgress
                    function onChanged() { progressLabel.tick++; }
                }
                text: {
                    if (!bar.isStation || bar.stationKey.length === 0)
                        return "工装卡 · DeviceName";
                    const total = CloudClient.devices.length;
                    if (total === 0)
                        return "工装卡 · DeviceName";
                    const done = progressLabel.tick >= 0
                                 ? Session.stationDoneCount(bar.stationKey) : 0;
                    return "工装卡 · 本工位 " + done + " / " + total + " 已完成";
                }
                color: Theme.textDim
                font.family: TypeScale.family
                font.pointSize: TypeScale.caption
                horizontalAlignment: Text.AlignRight
                width: parent.width
            }
            DevicePicker {
                id: picker
                // 当前工位 key：浮层里的绿/红点表示"这个工位"做完没有
                station: bar.stationKey
                onMessage: (text, ok) => bar.deviceMessage(text, ok)
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
