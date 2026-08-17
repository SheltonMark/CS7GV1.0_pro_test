import QtQuick
import ptest
import QtQuick.Controls

// 设备发现结果面板（老 CP3 交互：搜索 → 列表 → 双击拉流）。
// 只管展示与双击选定；搜索的起停按钮在调焦页，UDP 协议在 DeviceDiscovery(C++)。
//
// ⚠️ 列表有货的前提是设备端有广播应答服务（监听 7320、认搜索字、
//    回 ip;mac 到 7319）。老 CP3 固件自带；新 battery_ipc 固件是否已
//    移植待确认 —— 没有则这里恒空，工人只能用调焦页的手动 IP 兜底。
Rectangle {
    id: root

    required property DeviceDiscovery discovery
    // 双击某行选定该设备（调焦页接住：停搜索 + 填 IP + 拉流）
    signal picked(string ip)

    radius: Theme.radius
    color: Theme.surface
    border.width: 1
    border.color: Theme.border
    implicitHeight: col.implicitHeight + Theme.s3 * 2

    Column {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top
                  margins: Theme.s3 }
        spacing: Theme.s2

        Row {
            spacing: Theme.s2

            BusyIndicator {
                running: root.discovery.searching
                visible: running
                implicitWidth: 16
                implicitHeight: 16
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: root.discovery.searching ? "广播搜索中…" : "搜索结果"
                color: Theme.textSecondary
                font.family: TypeScale.family
                font.pointSize: TypeScale.caption
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                visible: root.discovery.devices.length > 0
                text: "发现 " + root.discovery.devices.length + " 台  ·  双击行拉流"
                color: Theme.textDim
                font.family: TypeScale.family
                font.pointSize: TypeScale.caption
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // 空态给排查线索：搜不到大概率是防火墙拦包或不在同一网段
        Text {
            visible: root.discovery.devices.length === 0
            width: parent.width
            text: "未发现设备。请确认设备与本机网口直连或同一交换机、"
                  + "Windows 防火墙弹窗已选「允许」（首次搜索会弹）；也可直接手填 IP。"
            color: Theme.textDim
            font.family: TypeScale.family
            font.pointSize: TypeScale.caption
            wrapMode: Text.WordWrap
        }

        ListView {
            id: deviceList
            visible: root.discovery.devices.length > 0
            width: parent.width
            // 最多露 4 行，更多在内部滚 —— 面板不能把预览挤成一条缝
            height: Math.min(root.discovery.devices.length, 4) * 34
            clip: true
            model: root.discovery.devices

            delegate: Rectangle {
                id: deviceRow
                required property var modelData
                width: deviceList.width
                height: 34
                radius: Theme.radius
                color: hover.containsMouse ? Theme.surfaceAlt : "transparent"

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    x: Theme.s3
                    spacing: Theme.s5

                    Text {
                        text: deviceRow.modelData.ip
                        width: 150
                        color: Theme.textPrimary
                        font.family: "Consolas"
                        font.pointSize: TypeScale.body
                    }
                    Text {
                        text: deviceRow.modelData.mac
                        color: Theme.textSecondary
                        font.family: "Consolas"
                        font.pointSize: TypeScale.body
                    }
                }

                // 只挂 MouseArea、不给列表键盘焦点 —— 不抢工位页键盘流
                //（与 AppButton 的 NoFocus 同一条纪律）。双击选定沿用老 CP3
                // 的习惯，产线工人已有肌肉记忆。
                MouseArea {
                    id: hover
                    anchors.fill: parent
                    hoverEnabled: true
                    onDoubleClicked: root.picked(deviceRow.modelData.ip)
                }
            }
        }
    }
}
