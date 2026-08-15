import QtQuick
import ptest

// 键值行。label 定宽对齐,value 等宽字体 —— SN/IMEI/CRC 这类要逐字核对。
Item {
    property string label: ""
    property string value: ""
    property bool mono: true
    property color valueColor: Theme.textPrimary

    implicitHeight: Math.max(t1.implicitHeight, t2.implicitHeight)

    Text {
        id: t1
        text: label
        color: Theme.textSecondary
        font.family: TypeScale.family
        font.pointSize: TypeScale.body
        width: 92
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
    }

    Text {
        id: t2
        text: value.length > 0 ? value : "—"
        color: value.length > 0 ? valueColor : Theme.textDim
        font.family: mono ? "Consolas" : TypeScale.family
        font.pointSize: TypeScale.body
        font.weight: TypeScale.weightMedium
        elide: Text.ElideRight
        anchors {
            left: t1.right; right: parent.right
            leftMargin: Theme.s3
            verticalCenter: parent.verticalCenter
        }
    }
}
