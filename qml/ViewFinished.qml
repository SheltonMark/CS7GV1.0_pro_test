import QtQuick
import ptest
import QtQuick.Controls
import QtQuick.Layouts

// 成品/准成品工位 —— 信息最密的一屏,也是设计上最吃力的一屏。
// 布局:左=流程步骤 / 中=测试项主表 / 右=结果爆点+设备信息
Item {
    property bool semi: false

    ConfirmDialog { id: confirm }

    // 实际下发行集(规则4) = profile 固定项 ∩ 设备 SupportedItems:
    // - profile 要求而设备未上报 → state 覆写为 5(缺能力,标红,计不通过),不静默跳过
    // - 设备上报而 profile 不含 → 不出现在列表(不下发)
    // SupportedItems 是运行时上报值,这里每次现算,不落任何硬编码。
    readonly property var rows: {
        if (!Session.profile) return [];
        const dev = MockData.supportedItems;
        return Session.profile.items.map(function (bit) {
            const base = MockData.itemByBit(bit);
            if (dev & (1 << bit)) return base;
            return Object.assign({}, base, { state: 5, reading: "" });
        });
    }

    // 自动项(设备回读数,PC 比阈值可自动判) vs 人工项(设备只回 ok,
    // 真实结论在工人眼睛耳朵里)。分开的理由见 ManualVerifyPanel 头注释。
    // 人工判定项:设备只回 ok、发光/出声固件感知不到的项。
    // CS7G 无红外灯(全彩夜视用白光补光),故只有三项。
    readonly property var manualBits: [0, 2, 7]        // 指示灯/白光/喇叭
    readonly property var autoRows: rows.filter(r => manualBits.indexOf(r.item) < 0)
    readonly property var manualRows: rows.filter(r => manualBits.indexOf(r.item) >= 0)

    readonly property var counts: {
        const c = { pass: 0, fail: 0, run: 0, wait: 0, miss: 0 };
        rows.forEach(function (r) {
            if (r.state === 2) c.pass++;
            else if (r.state === 3) c.fail++;
            else if (r.state === 1) c.run++;
            else if (r.state === 5) c.miss++;
            else c.wait++;
        });
        return c;
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
                steps: MockData.finishedSteps
            }
        }

        // ---- 中:自动测试项 + 人工判定 + 写标识 ----
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
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
                        text: "SupportedItems  0x" + MockData.supportedItems.toString(16).toUpperCase()
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
                        text: "开始自动化测试"
                        glyph: Icons.play
                        kind: "primary"
                        Layout.fillWidth: true
                        // 自动项跑完后开放人工判定面板
                        onClicked: manualPanel.ready = true
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

            // 写标识:自动项全过 + 人工项全判且无异常,才允许写
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.s3

                AppButton {
                    text: semi ? "写准成品标识" : "写成品标识"
                    glyph: Icons.save
                    kind: "primary"
                    enabled: counts.fail === 0 && counts.miss === 0
                             && manualPanel.allDone && !manualPanel.anyFail
                    onClicked: confirm.ask(semi ? "写入准成品标识？" : "写入成品标识？",
                        "将写入" + (semi ? "准成品（Stage=2）" : "成品（Stage=3）")
                        + "完成时间戳，自动项与人工判定均已通过。",
                        function () { /* 真实实现:PtestWriteStage */ })
                }

                Text {
                    Layout.fillWidth: true
                    visible: !(counts.fail === 0 && counts.miss === 0
                               && manualPanel.allDone && !manualPanel.anyFail)
                    text: {
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

            Card {
                title: "设备信息"
                titleIcon: Icons.device
                Layout.fillWidth: true
                Layout.fillHeight: true

                Column {
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    spacing: Theme.s3

                    FieldRow { width: parent.width; label: "IMEI";    value: MockData.imei }
                    FieldRow { width: parent.width; label: "UUID";    value: MockData.uuid }
                    FieldRow { width: parent.width; label: "MAC";     value: MockData.mac }
                    FieldRow { width: parent.width; label: "软件";    value: MockData.swVersion }
                    FieldRow { width: parent.width; label: "硬件";    value: MockData.hwVersion }
                    FieldRow {
                        width: parent.width
                        label: "密钥校验"
                        value: MockData.secretCrc32
                        valueColor: Theme.pass
                    }

                    Rectangle { width: parent.width; height: 1; color: Theme.border }

                    FieldRow { width: parent.width; label: "调焦";   value: MockData.focusTime;   valueColor: Theme.pass }
                    FieldRow { width: parent.width; label: "准成品"; value: MockData.semiTime;    valueColor: Theme.pass }
                    FieldRow { width: parent.width; label: "成品";   value: MockData.finishTime }
                    FieldRow { width: parent.width; label: "检查";   value: MockData.inspectTime }
                }
            }
        }
    }
}
