import QtQuick
import ptest
import QtQuick.Controls
import QtQuick.Layouts

// 成品/准成品工位 —— 信息最密的一屏,也是设计上最吃力的一屏。
// 布局:左=流程步骤 / 中=测试项主表 / 右=结果爆点+设备信息
Item {
    id: root
    property bool semi: false

    ConfirmDialog { id: confirm }

    // 实际下发行集(规则4) = profile 固定项 ∩ 设备 SupportedItems:
    // - profile 要求而设备未上报 → state 覆写为 5(缺能力,标红,计不通过),不静默跳过
    // - 设备上报而 profile 不含 → 不出现在列表(不下发)
    // SupportedItems 用设备真实上报值(devInfo),建连前退回 MockData 演示值。
    // 各行状态来自本工位真实指令结果(itemStates),不再用 MockData 的假状态。
    readonly property var rows: {
        if (!Session.profile) return [];
        const dev = supportedItemsLive;
        return Session.profile.items.map(function (bit) {
            const base = MockData.itemByBit(bit);
            if (!(dev & (1 << bit)))
                return Object.assign({}, base, { state: 5, reading: "" });
            const st = itemStates[bit];
            return Object.assign({}, base, { state: st ? st.state : 0,
                                             reading: st ? st.reading : "" });
        });
    }

    // 自动项(设备回读数,PC 比阈值可自动判) vs 人工项(设备只回 ok,
    // 真实结论在工人眼睛耳朵里)。分开的理由见 ManualVerifyPanel 头注释。
    // 人工判定项:设备只回 ok、发光/出声固件感知不到的项。
    // CS7G 无红外灯(全彩夜视用白光补光),故只有三项。
    // 指示灯(0)/白光(2)/复位键(4)/云台(6)/喇叭(7)/咪头(8) 共 6 位、8 条判定
    //(指示灯拆红/蓝/闪三条)。判据都是"现象只有人能确认":
    // 分贝值证明不了"人听得清";云台电流正常但虚位转不到位固件感知不到;
    // 复位键得人去按,按键手感与回弹只能人手判断。
    readonly property var manualBits: [0, 2, 4, 6, 7, 8]
    readonly property var autoRows: rows.filter(r => manualBits.indexOf(r.item) < 0)
    readonly property var manualRows: rows.filter(r => manualBits.indexOf(r.item) >= 0)

    // 只统计自动项 —— 卡片标题写的就是"自动测试项",下面渲染的也是 autoRows。
    // 若按全部 rows 统计,头部会显示 9 项的计数而列表只有 6 行,工人对不上账。
    // 人工项的结论归 ManualVerifyPanel(它自己有 settledCount/anyFail),
    // 写标识按钮同时看两边,总判定不会漏项。
    readonly property var counts: {
        const c = { pass: 0, fail: 0, run: 0, wait: 0, miss: 0 };
        autoRows.forEach(function (r) {
            if (r.state === 2) c.pass++;
            else if (r.state === 3) c.fail++;
            else if (r.state === 1) c.run++;
            else if (r.state === 5) c.miss++;
            else c.wait++;
        });
        return c;
    }

    // ---- 云链路(2026-08-17 接入):自动项与写标识走真实指令闭环 ----
    // itemStates: item → {state, reading};reqToItem: RequestId → item(结果关联)
    property var itemStates: ({})
    property var reqToItem: ({})
    property bool autoStarted: false
    property bool autoRunning: false
    property int writeReqId: -1
    // 刚下发的阶段时间戳(等回读确认);确认后落 writtenStamp 并 toast ——
    // 工人看到的"成功"是从设备里读回来的值,不是一句空话。
    property string sentStamp: ""
    property string writtenStamp: ""
    // 设备最新上报(ProductTestInfo):右栏设备信息与写标识回读确认都取这里
    property var devInfo: ({})
    readonly property bool infoConnected: devInfo.SupportedItems !== undefined
    readonly property int supportedItemsLive: infoConnected ? devInfo.SupportedItems
                                                            : MockData.supportedItems

    // ---- 写标识后的自动链(需求 2026-08-17):准成品=配置清除→定时关机;
    //      成品=采集信息入库→配置清除→定时关机。链执行期间全页等待态转圈。 ----
    // 阶段: ""空闲 | write 写标识(成品含先写产测信息) | collect 采集入库
    //     | clear 配置清除 | shutdown 定时关机 | done 完成 | failed 失败
    property string chainPhase: ""
    property string chainError: ""
    property int identityReqId: -1
    property int imeiReqId: -1
    property int shutdownReqId: -1
    property int recIndex: -1          // 成品:本次使用的批次行
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

    // 批次导入后带出第一条未用;入库成功后自动跳下一条(2026-08-17 用户补充)
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

    // 写标识开放条件:自动项全绿 + 人工判定全过(外设逐项验证成功后才允许写入)
    readonly property bool canWrite: autoStarted && !autoRunning
        && counts.fail === 0 && counts.miss === 0
        && counts.wait === 0 && counts.run === 0
        && manualPanel.allDone && !manualPanel.anyFail

    // 设备信息取值:未上报显示 "—" 而不是空白(空白像坏了)
    function dv(key) {
        return devInfo[key] !== undefined && devInfo[key] !== "" ? devInfo[key] : "—";
    }

    function nowStamp17() {
        return Qt.formatDateTime(new Date(), "yyyyMMddHHmmsszzz");
    }

    // 自动项参数(语义=设备端 peripheral_executors 注释):
    // 电池/4G 查询(4G P1=0 当前槽不切卡);SD 用 Operation=4 写读校验,P1=大小MB。
    function autoParams(item) {
        if (item === 10) return { op: 4, p1: 1, p2: 0 };
        return { op: 0, p1: 0, p2: 0 };
    }

    function startAutoTest() {
        autoStarted = true;
        var states = {};
        var reqs = {};
        autoRows.forEach(function (r) {
            if (r.state === 5) return;            // 缺能力项不下发
            states[r.item] = { state: 1, reading: "" };
            const a = autoParams(r.item);
            const id = CloudClient.peripheralTest(r.item, a.op, a.p1, a.p2, "");
            reqs[id] = r.item;
        });
        itemStates = states;
        reqToItem = reqs;
        autoRunning = Object.keys(reqs).length > 0;
        if (!autoRunning) manualPanel.ready = true;   // 全缺能力:直接开放人工
    }

    // 写标识:下发 → 设备写入(flash/联调期为文件) → 回 ProductTestResult →
    // PC 再回读 ProductTestInfo 核对时间戳 → toast。写入的证据是回读值。
    // 成品:先写产测信息(批次记录),后写成品标识 —— finishTestFlag 非空设备即按
    // "成品"从分区加载身份,顺序反了会产出"空身份的成品"。
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
        CloudClient.invokeGenericAction("SetDefaultDevConfigs");
    }

    // 成品采集入库校验:设备回传的产测信息 vs InputData1 源记录逐字段比对。
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
        if (reqToItem[requestId] !== undefined) {       // —— 外设自动项结果
            const item = reqToItem[requestId];
            var states = {};
            for (var k in itemStates) states[k] = itemStates[k];
            if (code === 0)
                states[item] = { state: 2, reading: detail.length > 0 ? detail : "ok" };
            else if (code === 4)
                states[item] = { state: 5, reading: "设备回:不支持" };
            else
                states[item] = { state: 3, reading: detail };
            itemStates = states;
            var reqs = {};
            for (var r in reqToItem)
                if (parseInt(r) !== requestId) reqs[r] = reqToItem[r];
            reqToItem = reqs;
            if (Object.keys(reqs).length === 0) {
                autoRunning = false;
                manualPanel.ready = true;               // 自动项收尾 → 开放人工判定
            }
            return;
        }
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
                CloudClient.refreshInfo();              // 取 Imei + 全量校验,见 onInfoUpdated
            } else {
                // 口径:校验不过 IMEI 留空白、不置入库标记,链中止转维修
                chainFail("获取 IMEI 失败(4G)  Code=" + code
                          + (detail.length > 0 ? "  " + detail : ""));
            }
            return;
        }
        if (requestId === shutdownReqId) {              // —— 定时关机(下发成功=完成)
            shutdownReqId = -1;
            if (code === 0) {
                chainPhase = "done";
                toast.show((semi ? "准成品" : "成品")
                           + "流程完成:设备将在 120 秒后关机", true);
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
            root.shutdownReqId = CloudClient.shutdownDevice(120);
        }
    }

    Toast { id: toast }

    // 进工位即读一次设备上报:步骤条"连接设备"与右栏设备信息都靠它;
    // 成品工位同时带出第一条未入库 MAC
    Component.onCompleted: {
        CloudClient.refreshInfo();
        refillMac();
    }

    // ---- 工位步骤(动态跟随真实进度;准成品工位写标识步文案=写准成品标识) ----
    readonly property var steps: {
        const rank = ["write", "collect", "clear", "shutdown", "done"].indexOf(chainPhase);
        var out = [
            { name: "连接设备 · 读信息",
              state: infoConnected ? 2 : 1 },
            { name: "外设自动项",
              state: autoRunning ? 1
                     : (autoStarted && counts.fail === 0 && counts.miss === 0
                        && counts.wait === 0 ? 2 : (autoStarted ? 1 : 0)) },
            { name: "人工判定",
              state: manualPanel.allDone ? 2 : (manualPanel.ready ? 1 : 0) },
            { name: semi ? "写准成品标识" : "写成品标识",
              state: writtenStamp.length > 0 ? 2
                     : (chainPhase === "write" || canWrite ? 1 : 0) }
        ];
        if (!semi)
            out.push({ name: "采集信息入库",
                       state: rank > 1 ? 2 : (chainPhase === "collect" ? 1 : 0) });
        out.push({ name: "配置清除",
                   state: rank > 2 ? 2 : (chainPhase === "clear" ? 1 : 0) });
        out.push({ name: "定时关机 120s",
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

        // ---- 中:自动测试项 + 人工判定 + 写标识 ----
        // 窗口非全屏时(默认 1440x900,产线机器还可能更小)内容高度会超出可视区,
        // 写标识按钮被挤到屏幕外 —— 工人以为"没有这个按钮"。
        // 解法:测试项与判定面板放进 ScrollView 可滚,写标识条钉在底部常驻。
        // 主操作永不随滚动消失,这是产线工具的硬要求。
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.s4

        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: availableWidth        // 只纵向滚
            clip: true
            ScrollBar.vertical.policy: ScrollBar.AsNeeded

            ColumnLayout {
                width: parent.width
                spacing: Theme.s4

        Card {
            title: "自动测试项  ·  设备回读数，PC 判阈值"
            titleIcon: Icons.navFinished
            fitContent: true
            Layout.fillWidth: true

            // fitContent 卡片内层禁用 anchors.fill —— 卡高取决于内容、
            // 内容又填满卡 = 循环依赖,整张卡会塌成一条
            ColumnLayout {
                anchors { left: parent.left; right: parent.right; top: parent.top }
                spacing: Theme.s3

                // 汇总条:通过/失败/待测计数,先给结论再给明细(倒金字塔)
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.s4

                    Repeater {
                        model: [
                            { label: "通过",   n: counts.pass, c: Theme.pass },
                            { label: "失败",   n: counts.fail, c: Theme.fail },
                            { label: "执行中", n: counts.run,  c: Theme.running },
                            { label: "待测",   n: counts.wait, c: Theme.textSecondary },
                            { label: "缺能力", n: counts.miss, c: Theme.fail }
                        ]
                        Row {
                            required property var modelData
                            spacing: Theme.s1
                            Text {
                                text: modelData.n
                                color: modelData.c
                                font.family: TypeScale.family
                                font.pointSize: TypeScale.heading
                                font.weight: TypeScale.weightBold
                            }
                            Text {
                                text: modelData.label
                                color: Theme.textDim
                                font.family: TypeScale.family
                                font.pointSize: TypeScale.caption
                                anchors.baseline: parent.children[0].baseline
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: "SupportedItems  0x" + root.supportedItemsLive.toString(16).toUpperCase()
                              + (root.infoConnected ? "" : " (未连接)")
                        color: Theme.textDim
                        font.family: "Consolas"
                        font.pointSize: TypeScale.caption
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

                // 用 Repeater 不用 ListView:自动项只 3 行且固定,
                // ListView 的 contentHeight 在布局时为 0,会把整张卡压没
                Column {
                    Layout.fillWidth: true
                    spacing: 2

                    Repeater {
                        model: autoRows
                        TestItemRow {
                            required property var modelData
                            width: parent.width
                            model: modelData
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.s3

                    AppButton {
                        text: root.autoRunning ? "自动测试中…" : "开始自动化测试"
                        glyph: Icons.play
                        kind: "primary"
                        Layout.fillWidth: true
                        enabled: !root.autoRunning
                        // 逐项下发 PtestPeripheralTest,结果按 RequestId 回填行状态;
                        // 全部收尾后开放人工判定面板
                        onClicked: root.startAutoTest()
                    }
                    AppButton {
                        text: "跳过当前项"
                        glyph: Icons.skip
                        // 权限矩阵:跳过=工程师+;技术员直接隐藏(SW_HIDE 惯例)
                        visible: Session.canSkipItem
                        // 跳过=质量口径的人工决定 → 确认;开始自动化测试可重来,不设卡
                        onClicked: confirm.ask("跳过当前项？",
                            "该测试项将标记为跳过并继续下一项，跳过记录会进产测台账。",
                            function () { /* 真实实现:跳过并推进 */ })
                    }
                }
            }
        }

            // 人工判定面板:自动项跑完后集中确认四个人工项。
            // 设备回 ok 只代表"指令执行了",发光/出声固件感知不到。
            ManualVerifyPanel {
                id: manualPanel
                Layout.fillWidth: true
            }

            }
        }

            // 写标识条。钉在中栏底部,不进 ScrollView —— 永远可见可点。
            Rectangle {
                Layout.fillWidth: true
                // 高度取按钮实高 + 上下内距。用 s3 而非 s4 ——
                // 1180x720(窗口最小尺寸)下 s4 会让操作条被窗口底边切掉一线。
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

                // 成品:MAC 输入。默认带出第一条未入库记录,可改;
                // 校验 = 必须在批次内 且 未被使用过(入库标记=0)。
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
                    // 写入条件 canWrite + 成品需 MAC 校验通过;链在途/已完成禁用
                    enabled: root.canWrite && !root.chainBusy
                             && root.chainPhase !== "done"
                             && (root.semi || root.macError.length === 0)
                    onClicked: confirm.ask(semi ? "写入准成品标识？" : "写入成品标识？",
                        semi ? "将写入准成品（Stage=2）完成时间戳并回读核对，随后自动执行：配置清除 → 定时关机（120 秒）。"
                             : "将写入该 MAC 对应批次记录的产测信息与成品标识，随后自动执行：采集信息入库（IMEI+校验）→ 配置清除 → 定时关机（120 秒）。",
                        function () { root.doWriteStage() })
                }

                Text {
                    Layout.fillWidth: true
                    visible: root.chainPhase === "failed"
                             || (!root.canWrite && root.writtenStamp.length === 0)
                    text: {
                        if (root.chainPhase === "failed") return "流程失败: " + root.chainError;
                        if (!root.autoStarted) return "先完成外设自动项测试";
                        if (root.autoRunning || counts.run > 0) return "自动项执行中…";
                        if (counts.fail > 0 || counts.miss > 0) return "自动项有未通过";
                        if (!manualPanel.allDone) return "人工判定未完成";
                        return "人工判定有异常项";
                    }
                    color: Theme.warn
                    font.family: TypeScale.family
                    font.pointSize: TypeScale.body
                    wrapMode: Text.WordWrap
                }
            }
            }
        }

        // ---- 右:结果 + 设备信息 ----
        ColumnLayout {
            Layout.preferredWidth: 320
            Layout.fillWidth: false
            Layout.fillHeight: true
            spacing: Theme.s4

            ResultBanner {
                Layout.fillWidth: true
                Layout.preferredHeight: 172
                state_: {
                    if (counts.fail > 0 || counts.miss > 0 || manualPanel.anyFail) return "fail";
                    if (manualPanel.allDone) return "pass";
                    if (counts.run > 0) return "running";
                    return "idle";
                }
                caption: {
                    if (counts.fail > 0 || counts.miss > 0) return "自动项不通过";
                    if (manualPanel.anyFail) return "人工判定不通过";
                    if (manualPanel.allDone) return "全部通过，可写标识";
                    if (manualPanel.ready) return "待人工判定  " + manualPanel.settledCount
                                                  + " / " + manualPanel.checks.length;
                    if (counts.run > 0) return "自动项执行中";
                    return "待开始";
                }
            }

            // 拉流小窗。这两个工位不调焦，但仍要确认"画面确实出来了"
            // （摄像头模块虚焊/排线松在这里最容易暴露）。小窗看不清细节时
            // 双击进入全屏，Esc 退回。
            Card {
                id: liveCard
                title: "实时画面"
                titleIcon: Icons.navFocus
                Layout.fillWidth: true
                // 固定高度而非 fitContent:内容用 anchors 撑满时
                // fitContent 的 childrenRect 会成绑定环。
                Layout.preferredHeight: 180 + Theme.s6 + Theme.s4

                LivePreview {
                    anchors {
                        left: parent.left; right: parent.right; bottom: parent.bottom
                    }
                    height: 180
                    compact: true
                    showGrid: false
                    hint: ""              // 小窗不放提示文字，画面干净
                    showZoomHint: false   // 双击全屏功能保留，只是不提示
                    onFullscreenRequested:
                        liveFull.open((root.semi ? "准成品" : "成品") + " · 实时画面")
                }
            }

            Card {
                title: "设备信息"
                titleIcon: Icons.device
                Layout.fillWidth: true
                Layout.fillHeight: true

                // 全部取设备真实上报(devInfo),未连接显示 "—"。
                Column {
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    spacing: Theme.s3

                    FieldRow { width: parent.width; label: "IMEI";    value: root.dv("Imei") }
                    FieldRow { width: parent.width; label: "UUID";    value: root.dv("Uuid") }
                    FieldRow { width: parent.width; label: "MAC";     value: root.dv("Mac") }
                    FieldRow { width: parent.width; label: "SN";      value: root.dv("Sn") }
                    FieldRow { width: parent.width; label: "软件";    value: root.dv("SwVersion") }
                    FieldRow { width: parent.width; label: "硬件";    value: root.dv("HwVersion") }
                    FieldRow {
                        width: parent.width
                        label: "密钥校验"
                        value: root.dv("SecretCrc32")
                        valueColor: Theme.pass
                    }

                    Rectangle { width: parent.width; height: 1; color: Theme.border }

                    // 回读值即设备侧真值 —— 工人核对的是"设备里现在是什么",
                    // 本工位刚写入的那一行标绿。
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

    // 自动链等待层:写标识后的自动步骤(采集入库/配置清除/定时关机)期间盖住
    // 全页 —— 样式对齐拉流建联的转圈(BusyIndicator)。done/failed 自动收起;
    // MouseArea 拦截点击,链执行期间不允许任何操作。
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
                    if (root.chainPhase === "shutdown") return "下发定时关机（120 秒）…";
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
