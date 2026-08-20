#pragma once

#include <QAtomicInteger>
#include <QElapsedTimer>
#include <QMutex>
#include <QObject>
#include <QPointer>
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
//
// ⚠️ 线程模型（2026-08-19 修）：libvlc 的 new/play/stop **全部同步阻塞**，
// 首次 libvlc_new 要扫插件目录建缓存（实测 5-8 秒），放 UI 线程的直接后果是
// 双击 IP 后整个软件假死 —— 连"拉流建联中"的转圈都停在原地（事件循环被堵，
// 动画不走）。故所有 libvlc 控制调用移到一条**专用控制线程**：QML 侧
// setSource() 立即返回，状态经队列信号回主线程，转圈真的在转。
// 控制线程在程序启动时就预热运行时，把插件扫描的代价挪到开机而非首次拉流。
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

    // 以下两个跑在控制线程（非 UI）：libvlc 的阻塞调用都关在这里
    void startOnControl(int generation, const QString &url);
    void teardownOnControl();

    void postStatus(int generation, const QString &text);
    void postError(int generation, const QString &text);
    void setPlayingQueued(int generation, bool value);

    QString source_;
    QPointer<QVideoSink> sink_;
    bool playing_ {false};
    QString error_text_;
    QString status_text_;

    // 换流代次。setSource 每次自增 —— 控制线程/解码线程上晚到的旧流回调
    // 靠它作废（否则"停止后旧流的错误/首帧"会盖掉新流的状态，最坏情况是
    // 停止后 LIVE 徽标还亮着，即"没画面却说在播"）。
    // play_generation_：当前真在播的那一代，控制线程 play 前写、回调侧读；
    // 拆流时先置 -1，正在收尾的旧回调据此自我作废。
    QAtomicInteger<int> generation_ {0};
    QAtomicInteger<int> play_generation_ {-1};

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

    // 起播预热丢帧（都受 frame_mutex_ 保护，解码线程读写、setSource 重置）。
    // 现象：拉流头几帧是灰底带彩色斑块的烂图（截图实证）—— RTSP over UDP 起
    // 会话时首个 IDR 的分片常丢，解码器拿 P 帧硬凑参考帧就是这个样子，要等下
    // 一个关键帧才刷干净。产线工人看到这种图会以为镜头脏或者机器坏。
    // 处置：预热窗口内的帧一律不送 sink（转圈继续转）。产线口径是**宁可多转
    // 几秒圈，也不许把灰图/卡住的图放上去**，所以放行只认正面证据：过了下限
    // 之后，要连续 8 帧同时"不平坦（不是灰底）"且"与上一帧不同（真的在动）"
    // 才出图，任一帧不合格就重新数；上限强制收场（真·平坦画面靠这条）。
    // 只按时长放行是在猜关键帧到没到；只看单帧也不够 —— 灰图上彩斑攒够了
    // 平坦度会掉下来，单帧判据会被骗过去（两者实测都仍会灰）。
    // 等不到理想画面时分三级让步（见 .cpp 里的 kFlat*/kWarmup* 常量）：
    // 连击 → 宽限（10s，只拦明显灰底）→ 死线（15s，无条件放行，否则转圈无限
    // 转会被当成软件卡死）。"放弃等待"不等于"可以放灰图"，中间那级就是为此。
    QElapsedTimer warmup_timer_;
    int warmup_frames_left_ {0};
    bool shown_ {false};      // 已送出过至少一帧干净图
    // 上一次记进排障日志的缓冲百分比。buffering 事件很密，只记变化点。
    // -1 = 还没记过，保证 0% 也能记下第一次（"只有 0%"本身就是关键证据）。
    int last_logged_buffer_ {-1};
    // 连续"不平坦且与上一帧不同"的帧数。只认连击、不认单帧：起播灰图上彩斑攒
    // 够了平坦度也会掉下来，单帧判据会被骗过去（实测出图仍是灰的）。
    int stable_run_ {0};
    std::uint32_t last_hash_ {0};
    bool last_hash_valid_ {false};
    // 出图那一刻的放行原因与平坦度，只为起播日志留证（调阈值就看这两个数）。
    // 指向的都是字面量常量，不用管生命周期。
    const char *release_reason_ {"?"};
    unsigned release_flat_percent_ {0};
};
