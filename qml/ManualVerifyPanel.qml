import QtQuick
import ptest
import QtQuick.Controls
import QtQuick.Layouts

// 人工判定面板。解决一个正确性问题:
//
// 九项外设里有三项(指示灯/白光/喇叭)设备只回 `ok`,意思是
// "GPIO 拉高了 / 音频送进功放了" —— 灯泡烧了、白光 LED 虚焊、喇叭线没焊上,
// 设备照样回 ok,因为固件感知不到发光和出声。
// 直接把 Code=0 打成绿✓ = 把"指令下发成功"伪装成"硬件合格",
// 灯不亮的机器会一路绿灯走完产测。
//
// 所以:自动项(电池/4G/SD,设备回读数)由 PC 比阈值自动判;
// 人工项在自动流程跑完后集中确认,一屏勾完,工人点过才算通过。
//
// 集中确认(而非逐项弹窗)是刻意的:点击次数一样,但只打断一次,产线节拍更顺。
Card {
    id: panel

    title: "人工判定  ·  目视与听音"
    titleIcon: Icons.whiteLight
    fitContent: true

    // 判定结果:key → true(通过)/false(不通过)/undefined(未判)
    property var verdicts: ({})
    // 是否已具备判定条件(自动项跑完 + 拉流已建立)
    property bool ready: false

    signal allSettled()

    // 八条人工判定。共同点：设备只能回报"指令已执行"，**现象只有人能确认**。
    // 每条都配一个「测试」按钮 —— 点它才下发（PC → 云端 → 设备），
    // 设备做出动作后由工人判正常/异常。判定按钮在下发前禁用，
    // 防止不测就点"正常"（这是产测台账失真的常见来源）。
    readonly property var checks: [
        { key: "led_red",   group: "指示灯", label: "红灯常亮",        glyph: Icons.light },
        { key: "led_blue",  group: "指示灯", label: "蓝灯常亮",        glyph: Icons.light },
        { key: "led_blink", group: "指示灯", label: "双色闪烁 500ms",  glyph: Icons.light },
        // 无红外灯条目 —— CS7G 是全彩夜视,用白光补光,没有 IR 灯硬件。
        { key: "white",     group: "白光灯", label: "亮度 100 发光",   glyph: Icons.whiteLight },
        // 喇叭与咪头拆成两条 —— 不同硬件、不同故障点：喇叭坏=放音听不到，
        // 咪头坏=说话对方听不到。合成一条判不合格时无法区分该换哪个器件。
        { key: "speaker",   group: "喇叭",   label: "能从设备听到提示音",
          glyph: Icons.speaker },
        { key: "mic",       group: "咪头",   label: "对着设备说话，能从电脑听到自己的声音",
          glyph: Icons.mic },
        // 云台与复位按键同样改人工：云台"转到位、无异响、无卡顿"固件测不出
        //（电机堵转但电流正常的虚位它感知不到）；复位键要人去按，
        // 设备只能上报"收到按键事件"，按键手感/回弹得人手判断。
        { key: "gimbal",    group: "云台",   label: "上下左右转动到位，无异响、无卡顿",
          glyph: Icons.gimbal },
        { key: "reset_key", group: "复位按键", label: "按住复位键 3 秒，设备应上报按键事件",
          glyph: Icons.button }
    ]

    // 每项是否已下发测试指令。未下发 → 判定按钮禁用。
    property var dispatched: ({})
    // 正在下发的项与其 RequestId（云链路真实闭环，2026-08-17 接入）
    property string pendingKey: ""
    property int pendingReq: -1
    // 最近一次下发失败原因（工人可见；下次下发时清空）
    property string lastError: ""

    // key → PtestPeripheralTest 参数。语义与设备端 peripheral_executors 对齐：
    // 指示灯 P1 颜色 0红/1蓝/2双色、P2 闪烁周期ms(0=常亮)；白光 P1 亮度；
    // 喇叭 P2 次数（P1 音量固定出厂默认）；复位键=查询等待按键事件。
    readonly property var actionMap: ({
        led_red:   { item: 0, op: 1, p1: 0,   p2: 0 },
        led_blue:  { item: 0, op: 1, p1: 1,   p2: 0 },
        led_blink: { item: 0, op: 1, p1: 2,   p2: 500 },
        white:     { item: 2, op: 1, p1: 100, p2: 0 },
        speaker:   { item: 7, op: 4, p1: 0,   p2: 1 },
        mic:       { item: 8, op: 1, p1: 0,   p2: 0 },
        gimbal:    { item: 6, op: 4, p1: 0,   p2: 0 },
        reset_key: { item: 4, op: 0, p1: 0,   p2: 0 }
    })

    function dispatch(key) {
        const a = actionMap[key];
        lastError = "";
        pendingKey = key;
        pendingReq = CloudClient.peripheralTest(a.item, a.op, a.p1, a.p2, "");
    }

    Connections {
        target: CloudClient
        function onCommandFinished(requestId, command, item, code, detail) {
            if (requestId !== panel.pendingReq) return;   // 不是本面板的指令
            const key = panel.pendingKey;
            panel.pendingReq = -1;
            panel.pendingKey = "";
            if (code === 0) {
                var d = {};
                for (var k in panel.dispatched) d[k] = panel.dispatched[k];
                d[key] = true;
                panel.dispatched = d;
            } else {
                // 设备没做出动作，现象无从判定 → 不开判定按钮，报原因供重试
                panel.lastError = "下发未执行  Code=" + code
                                  + (detail.length > 0 ? "  " + detail : "");
            }
        }
        function onCommandTimeout(requestId) {
            if (requestId !== panel.pendingReq) return;
            panel.pendingReq = -1;
            panel.pendingKey = "";
            panel.lastError = "等待设备上报超时，可重试";
        }
        function onCommandFailed(requestId, error) {
            if (requestId !== panel.pendingReq) return;
            panel.pendingReq = -1;
            panel.pendingKey = "";
            panel.lastError = "通道错误: " + error;
        }
    }

    readonly property int settledCount: {
        var n = 0;
        for (var i = 0; i < checks.length; i++)
            if (verdicts[checks[i].key] !== undefined) n++;
        return n;
    }
    readonly property bool allDone: settledCount === checks.length
    readonly property bool anyFail: {
        for (var i = 0; i < checks.length; i++)
            if (verdicts[checks[i].key] === false) return true;
        return false;
    }

    function setVerdict(key, ok) {
        var v = {};
        for (var k in verdicts) v[k] = verdicts[k];
        v[key] = ok;
        verdicts = v;
        if (allDone) allSettled();
    }

    // 换机器要一起清 dispatched —— 否则上一台的"已下发"状态残留,
    // 新机器不测就能直接点"正常"。
    function reset() {
        verdicts = ({});
        dispatched = ({});
        pendingKey = "";
        pendingReq = -1;
        lastError = "";
    }

    ConfirmDialog { id: confirm }

    ColumnLayout {
        anchors { left: parent.left; right: parent.right; top: parent.top }
        spacing: Theme.s2

        Text {
            Layout.fillWidth: true
            text: panel.ready
                  ? "逐条点「测试」下发指令，设备动作后判定实际现象。设备回报「指令已执行」不代表硬件正常。"
                  : "自动项完成并拉流后开放判定。"
            color: panel.ready ? Theme.textSecondary : Theme.textDim
            font.family: TypeScale.family
            font.pointSize: TypeScale.body
            wrapMode: Text.WordWrap
        }

        Text {
            Layout.fillWidth: true
            visible: panel.lastError.length > 0
            text: panel.lastError
            color: Theme.fail
            font.family: TypeScale.family
            font.pointSize: TypeScale.caption
            wrapMode: Text.WordWrap
        }

        Repeater {
            model: panel.checks

            RowLayout {
                required property var modelData
                readonly property var verdict: panel.verdicts[modelData.key]

                Layout.fillWidth: true
                spacing: Theme.s2
                enabled: panel.ready

                Rectangle {
                    width: 26; height: 26
                    radius: Theme.radius
                    color: verdict === undefined ? Qt.rgba(1, 1, 1, 0.04)
                           : verdict ? Qt.rgba(0.133, 0.773, 0.369, 0.13)
                                     : Qt.rgba(0.937, 0.267, 0.267, 0.13)
                    Behavior on color { ColorAnimation { duration: Theme.durFast } }

                    Icon {
                        anchors.centerIn: parent
                        text: modelData.glyph
                        size: 15
                        color: verdict === undefined ? Theme.textSecondary
                               : verdict ? Theme.pass : Theme.fail
                    }
                }

                ColumnLayout {
                    spacing: 1
                    Layout.fillWidth: true

                    Text {
                        text: modelData.group
                        color: Theme.textPrimary
                        font.family: TypeScale.family
                        font.pointSize: TypeScale.body
                        font.weight: TypeScale.weightMedium
                    }
                    Text {
                        text: modelData.label
                        color: Theme.textSecondary
                        font.family: TypeScale.family
                        font.pointSize: TypeScale.caption
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }

                // 「测试」= 下发本项指令（PC → 云端 → 设备）。设备动作后才有现象可判，
                // 所以它是每一项的入口；下发中显示进行态，完成后可重复点（重测）。
                AppButton {
                    readonly property bool sending: panel.pendingKey === modelData.key
                    readonly property bool done: panel.dispatched[modelData.key] === true
                    text: sending ? "下发中…" : (done ? "重测" : "测试")
                    glyph: sending ? Icons.reset : modelData.glyph
                    kind: done ? "normal" : "primary"
                    // 一次只允许一条在途:pendingReq 是单槽,并发会错配结果
                    enabled: panel.ready && panel.pendingKey.length === 0
                    implicitHeight: Theme.hit - 8
                    Layout.preferredWidth: 96
                    onClicked: panel.dispatch(modelData.key)
                }

                // 判定按钮:必须先「测试」下发过才可点 ——
                // 否则台账里会出现"没测就判通过"的记录。
                AppButton {
                    text: "正常"
                    glyph: Icons.pass
                    kind: verdict === true ? "primary" : "normal"
                    enabled: panel.dispatched[modelData.key] === true
                    implicitHeight: Theme.hit - 8
                    onClicked: panel.setVerdict(modelData.key, true)
                }

                AppButton {
                    text: "异常"
                    glyph: Icons.fail
                    kind: verdict === false ? "danger" : "normal"
                    enabled: panel.dispatched[modelData.key] === true
                    implicitHeight: Theme.hit - 8
                    // 判不良是终局结论,要确认
                    onClicked: confirm.ask("判定异常？",
                        modelData.group + "（" + modelData.label + "）将记为不通过，设备转维修。",
                        function () { panel.setVerdict(modelData.key, false) })
                }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderSoft }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.s3

            Text {
                text: "已判定 " + panel.settledCount + " / " + panel.checks.length
                color: panel.allDone ? (panel.anyFail ? Theme.fail : Theme.pass)
                                     : Theme.textSecondary
                font.family: TypeScale.family
                font.pointSize: TypeScale.body
                font.weight: TypeScale.weightMedium
            }

            Item { Layout.fillWidth: true }

            AppButton {
                text: "全部重判"
                glyph: Icons.reset
                implicitHeight: Theme.hit - 8
                visible: panel.settledCount > 0
                onClicked: panel.reset()
            }
        }
    }
}
