import QtQuick
import ptest
import QtQuick.Controls

// 产测 PC 客户端。目前只有 UI 外观，数据全来自 MockData.qml。
// 构建见根目录 README.md
ApplicationWindow {
    id: win
    width: 1440
    height: 900
    minimumWidth: 1180
    minimumHeight: 720
    visible: true
    title: "产测工具"
    color: Theme.bg

    // 必须显式钉强调色。FluentWinUI3 默认跟随 Windows 系统强调色 ——
    // 产线机器若系统色是红色，复选框/主按钮会变红，与 FAIL 语义直接撞车。
    // 注意：qtquickcontrols2.conf 里写 Accent= 无效，只有 palette.accent 生效。
    palette.accent: Theme.accent

    NavRail {
        id: rail
        width: 96
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
    }

    TopBar {
        id: bar
        height: 76
        anchors { left: rail.right; right: parent.right; top: parent.top }
        station: rail.entries[rail.currentIndex].key
        isStation: rail.currentIndex <= 3
        online: true
    }

    StackLayout_ {
        anchors {
            left: rail.right; right: parent.right
            top: bar.bottom; bottom: parent.bottom
        }
        index: rail.currentIndex
    }

    // 极简栈:只让当前页可见,并做一次淡入(全屏转场 300-400ms 预算内)
    component StackLayout_: Item {
        property int index: 0

        ViewFocus    { anchors.fill: parent; visible: index === 0; opacity: visible ? 1 : 0
                       Behavior on opacity { NumberAnimation { duration: Theme.durSlow } } }
        ViewFinished { anchors.fill: parent; visible: index === 1; semi: true
                       opacity: visible ? 1 : 0
                       Behavior on opacity { NumberAnimation { duration: Theme.durSlow } } }
        ViewFinished { anchors.fill: parent; visible: index === 2
                       opacity: visible ? 1 : 0
                       Behavior on opacity { NumberAnimation { duration: Theme.durSlow } } }
        ViewRepair   { anchors.fill: parent; visible: index === 3; opacity: visible ? 1 : 0
                       Behavior on opacity { NumberAnimation { duration: Theme.durSlow } } }
        ViewProfile  { anchors.fill: parent; visible: index === 4; opacity: visible ? 1 : 0
                       Behavior on opacity { NumberAnimation { duration: Theme.durSlow } } }
        ViewAbout    { anchors.fill: parent; visible: index === 5; opacity: visible ? 1 : 0
                       Behavior on opacity { NumberAnimation { duration: Theme.durSlow } } }
    }
}
