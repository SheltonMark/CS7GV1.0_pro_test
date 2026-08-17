import QtQuick
import ptest
import QtQuick.Controls
import QtQuick.Layouts

// 维修工位 —— 唯一有不可逆操作的一屏,设计重心是"防手滑"。
// 清除会擦掉身份+SUID,所以:先存档、再二次确认、危险按钮不做主色。
Item {
    id: root
    property bool archived: false

    // ---- 云链路(2026-08-17 接入):读上报 + 真实清除/恢复默认 ----
    property var devInfo: ({})
    property int clearReqId: -1
    property bool restorePending: false

    function dv(key) {
        return devInfo[key] !== undefined && devInfo[key] !== "" ? devInfo[key] : "—";
    }

    ConfirmDialog { id: confirm }
    Toast { id: toast }

    ListModel { id: flowLog }

    Connections {
        target: CloudClient
        function onInfoUpdated(info) { root.devInfo = info; }
        function onCommandFinished(requestId, command, item, code, detail) {
            if (requestId !== root.clearReqId) return;
            root.clearReqId = -1;
            flowLog.insert(0, { line: (code === 0 ? "✅ 清除完成"
                                       : "❌ 清除失败 Code=" + code)
                                      + (detail.length > 0 ? "  " + detail : "") });
            toast.show(code === 0 ? "加密分区清除完成" : "清除失败  Code=" + code,
                       code === 0);
            if (code === 0) CloudClient.refreshInfo();   // 回读:身份字段应已清空
        }
        function onCommandTimeout(requestId) {
            if (requestId !== root.clearReqId) return;
            root.clearReqId = -1;
            flowLog.insert(0, { line: "❌ 清除超时，可重试" });
            toast.show("清除超时，可重试", false);
        }
        function onCommandFailed(requestId, error) {
            if (requestId !== root.clearReqId) return;
            root.clearReqId = -1;
            flowLog.insert(0, { line: "❌ 通道错误: " + error });
        }
        function onGenericActionDone(actionId, ok, error) {
            if (actionId !== "SetDefaultDevConfigs" || !root.restorePending) return;
            root.restorePending = false;
            flowLog.insert(0, { line: ok ? "✅ 恢复默认已受理"
                                         : "❌ 恢复默认失败: " + error });
            toast.show(ok ? "恢复默认配置已下发" : "恢复默认失败: " + error, ok);
        }
    }

    Component.onCompleted: CloudClient.refreshInfo()

    RowLayout {
        anchors.fill: parent
        anchors.margins: Theme.s5
        spacing: Theme.s4

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.s4

            Card {
                title: "第 1 步  ·  读产测信息并存档"
                titleIcon: Icons.save
                fitContent: true
                Layout.fillWidth: true

                ColumnLayout {
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    spacing: Theme.s3

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: Theme.s6
                        rowSpacing: Theme.s3

                        FieldRow { Layout.fillWidth: true; label: "SN";   value: root.dv("Sn") }
                        FieldRow { Layout.fillWidth: true; label: "IMEI"; value: root.dv("Imei") }
                        FieldRow { Layout.fillWidth: true; label: "UUID"; value: root.dv("Uuid") }
                        FieldRow { Layout.fillWidth: true; label: "MAC";  value: root.dv("Mac") }
                    }

                    Row {
                        spacing: Theme.s3
                        AppButton {
                            text: root.archived ? "已存档" : "读取并存档"
                            glyph: root.archived ? Icons.pass : Icons.save
                            kind: root.archived ? "normal" : "primary"
                            enabled: !root.archived
                            width: 168
                            onClicked: {
                                CloudClient.refreshInfo();   // 存档前取最新回读值
                                root.archived = true;
                            }
                        }
                        Row {
                            visible: root.archived
                            spacing: Theme.s2
                            anchors.verticalCenter: parent.verticalCenter
                            Icon {
                                text: Icons.pass
                                size: 14
                                color: Theme.pass
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: "已读取（台账落库待接 SQLite）"
                                color: Theme.pass
                                font.family: TypeScale.family
                                font.pointSize: TypeScale.body
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                }
            }

            // 危险区:视觉上与正常流程隔开
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: dangerCol.implicitHeight + Theme.s5 * 2
                radius: Theme.radiusLg
                color: Qt.rgba(Theme.fail.r, Theme.fail.g, Theme.fail.b, 0.05)
                border.width: 1
                border.color: Qt.rgba(Theme.fail.r, Theme.fail.g, Theme.fail.b, 0.4)

                ColumnLayout {
                    id: dangerCol
                    anchors {
                        left: parent.left; right: parent.right; top: parent.top
                        margins: Theme.s5
                    }
                    spacing: Theme.s3

                    Text {
                        text: "第 2 步  ·  清除加密分区（不可逆）"
                        color: Theme.fail
                        font.family: TypeScale.family
                        font.pointSize: TypeScale.heading
                        font.weight: TypeScale.weightBold
                    }
                    Text {
                        Layout.fillWidth: true
                        text: "「全部」会清掉阶段标识、身份四元组与 SUID，设备回未测态，需重新完整产测并重新下发 InputData。请先完成上一步存档。"
                        color: Theme.textSecondary
                        font.family: TypeScale.family
                        font.pointSize: TypeScale.body
                        wrapMode: Text.WordWrap
                    }

                    RowLayout {
                        spacing: Theme.s4
                        RadioButton { id: scopeOnlyBtn; text: "仅标识（保留身份）"; checked: true }
                        RadioButton { id: scopeAllBtn;  text: "全部" }
                    }

                    Row {
                        spacing: Theme.s3
                        AppButton {
                            text: "清除加密分区"
                            glyph: Icons.erase
                            kind: "danger"
                            enabled: root.archived
                            width: 176
                            onClicked: confirmDialog.open()
                        }
                        Text {
                            visible: !root.archived
                            text: "请先存档"
                            color: Theme.warn
                            font.family: TypeScale.family
                            font.pointSize: TypeScale.body
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }
            }

            Card {
                title: "第 3 步  ·  恢复默认并重启"
                titleIcon: Icons.reboot
                fitContent: true
                Layout.fillWidth: true

                Row {
                    anchors { left: parent.left; top: parent.top }
                    spacing: Theme.s3
                    AppButton {
                        text: "恢复默认配置"; glyph: Icons.reset; width: 168
                        // 覆写设备全部持久化配置 → 确认
                        onClicked: confirm.ask("恢复默认配置？",
                            "设备全部持久化配置将覆写回出厂值（SetDefaultDevConfigs）。",
                            function () {
                                root.restorePending = true;
                                flowLog.insert(0, { line: "→ 下发恢复默认配置" });
                                CloudClient.invokeGenericAction("SetDefaultDevConfigs", {});
                            })
                    }
                    AppButton {
                        text: "定时重启"; glyph: Icons.reboot; width: 146; enabled: false
                        onClicked: confirm.ask("定时重启？",
                            "设备将按配置延时重启（须先恢复默认成功）。",
                            function () { /* 真实实现:下发 Reboot(delay) */ })
                    }
                    Text {
                        text: "重启须在恢复默认成功之后"
                        color: Theme.textDim
                        font.family: TypeScale.family
                        font.pointSize: TypeScale.caption
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            Item { Layout.fillHeight: true }
        }

        Card {
            title: "指令流水  ·  RequestId 关联"
            Layout.preferredWidth: 340
            Layout.fillHeight: true

            ListView {
                anchors.fill: parent
                clip: true
                spacing: Theme.s1
                model: flowLog
                ScrollBar.vertical: ScrollBar {}

                delegate: Text {
                    required property string line
                    width: ListView.view.width
                    text: line
                    color: line.indexOf("❌") >= 0 ? Theme.fail
                           : line.indexOf("✅") >= 0 ? Theme.pass : Theme.textSecondary
                    font.family: "Consolas"
                    font.pointSize: TypeScale.caption
                    wrapMode: Text.WrapAnywhere
                }
            }
        }
    }

    Dialog {
        id: confirmDialog
        title: "确认清除加密分区？"
        modal: true
        anchors.centerIn: parent
        standardButtons: Dialog.Cancel | Dialog.Ok
        onAccepted: {
            const all = scopeAllBtn.checked;
            flowLog.insert(0, { line: "→ 清除加密分区  scope=" + (all ? "全部" : "仅标识") });
            root.clearReqId = CloudClient.clearPartition(all ? 0 : 1);
        }

        Text {
            text: "此操作不可逆。设备 " + root.dv("Sn") + " 将按「"
                  + (scopeAllBtn.checked ? "全部（标识+身份+SUID）" : "仅标识")
                  + "」范围清除。"
            color: Theme.textPrimary
            font.family: TypeScale.family
            font.pointSize: TypeScale.body
            wrapMode: Text.WordWrap
            width: 320
        }
    }
}
