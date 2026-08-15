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

        // ---- 中:测试项 ----
        Card {
            title: "测试项  ·  profile ∩ 设备能力集"
            titleIcon: Icons.navFinished
            Layout.fillWidth: true
            Layout.fillHeight: true

            ColumnLayout {
                anchors.fill: parent
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

                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 2
                    model: rows
                    ScrollBar.vertical: ScrollBar {}

                    delegate: TestItemRow {
                        required property var modelData
                        width: ListView.view.width
                        model: modelData
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

        // ---- 右:结果 + 设备信息 ----
        ColumnLayout {
            Layout.preferredWidth: 320
            Layout.fillWidth: false
            Layout.fillHeight: true
            spacing: Theme.s4

            ResultBanner {
                Layout.fillWidth: true
                Layout.preferredHeight: 172
                state_: "running"
                caption: "喇叭  ·  等待设备回报"
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
