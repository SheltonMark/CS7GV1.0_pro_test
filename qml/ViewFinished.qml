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
                     noCommand: c.noCommand === true,
                     // 人动作+设备判(复位按键):照常下发与查能力位,只是结果
                     // 按 Code 自动判、running 相位换成动作提示
                     deviceJudged: c.deviceJudged === true,
                     runningText: c.runningText !== undefined ? c.runningText : "",
                     // 无指令项不查能力位:不下发就无所谓设备有没有执行体,
                     // 否则咪头 bit8 不在 SupportedItems 会被误判"设备缺能力"
                     miss: c.noCommand === true
                           ? false
                           : (supportedItemsLive & (1 << c.item)) === 0 });
        });
        return q;
    }

    // 结果确认门(需求补充):汇总页回车确认后才算测试完成
    readonly property bool testsClean: seqPanel.confirmed && !seqPanel.anyBad

    // ---- 写标识后的自动链 ----
    // 成品相位(定稿 2026-08-18,校验挡在写标识前面):
    //   "" | verify 产测信息校验(写身份→IMEI→读回比对) | collect 采集信息入库
    //   | write 写成品标识 | clear 配置清除 | shutdown 定时关机 | done | failed
    // 准成品: "" | write 写准成品标识 | clear | shutdown | done | failed
    // 校验不一致绝不能写成品标识:标识一写产测态即退(RTSP 关、身份按成品加载),
    // 台账里又没这台,只能返修清分区 —— 所以 verify 不过就断链。
    property string chainPhase: ""
    property string chainError: ""
    property int identityReqId: -1
    property int writeReqId: -1
    property int imeiReqId: -1
    property int shutdownReqId: -1
    property int recIndex: -1          // 成品:本次使用的批次行
    property string sentStamp: ""      // 刚下发的时间戳(等回读确认)
    property string writtenStamp: ""   // 回读确认后的设备侧真值
    property string collectedImei: ""  // 成品:校验通过已入库的 IMEI(""=未到该步)
    // 断点续走:校验/入库都成了、只差成品标识(写标识那步失败)——
    // 重试只补写标识,不重写身份、不重复入库
    readonly property bool canResume: !semi && chainPhase === "failed"
                                      && collectedImei.length > 0
                                      && writtenStamp.length === 0 && recIndex >= 0
    readonly property bool chainBusy: chainPhase === "verify" || chainPhase === "collect"
                                      || chainPhase === "write" || chainPhase === "clear"
                                      || chainPhase === "shutdown"

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
            // 链执行中/失败待续走时不自动跳 MAC —— 入库发生在写标识之前,
            // 这时跳到下一条会让"重试补写标识"对错行;完结后由 done 分支跳
            if (root.chainBusy || root.chainPhase === "failed") return;
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

    // ───────────────────── 实时画面（云拉流）─────────────────────────
    // 这两个工位**一律走云**，不看 profile.focusRtsp：那个开关只描述"调焦工位
    // 的裸机有网口"这一个场景。到了准成品/成品，壳已经套上，网口被挡住，
    // CS7GV1.0 和 CS6GV2.0 都只能走云（2026-08-20 与产线确认）。
    //
    // 起播时机：**手动**。画面中心一个播放按钮，工人要看才点。
    // 不自动拉的理由：拉流会占着设备的并发名额（README 第 24 条），而这两站
    // 大部分时间在跑逐项测试、没人看画面；真出问题要查日志去调焦工位。
    function startCloudStream() {
        if (!Xp2pClient.available) {
            toast.show("云拉流 SDK 未就绪（dist/xp2p/app_interface.dll 缺失）", false);
            return;
        }
        livePrev.sourceUrl = "";
        Xp2pClient.start(CloudClient.productId, CloudClient.deviceName, "super");
    }

    onVisibleChanged: {
        // 只管收尾。切走必须停：不收会占着并发名额，下次拉会被拒
        //（README 第 24 条）。Xp2pClient 是单例，切到调焦页也靠这一步让出会话。
        if (!visible) {
            livePrev.sourceUrl = "";
            Xp2pClient.stop();
        }
    }

    // 本台在本工位彻底完事 → 自动跳下一台。清掉整条链的状态，否则下一台会带着
    // 上一台的 chainPhase（显示"流程完成"）和时间戳。
    function finishAndAdvance() {
        livePrev.sourceUrl = "";
        Xp2pClient.stop();
        chainPhase = "";
        chainError = "";
        sentStamp = "";
        writtenStamp = "";
        collectedImei = "";
        recIndex = -1;
        seqPanel.reset();
        // stationKey 已在上方定义（semi ? "semi" : "finished"）——
        // 准成品与成品共用本页，进度分开记
        Session.advanceStation(root.stationKey);
    }

    Connections {
        target: Xp2pClient
        // ⚠️ 必须按可见性开关。工位页常驻不销毁，而 Xp2pClient 是单例 —— 不加
        // 这条，本页在后台也会收到别的工位触发的 onLiveUrlReady，于是同一个 URL
        // 被两个播放器同时打开、两个 HTTP GET 打本机代理，设备只维持一路会话，
        // 第二个请求进来就把第一个踢掉（实测：刚出图就 StreamEnd）。
        enabled: root.visible
        function onLiveUrlReady(url) { livePrev.sourceUrl = url; }
        function onErrorTextChanged() {
            if (Xp2pClient.errorText.length > 0) {
                livePrev.sourceUrl = "";
                toast.show("云拉流失败: " + Xp2pClient.errorText, false);
            }
        }
        function onStreamEnded(reason) {
            livePrev.sourceUrl = "";
            toast.show(reason, false);
        }
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

    // 链入口。成品顺序(定稿 2026-08-18):写产测信息 → 读回比对+采IMEI(verify)
    // → 一致才入库(collect) → 才写成品标识(write) → 清除 → 关机。
    // 身份仍先于标识(finishTestFlag 非空设备即按"成品"从分区加载身份,
    // 反了会产出"空身份的成品");校验不一致在 verify 断链,标识不会写。
    function doWriteStage() {
        chainError = "";
        if (semi) {
            chainPhase = "write";
            sentStamp = nowStamp17();
            writeReqId = CloudClient.writeStage(2, sentStamp);
            return;
        }
        if (canResume) {   // 上轮已校验入库、只差标识 → 直接补写
            chainPhase = "write";
            sentStamp = nowStamp17();
            writeReqId = CloudClient.writeStage(3, sentStamp);
            return;
        }
        collectedImei = "";
        writtenStamp = "";
        chainPhase = "verify";
        recIndex = macIndex;
        const rec = Session.batchRecords[recIndex];
        identityReqId = CloudClient.writeIdentity({
            Mac: rec[0], Sn: rec[1], DeviceName: rec[2], Uuid: rec[3],
            DeviceSecret: rec[4], ProductKey: rec[5], ProductSecret: rec[6],
            Language: rec[7]
        });
        // 身份结果回来 → 采 IMEI → 读回比对,见 handleResult / onInfoUpdated
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
                // 身份已落分区 → 读回比对要连同 IMEI,先发 4G 查询(仍在 verify)
                imeiReqId = CloudClient.peripheralTest(9, 0, 0, 0, "");
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
                refillMac();   // 本台完结才跳下一条 MAC(入库时刻已不再自动跳)
                // 自动跳下一台。**必须等到这里**，不能在写完标识就跳：
                // 后面还有 配置清除 → 定时关机 两步，都用 CloudClient 对当前设备
                // 下发，提前切走会把这些指令发到下一台去。
                root.finishAndAdvance();
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
            // 顺手用设备真值校正本地进度（顶栏浮层的绿/红点）。零额外调用 ——
            // 这份上报本来就要读。设备侧时间戳是权威，本地缓存只为重启后不丢。
            StationProgress.syncFromDevice(
                CloudClient.productId, CloudClient.deviceName,
                info.FocusTime || "", info.SemiTime || "",
                info.FinishTime || "", info.InspectTime || "");
            // ① 写标识回读确认 → 接续自动链
            if (root.sentStamp.length > 0) {
                const key = root.semi ? "SemiTime" : "FinishTime";
                if (info[key] === root.sentStamp) {     // 回读值==下发值,写入坐实
                    root.writtenStamp = root.sentStamp;
                    root.sentStamp = "";
                    toast.show((root.semi ? "准成品" : "成品") + "标识已写入并回读确认  "
                               + root.writtenStamp, true);
                    root.startClear();   // 成品的校验/入库已在写标识之前完成
                }
                return;
            }
            // ② 成品·产测信息校验:IMEI 指令已回,此次回读做全量比对+取 IMEI。
            // 通过才入库、才轮到写成品标识(定稿 2026-08-18:校验不一致绝不能
            // 写标识 —— 见 chainPhase 注释)。
            if (root.chainPhase === "verify" && root.imeiReqId < 0 && root.recIndex >= 0) {
                const rec = Session.batchRecords[root.recIndex];
                const bad = root.verifyRecord(rec, info);
                const imei = info.Imei !== undefined ? info.Imei : "";
                if (bad.length > 0 || imei.length === 0) {
                    // 口径:校验不过 → 不写标识;InputData2 该行 IMEI 留空白、
                    // 不置入库标记(设备转维修后该批次行仍可用)
                    root.chainFail(bad.length > 0
                        ? "产测信息校验不匹配: " + bad.join("、")
                        : "设备未上报 IMEI");
                    return;
                }
                root.chainPhase = "collect";
                Session.markBatchDone(root.recIndex, imei);
                root.collectedImei = imei;
                toast.show("产测信息校验一致，已入库  IMEI " + imei, true);
                // 入库完成 → 写成品标识
                root.chainPhase = "write";
                root.sentStamp = root.nowStamp17();
                root.writeReqId = CloudClient.writeStage(3, root.sentStamp);
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

    // ---- 工位步骤(动态跟随;成品顺序=定稿 2026-08-18) ----
    // 成品: 连接 → 逐项测试 → 产测信息校验 → 采集信息入库 → 写成品标识 → 清除 → 关机
    // 准成品: 连接 → 逐项测试 → 写准成品标识 → 清除 → 关机
    readonly property var steps: {
        const rank = ["verify", "collect", "write", "clear", "shutdown", "done"]
                         .indexOf(chainPhase);
        var out = [
            { name: "连接设备 · 读信息",
              state: infoConnected ? 2 : 1 },
            { name: "逐项测试 " + seqPanel.settled + "/" + seqPanel.total,
              state: seqPanel.confirmed ? (seqPanel.anyBad ? 1 : 2)
                     : (seqPanel.settled > 0 || seqPanel.phase === "running"
                        || seqPanel.phase === "summary" ? 1 : 0) }
        ];
        if (!semi) {
            out.push({ name: "产测信息校验",
                       state: collectedImei.length > 0 ? 2
                              : (chainPhase === "verify"
                                 || (testsClean && macError.length === 0
                                     && !chainBusy && writtenStamp.length === 0)
                                 ? 1 : 0) });
            out.push({ name: "采集信息入库",
                       state: collectedImei.length > 0 ? 2
                              : (chainPhase === "collect" ? 1 : 0) });
        }
        out.push({ name: semi ? "写准成品标识" : "写成品标识",
                   state: writtenStamp.length > 0 ? 2
                          : (chainPhase === "write"
                             || (semi && testsClean) || canResume ? 1 : 0) });
        out.push({ name: "配置清除",
                   state: rank > 3 ? 2 : (chainPhase === "clear" ? 1 : 0) });
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
                                 && (root.semi || root.macError.length === 0
                                     || root.canResume)
                        onClicked: confirm.ask(
                            semi ? "写入准成品标识？" : "写入成品标识？",
                            semi ? "将写入准成品（Stage=2）时间戳并回读核对，随后自动执行：配置清除 → 定时关机（"
                                   + FactoryConfig.shutdownDelaySec + " 秒）。"
                                 : (root.canResume
                                    ? "上次已校验一致并入库、仅成品标识未写：本次只补写标识，随后自动执行：配置清除 → 定时关机（"
                                      + FactoryConfig.shutdownDelaySec + " 秒）。"
                                    : "将写入该 MAC 批次记录的产测信息并读回校验（含 IMEI），校验一致才入库并写成品标识；随后自动执行：配置清除 → 定时关机（"
                                      + FactoryConfig.shutdownDelaySec + " 秒）。校验不一致将中止，不写成品标识。"),
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
            // 走云:装壳后网口被挡,CS7GV1.0 与 CS6GV2.0 都只能走 XP2P。进页面
            // 自动拉,离开自动停(见上面的 onVisibleChanged / startCloudStream)。
            Card {
                id: liveCard
                title: "实时画面"
                titleIcon: Icons.navFocus
                Layout.fillWidth: true
                // 高度按各部分显式相加，别再用 180+s6+s4 那种凑出来的数：那样算出
                // 228px，扣掉上下内距 32 + 标题约 15 + 标题下 12 后内容区只剩约
                // 169px，而槽位写死 180px 又锚在底部，就往上溢 11px 压到标题上
                // （现象：「实时画面」和画面贴在一起）。
                //   内距*2 + 标题 + Card 自带的标题下间距 + 额外间距 + 画面
                // 多出来的高度由下方「设备信息」卡片自动让出（它是 fillHeight），
                // 右栏总高不变。
                readonly property int titleH: 15
                // Card 的内容区本身已带 topMargin = Theme.s3(12px)，这里再加一点，
                // 合计 16px —— 这就是你要的"拉开一点距离"。
                readonly property int extraGap: Theme.s1
                readonly property int videoH: 180
                Layout.preferredHeight: Theme.s4 * 2 + titleH + Theme.s3
                                        + extraGap + videoH

                // 槽位 Item：全屏是把 livePrev 重挂到 liveFull 的顶层容器，
                // 槽位留在卡片里占位，退出全屏时挂回来自动填满。
                // ⚠️ 填满内容区而不是写死高度 —— 写死就会跟卡片算出来的内容区打架，
                //    那正是标题被顶住的原因。
                Item {
                    anchors.fill: parent
                    anchors.topMargin: liveCard.extraGap

                    LivePreview {
                        id: livePrev
                        anchors.fill: parent
                        compact: true
                        showGrid: false
                        // 小窗不写清楚工人不会想到能放大。用组件自带的悬停角标
                        // （鼠标移上去才出，不挡画面），不要塞进 hint —— hint 只在
                        // **没出画面**时显示，那时候提示"双击全屏"正好是反的。
                        showZoomHint: true
                        // 手动起播：中心播放按钮 + 建联中转圈，都由组件自己管。
                        // connecting 必须喂进去，否则点了按钮到拿到 URL 之间
                        // streaming 仍是假，转圈不转、按钮还在，像是没反应。
                        showPlayButton: true
                        connecting: Xp2pClient.connecting
                        onPlayRequested: root.startCloudStream()
                        onFullscreenRequested:
                            liveFull.open((root.semi ? "准成品" : "成品")
                                          + " · 实时画面", livePrev)
                    }

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
                    if (root.chainPhase === "verify")
                        return "产测信息校验：写入产测信息并读回比对（含 IMEI）…";
                    if (root.chainPhase === "collect") return "采集信息入库…";
                    if (root.chainPhase === "write")
                        return root.semi ? "正在写入准成品标识…" : "正在写入成品标识…";
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
