import QtQuick
import ptest
import QtQuick.Controls
import QtQuick.Layouts

// 工装卡名单条 —— 一批 10 台设备同时在线时，选当前要测的那台。
//
// 为什么挂在 Main 里而不是各工位页：工人在每个工位都要看/切设备，挂顶层一处，
// 所有工位页零改动就都有了；也避免每页一份、状态各走各的。
//
// 交互沿用页面里已有的约定：**双击**选中（同"双击搜索结果拉流"）。单击只是
// 高亮预览，避免手滑就把正在测的设备切走 —— 切设备会断掉云会话、清掉进度显示。
//
// ⚠️ 不许滚动（老板要求）。所以卡片宽度按台数自适应：10 台以内保持舒适宽度，
//    超了就压缩字号/宽度，实在放不下才降级成两行。
Rectangle {
    id: root

    // 当前选中的设备名。空 = 还没选（工人必须先选一台才能干活）。
    property string current: CloudClient.deviceName

    implicitHeight: content.implicitHeight + Theme.s3 * 2
    color: Theme.bgDeep
    // 只画下边框：视觉上它是 TopBar 的延续，不是独立卡片
    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 1
        color: Theme.border
    }

    // 进产品页/切产品后要重新问名单。productId 变了就重刷 —— 这就是"按产品
    // 过滤"的入口：名单只包含当前 productId 下的设备。
    Connections {
        target: CloudClient
        function onDeviceChanged() { rosterPoll.restart(); }
    }
    Component.onCompleted: CloudClient.refreshDevices()

    // 在线状态会变（设备上电/掉电/装壳时断电），得周期性重问。
    // 15s 一次：这是"谁在线"的粒度，不是心跳粒度，不用更快。
    Timer {
        id: rosterPoll
        interval: 15000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: CloudClient.refreshDevices()
    }

    RowLayout {
        id: content
        anchors {
            left: parent.left; right: parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: Theme.s4; rightMargin: Theme.s4
        }
        spacing: Theme.s3

        Label {
            text: "工装卡"
            color: Theme.textSecondary
            font.family: TypeScale.family
            font.pointSize: TypeScale.caption
            font.weight: TypeScale.weightMedium
        }

        // 卡片区。用 Repeater 平铺，Layout 自己分宽度 —— 不用 ListView，
        // 就是为了物理上不可能出现滚动条。
        Repeater {
            model: CloudClient.devices

            delegate: Rectangle {
                id: chip
                required property var modelData

                readonly property bool isCurrent: modelData.deviceName === root.current
                readonly property bool isOnline: modelData.online === true

                Layout.fillWidth: true
                // 上限防止台数少时卡片被拉得过宽（2 台时一张占半屏很怪）
                Layout.maximumWidth: 168
                Layout.minimumWidth: 76
                implicitHeight: 46

                radius: Theme.radius
                color: isCurrent ? Theme.brandWash
                       : hover.containsMouse ? Theme.surfaceAlt
                       : Theme.surface
                border.width: isCurrent ? 2 : 1
                border.color: isCurrent ? Theme.brand
                              : isOnline ? Theme.border : Theme.borderSoft
                Behavior on color { ColorAnimation { duration: Theme.durFast } }

                // 离线的整体压暗：一眼分出"能测的"和"没上电的"
                opacity: isOnline || isCurrent ? 1.0 : 0.45

                Column {
                    anchors.centerIn: parent
                    spacing: 1

                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: Theme.s1 + 2

                        // 在线点。绿=在线，灰=离线。
                        // ⚠️ 用 chip.isOnline，不要 parent.parent.parent —— 那是按
                        //    层级位置找对象，谁加一层包装就断。
                        Rectangle {
                            width: 7; height: 7; radius: 3.5
                            anchors.verticalCenter: parent.verticalCenter
                            color: chip.isOnline ? Theme.pass : Theme.idle
                        }
                        Text {
                            text: "卡 " + modelData.card
                            color: Theme.textPrimary
                            font.family: TypeScale.family
                            font.pointSize: TypeScale.body
                            font.weight: TypeScale.weightMedium
                        }
                    }

                    // 设备名。10 位数字全显示太挤，只给尾 4 位 —— 卡号才是工人
                    // 手上对得上的东西，全名在 tooltip 和云调试页里看。
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "…" + String(modelData.deviceName).slice(-4)
                        color: Theme.textDim
                        font.family: "Consolas"
                        font.pointSize: TypeScale.caption
                    }
                }

                MouseArea {
                    id: hover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    // 双击才切：切设备会断云会话、清进度，手滑代价太大
                    onDoubleClicked: root.pick(modelData.deviceName, modelData.online)
                }

                ToolTip.visible: hover.containsMouse
                ToolTip.text: chip.modelData.deviceName
                              + (chip.isOnline ? "" : "（离线）")
                              + "\n双击选中"
            }
        }

        // 名单为空时的说明。产线上"一台都没列出来"最容易被当成软件坏了，
        // 必须写清楚是在等云端还是真没有。
        Text {
            visible: CloudClient.devices.length === 0
            Layout.fillWidth: true
            text: CloudClient.devicesLoading
                  ? "正在读取设备名单…"
                  : "该产品下没有设备 —— 确认工装卡已插好、设备已上电"
            color: Theme.textDim
            font.family: TypeScale.family
            font.pointSize: TypeScale.caption
        }

        Item { Layout.fillWidth: CloudClient.devices.length === 0 }

        // 在线台数一眼可见，工人自己就能核对"这批 10 台都上电了吗"
        Label {
            visible: CloudClient.devices.length > 0
            text: {
                let on = 0;
                for (const d of CloudClient.devices) if (d.online) ++on;
                return on + " / " + CloudClient.devices.length + " 在线";
            }
            color: Theme.textSecondary
            font.family: TypeScale.family
            font.pointSize: TypeScale.caption
        }
    }

    signal picked(string deviceName)
    // ⚠️ 提示不在本组件里显示：本条只有 ~70px 高，Toast 锚在 parent.bottom 会跑到
    //    条子外面去（而且它不 clip，会浮在页面上一个很怪的位置）。交给窗口根层。
    signal message(string text, bool ok)

    function pick(name, online) {
        if (!online) {
            root.message("该设备离线，先确认工装卡已插好、设备已上电", false);
            return;
        }
        if (name === root.current)
            return;
        CloudClient.deviceName = name;   // 一处改，所有工位页的指令自动指向新设备
        CloudClient.refreshInfo();       // 立刻拉一次上报，进度徽标别停在上一台
        root.picked(name);
        root.message("已切到 " + name, true);
    }
}
