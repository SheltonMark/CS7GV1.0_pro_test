import QtQuick
import ptest
import QtQuick.Controls
import QtQuick.Layouts

// 云链路调试页（联调用，非工位）。目标：不进任何工位流程就能
//   ① 看当前传输形态（Mock 假设备 / 腾讯云直连，由 cloud_config.json 决定）
//   ② 逐条下发 6 个产测 action，盯"受理→设备执行→上报"的完整闭环
//   ③ 随时读 ProductTestInfo 汇总 + 心跳计数/年龄（在线判定的原始依据）
//   ④ 盯设备端最近异常与日志尾部（阶段4：PC 没下发指令时的失败也看得见）
// 工位页接真实流程前，所有链路问题先在这页定位——工位页保持 Mock 数据不动。
Item {
    id: root

    // 日志上限：联调一天几千条封顶，500 够回看且不吃内存
    readonly property int maxLogLines: 500

    // 心跳年龄是"距今"的量，属性只在收到新心跳时通知。秒级 tick 让读数在
    // 界面上真的走字，否则两拍之间看着像卡住，反倒像是链路断了。
    property int clockTick: 0

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.clockTick++
    }

    // 切设备/选到离线设备的提示
    Toast { id: toast }

    // ---- 阶段4 日志展示（PtestLastError / PtestLogTail，物模型 v3）----
    // 设备端稍后上报；null = 一次都没收到（旧固件/旧物模型），界面显示"—"。
    // 收到后粘滞——单拍缺键不清空（设备属性本来就是快照式的，缺=没变不是没了）。
    property var lastError: null
    // 日志尾部只认 Seq 变化才刷新：轮询最快 500ms 一拍，每拍重设 text 会闪烁
    property int logTailSeq: -1
    property string logTailText: ""

    // Stage 枚举（物模型 v3 PtestLastError.Stage）
    readonly property var stageNames:
        ["读工装卡", "启动自检", "上云", "写加密分区", "产测信息校验", "电量门"]

    function lastErrorStageText() {
        if (lastError === null) return "";
        const s = Number(lastError.Stage);
        const name = stageNames[s] !== undefined ? stageNames[s] : ("阶段" + s);
        return name + "　Code=" + lastError.Code;
    }
    function lastErrorTimeText() {
        if (lastError === null || lastError.Ts === undefined) return "";
        return Qt.formatDateTime(new Date(Number(lastError.Ts) * 1000),
                                 "yyyy-MM-dd hh:mm:ss");
    }

    // tick 只为让绑定跟着秒钟重算，函数体不用它。
    function heartbeatText(value, ageMs, tick) {
        if (value < 0) return "";
        const age = ageMs < 0 ? "未收到"
                  : ageMs < 10000 ? ageMs + " ms"
                  : Math.round(ageMs / 1000) + " s";
        return value + "  (" + age + " 前)";
    }

    // 单块文本而非 ListView 逐行 delegate：每行各是一个 TextEdit 时选区
    // 跨不过行边界（2026-08-19 现场反馈"只能选一两行"）——多行复制必须是
    // 同一个文本对象。代价是丢逐行着色，行内 ✓/✗/⏱/← 符号本就承载状态。
    property var logLines: []
    property string logText: ""

    function appendLog(line) {
        logLines.push(line);
        if (logLines.length > root.maxLogLines)
            logLines.splice(0, logLines.length - root.maxLogLines);
        logText = logLines.join("\n");
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
        function onInfoUpdated(info) {
            infoText.text = JSON.stringify(info, null, 2);
            if (info.PtestLastError !== undefined)
                root.lastError = info.PtestLastError;
            const tail = info.PtestLogTail;
            if (tail !== undefined && tail.Seq !== root.logTailSeq) {
                root.logTailSeq = tail.Seq;
                root.logTailText = tail.Text !== undefined ? tail.Text : "";
            }
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: Theme.s5
        spacing: Theme.s4

        // ---- 左列：链路状态 + 指令面板 + 产测信息 ----
        // ⚠️ 必须保持可伸缩：指令卡片最宽那行(读产测信息/清配置/关机120s +
        // 清标识/全清)要 ~620px，钉死在 preferredWidth 上会把按钮裁到卡片外。
        // 两列的宽度分配靠右列的 preferredWidth 定(见下)，不要在这里关 fillWidth。
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

                    // DeviceName 用下拉而不是手填：名单本来就在云端（同一 ProductId
                    // 下的全部工装卡），手填只会打错。下拉项带在线点，能直接看出
                    // 哪几张卡没上电。手填入口保留在下面那个"手动指定"里 —— 调试
                    // 偶尔要指向名单外的设备（新建但还没上电的卡）。
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.s3
                        Text {
                            text: "DeviceName"
                            color: Theme.textDim
                            font.family: TypeScale.family
                            font.pointSize: TypeScale.caption
                        }
                        DevicePicker {
                            Layout.fillWidth: true
                            onMessage: (text, ok) => toast.show(text, ok)
                        }
                        AppButton {
                            text: "刷新名单"
                            glyph: Icons.reset
                            implicitHeight: 32
                            onClicked: CloudClient.refreshDevices()
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.s3
                        Text {
                            text: "手动指定"
                            color: Theme.textDim
                            font.family: TypeScale.family
                            font.pointSize: TypeScale.caption
                        }
                        TextField {
                            id: deviceField
                            Layout.fillWidth: true
                            text: CloudClient.deviceName
                            placeholderText: "名单外的 DeviceName（调试用）"
                            font.family: "Consolas"
                            font.pointSize: TypeScale.body
                            onEditingFinished: CloudClient.deviceName = text
                        }
                    }

                    // 在线判定的原始依据，摊开给人看 —— 顶栏那个绿点只有"在/不在"，
                    // 排障时要知道是哪一头断的：
                    //   计数不动          = 固件没在上报（产测态没进 / 心跳线程没起）
                    //   计数在动、年龄很大 = 云端 LastUpdate 单位或有无与预期不符，
                    //                       此时在线判定靠"计数变化"兜底，仍准
                    //   整行是"—"        = 这台设备一次心跳都没读到（旧物模型 v1 无此属性）
                    FieldRow {
                        Layout.fillWidth: true
                        label: "心跳"
                        value: root.heartbeatText(CloudClient.heartbeatValue,
                                                  CloudClient.heartbeatAgeMs,
                                                  root.clockTick)
                        valueColor: CloudClient.online ? Theme.pass : Theme.fail
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
                            onClicked: CloudClient.invokeGenericAction("SetDefaultDevConfigs", {})
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
                    id: infoScroll
                    anchors.fill: parent
                    clip: true
                    TextArea {
                        id: infoText
                        // 必须钉宽度,否则 TextArea 按内容取隐式宽 ⇒ 长行(日志尾部
                        // 那种无空格长串)永远不换行,只把自己横向拉出可视区。
                        width: infoScroll.availableWidth
                        readOnly: true
                        selectByMouse: true    // 排障要抄字段值,readOnly 默认不可选
                        text: "（点「读产测信息」拉取）"
                        wrapMode: TextArea.WrapAnywhere
                        background: null
                        color: Theme.textSecondary
                        font.family: "Consolas"
                        font.pointSize: TypeScale.caption
                    }
                }
            }
        }

        // ---- 右列：指令流水 + 阶段4 设备侧诊断 ----
        // ⚠️ preferredWidth 必须显式给：Card 的 implicitWidth 恒为 0（内容挂在
        // anchors 里，不往上传尺寸），所以本列若不写期望宽就等于"我不要地方"，
        // 实测会被压到十几像素、只剩竖排的标签字。给了之后两列约 845 / 912。
        ColumnLayout {
            Layout.fillWidth: true
            Layout.preferredWidth: 560
            Layout.minimumWidth: 420
            Layout.fillHeight: true
            spacing: Theme.s4

            Card {
                title: "指令流水"
                titleIcon: Icons.history
                Layout.fillWidth: true
                Layout.fillHeight: true

                ScrollView {
                    id: logScroll
                    anchors.fill: parent
                    clip: true
                    TextArea {
                        id: logArea
                        width: logScroll.availableWidth  // 不钉宽度长行不换行
                        readOnly: true
                        selectByMouse: true              // 单块文本 ⇒ 选区可跨任意多行
                        text: root.logText
                        // 新行到来自动滚到底（游标追到末尾，ScrollView 跟随）。
                        // 代价：正选中时来了新行会清掉选区——流水只在下发/读取
                        // 时新增，不是持续刷屏，可接受。
                        onTextChanged: cursorPosition = length
                        wrapMode: TextArea.WrapAnywhere
                        background: null
                        color: Theme.textSecondary
                        font.family: "Consolas"
                        font.pointSize: TypeScale.caption
                    }
                }

                AppButton {
                    anchors { top: parent.top; right: parent.right }
                    z: 1
                    height: 30
                    text: copiedTick.running ? "已复制" : "复制"
                    onClicked: {
                        FileIo.copyText(root.logText);
                        copiedTick.restart();
                    }
                    Timer { id: copiedTick; interval: 1200 }
                }
            }

            // 最近一条非指令类失败（起机 provision/自检等，PC 没下发指令时的
            // 失败此前只在设备 stderr）。没收到属性时三行都显 "—"。
            Card {
                title: "最近设备异常 PtestLastError"
                titleIcon: Icons.fail
                fitContent: true
                Layout.fillWidth: true

                ColumnLayout {
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    spacing: Theme.s2

                    FieldRow {
                        Layout.fillWidth: true
                        label: "阶段"
                        mono: false
                        value: root.lastErrorStageText()
                        valueColor: Theme.fail
                    }
                    FieldRow {
                        Layout.fillWidth: true
                        label: "时间"
                        value: root.lastErrorTimeText()
                    }
                    // 详情不用 FieldRow —— 它按 SN/IMEI 那类定长值设计会 elide,
                    // 而 Detail 最长 128 字符，截断了正好丢掉排障要看的那半句。
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.s3
                        Text {
                            text: "详情"
                            color: Theme.textSecondary
                            font.family: TypeScale.family
                            font.pointSize: TypeScale.body
                            Layout.preferredWidth: 92      // 与 FieldRow 的标签同宽
                            Layout.alignment: Qt.AlignTop
                        }
                        Text {
                            Layout.fillWidth: true
                            readonly property string detail:
                                root.lastError !== null && root.lastError.Detail !== undefined
                                ? String(root.lastError.Detail) : ""
                            text: detail.length > 0 ? detail : "—"
                            color: detail.length > 0 ? Theme.textPrimary : Theme.textDim
                            font.family: "Consolas"
                            font.pointSize: TypeScale.body
                            font.weight: TypeScale.weightMedium
                            wrapMode: Text.WrapAnywhere
                        }
                    }
                }
            }

            // 设备 ptest.log 尾部原文（管道分隔：时间戳|请求号|指令|测试项|结果码|详情）
            Card {
                title: "设备日志尾部 PtestLogTail"
                titleIcon: Icons.history
                Layout.fillWidth: true
                Layout.preferredHeight: 240

                ScrollView {
                    id: tailScroll
                    anchors.fill: parent
                    clip: true
                    TextArea {
                        width: tailScroll.availableWidth   // 同上:不钉宽度长行不换行
                        readOnly: true
                        selectByMouse: true
                        // 内容 = root.logTailText，仅 Seq 变化时被 onInfoUpdated 更新
                        text: root.logTailText.length > 0 ? root.logTailText
                                                          : "—（设备未上报该属性）"
                        wrapMode: TextArea.WrapAnywhere
                        background: null
                        color: Theme.textSecondary
                        font.family: "Consolas"
                        font.pointSize: TypeScale.caption
                    }
                }

                AppButton {
                    anchors { top: parent.top; right: parent.right }
                    z: 1
                    height: 30
                    visible: root.logTailText.length > 0
                    text: tailCopiedTick.running ? "已复制" : "复制"
                    onClicked: {
                        FileIo.copyText(root.logTailText);
                        tailCopiedTick.restart();
                    }
                    Timer { id: tailCopiedTick; interval: 1200 }
                }
            }
        }
    }
}
