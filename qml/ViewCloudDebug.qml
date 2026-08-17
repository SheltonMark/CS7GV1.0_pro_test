import QtQuick
import ptest
import QtQuick.Controls
import QtQuick.Layouts

// 云链路调试页（联调用，非工位）。目标：不进任何工位流程就能
//   ① 看当前传输形态（Mock 假设备 / 腾讯云直连，由 cloud_config.json 决定）
//   ② 逐条下发 5 个产测 action，盯"受理→设备执行→上报"的完整闭环
//   ③ 随时读 ProductTestInfo 汇总
// 工位页接真实流程前，所有链路问题先在这页定位——工位页保持 Mock 数据不动。
Item {
    id: root

    // 日志上限：联调一天几千条封顶，500 够回看且不吃内存
    readonly property int maxLogLines: 500

    function appendLog(line) {
        logModel.append({ line: line });
        if (logModel.count > root.maxLogLines)
            logModel.remove(0, logModel.count - root.maxLogLines);
        logView.positionViewAtEnd();
    }

    // 17 位 YYYYMMDDHHMMSSmmm——写阶段用 PC 时钟（产线台账以 PC 时间为准）
    function nowStamp17() {
        return Qt.formatDateTime(new Date(), "yyyyMMddHHmmsszzz");
    }

    Connections {
        target: CloudClient
        function onLogLine(line) { root.appendLog(line); }
        function onCommandFinished(requestId, command, item, code, detail) {
            root.appendLog(code === 0 ? "        ✅ 通过"
                                      : "        ❌ 失败 Code=" + code
                                        + (detail.length > 0 ? " " + detail : ""));
        }
        function onCommandTimeout(requestId) { root.appendLog("        ❌ 等结果超时"); }
        function onCommandFailed(requestId, error) { root.appendLog("        ❌ 通道错误"); }
        function onInfoUpdated(info) { infoText.text = JSON.stringify(info, null, 2); }
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: Theme.s5
        spacing: Theme.s4

        // ---- 左列：链路状态 + 指令面板 + 产测信息 ----
        ColumnLayout {
            Layout.preferredWidth: 460
            Layout.fillHeight: true
            spacing: Theme.s4

            Card {
                title: "链路"
                titleIcon: Icons.cloud
                fitContent: true
                Layout.fillWidth: true

                ColumnLayout {
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    spacing: Theme.s3

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.s2

                        Rectangle {
                            width: modeText.implicitWidth + Theme.s4
                            height: 26; radius: 13
                            color: CloudClient.mode === "mock"
                                   ? Qt.rgba(1, 1, 1, 0.06) : Theme.brandWash
                            border.width: 1
                            border.color: CloudClient.mode === "mock"
                                          ? Theme.borderSoft : Theme.brandEdge
                            Text {
                                id: modeText
                                anchors.centerIn: parent
                                text: CloudClient.mode === "mock" ? "Mock 假设备" : "腾讯云直连"
                                color: CloudClient.mode === "mock" ? Theme.textSecondary : Theme.brand
                                font.family: TypeScale.family
                                font.pointSize: TypeScale.caption
                            }
                        }

                        Item { Layout.fillWidth: true }

                        AppButton {
                            text: "重载配置"
                            glyph: Icons.reset
                            implicitHeight: Theme.hit - 10
                            onClicked: CloudClient.reloadConfig()
                        }
                    }

                    FieldRow {
                        Layout.fillWidth: true
                        label: "ProductId"
                        value: CloudClient.productId
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.s3
                        Text {
                            text: "DeviceName"
                            color: Theme.textDim
                            font.family: TypeScale.family
                            font.pointSize: TypeScale.caption
                        }
                        TextField {
                            id: deviceField
                            Layout.fillWidth: true
                            text: CloudClient.deviceName
                            font.family: "Consolas"
                            font.pointSize: TypeScale.body
                            onEditingFinished: CloudClient.deviceName = text
                        }
                    }
                }
            }

            Card {
                title: "指令"
                titleIcon: Icons.play
                fitContent: true
                Layout.fillWidth: true

                ColumnLayout {
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    spacing: Theme.s3

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.s2
                        ComboBox {
                            id: stageBox
                            Layout.fillWidth: true
                            model: ["1 调焦", "2 准成品", "3 成品", "4 检查"]
                        }
                        AppButton {
                            text: "写阶段"
                            glyph: Icons.save
                            kind: "primary"
                            enabled: !CloudClient.busy
                            implicitHeight: Theme.hit - 10
                            onClicked: CloudClient.writeStage(stageBox.currentIndex + 1,
                                                              root.nowStamp17())
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.s2
                        ComboBox {
                            id: itemBox
                            Layout.fillWidth: true
                            model: ["0 指示灯", "1 红外灯", "2 白光灯", "3 日夜切换",
                                    "4 复位按键", "5 电池", "6 云台", "7 喇叭",
                                    "8 咪头", "9 4G", "10 SD卡"]
                        }
                        ComboBox {
                            id: opBox
                            Layout.preferredWidth: 130
                            model: ["0 查询", "1 开启", "2 关闭", "3 切换", "4 执行"]
                        }
                        AppButton {
                            text: "外设"
                            glyph: Icons.play
                            enabled: !CloudClient.busy
                            implicitHeight: Theme.hit - 10
                            onClicked: CloudClient.peripheralTest(itemBox.currentIndex,
                                                                  opBox.currentIndex, 0, 0, "")
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.s2
                        TextField {
                            id: snField
                            Layout.fillWidth: true
                            placeholderText: "SN（空=不写）"
                            font.family: "Consolas"
                            font.pointSize: TypeScale.body
                        }
                        TextField {
                            id: macField
                            Layout.fillWidth: true
                            placeholderText: "MAC（空=不写）"
                            font.family: "Consolas"
                            font.pointSize: TypeScale.body
                        }
                        AppButton {
                            text: "写身份"
                            glyph: Icons.save
                            enabled: !CloudClient.busy
                            implicitHeight: Theme.hit - 10
                            onClicked: CloudClient.writeIdentity({ Sn: snField.text,
                                                                   Mac: macField.text })
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.s2
                        TextField {
                            id: suidField
                            Layout.fillWidth: true
                            placeholderText: "SUID（加密串号）"
                            font.family: "Consolas"
                            font.pointSize: TypeScale.body
                        }
                        AppButton {
                            text: "写SUID"
                            glyph: Icons.save
                            enabled: !CloudClient.busy
                            implicitHeight: Theme.hit - 10
                            onClicked: CloudClient.writeSuid(suidField.text)
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.s2
                        AppButton {
                            text: "读产测信息"
                            glyph: Icons.history
                            implicitHeight: Theme.hit - 10
                            onClicked: CloudClient.refreshInfo()
                        }
                        AppButton {
                            text: "清配置"
                            glyph: Icons.reset
                            implicitHeight: Theme.hit - 10
                            // 通用 action(恢复出厂),受理即完成,结果看流水
                            onClicked: CloudClient.invokeGenericAction("SetDefaultDevConfigs")
                        }
                        AppButton {
                            text: "关机120s"
                            glyph: Icons.reboot
                            enabled: !CloudClient.busy
                            implicitHeight: Theme.hit - 10
                            onClicked: CloudClient.shutdownDevice(120)
                        }
                        Item { Layout.fillWidth: true }
                        AppButton {
                            text: "清标识"
                            glyph: Icons.erase
                            kind: "danger"
                            enabled: !CloudClient.busy
                            implicitHeight: Theme.hit - 10
                            onClicked: CloudClient.clearPartition(1)
                        }
                        AppButton {
                            text: "全清"
                            glyph: Icons.erase
                            kind: "danger"
                            enabled: !CloudClient.busy
                            implicitHeight: Theme.hit - 10
                            onClicked: CloudClient.clearPartition(0)
                        }
                    }
                }
            }

            Card {
                title: "产测信息 ProductTestInfo"
                titleIcon: Icons.device
                Layout.fillWidth: true
                Layout.fillHeight: true

                ScrollView {
                    anchors.fill: parent
                    clip: true
                    TextArea {
                        id: infoText
                        readOnly: true
                        text: "（点「读产测信息」拉取）"
                        wrapMode: TextArea.Wrap
                        background: null
                        color: Theme.textSecondary
                        font.family: "Consolas"
                        font.pointSize: TypeScale.caption
                    }
                }
            }
        }

        // ---- 右列：指令流水 ----
        Card {
            title: "指令流水"
            titleIcon: Icons.history
            Layout.fillWidth: true
            Layout.fillHeight: true

            ListView {
                id: logView
                anchors.fill: parent
                clip: true
                spacing: 2
                model: ListModel { id: logModel }

                delegate: Text {
                    required property string line
                    width: logView.width
                    text: line
                    color: line.indexOf("❌") >= 0 || line.indexOf("✗") >= 0
                             || line.indexOf("⏱") >= 0 ? Theme.fail
                           : line.indexOf("✅") >= 0 ? Theme.pass
                           : line.indexOf("←") >= 0 ? Theme.textPrimary
                           : Theme.textSecondary
                    font.family: "Consolas"
                    font.pointSize: TypeScale.caption
                    wrapMode: Text.WrapAnywhere
                }
            }
        }
    }
}
