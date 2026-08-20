import QtQuick
import ptest
import QtQuick.Controls
import QtQuick.Layouts

// 工装卡选择器 —— 一批 10 台设备同时在线时，选当前要测的那台。
//
// 为什么是下拉而不是一条卡片列表：**任何占高度的东西都会挤到画面**。调焦页的
// LivePreview 是 PreserveAspectCrop，可用高度一少就从上下裁，正好吃掉画面顶部的
// OSD 时间戳和底部 Tenda logo（README 第 18 条；日志面板和名单条各踩过一次）。
// 下拉的展开层浮在页面之上、不参与布局，所以零高度成本。
//
// 一处选中，所有工位页跟着走：改的是 CloudClient.deviceName，而 transport 每次
// 调用都带 deviceName，所以工位页的指令自动指向新设备，页面代码不用改。
ComboBox {
    id: root

    // 完整 device_name 列表（不是卡号）—— 工人要核对的就是这串数字本身
    model: CloudClient.devices
    textRole: "deviceName"
    valueRole: "deviceName"

    // 宽度按最长的 device_name 撑开，不要挤成省略号：核对标识时看半截等于没看
    implicitContentWidthPolicy: ComboBox.WidestText

    // 外部改了当前设备（如云调试页手填）也要同步高亮
    currentIndex: {
        for (let i = 0; i < CloudClient.devices.length; ++i)
            if (CloudClient.devices[i].deviceName === CloudClient.deviceName)
                return i;
        return -1;
    }

    displayText: CloudClient.deviceName.length > 0
                 ? CloudClient.deviceName
                 : (CloudClient.devicesLoading ? "读取名单中…" : "未选设备")

    font.family: "Consolas"
    font.pointSize: TypeScale.body

    signal message(string text, bool ok)

    onActivated: (index) => {
        const d = CloudClient.devices[index];
        if (!d)
            return;
        if (d.online !== true) {
            root.message("该设备离线，先确认工装卡已插好、设备已上电", false);
            return;
        }
        if (d.deviceName === CloudClient.deviceName)
            return;
        CloudClient.deviceName = d.deviceName;
        CloudClient.refreshInfo();   // 立刻拉一次上报，别让界面停在上一台的数据
        root.message("已切到 " + d.deviceName, true);
    }

    // 每项：在线点 + 完整 device_name。离线项压暗但仍可见 —— 工人需要知道
    // "这张卡在名单里，只是没上电"，而不是以为卡丢了。
    delegate: ItemDelegate {
        id: item
        required property var modelData
        required property int index

        width: root.width
        highlighted: root.highlightedIndex === index
        opacity: modelData.online === true ? 1.0 : 0.5

        contentItem: RowLayout {
            spacing: Theme.s2

            Rectangle {
                width: 7; height: 7; radius: 3.5
                color: item.modelData.online === true ? Theme.pass : Theme.idle
            }
            Text {
                Layout.fillWidth: true
                text: item.modelData.deviceName
                color: Theme.textPrimary
                font.family: "Consolas"
                font.pointSize: TypeScale.body
            }
            Text {
                visible: item.modelData.deviceName === CloudClient.deviceName
                text: "当前"
                color: Theme.brand
                font.family: TypeScale.family
                font.pointSize: TypeScale.caption
                font.weight: TypeScale.weightMedium
            }
        }
    }

    // 名单要主动去问，且在线状态会变（装壳时断电、下一批换卡），周期性重刷。
    // 15s 是"谁在线"的粒度，不是心跳粒度，不用更快。
    Component.onCompleted: CloudClient.refreshDevices()

    Connections {
        target: CloudClient
        // 切产品后 productId 变了，名单要重问 —— 这就是"按产品过滤"的入口
        function onDeviceChanged() { poll.restart(); }
    }

    Timer {
        id: poll
        interval: 15000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: CloudClient.refreshDevices()
    }
}
