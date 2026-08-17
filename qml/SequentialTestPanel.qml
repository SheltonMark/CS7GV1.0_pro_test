import QtQuick
import ptest
import QtQuick.Controls
import QtQuick.Layouts

// 逐项测试面板(2026-08-17 流程简化版)：工人只做两件事 —— 点一次开始、给判定。
//   「开始测试」(鼠标或空格) → 自动项连续执行 → 人工项逐条**自动下发**
//   (下发中转圈) → 直接出判定页：回车 = 正常，空格 = 异常 → 判完即下发下一条。
//   每项结果以 toast 气泡在卡片中间反馈(约 0.9s);展示期间按键忽略(防连按)。
//   自动项失败停留(空格重测/工程师跳过/↑↓换项);人工判异常已是终局记录,照常前进。
//   全部测完 → 汇总页：回车 = 确认结果(进写标识)，回格 = 返回可重测。
// 有失败/跳过最终不能写标识(定稿口径)。
FocusScope {
    id: panel

    // 队列条目:{ kind:"auto"|"manual", item, key?, name, sub, op, p1, p2, miss }
    property var queue: []

    property int cursor: 0
    property var results: ({})      // 索引 → {status:"pass"|"fail"|"skip", reading}
    // 相位: idle 无队列 | item 单项页 | running 指令在途 | judge 等人工判定
    //     | shown 结果气泡展示(按键屏蔽) | summary 汇总确认 | confirmed 已确认
    property string phase: "idle"
    property int pendingReq: -1
    property string toastText: ""
    property string toastStatus: "pass"   // pass | fail | skip

    readonly property var current: cursor < queue.length ? queue[cursor] : null
    readonly property var currentResult: results[cursor]
    readonly property int total: queue.length
    readonly property int settled: Object.keys(results).length
    readonly property bool confirmed: phase === "confirmed"
    readonly property bool anyBad: {
        for (var k in results)
            if (results[k].status !== "pass") return true;
        return false;
    }

    signal allFinished()

    onQueueChanged: reset()
    Component.onCompleted: reset()

    function reset() {
        cursor = 0;
        results = ({});
        pendingReq = -1;
        toastText = "";
        phase = queue.length > 0 ? "ready" : "idle";
    }

    // 「开始测试」:从头链式执行整条队列(自动项直接跑,人工项下发后出判定页)
    function startAll() {
        if (phase !== "ready" || total === 0) return;
        cursor = 0;
        phase = "item";
        startCurrent();
    }

    function startCurrent() {
        if (phase !== "item" || !current) return;
        if (current.miss) {
            record("fail", "设备缺能力（SupportedItems 未含该项）");
            return;
        }
        phase = "running";
        pendingReq = CloudClient.peripheralTest(current.item, current.op,
                                                current.p1, current.p2, "");
    }

    function judge(ok) {
        if (phase !== "judge") return;
        record(ok ? "pass" : "fail", ok ? "人工判定：正常" : "人工判定：异常");
    }

    function skipCurrent() {
        if (phase !== "item" || !current) return;
        record("skip", "已跳过（" + (Session.user ? Session.user.name : "") + "）");
    }

    // 记录结果 → toast 气泡(shown 相位,按键屏蔽) → afterShown 决定去向
    function record(status, reading) {
        var r = {};
        for (var k in results) r[k] = results[k];
        r[cursor] = { status: status, reading: reading };
        results = r;
        toastStatus = status;
        toastText = (status === "pass" ? "✅ 通过"
                     : status === "skip" ? "⏭ 已跳过" : "❌ 未通过")
                    + (reading.length > 0 ? "　" + reading : "");
        phase = "shown";
        shownTimer.restart();
    }

    function nextUnsettledAfter(idx) {
        for (var step = 1; step <= total; ++step) {
            const j = (idx + step) % total;
            if (results[j] === undefined) return j;
        }
        return -1;
    }

    function afterShown() {
        const failed = currentResult !== undefined && currentResult.status === "fail";
        // 自动项失败停留(设备问题要现场处理:重测/跳过/换项);
        // 人工判异常已是工人的终局结论,记录后照常前进(2026-08-17 简化流)。
        if (failed && current !== null && current.kind === "auto") {
            phase = "item";
            return;
        }
        const nxt = nextUnsettledAfter(cursor);
        if (nxt < 0) {
            phase = "summary";            // 全部有结果 → 汇总确认页
            return;
        }
        cursor = nxt;
        phase = "item";
        startCurrent();                   // 链式:下一项自动下发,人工项直接出判定页
    }

    function nav(delta) {
        if (phase !== "item") return;
        const next = cursor + delta;
        if (next < 0 || next >= total) return;
        cursor = next;
    }

    function confirmResults() {
        if (phase !== "summary") return;
        phase = "confirmed";
        allFinished();
    }

    function backToItems() {
        if (phase !== "summary") return;
        phase = "item";
    }

    Timer { id: shownTimer; interval: 900; onTriggered: panel.afterShown() }

    Connections {
        target: CloudClient
        function onCommandFinished(requestId, command, item, code, detail) {
            if (requestId !== panel.pendingReq) return;
            panel.pendingReq = -1;
            if (panel.current === null) return;
            if (panel.current.kind === "auto") {
                if (code === 0)
                    panel.record("pass", detail.length > 0 ? detail : "");
                else if (code === 4)
                    panel.record("fail", "设备回：不支持");
                else
                    panel.record("fail", "Code=" + code
                                 + (detail.length > 0 ? "  " + detail : ""));
            } else {
                if (code === 0)
                    panel.phase = "judge";
                else
                    panel.record("fail", "下发未执行  Code=" + code
                                 + (detail.length > 0 ? "  " + detail : ""));
            }
        }
        function onCommandTimeout(requestId) {
            if (requestId !== panel.pendingReq) return;
            panel.pendingReq = -1;
            panel.record("fail", "等待设备上报超时");
        }
        function onCommandFailed(requestId, error) {
            if (requestId !== panel.pendingReq) return;
            panel.pendingReq = -1;
            panel.record("fail", "通道错误: " + error);
        }
    }

    focus: true
    Keys.onPressed: (event) => {
        // shown/running 相位一律忽略按键:结果展示与指令在途时手快连按不生效
        if (event.key === Qt.Key_Space) {
            if (phase === "ready") { startAll(); event.accepted = true; }
            else if (phase === "item") { startCurrent(); event.accepted = true; }
            else if (phase === "judge") { judge(false); event.accepted = true; }  // 空格=异常
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (phase === "judge") { judge(true); event.accepted = true; }        // 回车=正常
            else if (phase === "summary") { confirmResults(); event.accepted = true; }
        } else if (event.key === Qt.Key_Backspace) {
            if (phase === "summary") { backToItems(); event.accepted = true; }
        } else if (event.key === Qt.Key_Up) {
            if (phase === "item") { nav(-1); event.accepted = true; }
        } else if (event.key === Qt.Key_Down) {
            if (phase === "item") { nav(1); event.accepted = true; }
        }
    }

    // 键帽:按键提示做"实体键"观感(反馈#3:整体加大)
    component KeyCap: Rectangle {
        property string cap: ""
        width: capText.implicitWidth + Theme.s5
        height: 38
        radius: 7
        color: Qt.rgba(1, 1, 1, 0.07)
        border.width: 1
        border.color: Theme.border
        Text {
            id: capText
            anchors.centerIn: parent
            text: parent.cap
            color: Theme.textPrimary
            font.family: TypeScale.family
            font.pointSize: TypeScale.body
            font.weight: TypeScale.weightBold
        }
    }

    component KeyHint: Row {
        property string cap: ""
        property string label: ""
        property color labelColor: Theme.textSecondary
        spacing: Theme.s2
        KeyCap { cap: parent.cap; anchors.verticalCenter: parent.verticalCenter }
        Text {
            text: parent.label
            color: parent.labelColor
            font.family: TypeScale.family
            font.pointSize: TypeScale.heading
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    Card {
        anchors.fill: parent
        title: phase === "summary" ? "测试结果汇总  ·  确认后进入写标识"
                                   : "逐项测试"
        titleIcon: Icons.navFinished

        MouseArea {
            anchors.fill: parent
            onClicked: panel.forceActiveFocus()
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: Theme.s3

            // ---- 进度点列 + 上/下项按钮 ----
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Theme.s2
                visible: panel.total > 0 && panel.phase !== "summary"
                         && panel.phase !== "confirmed" && panel.phase !== "ready"
                spacing: Theme.s3

                AppButton {
                    text: "上一项"
                    glyph: Icons.skip
                    enabled: panel.phase === "item" && panel.cursor > 0
                    implicitHeight: Theme.hit - 12
                    onClicked: { panel.nav(-1); panel.forceActiveFocus(); }
                }

                Item { Layout.fillWidth: true }

                Row {
                    spacing: Theme.s2
                    Repeater {
                        model: panel.total
                        Rectangle {
                            required property int index
                            readonly property var res: panel.results[index]
                            width: index === panel.cursor ? 15 : 11
                            height: width
                            radius: width / 2
                            anchors.verticalCenter: parent.verticalCenter
                            color: res === undefined
                                   ? (index === panel.cursor ? Theme.running
                                                             : Qt.rgba(1, 1, 1, 0.10))
                                   : (res.status === "pass" ? Theme.pass
                                      : res.status === "skip" ? Theme.warn : Theme.fail)
                            border.width: index === panel.cursor ? 1 : 0
                            border.color: Theme.textPrimary
                            Behavior on width { NumberAnimation { duration: Theme.durFast } }
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                AppButton {
                    text: "下一项"
                    glyph: Icons.play
                    enabled: panel.phase === "item" && panel.cursor < panel.total - 1
                    implicitHeight: Theme.hit - 12
                    onClicked: { panel.nav(1); panel.forceActiveFocus(); }
                }
            }

            // ---- 主区 ----
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                // 空队列/已确认 终态
                Column {
                    visible: panel.phase === "idle" || panel.phase === "confirmed"
                    anchors.centerIn: parent
                    spacing: Theme.s3

                    Icon {
                        text: panel.confirmed ? (panel.anyBad ? Icons.fail : Icons.passRing)
                                              : Icons.pending
                        size: 52
                        color: panel.confirmed ? (panel.anyBad ? Theme.fail : Theme.pass)
                                               : Theme.textDim
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                    Text {
                        text: panel.phase === "idle"
                              ? "无勾选测试项（管理员在产品选择页配置）"
                              : (panel.anyBad ? "结果已确认：有未通过/跳过项"
                                              : "结果已确认：全部通过")
                        color: panel.confirmed && !panel.anyBad ? Theme.pass
                                                                : Theme.textSecondary
                        font.family: TypeScale.family
                        font.pointSize: TypeScale.heading * 1.2
                        font.weight: TypeScale.weightBold
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }

                // 就绪页:一颗开始按钮(鼠标/空格),之后整条队列链式执行
                Column {
                    visible: panel.phase === "ready"
                    anchors.centerIn: parent
                    spacing: Theme.s4

                    Text {
                        text: "共 " + panel.total + " 项测试（自动 + 人工）"
                        color: Theme.textSecondary
                        font.family: TypeScale.family
                        font.pointSize: TypeScale.heading
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                    AppButton {
                        text: "开始测试"
                        glyph: Icons.play
                        kind: "primary"
                        implicitHeight: Theme.hit + 10
                        implicitWidth: 220
                        anchors.horizontalCenter: parent.horizontalCenter
                        onClicked: { panel.startAll(); panel.forceActiveFocus(); }
                    }
                    KeyHint {
                        cap: "空格"; label: "开始"
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                    Text {
                        text: "自动项连续执行；人工项自动下发后直接判定：回车 = 正常，空格 = 异常"
                        color: Theme.textDim
                        font.family: TypeScale.family
                        font.pointSize: TypeScale.body
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }

                // 单项页(item/running/judge/shown)——反馈#3:字号整体加大
                Column {
                    visible: panel.current !== null
                             && (panel.phase === "item" || panel.phase === "running"
                                 || panel.phase === "judge" || panel.phase === "shown")
                    anchors.centerIn: parent
                    width: parent.width - Theme.s6 * 2
                    spacing: Theme.s4

                    Row {
                        spacing: Theme.s3
                        anchors.horizontalCenter: parent.horizontalCenter
                        Rectangle {
                            width: kindText.implicitWidth + Theme.s4
                            height: 28; radius: 14
                            color: Qt.rgba(1, 1, 1, 0.06)
                            border.width: 1; border.color: Theme.borderSoft
                            anchors.verticalCenter: parent.verticalCenter
                            Text {
                                id: kindText
                                anchors.centerIn: parent
                                text: panel.current !== null && panel.current.kind === "auto"
                                      ? "自动" : "人工"
                                color: Theme.textSecondary
                                font.family: TypeScale.family
                                font.pointSize: TypeScale.body
                            }
                        }
                        Text {
                            text: "第 " + (panel.cursor + 1) + " / " + panel.total + " 项"
                            color: Theme.textDim
                            font.family: TypeScale.family
                            font.pointSize: TypeScale.body
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    Text {
                        text: panel.current !== null ? panel.current.name : ""
                        color: Theme.textPrimary
                        font.family: TypeScale.family
                        font.pointSize: TypeScale.display * 1.5
                        font.weight: TypeScale.weightBold
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    Text {
                        width: parent.width
                        text: panel.current !== null ? panel.current.sub : ""
                        color: Theme.textSecondary
                        font.family: TypeScale.family
                        font.pointSize: TypeScale.heading
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                    }

                    // 已有结果(导航回看/失败停留)
                    Column {
                        visible: panel.phase === "item" && panel.currentResult !== undefined
                        spacing: Theme.s2
                        anchors.horizontalCenter: parent.horizontalCenter

                        Text {
                            text: panel.currentResult === undefined ? ""
                                  : panel.currentResult.status === "pass" ? "✅ 通过"
                                  : panel.currentResult.status === "skip" ? "⏭ 已跳过"
                                  : "❌ 未通过"
                            color: panel.currentResult !== undefined
                                   && panel.currentResult.status === "pass" ? Theme.pass
                                   : panel.currentResult !== undefined
                                     && panel.currentResult.status === "skip" ? Theme.warn
                                   : Theme.fail
                            font.family: TypeScale.family
                            font.pointSize: TypeScale.heading * 1.3
                            font.weight: TypeScale.weightBold
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                        Text {
                            visible: panel.currentResult !== undefined
                                     && panel.currentResult.reading.length > 0
                            text: panel.currentResult !== undefined
                                  ? panel.currentResult.reading : ""
                            color: Theme.textSecondary
                            font.family: "Consolas"
                            font.pointSize: TypeScale.body
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                        Row {
                            spacing: Theme.s3
                            anchors.horizontalCenter: parent.horizontalCenter
                            KeyHint { cap: "空格"; label: "重测" }
                            AppButton {
                                text: "跳过本项"
                                glyph: Icons.skip
                                visible: Session.canSkipItem
                                         && panel.currentResult !== undefined
                                         && panel.currentResult.status === "fail"
                                implicitHeight: Theme.hit - 8
                                onClicked: {
                                    panel.skipCurrent();
                                    panel.forceActiveFocus();
                                }
                            }
                        }
                    }

                    // 未测项停留态只在手动导航(↑↓)到未测项时出现;
                    // 正常链式流程不会停在这里。
                    KeyHint {
                        visible: panel.phase === "item" && panel.currentResult === undefined
                        cap: "空格"; label: "执行本项"
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    Column {
                        visible: panel.phase === "running"
                        spacing: Theme.s2
                        anchors.horizontalCenter: parent.horizontalCenter
                        BusyIndicator {
                            running: panel.phase === "running"
                            implicitWidth: 44; implicitHeight: 44
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                        Text {
                            text: "指令执行中，等待设备…"
                            color: Theme.textSecondary
                            font.family: TypeScale.family
                            font.pointSize: TypeScale.heading
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }

                    Column {
                        visible: panel.phase === "judge"
                        spacing: Theme.s3
                        anchors.horizontalCenter: parent.horizontalCenter
                        Text {
                            text: "设备已执行，请确认实际现象"
                            color: Theme.textPrimary
                            font.family: TypeScale.family
                            font.pointSize: TypeScale.heading
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                        Row {
                            spacing: Theme.s5
                            anchors.horizontalCenter: parent.horizontalCenter
                            KeyHint { cap: "回车"; label: "正常"; labelColor: Theme.pass }
                            KeyHint { cap: "空格"; label: "异常"; labelColor: Theme.fail }
                        }
                    }
                }

                // 结果 toast 气泡(反馈#5):卡片中间短暂展示,期间按键屏蔽
                Rectangle {
                    visible: panel.phase === "shown"
                    anchors.centerIn: parent
                    width: toastLabel.implicitWidth + Theme.s6 * 2
                    height: toastLabel.implicitHeight + Theme.s4 * 2
                    radius: Theme.radiusLg
                    color: Theme.bgDeep
                    border.width: 1
                    border.color: panel.toastStatus === "pass" ? Theme.pass
                                  : panel.toastStatus === "skip" ? Theme.warn : Theme.fail
                    z: 10

                    Text {
                        id: toastLabel
                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, 460)
                        text: panel.toastText
                        color: panel.toastStatus === "pass" ? Theme.pass
                               : panel.toastStatus === "skip" ? Theme.warn : Theme.fail
                        font.family: TypeScale.family
                        font.pointSize: TypeScale.heading * 1.2
                        font.weight: TypeScale.weightBold
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                // 汇总确认页:全部项 + 结果(自动+人工)
                ColumnLayout {
                    visible: panel.phase === "summary"
                    anchors.fill: parent
                    spacing: Theme.s2

                    ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: panel.total
                        spacing: 4

                        delegate: Rectangle {
                            required property int index
                            readonly property var entry: panel.queue[index]
                            readonly property var res: panel.results[index]
                            width: ListView.view.width
                            height: 44
                            radius: Theme.radius
                            color: Qt.rgba(1, 1, 1, 0.03)
                            border.width: 1
                            border.color: Theme.borderSoft

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.s3
                                anchors.rightMargin: Theme.s3
                                spacing: Theme.s3

                                Text {
                                    text: (index + 1) + "."
                                    color: Theme.textDim
                                    font.family: "Consolas"
                                    font.pointSize: TypeScale.body
                                }
                                Text {
                                    text: entry.kind === "auto" ? "自动" : "人工"
                                    color: Theme.textDim
                                    font.family: TypeScale.family
                                    font.pointSize: TypeScale.body
                                }
                                Text {
                                    text: entry.name
                                    color: Theme.textPrimary
                                    font.family: TypeScale.family
                                    font.pointSize: TypeScale.body
                                    font.weight: TypeScale.weightMedium
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                Text {
                                    text: res === undefined || res.reading === undefined
                                          ? "" : res.reading
                                    color: Theme.textDim
                                    font.family: "Consolas"
                                    font.pointSize: TypeScale.caption
                                    elide: Text.ElideRight
                                    Layout.maximumWidth: 220
                                }
                                Text {
                                    text: res === undefined ? "—"
                                          : res.status === "pass" ? "✅ 通过"
                                          : res.status === "skip" ? "⏭ 跳过" : "❌ 未通过"
                                    color: res !== undefined && res.status === "pass"
                                           ? Theme.pass
                                           : res !== undefined && res.status === "skip"
                                             ? Theme.warn : Theme.fail
                                    font.family: TypeScale.family
                                    font.pointSize: TypeScale.body
                                    font.weight: TypeScale.weightBold
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.s4

                        KeyHint { cap: "回车"; label: "确认结果"; labelColor: Theme.pass }
                        KeyHint { cap: "回格"; label: "返回重测" }

                        Item { Layout.fillWidth: true }

                        AppButton {
                            text: "返回重测"
                            glyph: Icons.reset
                            implicitHeight: Theme.hit - 10
                            onClicked: { panel.backToItems(); panel.forceActiveFocus(); }
                        }
                        AppButton {
                            text: "确认结果"
                            glyph: Icons.pass
                            kind: "primary"
                            implicitHeight: Theme.hit - 10
                            onClicked: { panel.confirmResults(); panel.forceActiveFocus(); }
                        }
                    }
                }
            }

            // ---- 底部常驻:已判定 X / Y ----
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.s3

                Text {
                    text: "已判定 " + panel.settled + " / " + panel.total
                    color: panel.settled === panel.total && panel.total > 0
                           ? (panel.anyBad ? Theme.fail : Theme.pass)
                           : Theme.textSecondary
                    font.family: TypeScale.family
                    font.pointSize: TypeScale.heading
                    font.weight: TypeScale.weightBold
                }

                Item { Layout.fillWidth: true }

                AppButton {
                    text: "重新测试"
                    glyph: Icons.reset
                    visible: panel.settled > 0
                    implicitHeight: Theme.hit - 10
                    onClicked: {
                        panel.reset();
                        panel.forceActiveFocus();
                    }
                }
            }
        }
    }
}
