import QtQuick
import ptest
import QtQuick.Controls
import QtQuick.Layouts

// 未实现工位的占位页。
//
// 为什么要有这一页而不是干脆不列这个工位:工位存在于产品的工艺路线里是事实,
// 软件没做是我们的进度。列出来并标明"待实现",产线和工艺看一眼就知道这台
// 工具覆盖到哪、还差哪 —— 藏起来只会让人以为该工位不需要测,到量产才发现漏项。
//
// 真实实现时把对应 station.key 的 pending 去掉、在 Main 的路由里接上真实页面即可,
// 本页无需改动。
Item {
    id: root

    // 工位定义(来自产品 profile 的 stations 项)
    property var station: null

    readonly property string title: station ? station.title : ""
    readonly property string sub:   station ? station.sub : ""

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width - Theme.s6 * 2, 560)
        spacing: Theme.s5

        Icon {
            text: Icons.pending
            size: 56
            color: Theme.textDim
            Layout.alignment: Qt.AlignHCenter
        }

        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: root.title + "工位"
            color: Theme.textPrimary
            font.family: TypeScale.family
            font.pointSize: TypeScale.title
            font.weight: TypeScale.weightBold
        }

        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: "待实现"
            color: Theme.warn
            font.family: TypeScale.family
            font.pointSize: TypeScale.heading
            font.weight: TypeScale.weightBold
        }

        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: "本工位属于 " + (Session.profile ? Session.profile.name : "当前产品")
                  + " 的工艺路线（" + root.sub + "），软件尚未实现。\n"
                  + "测试项定义、判定阈值与工装接口待与产测工程确认后开发。"
            color: Theme.textSecondary
            font.family: TypeScale.family
            font.pointSize: TypeScale.body
            lineHeight: 1.35
        }
    }
}
