import QtQuick
import ptest
import QtQuick.Controls
import QtMultimedia

// 拉流预览区。
//
// 三处复用：调焦页（大窗，构图三分线辅助对中）、准成品/成品页（小窗，
// 只为确认"这台机器的画面确实出来了"）。抽成组件是因为三处的 LIVE 标记、
// 建联中提示、双击全屏行为必须一致 —— 工人换工位时不该重新学一遍。
//
// 播放:Qt6 MediaPlayer(FFmpeg 后端),rtsp://(CS7G 调焦网口直拉)与
// XP2P 的本地 http-flv URL 都吃 —— 两条拉流通道共用这一个组件。
//
// 双击放大全屏、Esc 退出：产线工位屏常是 1080p 甚至更低，
// 小窗里看不清暗角和脏点，判画面时需要放到满屏。
Rectangle {
    id: root

    property bool showGrid: true       // 三分构图线（调焦要，其它工位不需要）
    property bool compact: false       // 小窗模式：缩小提示文字
    property string hint: "demo 无真实码流"
    // 悬停时的"双击全屏"角标。功能保留，只是不显示提示 ——
    // 准成品/成品工位的小窗上这行字挤在画面里，反而干扰看图。
    property bool showZoomHint: true

    // 拉流地址。空串 = 未拉流(占位态);赋值即自动播放,清空即停。
    property string sourceUrl: ""
    readonly property bool streaming: sourceUrl.length > 0
    readonly property bool playing: player.playbackState === MediaPlayer.PlayingState
    property string streamError: ""

    signal fullscreenRequested()

    color: "#0B0D10"
    radius: Theme.radiusLg
    border.width: 1
    border.color: Theme.border
    clip: true

    onSourceUrlChanged: {
        streamError = "";
        if (sourceUrl.length > 0) player.play();
        else player.stop();
    }

    // 诊断态：黑屏时"到底黑在哪一层"要能一眼看出——媒体状态告诉你是没建联、
    // 建联了没解出视频轨、还是解出来了但没帧（2026-08-19 现场排查这三层
    // 只能靠猜，界面只写"拉流失败"帮不上忙）。
    readonly property string diagText: {
        if (!streaming) return "";
        var st = player.mediaStatus === MediaPlayer.NoMedia ? "无媒体"
               : player.mediaStatus === MediaPlayer.LoadingMedia ? "解析中"
               : player.mediaStatus === MediaPlayer.LoadedMedia ? "已解析"
               : player.mediaStatus === MediaPlayer.StalledMedia ? "缓冲中断"
               : player.mediaStatus === MediaPlayer.BufferingMedia ? "缓冲中"
               : player.mediaStatus === MediaPlayer.BufferedMedia ? "已缓冲"
               : player.mediaStatus === MediaPlayer.EndOfMedia ? "流结束"
               : player.mediaStatus === MediaPlayer.InvalidMedia ? "媒体非法" : "?";
        return st + "｜视频轨 " + player.videoTracks.length
             + "｜音频轨 " + player.audioTracks.length;
    }

    MediaPlayer {
        id: player
        source: root.sourceUrl
        videoOutput: vout
        // 音频要出:成品工位"喇叭放音+咪头回传"一步双验靠 PC 音箱可闻
        audioOutput: AudioOutput { }
        onErrorOccurred: (error, errorString) => {
            root.streamError = errorString + "（错误码 " + error + "）";
            console.warn("[stream] error=" + error + " " + errorString
                         + " url=" + root.sourceUrl);
        }
        // 状态跃迁打日志：出问题时让工人/工程师能把这几行贴出来
        onMediaStatusChanged: console.log("[stream] mediaStatus=" + mediaStatus
                                         + " url=" + root.sourceUrl)
        onPlaybackStateChanged: console.log("[stream] playbackState=" + playbackState)
    }

    // 视频层在最底,三分线/LIVE 标记盖在其上
    VideoOutput {
        id: vout
        anchors.fill: parent
        visible: root.streaming
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
            running: root.visible && root.streaming && !root.playing
                     && root.streamError.length === 0
            visible: running
            implicitWidth: root.compact ? 28 : 44
            implicitHeight: root.compact ? 28 : 44
            anchors.horizontalCenter: parent.horizontalCenter
        }
        Text {
            text: root.streamError.length > 0 ? "拉流失败"
                  : (root.streaming ? "拉流建联中…" : "未拉流")
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

    // 左上角实时标记(真在播才亮 —— 不播时亮着是撒谎)
    Row {
        visible: root.playing
        anchors { left: parent.left; top: parent.top }
        anchors.leftMargin: root.compact ? Theme.s3 : Theme.s4
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

    Text {
        anchors { right: parent.right; bottom: parent.bottom; margins: Theme.s3 }
        anchors.rightMargin: Theme.s3
        anchors.bottomMargin: Theme.s3
        visible: hov.containsMouse && root.showZoomHint
        text: "双击全屏"
        color: Theme.textDim
        font.family: TypeScale.family
        font.pointSize: TypeScale.caption
        Behavior on visible { NumberAnimation { duration: Theme.durFast } }
    }
}
