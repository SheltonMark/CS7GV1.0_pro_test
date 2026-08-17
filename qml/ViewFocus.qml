import QtQuick
import ptest
import QtQuick.Controls
import QtQuick.Layouts

// 调焦工位 —— 画面是主角,占最大面积。无尘室里工人边转镜头边看这一屏。
//
// 拉流通道按产品分流(2026-08-17 定案):
//   CS7GV1.0(带网口) → RTSP 直拉。URL 模板在 factory_config.json,IP 来自
//     设备上报(DeviceInformation.IpAddress,自动带出),也允许手改 —— 产线
//     网段/静态 IP 变化不用改代码。RTSP 比上云快,调焦跟手。
//   CS6GV2.0(无网口) → 走云(XP2P),SDK spike 后接入,当前占位提示。
// 写调焦标识 = 真实指令闭环:下发(Stage=1) → 回读 FocusTime 核对 → toast。
Item {
    id: root

    // 画面人工判定:undefined 未判 / true 清晰 / false 不合格。
    // 写标识按钮以此为门 —— 没判过不许写(否则等于没测就盖章)。
    property var imageOk: undefined

    property var devInfo: ({})
    readonly property bool infoConnected: devInfo.SupportedItems !== undefined
    readonly property bool rtspMode: Session.profile
                                     ? Session.profile.focusRtsp === true : false
    readonly property string rtspUrl: ipField.text.trim().length > 0
        ? FactoryConfig.rtspUrlTemplate.arg(ipField.text.trim()) : ""

    property string sentStamp: ""
    property string writtenStamp: ""
    property int writeReqId: -1

    ConfirmDialog { id: confirm }
    Toast { id: toast }

    function dv(key) {
        return devInfo[key] !== undefined && devInfo[key] !== "" ? devInfo[key] : "—";
    }

    function nowStamp17() {
        return Qt.formatDateTime(new Date(), "yyyyMMddHHmmsszzz");
    }

    function doWriteStage() {
        sentStamp = nowStamp17();
        writeReqId = CloudClient.writeStage(1, sentStamp);
    }

    Connections {
        target: CloudClient
        function onInfoUpdated(info) {
            const hadIp = ipField.text.trim().length > 0;
            root.devInfo = info;
            // IP 自动带出(设备上报);工人手填过就不覆盖
            if (!hadIp && info.IpAddress !== undefined
                && ("" + info.IpAddress).length > 0)
                ipField.text = info.IpAddress;
            // 写标识回读确认:设备里读出的 FocusTime == 刚下发的才算写成功
            if (root.sentStamp.length > 0 && info.FocusTime === root.sentStamp) {
                root.writtenStamp = root.sentStamp;
                root.sentStamp = "";
                toast.show("调焦标识已写入并回读确认  " + root.writtenStamp, true);
            }
        }
        function onCommandFinished(requestId, command, item, code, detail) {
            if (requestId !== root.writeReqId) return;
            root.writeReqId = -1;
            if (code === 0) {
                CloudClient.refreshInfo();   // 回读验证,见 onInfoUpdated
            } else {
                root.sentStamp = "";
                toast.show("调焦标识写入失败  Code=" + code
                           + (detail.length > 0 ? "  " + detail : ""), false);
            }
        }
        function onCommandTimeout(requestId) {
            if (requestId !== root.writeReqId) return;
            root.writeReqId = -1;
            root.sentStamp = "";
            toast.show("写调焦标识超时，可重试", false);
        }
        function onCommandFailed(requestId, error) {
            if (requestId !== root.writeReqId) return;
            root.writeReqId = -1;
            root.sentStamp = "";
            toast.show("通道错误: " + error, false);
        }
    }

    Component.onCompleted: {
        CloudClient.refreshInfo();
        // 工位开头同步设备时间(设备端"时间戳留空用本地时间"依赖它)
        const d = new Date();
        CloudClient.invokeGenericAction("SetDeviceTime", {
            Year: d.getFullYear(), Month: d.getMonth() + 1, Day: d.getDate(),
            Hour: d.getHours(), Minute: d.getMinutes(), Second: d.getSeconds() });
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: Theme.s5
        spacing: Theme.s4

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.s4

            // 预览区。双击 → 全屏（Main 顶层的 liveFull 层，Esc 退出）。
            LivePreview {
                id: preview
                Layout.fillWidth: true
                Layout.fillHeight: true
                showGrid: true
                hint: root.rtspMode ? "RTSP 直拉（网口）· 点「开始拉流」"
                                    : "该产品无网口，拉流走云（XP2P 待接入）"
                onFullscreenRequested: liveFull.open("调焦 · 实时画面")
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.s3

                // CS7G:设备 IP(上报自动带出,可手改)。URL = 模板.arg(IP)
                TextField {
                    id: ipField
                    visible: root.rtspMode
                    Layout.preferredWidth: 176
                    placeholderText: "设备 IP（自动带出）"
                    enabled: !preview.streaming
                    font.family: "Consolas"
                    font.pointSize: TypeScale.body
                }

                AppButton {
                    text: preview.streaming ? "重新拉流" : "开始拉流"
                    glyph: Icons.play
                    kind: "primary"
                    enabled: root.rtspMode && root.rtspUrl.length > 0
                    Layout.preferredWidth: 158
                    onClicked: {
                        preview.sourceUrl = "";          // 重拉:先断再连
                        preview.sourceUrl = root.rtspUrl;
                    }
                }
                AppButton {
                    text: "停止"
                    glyph: Icons.stop
                    enabled: preview.streaming
                    Layout.preferredWidth: 118
                    onClicked: preview.sourceUrl = ""
                }

                Text {
                    visible: root.rtspMode && preview.streaming
                    text: root.rtspUrl
                    color: Theme.textDim
                    font.family: "Consolas"
                    font.pointSize: TypeScale.caption
                    elide: Text.ElideMiddle
                    Layout.maximumWidth: 300
                }

                Item { Layout.fillWidth: true }

                AppButton {
                    text: "调焦完成，写标识"
                    glyph: Icons.save
                    kind: "primary"
                    Layout.preferredWidth: 204
                    // 画面未判定或判为不合格 → 不许写;指令在途禁用
                    enabled: root.imageOk === true && root.writeReqId < 0
                             && root.sentStamp.length === 0
                    onClicked: confirm.ask("写入调焦标识？",
                        "将向设备写入调焦完成时间戳（Stage=1，只增不覆盖），写入后自动回读核对。",
                        function () { root.doWriteStage() })
                }
            }
        }

        // 右栏:极简 —— 调焦工位工人手在转镜头,不该被信息干扰
        ColumnLayout {
            Layout.preferredWidth: 300
            Layout.fillWidth: false
            Layout.fillHeight: true
            spacing: Theme.s4

            ResultBanner {
                Layout.fillWidth: true
                Layout.preferredHeight: 160
                state_: root.imageOk === undefined ? "idle"
                        : (root.imageOk ? "pass" : "fail")
                caption: root.imageOk === undefined ? "等待画面确认"
                         : (root.imageOk ? "画面清晰，可写标识" : "画面不合格，转返修")
            }

            // 调焦工位的核心判定就是"画面清不清晰",而这只能人工看。
            // 咪头判定在成品页与喇叭合并(一步双验) —— 无尘室噪音大,
            // 声音判定不宜放这里。
            Card {
                title: "画面  ·  人工判定"
                titleIcon: Icons.navFocus
                fitContent: true
                Layout.fillWidth: true

                Column {
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    spacing: Theme.s3

                    Text {
                        width: parent.width
                        text: "转动镜头至画面最清晰，确认无偏色、无暗角、无异物后判定。"
                        color: Theme.textSecondary
                        font.family: TypeScale.family
                        font.pointSize: TypeScale.body
                        wrapMode: Text.WordWrap
                    }

                    Row {
                        spacing: Theme.s3
                        // 人工判定 = 终局结论,两个方向都要确认
                        AppButton {
                            text: "清晰"
                            glyph: Icons.pass
                            kind: root.imageOk === true ? "primary" : "normal"
                            width: 116
                            onClicked: confirm.ask("画面判定：清晰？",
                                "确认画面已调至最清晰，该工位可写调焦标识。",
                                function () { root.imageOk = true })
                        }
                        AppButton {
                            text: "不合格"
                            glyph: Icons.fail
                            kind: root.imageOk === false ? "danger" : "normal"
                            width: 116
                            onClicked: confirm.ask("画面判定：不合格？",
                                "该设备记为调焦不合格并转返修。",
                                function () { root.imageOk = false })
                        }
                    }

                    // 写进设备的真值回显 —— 工人核对的是回读值,不是一句"成功"
                    FieldRow {
                        width: parent.width
                        label: "调焦时间戳"
                        value: root.dv("FocusTime")
                        valueColor: root.writtenStamp.length > 0 ? Theme.pass
                                                                 : Theme.textPrimary
                    }
                }
            }

            Card {
                title: "工位流程"
                titleIcon: Icons.navFocus
                Layout.fillWidth: true
                Layout.fillHeight: true

                StepList {
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    steps: [
                        { name: "连接设备 · 读信息",
                          state: root.infoConnected ? 2 : 1 },
                        { name: root.rtspMode ? "RTSP 拉流调焦" : "云拉流调焦（待接入）",
                          state: preview.playing ? 1
                                 : (root.writtenStamp.length > 0 ? 2 : 0) },
                        { name: "画面判定",
                          state: root.imageOk !== undefined ? 2 : 0 },
                        { name: "写调焦标识",
                          state: root.writtenStamp.length > 0 ? 2
                                 : (root.imageOk === true ? 1 : 0) },
                        { name: "停止拉流",
                          state: root.writtenStamp.length > 0 && !preview.streaming
                                 ? 2 : 0 }
                    ]
                }
            }
        }
    }
}
