#pragma once

#include <QMutex>
#include <QObject>
#include <QQmlEngine>
#include <QString>
#include <QVideoSink>

#include <cstdint>
#include <vector>

// libvlc 拉流播放器（RTSP / http-flv 通吃）。
//
// 为什么不用 Qt Multimedia：2026-08-19 现场，设备 RTSP（H265 2560x1472）在
// MediaPlayer 上"已解析｜视频轨 1"却永不出帧，而同机 VLC 3.0.23 清晰播放；
// 兄弟部门（D:\tendasecuritypc）同样弃用 Qt Multimedia 改用 VLC-Qt，且云端
// 拉流是 http-flv 直播——Qt Multimedia 连 FLV 直播都不支持，两条通道都得换。
//
// 为什么不直接搬他们的 VLC-Qt：VLCQtCore.dll 依赖 Qt5Core + MSVC C++ 修饰，
// 与本工程（Qt 6.8 + MinGW）双重不兼容，且 VLC-Qt 已停更无 Qt6 版。
// libvlc 本身是**纯 C ABI**，跨编译器通用——本类即"Qt6 版的那层薄封装"，
// 引擎与插件复用 VLC 3.0.x 运行时（dist/vlc/，build.sh 负责拷入）。
//
// 加载方式是 QLibrary 动态解析而非链接期依赖：缺 dist/vlc/ 时 exe 照常启动、
// 界面给出明确报错，而不是整个程序弹"找不到 DLL"起不来。
//
// 视频路径：libvlc 解码（硬解优先，引擎自己协商）→ I420 回调 → QVideoFrame
// → QVideoSink。QML 侧 VideoOutput 原样保留，LivePreview 只换播放器对象。
class VlcStreamPlayer : public QObject {
    Q_OBJECT
    QML_ELEMENT

    // 拉流地址。空串=停止；赋值即开始（与旧 MediaPlayer 用法对齐）。
    Q_PROPERTY(QString source READ source WRITE setSource NOTIFY sourceChanged)
    Q_PROPERTY(QVideoSink *videoSink READ videoSink WRITE setVideoSink
                   NOTIFY videoSinkChanged)
    // true = 首帧已送达（LIVE 徽标语义：真在出图才亮，连上没画面不算）
    Q_PROPERTY(bool playing READ playing NOTIFY playingChanged)
    Q_PROPERTY(QString errorText READ errorText NOTIFY errorTextChanged)
    // 分层诊断（连接中/缓冲 N%/已出图/错误），排障时替代黑盒转圈
    Q_PROPERTY(QString statusText READ statusText NOTIFY statusTextChanged)

public:
    explicit VlcStreamPlayer(QObject *parent = nullptr);
    ~VlcStreamPlayer() override;

    QString source() const { return source_; }
    void setSource(const QString &url);

    QVideoSink *videoSink() const;
    void setVideoSink(QVideoSink *sink);

    bool playing() const { return playing_; }
    QString errorText() const { return error_text_; }
    QString statusText() const { return status_text_; }

signals:
    void sourceChanged();
    void videoSinkChanged();
    void playingChanged();
    void errorTextChanged();
    void statusTextChanged();

private:
    // —— 以下回调运行在 libvlc 线程，只做拷帧/发队列信号，不碰 QML ——
    static unsigned SetupCb(void **opaque, char *chroma, unsigned *width,
                            unsigned *height, unsigned *pitches, unsigned *lines);
    static void CleanupCb(void *opaque);
    static void *LockCb(void *opaque, void **planes);
    static void UnlockCb(void *opaque, void *picture, void *const *planes);
    static void DisplayCb(void *opaque, void *picture);
    static void EventCb(const void *event, void *opaque);

    void start();
    void stop();
    void postStatus(const QString &text);
    void postError(const QString &text);
    void setPlayingQueued(bool value);

    QString source_;
    QPointer<QVideoSink> sink_;
    bool playing_ {false};
    QString error_text_;
    QString status_text_;

    // libvlc 对象（void* 持有——无头文件，全部经 QLibrary 解析的 C 接口操作）
    void *media_ {nullptr};
    void *player_ {nullptr};

    // 解码输出缓冲（I420 三平面连续布局），尺寸在 SetupCb 协商后确定
    QMutex frame_mutex_;
    std::vector<std::uint8_t> frame_buffer_;
    unsigned width_ {0};
    unsigned height_ {0};
    unsigned pitch_y_ {0};
    unsigned pitch_uv_ {0};
    bool first_frame_seen_ {false};
};
