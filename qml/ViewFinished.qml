import QtQuick
import ptest
import QtQuick.Controls
import QtQuick.Layouts

// 成品/准成品工位。
// 中栏 = 逐项测试(键盘流,SequentialTestPanel):队列 = 管理员勾选 ∩ 产品 profile
// ∩ 设备能力;测完出汇总页,回车确认结果后才"跳出"写标识条(成品另有 MAC 输入)。
// 写标识后自动链(全程等待层转圈):
//   准成品: 写标识(回读核对) → 配置清除 → 定时关机
//   成品:   写产测信息+成品标识 → 采集信息入库(IMEI+逐字段校验+批次回填)
//           → 配置清除 → 定时关机
Item {
    id: root
    property bool semi: false

    ConfirmDialog { id: confirm }

    // ---- 设备上报(ProductTestInfo)与能力 ----
    property var devInfo: ({})
    readonly property bool infoConnected: devInfo.SupportedItems !== undefined
    readonly property int supportedItemsLive: infoConnected ? devInfo.SupportedItems
                                                            : MockData.supportedItems

    // ---- 测试队列(需求① 2026-08-17):管理员勾选 ∩ 产品 ∩ 设备能力标记 ----
    readonly property string stationKey: semi ? "semi" : "finished"

    readonly property var checkedAutoItems: {
        if (!Session.profile) return [];
        const all = Session.profile.items.filter(b => MockData.manualBits.indexOf(b) < 0);
        const sel = FactoryConfig.stationItems(Session.profile.productId, stationKey,
                                               "auto", all);
        return all.filter(b => sel.indexOf(b) >= 0);
    }

    readonly property var checkedManualChecks: {
        const allKeys = MockData.manualChecks.map(c => c.key);
        const sel = Session.profile
                    ? FactoryConfig.stationItems(Session.profile.productId, stationKey,
                                                 "manual", allKeys)
                    : allKeys;
        return MockData.manualChecks.filter(c => sel.indexOf(c.key) >= 0);
    }

    // 先自动后人工;p1/p2 的 -1 哨兵在此解析成工厂配置值
    readonly property var testQueue: {
        var q = [];
        checkedAutoItems.forEach(function (bit) {
            const base = MockData.itemByBit(bit);
            var op = 0, p1 = 0;
            if (bit === 10) { op = 4; p1 = FactoryConfig.sdTestSizeMb; }  // SD 写读校验
            q.push({ kind: "auto", item: bit,
                     name: base ? base.name : ("bit" + bit),
                     sub: base ? base.detail : "",
                     op: op, p1: p1, p2: 0,
                     miss: (supportedItemsLive & (1 << bit)) === 0 });
        });
        checkedManualChecks.forEach(function (c) {
            q.push({ kind: "manual", item: c.item, key: c.key,
                     name: c.group + (c.short.length > 0 ? " · " + c.short : ""),
                     sub: c.label,
                     op: c.op,
                     p1: c.p1 === -1 ? FactoryConfig.whiteBrightness : c.p1,
                     p2: c.p2 === -1 ? (c.key === "led_blink" ? FactoryConfig.ledBlinkMs
                                                              : FactoryConfig.speakerRepeat)
                                     : c.p2,
                     miss: (supportedItemsLive & (1 << c.item)) === 0 });
        });
        return q;
    }

    // 结果确认门(需求补充):汇总页回车确认后才算测试完成
    readonly property bool testsClean: seqPanel.confirmed && !seqPanel.anyBad

    // ---- 写标识后的自动链 ----
    // 阶段: ""空闲 | write 写标识(成品含先写产测信息) | collect 采集入库
    //     | clear 配置清除 | shutdown 定时关机 | done 完成 | failed 失败
    property string chainPhase: ""
    property string chainError: ""
    property int identityReqId: -1
    property int writeReqId: -1
    property int imeiReqId: -1
    property int shutdownReqId: -1
    property int recIndex: -1          // 成品:本次使用的批次行
    property string sentStamp: ""      // 刚下发的时间戳(等回读确认)
    property string writtenStamp: ""   // 回读确认后的设备侧真值
    readonly property bool chainBusy: chainPhase === "write" || chainPhase === "collect"
                                      || chainPhase === "clear" || chainPhase === "shutdown"

    // ---- 成品:MAC 选中批次记录(默认带出第一条未入库,可改,双重校验) ----
    readonly property int macIndex: semi ? -1 : Session.batchIndexOfMac(macField.text)
    readonly property string macError: {
        if (semi) return "";
        if (Session.batchRecords.length === 0) return "未导入 InputData1（批次文件页）";
        if (macField.text.trim().length === 0) return "输入设备 MAC 地址";
        if (macIndex < 0) return "MAC 不在批次内";
        if (Session.batchUsed[macIndex] === 1) return "该 MAC 已被其他设备使用（已入库）";
        return "";
    }

    function refillMac() {
        if (semi) return;
        macField.text = Session.nextUnusedMac();
    }

    // 批次导入后带出第一条未用;入库成功后自动跳下一条
    Connections {
        target: Session
        function onBatchRecordsChanged() { root.refillMac(); }
        function onBatchUsedChanged() {
            if (root.semi) return;
            const idx = Session.batchIndexOfMac(macField.text);
            if (macField.text.trim().length === 0
                || (idx >= 0 && Session.batchUsed[idx] === 1))
                root.refillMac();
        }
    }

    // 设备信息取值:未上报显示 "—" 而不是空白(空白像坏了)
    function dv(key) {
        return devInfo[key] !== undefined && devInfo[key] !== "" ? devInfo[key] : "—";
    }

    function nowStamp17() {
        return Qt.formatDateTime(new Date(), "yyyyMMddHHmmsszzz");
    }

    // 工位开头同步设备时间:设备端"时间戳留空用本地时间"依赖它;台账以 PC 钟为准
    function syncDeviceTime() {
        const d = new Date();
        CloudClient.invokeGenericAction("SetDeviceTime", {
            Year: d.getFullYear(), Month: d.getMonth() + 1, Day: d.getDate(),
            Hour: d.getHours(), Minute: d.getMinutes(), Second: d.getSeconds() });
    }

    // 写标识。成品:先写产测信息(批次记录),后写成品标识 —— finishTestFlag 非空
    // 设备即按"成品"从分区加载身份,顺序反了会产出"空身份的成品"。
    function doWriteStage() {
        chainError = "";
        chainPhase = "write";
        if (!semi) {
            recIndex = macIndex;
            const rec = Session.batchRecords[recIndex];
            identityReqId = CloudClient.writeIdentity({
                Mac: rec[0], Sn: rec[1], DeviceName: rec[2], Uuid: rec[3],
                DeviceSecret: rec[4], ProductKey: rec[5], ProductSecret: rec[6],
                Language: rec[7]
            });
            return;  // 身份结果回来再写标识,见 handleResult
        }
        sentStamp = nowStamp17();
        writeReqId = CloudClient.writeStage(2, sentStamp);
    }

    function chainFail(reason) {
        chainPhase = "failed";
        chainError = reason;
        toast.show(reason, false);
    }

    function startClear() {
        chainPhase = "clear";
        CloudClient.invokeGenericAction("SetDefaultDevConfigs", {});
    }

    // 成品采集入库校验:设备回传产测信息 vs InputData1 源记录逐字段比对。
    // 密钥不比明文,比 CRC32(评审 §2.6 口径)。返回不匹配字段名列表。
    function verifyRecord(rec, info) {
        var bad = [];
        function chk(name, expect, got) {
            if (("" + expect) !== ("" + (got === undefined ? "" : got))) bad.push(name);
        }
        chk("MAC", Session.normalizeMac(rec[0]), Session.normalizeMac(info.Mac || ""));
        chk("SN", rec[1], info.Sn);
        chk("DeviceName", rec[2], info.DeviceName);
        chk("UUID", rec[3], info.Uuid);
        chk("ProductKey", rec[5], info.ProductKey);
        chk("语言", rec[7], info.Language);
        chk("密钥CRC32", CloudClient.crc32Hex(rec[4] + rec[6]), info.SecretCrc32);
        return bad;
    }

    function handleResult(requestId, code, detail) {
        if (requestId === identityReqId) {              // —— 成品:写产测信息结果
            identityReqId = -1;
            if (code === 0) {
                sentStamp = nowStamp17();               // 身份已落,再写成品标识
                writeReqId = CloudClient.writeStage(3, sentStamp);
            } else {
                chainFail("产测信息写入失败  Code=" + code
                          + (detail.length > 0 ? "  " + detail : ""));
            }
            return;
        }
        if (requestId === writeReqId) {                 // —— 写标识结果
            writeReqId = -1;
            if (code === 0) {
                CloudClient.refreshInfo();              // 回读验证,确认在 onInfoUpdated
            } else {
                sentStamp = "";
                chainFail("标识写入失败  Code=" + code
                          + (detail.length > 0 ? "  " + detail : ""));
            }
            return;
        }
        if (requestId === imeiReqId) {                  // —— 成品:4G/IMEI 指令结果
            imeiReqId = -1;
            if (code === 0) {
                CloudClient.refreshInfo();              // 取 Imei + 全量校验
            } else {
                chainFail("获取 IMEI 失败(4G)  Code=" + code
                          + (detail.length > 0 ? "  " + detail : ""));
            }
            return;
        }
        if (requestId === shutdownReqId) {              // —— 定时关机(下发成功=完成)
            shutdownReqId = -1;
            if (code === 0) {
                chainPhase = "done";
                toast.show((semi ? "准成品" : "成品") + "流程完成：设备将在 "
                           + FactoryConfig.shutdownDelaySec + " 秒后关机", true);
            } else {
                chainFail("定时关机下发失败  Code=" + code
                          + (detail.length > 0 ? "  " + detail : ""));
            }
        }
    }

    Connections {
        target: CloudClient
        function onCommandFinished(requestId, command, item, code, detail) {
            root.handleResult(requestId, code, detail);
        }
        function onCommandTimeout(requestId) {
            root.handleResult(requestId, -2, "等待设备上报超时");
        }
        function onCommandFailed(requestId, error) {
            root.handleResult(requestId, -3, error);
        }
        function onInfoUpdated(info) {
            root.devInfo = info;
            // ① 写标识回读确认 → 接续自动链
            if (root.sentStamp.length > 0) {
                const key = root.semi ? "SemiTime" : "FinishTime";
                if (info[key] === root.sentStamp) {     // 回读值==下发值,写入坐实
                    root.writtenStamp = root.sentStamp;
                    root.sentStamp = "";
                    toast.show((root.semi ? "准成品" : "成品") + "标识已写入并回读确认  "
                               + root.writtenStamp, true);
                    if (root.semi) {
                        root.startClear();               // 准成品:直接进配置清除
                    } else {
                        root.chainPhase = "collect";     // 成品:采集入库,先要 IMEI
                        root.imeiReqId = CloudClient.peripheralTest(9, 0, 0, 0, "");
                    }
                }
                return;
            }
            // ② 成品采集入库:IMEI 指令已回,此次回读做全量校验+取 IMEI
            if (root.chainPhase === "collect" && root.imeiReqId < 0 && root.recIndex >= 0) {
                const rec = Session.batchRecords[root.recIndex];
                const bad = root.verifyRecord(rec, info);
                const imei = info.Imei !== undefined ? info.Imei : "";
                if (bad.length > 0 || imei.length === 0) {
                    // 口径:校验不过 → InputData2 该行 IMEI 留空白、不置入库标记
                    root.chainFail(bad.length > 0
                        ? "产测信息校验不匹配: " + bad.join("、")
                        : "设备未上报 IMEI");
                    return;
                }
                Session.markBatchDone(root.recIndex, imei);
                toast.show("采集信息入库完成  IMEI " + imei, true);
                root.startClear();
            }
        }
        function onGenericActionDone(actionId, ok, error) {
            // 只处理本页正处于"配置清除"阶段的回执(两工位页同时监听,靠相位隔离)
            if (actionId !== "SetDefaultDevConfigs" || root.chainPhase !== "clear") return;
            if (!ok) {
                root.chainFail("配置清除下发失败: " + error);
                return;
            }
            root.chainPhase = "shutdown";
            root.shutdownReqId = CloudClient.shutdownDevice(FactoryConfig.shutdownDelaySec);
        }
    }

    Toast { id: toast }

    Component.onCompleted: {
        CloudClient.refreshInfo();   // 步骤条"连接设备"与右栏设备信息
        syncDeviceTime();            // 工位开头同步时间(设备端依赖)
        refillMac();
        seqPanel.forceActiveFocus();
    }

    // ---- 工位步骤(动态跟随;准成品写标识步文案=写准成品标识) ----
    readonly property var steps: {
        const rank = ["write", "collect", "clear", "shutdown", "done"].indexOf(chainPhase);
        var out = [
            { name: "连接设备 · 读信息",
              state: infoConnected ? 2 : 1 },
            { name: "逐项测试 " + seqPanel.settled + "/" + seqPanel.total,
              state: seqPanel.confirmed ? (seqPanel.anyBad ? 1 : 2)
                     : (seqPanel.settled > 0 || seqPanel.phase === "running"
                        || seqPanel.phase === "summary" ? 1 : 0) },
            { name: semi ? "写准成品标识" : "写成品标识",
              state: writtenStamp.length > 0 ? 2
                     : (chainPhase === "write"
                        || (testsClean && (semi || macError.length === 0)) ? 1 : 0) }
        ];
        if (!semi)
            out.push({ name: "采集信息入库",
                       state: rank > 1 ? 2 : (chainPhase === "collect" ? 1 : 0) });
        out.push({ name: "配置清除",
                   state: rank > 2 ? 2 : (chainPhase === "clear" ? 1 : 0) });
        out.push({ name: "定时关机 " + FactoryConfig.shutdownDelaySec + "s",
                   state: chainPhase === "done" ? 2
                          : (chainPhase === "shutdown" ? 1 : 0) });
        return out;
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: Theme.s5
        spacing: Theme.s4

        // ---- 左:线性流程 ----
        Card {
            title: "工位流程"
            titleIcon: Icons.navSemi
            Layout.preferredWidth: 210
            Layout.fillHeight: true

            StepList {
                anchors { left: parent.left; right: parent.right; top: parent.top }
                steps: root.steps
            }
        }

        // ---- 中:逐项测试 + (确认后)写标识条 ----
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.s4

            SequentialTestPanel {
                id: seqPanel
                Layout.fillWidth: true
                Layout.fillHeight: true
                queue: root.testQueue
            }

            // 写标识条:结果确认后才跳出(需求②/补充)。钉在中栏底部。
            Rectangle {
                visible: seqPanel.confirmed
                Layout.fillWidth: true
                Layout.preferredHeight: writeRow.implicitHeight + Theme.s3 * 2
                Layout.minimumHeight: Theme.hit + Theme.s3 * 2
                color: Theme.surface
                radius: Theme.radiusLg
                border.width: 1
                border.color: Theme.borderSoft

                RowLayout {
                    id: writeRow
                    anchors.fill: parent
                    anchors.margins: Theme.s3
                    spacing: Theme.s3

                    // 成品:MAC 输入(默认带出第一条未入库,可改,双重校验)
                    ColumnLayout {
                        visible: !root.semi
                        spacing: 2
                        Layout.preferredWidth: 230

                        TextField {
                            id: macField
                            Layout.fillWidth: true
                            placeholderText: "MAC 地址"
                            enabled: !root.chainBusy
                            font.family: "Consolas"
                            font.pointSize: TypeScale.body
                        }
                        Text {
                            Layout.fillWidth: true
                            text: root.semi ? ""
                                  : (root.macError.length > 0 ? root.macError
                                     : "SN " + Session.batchRecords[root.macIndex][1])
                            color: root.macError.length > 0 ? Theme.fail : Theme.pass
                            font.family: TypeScale.family
                            font.pointSize: TypeScale.caption
                            elide: Text.ElideRight
                        }
                    }

                    AppButton {
                        text: semi ? "写准成品标识" : "写成品标识"
                        glyph: Icons.save
                        kind: "primary"
                        enabled: root.testsClean && !root.chainBusy
                                 && root.chainPhase !== "done"
                                 && (root.semi || root.macError.length === 0)
                        onClicked: confirm.ask(
                            semi ? "写入准成品标识？" : "写入成品标识？",
                            semi ? "将写入准成品（Stage=2）时间戳并回读核对，随后自动执行：配置清除 → 定时关机（"
                                   + FactoryConfig.shutdownDelaySec + " 秒）。"
                                 : "将写入该 MAC 对应批次记录的产测信息与成品标识，随后自动执行：采集信息入库（IMEI+校验）→ 配置清除 → 定时关机（"
                                   + FactoryConfig.shutdownDelaySec + " 秒）。",
                            function () { root.doWriteStage() })
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: root.chainPhase === "failed"
                                 || (!root.testsClean && root.writtenStamp.length === 0)
                        text: {
                            if (root.chainPhase === "failed")
                                return "流程失败: " + root.chainError;
                            return "有未通过/跳过的测试项，不能写标识";
                        }
                        color: Theme.warn
                        font.family: TypeScale.family
                        font.pointSize: TypeScale.body
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }

        // ---- 右:结果 + 拉流 + 设备信息 ----
        ColumnLayout {
            Layout.preferredWidth: 320
            Layout.fillWidth: false
            Layout.fillHeight: true
            spacing: Theme.s4

            ResultBanner {
                Layout.fillWidth: true
                Layout.preferredHeight: 172
                state_: {
                    if (root.chainPhase === "failed") return "fail";
                    if (seqPanel.confirmed && seqPanel.anyBad) return "fail";
                    if (root.chainPhase === "done") return "pass";
                    if (seqPanel.confirmed) return "pass";
                    if (seqPanel.phase === "running" || seqPanel.settled > 0
                        || seqPanel.phase === "summary") return "running";
                    return "idle";
                }
                caption: {
                    if (root.chainPhase === "done")
                        return "流程完成，设备 " + FactoryConfig.shutdownDelaySec + " 秒后关机";
                    if (root.chainPhase === "failed") return "自动链失败，见底部原因";
                    if (seqPanel.confirmed)
                        return seqPanel.anyBad ? "有未通过项，转维修" : "结果已确认，可写标识";
                    if (seqPanel.phase === "summary") return "请确认测试结果（回车确认）";
                    if (seqPanel.total === 0) return "无勾选测试项";
                    return "逐项测试  " + seqPanel.settled + " / " + seqPanel.total;
                }
            }

            // 拉流小窗:这两个工位不调焦,但要确认"画面确实出来了"
            //(摄像头虚焊/排线松最容易在这暴露)。双击全屏,Esc 退回。
            Card {
                id: liveCard
                title: "实时画面"
                titleIcon: Icons.navFocus
                Layout.fillWidth: true
                Layout.preferredHeight: 180 + Theme.s6 + Theme.s4

                LivePreview {
                    anchors {
                        left: parent.left; right: parent.right; bottom: parent.bottom
                    }
                    height: 180
                    compact: true
                    showGrid: false
                    hint: ""
                    showZoomHint: false
                    onFullscreenRequested:
                        liveFull.open((root.semi ? "准成品" : "成品") + " · 实时画面")
                }
            }

            Card {
                title: "设备信息"
                titleIcon: Icons.device
                Layout.fillWidth: true
                Layout.fillHeight: true

                // 全部取设备真实上报(devInfo),未上报显示 "—"。
                // 准成品阶段设备还没写身份(成品工位才写),身份类字段只在成品显示
                //(2026-08-17 补充需求:准成品不取 IMEI)。
                Column {
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    spacing: Theme.s3

                    FieldRow { visible: !root.semi; width: parent.width; label: "IMEI"; value: root.dv("Imei") }
                    FieldRow { visible: !root.semi; width: parent.width; label: "UUID"; value: root.dv("Uuid") }
                    FieldRow { visible: !root.semi; width: parent.width; label: "MAC";  value: root.dv("Mac") }
                    FieldRow { visible: !root.semi; width: parent.width; label: "SN";   value: root.dv("Sn") }
                    FieldRow { width: parent.width; label: "软件"; value: root.dv("SwVersion") }
                    FieldRow { width: parent.width; label: "硬件"; value: root.dv("HwVersion") }
                    FieldRow {
                        visible: !root.semi
                        width: parent.width
                        label: "密钥校验"
                        value: root.dv("SecretCrc32")
                        valueColor: Theme.pass
                    }

                    Rectangle { width: parent.width; height: 1; color: Theme.border }

                    // 回读值即设备侧真值;本工位刚写入的那一行标绿
                    FieldRow {
                        width: parent.width; label: "调焦"
                        value: root.dv("FocusTime")
                    }
                    FieldRow {
                        width: parent.width; label: "准成品"
                        value: root.dv("SemiTime")
                        valueColor: (root.semi && root.writtenStamp.length > 0)
                                    ? Theme.pass : Theme.textPrimary
                    }
                    FieldRow {
                        width: parent.width; label: "成品"
                        value: root.dv("FinishTime")
                        valueColor: (!root.semi && root.writtenStamp.length > 0)
                                    ? Theme.pass : Theme.textPrimary
                    }
                    FieldRow { width: parent.width; label: "检查"; value: root.dv("InspectTime") }
                }
            }
        }
    }

    // 自动链等待层:写标识后的自动步骤期间盖住全页(样式对齐拉流建联转圈)。
    // done/failed 自动收起;MouseArea 拦截点击,链执行期间不允许任何操作。
    Rectangle {
        anchors.fill: parent
        visible: root.chainBusy
        color: Qt.rgba(0, 0, 0, 0.55)
        z: 99

        MouseArea { anchors.fill: parent }

        Column {
            anchors.centerIn: parent
            spacing: Theme.s3

            BusyIndicator {
                running: root.chainBusy
                implicitWidth: 52
                implicitHeight: 52
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Text {
                text: {
                    if (root.chainPhase === "write")
                        return root.semi ? "正在写入准成品标识…" : "正在写入产测信息与成品标识…";
                    if (root.chainPhase === "collect") return "采集信息入库：获取 IMEI 并校验…";
                    if (root.chainPhase === "clear") return "配置清除：恢复出厂设置…";
                    if (root.chainPhase === "shutdown")
                        return "下发定时关机（" + FactoryConfig.shutdownDelaySec + " 秒）…";
                    return "";
                }
                color: Theme.textPrimary
                font.family: TypeScale.family
                font.pointSize: TypeScale.heading
                font.weight: TypeScale.weightBold
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Text {
                text: "请勿断开设备或关闭软件"
                color: Theme.textSecondary
                font.family: TypeScale.family
                font.pointSize: TypeScale.caption
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }
}
