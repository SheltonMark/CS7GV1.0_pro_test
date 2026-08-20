import QtQuick
import ptest
import QtQuick.Controls
import QtQuick.Effects
import QtMultimedia

// 拉流预览区。
//
// 三处复用：调焦页（大窗，构图三分线辅助对中）、准成品/成品页（小窗，
// 只为确认"这台机器的画面确实出来了"）。抽成组件是因为三处的 LIVE 标记、
// 建联中提示、双击全屏行为必须一致 —— 工人换工位时不该重新学一遍。
//
// 播放:libvlc(VlcStreamPlayer,dist/vlc 运行时),rtsp://(CS7G 调焦网口直拉)与
// XP2P 的本地 http-flv URL 都吃 —— 两条拉流通道共用这一个组件。
// VideoOutput 仍来自 QtMultimedia(帧经 QVideoSink 送入),只换了解码引擎。
//
// 双击放大全屏、Esc 退出：产线工位屏常是 1080p 甚至更低，
// 小窗里看不清暗角和脏点，判画面时需要放到满屏。
Rectangle {
    id: root

    property bool showGrid: true       // 三分构图线（调焦要，其它工位不需要）
    property bool compact: false       // 小窗模式：缩小提示文字
    // 占位态的补充说明，由使用方按场景给（如"点「开始拉流」建联"）。
    // 默认空：不给就什么都不显示。⚠️ 别在这里写死文案 —— 早先默认值是
    // "demo 无真实码流"，接了真码流后就成了误导现场的过期提示。
    property string hint: ""
    // 悬停时的"双击全屏"角标。功能保留，只是不显示提示 ——
    // 准成品/成品工位的小窗上这行字挤在画面里，反而干扰看图。
    property bool showZoomHint: true

    // 全屏托管态：LiveFullscreen 把本组件整体重挂(reparent)到顶层时置 true。
    // 全屏下去圆角去边框，悬停角标换成"退出"话术。
    property bool fullscreenHosted: false

    // 拉流地址。空串 = 未拉流(占位态);赋值即自动播放,清空即停。
    property string sourceUrl: ""
    readonly property bool streaming: sourceUrl.length > 0
    // LIVE 徽标语义：首帧真送达才算在播（连上没画面不算）
    readonly property bool playing: player.playing
    property string streamError: ""

    // ── 手动起播（准成品/成品工位用）─────────────────────────────────
    // 画面中心给一个播放按钮，点了就发 playRequested，由页面去建联。
    // 调焦工位不用（起播按钮在页面下方那一排），默认关。
    property bool showPlayButton: false
    // 外部建联中。⚠️ 必须由页面告知：云拉流是先建联、拿到 URL 才赋 sourceUrl，
    // 这段时间 streaming 还是假，光看 streaming 会出现"点了按钮什么都没发生"
    // 的空档（转圈不转、文字不变）。
    property bool connecting: false

    signal fullscreenRequested()
    signal playRequested()

    color: "#0B0D10"
    radius: fullscreenHosted ? 0 : Theme.radiusLg
    border.width: fullscreenHosted ? 0 : 1
    border.color: Theme.border
    clip: true

    // 播放/停止由 VlcStreamPlayer 跟随 source 属性自理；此处只清错误提示
    onSourceUrlChanged: streamError = ""

    // 拉流引擎 = libvlc（2026-08-19 定案）：Qt Multimedia 对 RTSP/H265 大流
    // 与 http-flv 直播都不行——设备 2560x1472 主码流"已解析却零帧"，云拉流
    // FLV 更是压根不支持；兄弟部门 PC 端同样弃 Qt 用 VLC。诊断/播放语义由
    // VlcStreamPlayer 提供（statusText 分层报告：连接中/协商分辨率/缓冲/已出图）。
    readonly property string diagText: streaming ? player.statusText : ""

    VlcStreamPlayer {
        id: player
        source: root.sourceUrl
        videoSink: vout.videoSink
        // 音频（云拉流 FLV 带音轨时）由 libvlc 直接走系统默认输出——
        // 成品工位"喇叭放音+咪头回传"靠 PC 音箱可闻的需求仍然成立。
        onErrorTextChanged: {
            root.streamError = errorText;
            if (errorText.length > 0)
                console.warn("[stream] " + errorText + " url=" + root.sourceUrl);
        }
        onStatusTextChanged: if (statusText.length > 0)
                                 console.log("[stream] " + statusText);
    }

    // 视频层在最底,三分线/LIVE 标记盖在其上。
    // 圆角用 MultiEffect 遮罩裁出来 —— Item.clip 只做矩形裁剪,占满后视频
    // 方角会压出 Rectangle 的圆角外。全屏托管时 radius=0,遮罩自动停用。
    //
    // fillMode 分两态(2026-08-19):
    //   小窗 Crop —— 等比放大占满圆角区,不留黑边,页面观感干净;
    //     2560x1472(1.74) 对上工位页预览区比例只裁掉个位数百分比。
    //   全屏 Fit —— **不裁**。全屏的目的就是看清四角暗角、脏点和 OSD,
    //     而全屏窗口比视频更宽(1080p 满屏约 1.93 : 1.74),Crop 会从上下切,
    //     正好吃掉顶部 OSD 时间戳和底部 Tenda logo 下缘(实测)。
    //     两侧留深底不好看,但"画面被切掉一条"是判定失真,不能换。
    VideoOutput {
        id: vout
        anchors.fill: parent
        visible: root.streaming
        fillMode: root.fullscreenHosted ? VideoOutput.PreserveAspectFit
                                        : VideoOutput.PreserveAspectCrop
        layer.enabled: root.streaming && root.radius > 0
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: videoMask
        }
    }

    // 遮罩形状:与预览区同圆角的实心块,只有 alpha 通道被用到
    Item {
        id: videoMask
        anchors.fill: vout
        visible: false
        layer.enabled: true
        Rectangle { anchors.fill: parent; radius: root.radius; color: "white" }
    }

    // 三分法构图辅助线，帮工人把画面对中
    Repeater {
        model: root.showGrid ? 2 : 0
        Rectangle {
            required property int index
            color: Qt.rgba(1, 1, 1, 0.07)
            width: 1
            height: parent.height
            x: parent.width * (index + 1) / 3
        }
    }
    Repeater {
        model: root.showGrid ? 2 : 0
        Rectangle {
            required property int index
            color: Qt.rgba(1, 1, 1, 0.07)
            height: 1
            width: parent.width
            y: parent.height * (index + 1) / 3
        }
    }

    // 占位/建联中/出错 三态提示;画面出来后整块隐藏
    Column {
        anchors.centerIn: parent
        spacing: root.compact ? Theme.s2 : Theme.s3
        visible: !root.playing

        BusyIndicator {
            // connecting 也要转：那会儿 sourceUrl 还空着、streaming 为假。
            running: root.visible && (root.streaming || root.connecting)
                     && !root.playing && root.streamError.length === 0
            visible: running
            implicitWidth: root.compact ? 28 : 44
            implicitHeight: root.compact ? 28 : 44
            anchors.horizontalCenter: parent.horizontalCenter
        }
        Text {
            text: root.streamError.length > 0 ? "拉流失败"
                  : (root.streaming || root.connecting) ? "拉流建联中…"
                  // 有播放按钮时连"未拉流"都不写 —— 按钮本身已经说清楚了
                  : (root.showPlayButton ? "" : "未拉流")
            visible: text.length > 0
            color: root.streamError.length > 0 ? Theme.fail : Theme.textSecondary
            font.family: TypeScale.family
            font.pointSize: root.compact ? TypeScale.caption : TypeScale.body
            anchors.horizontalCenter: parent.horizontalCenter
        }
        Text {
            text: root.streamError.length > 0 ? root.streamError : root.hint
            visible: text.length > 0
            color: Theme.textDim
            font.family: TypeScale.family
            font.pointSize: TypeScale.caption
            anchors.horizontalCenter: parent.horizontalCenter
        }
        // 建联/解码分层诊断（只在拉流态显示，画面出来即整块隐藏）
        Text {
            text: root.diagText
            visible: text.length > 0 && !root.compact
            color: Theme.textDim
            font.family: "Consolas"
            font.pointSize: TypeScale.caption
            anchors.horizontalCenter: parent.horizontalCenter
        }
        // URL 可选中复制——排障要拿它去 VLC 对照验证
        TextEdit {
            visible: root.streaming && !root.compact
            text: root.sourceUrl
            readOnly: true
            selectByMouse: true
            color: Theme.textDim
            font.family: "Consolas"
            font.pointSize: TypeScale.caption
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }

    // 右上角实时标记(真在播才亮 —— 不播时亮着是撒谎)。
    // 靠右不靠左:设备自己的 OSD 时间戳烧在画面左上角,徽标压上去两行字叠一起,
    // 而时间戳是产线核对录像时间的依据,不能被遮。
    Row {
        visible: root.playing
        anchors { right: parent.right; top: parent.top }
        anchors.rightMargin: root.compact ? Theme.s3 : Theme.s4
        anchors.topMargin: root.compact ? Theme.s3 : Theme.s4
        spacing: Theme.s2

        Rectangle {
            width: 8; height: 8; radius: 4
            color: Theme.fail
            anchors.verticalCenter: parent.verticalCenter
            SequentialAnimation on opacity {
                running: root.playing; loops: Animation.Infinite
                NumberAnimation { to: 0.2; duration: 800 }
                NumberAnimation { to: 1.0; duration: 800 }
            }
        }
        Text {
            text: "LIVE"
            color: Theme.textPrimary
            font.family: TypeScale.family
            font.pointSize: TypeScale.caption
            font.weight: TypeScale.weightBold
            font.letterSpacing: 1.5
        }
    }

    // 双击全屏。用 MouseArea 而不是 TapHandler ——
    // TapHandler 的 onDoubleTapped 要求两次 tap 落在同一位置且有手势识别延迟，
    // 在小窗里工人手抖一两个像素就判成两次单击，实测不触发。
    // MouseArea.onDoubleClicked 走系统双击语义，可靠得多。
    MouseArea {
        id: hov
        anchors.fill: parent
        hoverEnabled: true
        onDoubleClicked: root.fullscreenRequested()
    }

    // 悬停角标放左下:右下角是设备烧的 Tenda 水印,叠上去糊成一团
    Text {
        anchors { left: parent.left; bottom: parent.bottom }
        anchors.leftMargin: Theme.s3
        anchors.bottomMargin: Theme.s3
        visible: hov.containsMouse && (root.showZoomHint || root.fullscreenHosted)
        text: root.fullscreenHosted ? "双击退出全屏" : "双击全屏"
        color: Theme.textDim
        font.family: TypeScale.family
        font.pointSize: TypeScale.caption
        Behavior on visible { NumberAnimation { duration: Theme.durFast } }
    }

    // 中心播放按钮 = 开始拉流。
    // ⚠️ 必须声明在上面那个 hov(MouseArea) **之后**：hov 是 anchors.fill，
    //    声明在前会把按钮盖住，点下去只会去凑双击全屏的判定。
    Rectangle {
        anchors.centerIn: parent
        width: 56; height: 56; radius: 28
        visible: root.showPlayButton && !root.streaming
                 && !root.connecting && !root.playing
        color: playHit.containsMouse ? Qt.rgba(1, 1, 1, 0.16)
                                     : Qt.rgba(1, 1, 1, 0.08)
        border.width: 1
        border.color: Theme.border
        Behavior on color { ColorAnimation { duration: Theme.durFast } }

        Icon {
            anchors.centerIn: parent
            // 三角形重心偏左，光学居中要往右挪一点
            anchors.horizontalCenterOffset: 2
            text: Icons.play
            size: 24
            color: Theme.textPrimary
        }

        MouseArea {
            id: playHit
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.playRequested()
        }
    }
}
