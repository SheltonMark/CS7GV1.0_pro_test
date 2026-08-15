import QtQuick
import ptest
import QtQuick.Controls

// 测试项行:大号复选框 + 名称 + 读数 + 状态。
// 三态分色是关键 —— 灰=设备不支持(正常跳过)、红=profile要但设备缺(疑似没接线)。
Rectangle {
    property var model: ({})

    readonly property int st: model.state !== undefined ? model.state : 0
    readonly property bool unsupported: st === 4
    readonly property bool missingCap: st === 5

    height: Theme.hit + Theme.s2
    radius: Theme.radius
    color: hover.hovered && !unsupported ? Theme.surfaceAlt : "transparent"

    HoverHandler { id: hover }

    Behavior on color { ColorAnimation { duration: Theme.durFast } }

    // 左侧状态条:执行中/通过/失败一眼可辨
    Rectangle {
        width: 3
        radius: 2
        color: Theme.itemStateColor(st)
        opacity: st === 0 ? 0 : 1
        anchors {
            left: parent.left; top: parent.top; bottom: parent.bottom
            topMargin: Theme.s2; bottomMargin: Theme.s2
        }
    }

    // 外设图标。图标 + 文字双编码：工人扫一眼就知道这行测的是什么硬件，
    // 不必逐字读。图标底色跟状态走，让整行状态在外围视觉里也成立。
    Rectangle {
        id: itemIcon
        width: 30; height: 30
        radius: Theme.radius
        anchors.left: parent.left
        anchors.leftMargin: Theme.s3
        anchors.verticalCenter: parent.verticalCenter

        readonly property color tone: Theme.itemStateColor(st)
        color: st === 0 || unsupported
               ? Qt.rgba(1, 1, 1, 0.04)
               : Qt.rgba(tone.r, tone.g, tone.b, 0.13)
        Behavior on color { ColorAnimation { duration: Theme.durFast } }

        Icon {
            anchors.centerIn: parent
            text: Icons.forItem(model.item !== undefined ? model.item : -1)
            size: 15
            color: unsupported ? Theme.textDim
                   : (st === 0 ? Theme.textSecondary : itemIcon.tone)
            Behavior on color { ColorAnimation { duration: Theme.durFast } }
        }
    }

    Column {
        anchors {
            left: itemIcon.right; right: statusCol.left
            leftMargin: Theme.s3; rightMargin: Theme.s3
            verticalCenter: parent.verticalCenter
        }
        spacing: 2

        Text {
            text: model.name !== undefined ? model.name : ""
            color: unsupported ? Theme.textDim : Theme.textPrimary
            font.family: TypeScale.family
            font.pointSize: TypeScale.body
            font.weight: TypeScale.weightMedium
        }
        Text {
            text: {
                if (missingCap) return "设备未上报能力，检查接线";
                if (model.reading !== undefined && model.reading.length > 0) return model.reading;
                return model.detail !== undefined ? model.detail : "";
            }
            color: missingCap ? Theme.fail : Theme.textSecondary
            font.family: missingCap ? TypeScale.family : "Consolas"
            font.pointSize: TypeScale.caption
            elide: Text.ElideRight
            width: parent.width
        }
    }

    Row {
        id: statusCol
        spacing: Theme.s2
        anchors.right: parent.right
        anchors.rightMargin: Theme.s3
        anchors.verticalCenter: parent.verticalCenter

        BusyIndicator {
            running: st === 1
            visible: st === 1
            implicitWidth: 18
            implicitHeight: 18
            anchors.verticalCenter: parent.verticalCenter
        }

        // 状态徽标:图标 + 文字。色盲工人靠图标形状也能区分通过/失败，
        // 不能只靠红绿 —— 红绿色盲在男性中约 8%。
        Rectangle {
            visible: st !== 0 && st !== 1
            width: badgeRow.implicitWidth + Theme.s3
            height: 24
            radius: 12
            anchors.verticalCenter: parent.verticalCenter

            readonly property color tone: Theme.itemStateColor(st)
            color: Qt.rgba(tone.r, tone.g, tone.b, 0.12)
            border.width: 1
            border.color: Qt.rgba(tone.r, tone.g, tone.b, 0.45)

            Row {
                id: badgeRow
                spacing: Theme.s1
                anchors.centerIn: parent

                Icon {
                    text: {
                        switch (st) {
                        case 2: return Icons.pass;
                        case 3: return Icons.fail;
                        case 4: return Icons.blocked;
                        case 5: return Icons.warning;
                        default: return "";
                        }
                    }
                    size: 11
                    color: Theme.itemStateColor(st)
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    text: Theme.itemStateText(st)
                    color: Theme.itemStateColor(st)
                    font.family: TypeScale.family
                    font.pointSize: TypeScale.caption
                    font.weight: TypeScale.weightMedium
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }
}
