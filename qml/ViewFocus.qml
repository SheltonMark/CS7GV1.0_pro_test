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
//   CS6GV2.0(无网口) → 走云: Xp2pClient 建联取本机 http-flv URL 交同一个
//     LivePreview 播放。设备标识来自 cloud_config.json(经 CloudClient 暴露)。
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

    // 云拉流模式 = 非 RTSP 产品（无网口，如 CS6GV2.0）。走 XP2P 建联拿本机
    // http-flv URL，再交给同一个 LivePreview 播放（见 Xp2pClient / 拉流整合方案）。
    readonly property bool cloudMode: !rtspMode

    // 拉流排障面板开关。默认收起（见 StreamLogPanel），出问题工人点开即可
    // 「复制全部」发回来，所以常驻不再是负担。
    readonly property bool showStreamDebug: true

    property string sentStamp: ""
    property string writtenStamp: ""
    property int writeReqId: -1

    ConfirmDialog { id: confirm }
    Toast { id: toast }

    // 局域网设备发现(UDP 广播,CP3 老协议,详见 device_discovery.hpp)。
    // 页面级实例,非单例 —— 只有调焦工位用,7319 端口仅在搜索期间占用。
    DeviceDiscovery { id: finder }

    // 工位页常驻不销毁(Main 里只切 visible),切走页面必须停广播,否则搜索会
    // 在后台一直发包;云会话也要收 —— 同一设备并发拉流有上限,不收会占名额
    // (docs/拉流整合方案.md §1.2)。RTSP 侧由 sourceUrl 清空自理。
    onVisibleChanged: if (!visible) { finder.stop(); Xp2pClient.stop(); }

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

    // 双击搜索结果 = 选定该设备:停广播(目的已达成,不再打扰网络)、
    // 填 IP、立即拉流。换台设备时再点搜索,起搜前会 clear 旧列表。
    function pickDevice(ip) {
        finder.stop();
        ipField.text = ip;
        preview.sourceUrl = "";          // 与「重新拉流」同款:先断再连
        preview.sourceUrl = root.rtspUrl;
    }

    // 云拉流开始/重来:先断旧画面,再让 XP2P 建联。URL 就绪经 onLiveUrlReady
    // 回来塞给 preview;失败/断流经 Connections 提示。设备标识来自 cloud_config。
    function startCloudStream() {
        preview.sourceUrl = "";
        // quality=super（主码流）。合法值 standard/high/super，字符串→码流的映射
        // 在闭源 app_interface.dll 里。**对齐服役的手机 App**：其 mapLiveQuality
        // 主码流恒返回 "super"（子码流才 "standard"），从不用 "high"。之前照 SDK
        // 泛用样例试 standard/high 都卡 0%——设备/SDK 这套组合很可能不把 "high"
        // 路由到在跑的主编码器。super 是参考实现实际在用的值，不是猜。
        Xp2pClient.start(CloudClient.productId, CloudClient.deviceName, "super");
    }

    Connections {
        target: Xp2pClient
        // ⚠️ 必须按页面可见性开关。工位页常驻不销毁（Main 只切 visible），而
        // Xp2pClient 是单例 —— 不加这一条，本页在后台也会收到别的工位触发的
        // onLiveUrlReady，于是**同一个 URL 被两个播放器同时打开**，两个 HTTP GET
        // 打本机代理。设备只支持一路直播会话，第二个请求进来就把第一个踢掉，
        // 表现为刚出图就 StreamEnd（实测日志：同一 URL 相隔 8ms 打开两次，
        // 缓冲/cipher init/nettype 全部成对出现）。
        enabled: root.visible
        function onLiveUrlReady(url) {
            preview.sourceUrl = url;     // 本机 http-flv,libvlc 直接播
        }
        function onErrorTextChanged() {
            if (Xp2pClient.errorText.length > 0) {
                preview.sourceUrl = "";
                toast.show("云拉流失败: " + Xp2pClient.errorText, false);
            }
        }
        function onStreamEnded(reason) {
            preview.sourceUrl = "";
            toast.show(reason, false);
        }
    }


    Connections {
        target: finder
        function onLastErrorChanged() {
            // 7319 被占/被安全软件拦时工人要看到原因,不是"点了没反应"
            if (finder.lastError.length > 0)
                toast.show("设备搜索失败: " + finder.lastError, false);
        }
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

            // 预览区。双击 → 全屏（Main 顶层的 liveFull 层把 preview 重挂过去，
            // Esc/再双击退出）。外面包一层槽位 Item：若 preview 直接挂在
            // ColumnLayout 下，全屏挂回来会被排到布局末尾（Layout 按子项
            // 顺序摆位）；槽位不动，preview 来去都 anchors.fill 当前父项。
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                LivePreview {
                    id: preview
                    anchors.fill: parent
                    showGrid: true
                    hint: root.rtspMode
                          ? "RTSP 直拉（网口）· 点「搜索设备」或手填 IP"
                          : (Xp2pClient.available
                             ? "该产品无网口，拉流走云 · 点「开始拉流」建联"
                             : "云拉流 SDK 未就绪（dist/xp2p/app_interface.dll 缺失）")
                    onFullscreenRequested: liveFull.open("调焦 · 实时画面", preview)
                }
            }

            // 发现面板:搜索中或有结果且未拉流时出现;拉流一开就让位 ——
            // 画面是主角,面板不跟它抢高度。visible 条件收在本页,
            // 面板文件只管展示。
            DeviceDiscoveryPanel {
                discovery: finder
                visible: root.rtspMode && (finder.searching
                         || (finder.devices.length > 0 && !preview.streaming))
                Layout.fillWidth: true
                Layout.preferredHeight: implicitHeight
                onPicked: ip => root.pickDevice(ip)
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.s3

                // 搜索设备(老 CP3 交互):UDP 广播搜索字 → 设备应答进上方
                // 列表 → 双击拉流。手动 IP 框保留作兜底(设备端没有广播
                // 应答服务时列表恒空,见 device_discovery.hpp 头注)。
                AppButton {
                    visible: root.rtspMode
                    text: finder.searching ? "停止搜索" : "搜索设备"
                    glyph: finder.searching ? Icons.stop : Icons.device
                    Layout.preferredWidth: 142
                    onClicked: {
                        if (finder.searching) {
                            finder.stop();
                        } else {
                            finder.clear();   // 新一轮不留旧结果,防误选上一台
                            finder.start();
                        }
                    }
                }

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
                    // 两种模式共用这颗按钮:RTSP 拼 URL 直连,云走 XP2P 建联。
                    text: root.cloudMode && Xp2pClient.connecting ? "建联中…"
                          : (preview.streaming ? "重新拉流" : "开始拉流")
                    glyph: Icons.play
                    kind: "primary"
                    // RTSP:要有 URL。云:SDK 就绪且不在建联中(建联期防连点)。
                    enabled: root.rtspMode
                             ? root.rtspUrl.length > 0
                             : (Xp2pClient.available && !Xp2pClient.connecting)
                    Layout.preferredWidth: 158
                    onClicked: {
                        if (root.rtspMode) {
                            preview.sourceUrl = "";      // 重拉:先断再连
                            preview.sourceUrl = root.rtspUrl;
                        } else {
                            root.startCloudStream();
                        }
                    }
                }
                AppButton {
                    text: "停止"
                    glyph: Icons.stop
                    enabled: preview.streaming || (root.cloudMode && Xp2pClient.connecting)
                    Layout.preferredWidth: 118
                    onClicked: {
                        preview.sourceUrl = "";
                        if (root.cloudMode) Xp2pClient.stop();
                    }
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

                // 拉流日志：跟拉流按钮同排，只一个按钮。正文/复制/清空全在模态
                // 框里 —— **不占预览高度**。早先做成页面里独立一行，把小窗挤矮，
                // Crop 从上下裁掉了画面顶部时间戳和底部 logo（同 README 第 18 条）。
                StreamLogPanel {
                    visible: root.showStreamDebug
                    Layout.preferredWidth: 150
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
                        { name: root.rtspMode ? "RTSP 拉流调焦" : "云拉流调焦",
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
