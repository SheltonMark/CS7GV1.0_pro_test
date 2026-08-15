import QtQuick
import ptest
import QtQuick.Effects

// 基础卡片:统一圆角/描边/内距 + 投影。
// Uniform Connectedness —— 同框即同组。投影给层次感，让卡片"浮"在底色上，
// 而不是一堆描边框拼在一起(那是之前看起来像线框图的主因)。
Item {
    id: root

    default property alias content: inner.data
    property string title: ""
    property alias titleIcon: heading.icon
    property int pad: Theme.s4
    property color tint: Theme.surface

    // fitContent=true:高度由内容决定。放在 ColumnLayout 里且不 fillHeight 的卡片
    // 必须开这个,否则 implicitHeight=0 会被同级 fillHeight 项压成 0。
    // 默认 false:内容 anchors.fill 撑满卡片的场景(如 ListView),开了会成绑定环。
    property bool fitContent: false

    implicitHeight: fitContent
        ? (heading.visible ? heading.implicitHeight + Theme.s3 : 0)
          + inner.childrenRect.height + pad * 2
        : 0

    Rectangle {
        id: plate
        anchors.fill: parent
        color: root.tint
        radius: Theme.radiusLg
        border.width: 1
        border.color: Theme.borderSoft

        // 顶部高光:1px 微亮内描边，模拟受光面。成本几乎为零，
        // 但能把"平面色块"变成"有厚度的面板"。
        Rectangle {
            anchors { left: parent.left; right: parent.right; top: parent.top }
            anchors.margins: 1
            height: 1
            color: Qt.rgba(1, 1, 1, 0.05)
        }
    }

    // 投影。MultiEffect 是 Qt6 原生、GPU 合成，比 Qt5Compat 的
    // DropShadow 便宜得多，不做实时模糊采样。
    layer.enabled: true
    layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: Qt.rgba(0, 0, 0, 0.45)
        shadowBlur: 0.55
        shadowVerticalOffset: 2
        shadowHorizontalOffset: 0
    }

    Row {
        id: heading
        property string icon: ""
        visible: root.title.length > 0
        spacing: Theme.s2
        anchors {
            left: parent.left; top: parent.top; right: parent.right
            leftMargin: pad; topMargin: pad; rightMargin: pad
        }

        Icon {
            visible: heading.icon.length > 0
            text: heading.icon
            size: 13
            color: Theme.brand
            anchors.verticalCenter: label.verticalCenter
        }

        Text {
            id: label
            text: root.title
            color: Theme.textSecondary
            font.family: TypeScale.family
            font.pointSize: TypeScale.caption
            font.weight: TypeScale.weightMedium
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1.2
        }
    }

    Item {
        id: inner
        anchors {
            left: parent.left; right: parent.right
            top: heading.visible ? heading.bottom : parent.top
            bottom: parent.bottom
            leftMargin: pad; rightMargin: pad; bottomMargin: pad
            topMargin: heading.visible ? Theme.s3 : pad
        }
    }
}
