import QtQuick
import ptest
import QtQuick.Controls
import QtQuick.Layouts

// 检查工位(第四产测阶段,评审表 §4.10)。语义 = 前几步的检查总结:
// 核对四时间戳/时序/信息完整性,全过才允许写检查标识(Stage=4)。
//
// 三条已定协议(勿改):
// 1. 页面可用性只看设备在线,不看 ProductTestInfo.Active —— 检查排在成品后,
//    设备已退出产测态(Active=false),但产测指令刻意保持常驻受理。
// 2. 超时重试必须复用同一 Timestamp(换新值=多一次 flash 擦写+台账漂移),
//    RequestId 用新的。见 inspectTs 只生成一次。
// 3. Timestamp 非法会被设备 mapper 同步拒绝且不回 ProductTestResult,
//    靠指令超时兜底(真实实现里),不能死等。
Item {
    id: root

    // ---- 设备上报(ProductTestInfo 真实回读值) ----
    property var devInfo: ({})
    function dv(key) { return devInfo[key] !== undefined ? ("" + devInfo[key]) : ""; }

    // ---- 核对项(读回后本地算) ----
    readonly property bool tsFocus:  dv("FocusTime").length > 0
    readonly property bool tsSemi:   dv("SemiTime").length > 0
    readonly property bool tsFinish: dv("FinishTime").length > 0
    readonly property bool tsAll: tsFocus && tsSemi && tsFinish
    // 17 位纯数字 YYYYMMDDHHMMSSmmm:字典序 == 时间序,直接字符串比较
    readonly property bool orderOk: tsAll
        && dv("FocusTime") <= dv("SemiTime")
        && dv("SemiTime") <= dv("FinishTime")

    readonly property var infoFields: [
        { k: "Sn",          v: dv("Sn") },
        { k: "Mac",         v: dv("Mac") },
        { k: "Uuid",        v: dv("Uuid") },
        { k: "Imei",        v: dv("Imei") },
        { k: "Suid",        v: dv("Suid") },
        { k: "Language",    v: dv("Language") },
        { k: "ProductKey",  v: dv("ProductKey") },
        { k: "DeviceName",  v: dv("DeviceName") },
        { k: "SecretCrc32", v: dv("SecretCrc32") }
    ]
    readonly property bool infoOk: infoFields.every(f => f.v.length > 0)
    // §2.6:zlib CRC32(DeviceSecret明文+ProductSecret明文),8 位大写 hex。
    // 本地明文按设备 MAC 从 InputData1 批次检索;检查工位没导批次时退化为
    // 只查非空(明文不在设备回报里,无从比对)。
    readonly property string localCrc: {
        const i = Session.batchIndexOfMac(dv("Mac"));
        if (i < 0) return "";
        const rec = Session.batchRecords[i];
        return CloudClient.crc32Hex(rec[4] + rec[6]);
    }
    readonly property bool crcOk: dv("SecretCrc32").length > 0
        && (localCrc.length === 0 || localCrc === dv("SecretCrc32"))

    readonly property bool allPass: tsAll && orderOk && infoOk && crcOk

    // ---- 写检查标识(真实指令闭环) ----
    property bool writing: false
    property bool done: false
    property string inspectTs: ""      // 协议要点2:首次生成,重试复用
    property int inspectReqId: -1

    function nowTs17() {
        return Qt.formatDateTime(new Date(), "yyyyMMddHHmmsszzz");
    }

    function writeInspectStage() {
        if (inspectTs.length === 0)
            inspectTs = nowTs17();     // 只生成一次(重试换 Timestamp=多次擦写+台账漂移)
        writing = true;
        inspectReqId = CloudClient.writeStage(4, inspectTs);   // RequestId 每次新
        flowLog.insert(0, { rid: inspectReqId, cmd: "PtestWriteStage", item: "检查",
                            code: -1, detail: "等待设备回报…" });
    }

    Connections {
        target: CloudClient
        function onInfoUpdated(info) { root.devInfo = info; }
        function onCommandFinished(requestId, command, item, code, detail) {
            if (requestId !== root.inspectReqId) return;
            root.inspectReqId = -1;
            root.writing = false;
            flowLog.setProperty(0, "code", code);
            flowLog.setProperty(0, "detail", code === 0 ? "ok"
                : "Code=" + code + (detail.length > 0 ? " " + detail : ""));
            if (code === 0) {
                root.done = true;
                toast.show("检查标识写入成功  " + root.inspectTs, true);
                CloudClient.refreshInfo();    // 回读刷新 InspectTime
            } else {
                toast.show("检查标识写入失败  Code=" + code, false);
            }
        }
        function onCommandTimeout(requestId) {
            if (requestId !== root.inspectReqId) return;
            root.inspectReqId = -1;
            root.writing = false;
            flowLog.setProperty(0, "code", -2);
            flowLog.setProperty(0, "detail", "超时 — 可重试(复用同 Timestamp)");
            toast.show("写检查标识超时，可重试", false);
        }
        function onCommandFailed(requestId, error) {
            if (requestId !== root.inspectReqId) return;
            root.inspectReqId = -1;
            root.writing = false;
            flowLog.setProperty(0, "code", -3);
            flowLog.setProperty(0, "detail", error);
        }
    }

    Component.onCompleted: CloudClient.refreshInfo()

    ListModel { id: flowLog }

    Toast { id: toast }

    ConfirmDialog { id: confirm }

    // 单行核对项
    component CheckRow: RowLayout {
        property bool ok: false
        property string label: ""
        property string value: ""
        spacing: Theme.s2

        Icon {
            text: ok ? Icons.pass : Icons.fail
            size: 14
            color: ok ? Theme.pass : Theme.fail
        }
        Text {
            text: label
            color: Theme.textSecondary
            font.family: TypeScale.family
            font.pointSize: TypeScale.body
            Layout.preferredWidth: 150
        }
        Text {
            text: value
            color: ok ? Theme.textPrimary : Theme.fail
            font.family: "Consolas"
            font.pointSize: TypeScale.body
            elide: Text.ElideRight
            Layout.fillWidth: true
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: Theme.s5
        spacing: Theme.s4

        // ---- 左:两步卡片 ----
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.s4

            Card {
                title: "第 1 步  ·  读取并核对"
                titleIcon: Icons.navInspect
                fitContent: true
                Layout.fillWidth: true

                ColumnLayout {
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    spacing: Theme.s3

                    // 1) 前三阶段时间戳(空 = 漏测/跳站,四时间戳字段的设计目的)
                    CheckRow { Layout.fillWidth: true; ok: root.tsFocus
                        label: "调焦 FocusTime";   value: root.dv("FocusTime")  || "缺失" }
                    CheckRow { Layout.fillWidth: true; ok: root.tsSemi
                        label: "准成品 SemiTime";  value: root.dv("SemiTime")   || "缺失" }
                    CheckRow { Layout.fillWidth: true; ok: root.tsFinish
                        label: "成品 FinishTime";  value: root.dv("FinishTime") || "缺失" }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderSoft }

                    // 2) 时序(倒挂 = 返工后未重写后序标识)
                    CheckRow { Layout.fillWidth: true; ok: root.orderOk
                        label: "时序核对"
                        value: root.orderOk ? "Focus ≤ Semi ≤ Finish"
                                            : "时间倒挂 —— 返工后未重写后序标识" }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderSoft }

                    // 3) 信息完整(9 字段逐项)
                    Flow {
                        Layout.fillWidth: true
                        spacing: Theme.s2

                        Repeater {
                            model: root.infoFields
                            Rectangle {
                                required property var modelData
                                readonly property bool ok: modelData.v.length > 0
                                width: chipRow.implicitWidth + Theme.s3
                                height: 24
                                radius: 12
                                color: ok ? Qt.rgba(0.133, 0.773, 0.369, 0.10)
                                          : Qt.rgba(0.937, 0.267, 0.267, 0.14)
                                border.width: 1
                                border.color: ok ? Qt.rgba(0.133, 0.773, 0.369, 0.35)
                                                 : Qt.rgba(0.937, 0.267, 0.267, 0.55)
                                Row {
                                    id: chipRow
                                    anchors.centerIn: parent
                                    spacing: Theme.s1
                                    Icon {
                                        text: parent.parent.ok ? Icons.pass : Icons.fail
                                        size: 10
                                        color: parent.parent.ok ? Theme.pass : Theme.fail
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Text {
                                        text: modelData.k
                                        color: parent.parent.ok ? Theme.textSecondary : Theme.fail
                                        font.family: TypeScale.family
                                        font.pointSize: TypeScale.caption
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                            }
                        }
                    }

                    // SecretCrc32 一致性(设备回报 vs 本地按 §2.6 算得)
                    CheckRow { Layout.fillWidth: true; ok: root.crcOk
                        label: "密钥校验一致"
                        value: "设备 " + (root.dv("SecretCrc32") || "—")
                               + "  ·  本地 " + (root.localCrc || "未导批次(仅查非空)") }

                    // 引导:任一 ✗ 时告诉工人去哪补救
                    Text {
                        visible: !root.allPass
                        Layout.fillWidth: true
                        text: {
                            if (!root.tsAll) return "有阶段时间戳缺失 —— 回对应工位补测后再检查。";
                            if (!root.orderOk) return "时间倒挂 —— 回后序工位重写标识。";
                            if (!root.crcOk) return "密钥校验不符 —— 转维修工位清除后重新产测。";
                            return "信息字段缺失 —— 回准成品/成品工位补写 InputData/SUID。";
                        }
                        color: Theme.warn
                        font.family: TypeScale.family
                        font.pointSize: TypeScale.body
                        wrapMode: Text.WordWrap
                    }

                    AppButton {
                        text: "重新读取"
                        glyph: Icons.reset
                        width: 132
                        onClicked: CloudClient.refreshInfo()
                    }
                }
            }

            Card {
                title: "第 2 步  ·  写检查标识"
                titleIcon: Icons.save
                fitContent: true
                Layout.fillWidth: true

                ColumnLayout {
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    spacing: Theme.s3

                    Text {
                        Layout.fillWidth: true
                        text: "全部核对通过后下发 PtestWriteStage（Stage=4，Timestamp=PC 当前时间），"
                            + "以 ProductTestResult 回 Code=0 为完成。"
                        color: Theme.textSecondary
                        font.family: TypeScale.family
                        font.pointSize: TypeScale.body
                        wrapMode: Text.WordWrap
                    }

                    Row {
                        spacing: Theme.s3

                        AppButton {
                            text: root.done ? "检查完成" : "写入检查标识"
                            glyph: root.done ? Icons.pass : Icons.save
                            kind: root.done ? "normal" : "primary"
                            enabled: root.allPass && !root.writing && !root.done
                            width: 176
                            onClicked: confirm.ask("写入检查标识？",
                                "将写入检查完成时间戳（Stage=4），完成后整机产测通过判据满足。",
                                function () { root.writeInspectStage() })
                        }

                        Text {
                            visible: !root.allPass
                            text: "有核对项未通过"
                            color: Theme.warn
                            font.family: TypeScale.family
                            font.pointSize: TypeScale.body
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Row {
                            visible: root.done
                            spacing: Theme.s2
                            anchors.verticalCenter: parent.verticalCenter
                            Icon {
                                text: Icons.pass
                                size: 14
                                color: Theme.pass
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: "InspectTime  " + root.inspectTs
                                color: Theme.pass
                                font.family: "Consolas"
                                font.pointSize: TypeScale.body
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                }
            }

            Item { Layout.fillHeight: true }
        }

        // ---- 右:结果爆点 + 指令流水 ----
        ColumnLayout {
            Layout.preferredWidth: 320
            Layout.fillWidth: false
            Layout.fillHeight: true
            spacing: Theme.s4

            ResultBanner {
                Layout.fillWidth: true
                Layout.preferredHeight: 160
                state_: root.done ? "pass" : (root.writing ? "running" : "idle")
                caption: root.done ? "检查完成，可流转" :
                         (root.writing ? "写检查标识 · 等待设备回报"
                                       : (root.allPass ? "核对通过，待写标识" : "有核对项未通过"))
            }

            Card {
                title: "指令流水  ·  RequestId 关联"
                titleIcon: Icons.history
                Layout.fillWidth: true
                Layout.fillHeight: true

                ListView {
                    anchors.fill: parent
                    clip: true
                    spacing: Theme.s1
                    model: flowLog
                    ScrollBar.vertical: ScrollBar {}

                    delegate: Item {
                        required property var model
                        width: ListView.view.width
                        height: 46

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            spacing: 1

                            Row {
                                spacing: Theme.s2
                                Text {
                                    text: "#" + model.rid
                                    color: Theme.accent
                                    font.family: "Consolas"
                                    font.pointSize: TypeScale.caption
                                }
                                Text {
                                    text: model.cmd
                                    color: Theme.textPrimary
                                    font.family: TypeScale.family
                                    font.pointSize: TypeScale.caption
                                    font.weight: TypeScale.weightMedium
                                }
                                Text {
                                    text: model.item
                                    color: Theme.textDim
                                    font.family: TypeScale.family
                                    font.pointSize: TypeScale.caption
                                }
                            }
                            Text {
                                text: model.detail
                                color: model.code === 0 ? Theme.pass
                                       : (model.code < 0 ? Theme.running : Theme.fail)
                                font.family: "Consolas"
                                font.pointSize: TypeScale.caption
                                elide: Text.ElideRight
                                width: parent.width
                            }
                        }
                    }
                }
            }
        }
    }
}
