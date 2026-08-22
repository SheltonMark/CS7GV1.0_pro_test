#include "vlc_stream_player.hpp"

#include "stream_log.hpp"

#include <QCoreApplication>
#include <QDir>
#include <QLibrary>
#include <QThread>
#include <QVideoFrame>
#include <QVideoFrameFormat>

#include <cstdarg>
#include <cstdio>
#include <cstring>
#include <utility>

// ───────────────────────── libvlc C ABI（无头文件，按 3.0.x 文档手写）─────────
// 只声明用到的十余个入口。全部 opaque 指针 + C 调用约定，x64 上无 stdcall
// 之分，跨编译器稳定——这正是弃 VLC-Qt（C++ ABI）改直连 libvlc 的原因。
namespace {

using vlc_instance_t = void;
using vlc_media_t = void;
using vlc_player_t = void;
using vlc_event_manager_t = void;

// libvlc_event_e（3.0.x 稳定值）
constexpr int kEventPlaying = 260;
constexpr int kEventBuffering = 259;
constexpr int kEventStopped = 262;
constexpr int kEventEndReached = 265;
constexpr int kEventError = 266;

struct VlcEvent {          // libvlc_event_t 头部（type 之后的 union 不取）
    int type;
    void *p_obj;
    union { struct { float cache; } buffering; } u;
};

struct Api {
    vlc_instance_t *(*new_)(int, const char *const *) {};
    void (*release)(vlc_instance_t *) {};
    const char *(*errmsg)() {};
    void (*log_set)(vlc_instance_t *, void (*)(void *, int, const void *,
                                               const char *, va_list), void *) {};
    vlc_media_t *(*media_new_location)(vlc_instance_t *, const char *) {};
    void (*media_add_option)(vlc_media_t *, const char *) {};
    void (*media_release)(vlc_media_t *) {};
    vlc_player_t *(*player_new_from_media)(vlc_media_t *) {};
    void (*player_release)(vlc_player_t *) {};
    int (*player_play)(vlc_player_t *) {};
    void (*player_stop)(vlc_player_t *) {};
    void (*video_set_callbacks)(vlc_player_t *, void *(*)(void *, void **),
                                void (*)(void *, void *, void *const *),
                                void (*)(void *, void *), void *) {};
    void (*video_set_format_callbacks)(
        vlc_player_t *,
        unsigned (*)(void **, char *, unsigned *, unsigned *, unsigned *, unsigned *),
        void (*)(void *)) {};
    vlc_event_manager_t *(*player_event_manager)(vlc_player_t *) {};
    int (*event_attach)(vlc_event_manager_t *, int,
                        void (*)(const void *, void *), void *) {};

    vlc_instance_t *instance {nullptr};
    QString load_error;
    bool tried {false};
};

Api &api()
{
    static Api a;
    return a;
}

void LogCb(void *, int level, const void *, const char *fmt, va_list args)
{
    // 只放行错误级 + 显式调试开关下的全量。libvlc 日志量在 -vv 下极大，
    // 不能无脑刷 stderr。
    static const bool debug_all = !qEnvironmentVariableIsEmpty("PTEST_STREAM_DEBUG");
    if (level < 4 && !debug_all)   // 4 = LIBVLC_ERROR
        return;
    char line[512];
    std::vsnprintf(line, sizeof(line), fmt, args);

    // 错误级进排障面板（界面可见、可截图）；调试开关下的全量只落日志文件，
    // 否则 -vv 的量会把面板冲爆。
    if (level >= 4) {
        StreamLog::append(QStringLiteral("[vlc] ") + QString::fromUtf8(line));
        return;
    }
    std::fprintf(stderr, "[vlc][%d] %s\n", level, line);

    // 例外：解复用器选型与轨道信息即使是 debug 级也送进面板。判"画面出不来"
    // 全靠这两条 —— 选中了哪个 demux、每条轨道的 fourcc 是什么。量很小
    // （每次起播几行），不会把面板冲爆。
    static const char *kKeep[] = {"using demux module", "selected codec",
                                  "adding track", "Track ID", "es out",
                                  "codec is not supported", "hevc", "hvc1"};
    for (const char *k : kKeep) {
        if (std::strstr(line, k)) {
            StreamLog::append(QStringLiteral("[vlc·demux] ") + QString::fromUtf8(line));
            break;
        }
    }
}

// 运行时定位顺序：dist/vlc/（随包发）→ D:\tools\VLC（本机联调兜底）。
// 先手动载入 libvlccore：libvlc.dll 的导入表按模块名解析，core 已在内存
// 就不会再去系统路径找——经典的"同目录私有 DLL"加载法。
//
// ⚠️ 只在控制线程调用（内部一堆非线程安全的函数级 static，且 libvlc_new 会
// 阻塞数秒）。UI 线程要碰的只有它算完之后的 api().load_error。
bool LoadRuntime()
{
    Api &a = api();
    if (a.tried)
        return a.load_error.isEmpty();
    a.tried = true;

    const QStringList candidates {
        QCoreApplication::applicationDirPath() + QStringLiteral("/vlc"),
        QStringLiteral("D:/tools/VLC"),
    };
    QString dir;
    for (const QString &c : candidates) {
        if (QFile::exists(c + QStringLiteral("/libvlc.dll"))) {
            dir = c;
            break;
        }
    }
    if (dir.isEmpty()) {
        a.load_error = QStringLiteral("未找到 VLC 运行时（dist/vlc/ 缺失）");
        return false;
    }

    // 插件路径必须在 libvlc_new 之前生效（实例创建时扫描）
    qputenv("VLC_PLUGIN_PATH", QDir::toNativeSeparators(dir + "/plugins").toUtf8());

    static QLibrary core(dir + QStringLiteral("/libvlccore.dll"));
    static QLibrary vlc(dir + QStringLiteral("/libvlc.dll"));
    if (!core.load() || !vlc.load()) {
        a.load_error = QStringLiteral("VLC 运行时加载失败：") +
            (core.isLoaded() ? vlc.errorString() : core.errorString());
        return false;
    }

    const auto need = [&](const char *name) {
        void *fn = reinterpret_cast<void *>(vlc.resolve(name));
        if (!fn && a.load_error.isEmpty())
            a.load_error = QStringLiteral("libvlc 缺少入口: ") + QLatin1String(name);
        return fn;
    };
    a.new_ = reinterpret_cast<decltype(a.new_)>(need("libvlc_new"));
    a.release = reinterpret_cast<decltype(a.release)>(need("libvlc_release"));
    a.errmsg = reinterpret_cast<decltype(a.errmsg)>(need("libvlc_errmsg"));
    a.log_set = reinterpret_cast<decltype(a.log_set)>(need("libvlc_log_set"));
    a.media_new_location = reinterpret_cast<decltype(a.media_new_location)>(
        need("libvlc_media_new_location"));
    a.media_add_option = reinterpret_cast<decltype(a.media_add_option)>(
        need("libvlc_media_add_option"));
    a.media_release = reinterpret_cast<decltype(a.media_release)>(
        need("libvlc_media_release"));
    a.player_new_from_media = reinterpret_cast<decltype(a.player_new_from_media)>(
        need("libvlc_media_player_new_from_media"));
    a.player_release = reinterpret_cast<decltype(a.player_release)>(
        need("libvlc_media_player_release"));
    a.player_play = reinterpret_cast<decltype(a.player_play)>(
        need("libvlc_media_player_play"));
    a.player_stop = reinterpret_cast<decltype(a.player_stop)>(
        need("libvlc_media_player_stop"));
    a.video_set_callbacks = reinterpret_cast<decltype(a.video_set_callbacks)>(
        need("libvlc_video_set_callbacks"));
    a.video_set_format_callbacks =
        reinterpret_cast<decltype(a.video_set_format_callbacks)>(
            need("libvlc_video_set_format_callbacks"));
    a.player_event_manager = reinterpret_cast<decltype(a.player_event_manager)>(
        need("libvlc_media_player_event_manager"));
    a.event_attach = reinterpret_cast<decltype(a.event_attach)>(
        need("libvlc_event_attach"));
    if (!a.load_error.isEmpty())
        return false;

    // 单实例整个进程共用（插件扫描秒级，不能每次拉流都来一遍）
    //
    // PTEST_STREAM_DEBUG 下必须同时把 verbosity 提到 -vv：LogCb 只能收到
    // libvlc 愿意发的等级，光在回调里放行 debug 是收不到东西的。要判定
    // "选了哪个解复用器、每条轨道的 fourcc 是什么"就靠这一档。
    const bool debug_all = !qEnvironmentVariableIsEmpty("PTEST_STREAM_DEBUG");
    const char *args_quiet[] = {"--no-video-title-show"};
    const char *args_debug[] = {"--no-video-title-show", "-vv"};
    a.instance = debug_all ? a.new_(2, args_debug) : a.new_(1, args_quiet);
    if (!a.instance) {
        a.load_error = QStringLiteral("libvlc_new 失败: ") +
            QString::fromUtf8(a.errmsg ? a.errmsg() : "");
        return false;
    }
    a.log_set(a.instance, LogCb, nullptr);
    std::fprintf(stderr, "[vlc] runtime ready: %s\n", qPrintable(dir));
    return true;
}

// 起播预热丢帧窗口。见头文件里的现象说明（灰底彩斑烂图）。
// 口径（2026-08-20 产线反馈定案）：**宁可多转几秒圈，也不许把灰图/卡住的图
// 放到界面上。** 所以判据只认"正面证据"—— 连续 kStableRun 帧同时满足
//   ① 不平坦（不是解码器灰底）
//   ② 与上一帧不同（画面真的在动，不是卡着的一张）
// 任一帧不合格就把连击数清零重新数。只放行"第一帧碰巧合格"是不够的：起播
// 灰图上彩斑攒够了也能让平坦度掉下来，单帧判据会被它骗过去（实测仍会灰）。
constexpr int kWarmupFloorMs = 800;
constexpr int kWarmupFloorFrames = 12;
constexpr int kStableRun = 8;
// 平坦度阈值（百分比）：见 ProbeLuma()。25→10。
// 为什么 25 还会漏：这个量是"整帧里仍严格平坦的占比"，阈值 25 就等于允许放行时
// 还有约四分之一的画面是灰底 —— 现象正是"出图带一点灰、随即刷干净"（实测）。
// 真实画面有传感器噪声，逐位相等占比只有个位数，收到 10 仍有余量。
constexpr unsigned kFlatPercent = 10;

// ── 上限：真·平坦画面（盖镜头、对白墙、平场标定）永远满足不了上面的判据，
//    不能让转圈一直转下去。但"放弃等待"不等于"可以放灰图"，所以分两级：
// 宽限级：放弃连击与"在动"的要求，但仍要求这一帧不是**明显**的灰底。
//   85% 这条线只有解码器的灰底填充够得着（严格逐位平坦，实测 95%+）；
//   真实的平坦场景（白墙、过曝天空）有噪声，通常落在 30~60%。
constexpr int kWarmupCeilMs = 10000;
constexpr unsigned kFlatRelaxPercent = 85;
// 死线级：连"不是明显灰底"都等不到（设备没出图/一直烂），无条件放行。
// 宁可给工人看一张烂图，也不能让转圈无限转下去 —— 那会被当成软件卡死。
constexpr int kWarmupHardMs = 15000;

// 一次采样同时取两个量，避免为此扫两遍大帧（2560x1472 一遍不便宜）。
struct LumaProbe {
    unsigned flat_percent {100};   // "与右邻居逐位相等"的占比，灰底接近 100
    std::uint32_t hash {0};        // 采样点校验和，用来判两帧是否一样
};

// 按 8px 稀疏网格采 Y 平面。
// flat_percent：起播灰底是大片**严格**平坦（逐位相等），真实摄像头画面有传感器
//   噪声，几乎不可能大面积逐位相等 —— 比判"像不像 128"稳，不依赖解码器填什么值。
// hash：拿同一批采样点算校验和。相邻两帧 hash 相同 = 画面没动（起播卡住的那张，
//   或解码器把同一张灰图重复吐出来）。只看 Y 够了：彩斑在 UV，但灰底的判定和
//   "动没动"的判定都由亮度承载，且 Y 采样最省。
LumaProbe ProbeLuma(const std::uint8_t *y, const unsigned pitch,
                    const unsigned w, const unsigned h)
{
    LumaProbe p;
    if (!y || w < 16 || h < 16)
        return p;                    // 尺寸异常：按"仍是灰底"处理，交给上限兜
    std::size_t total = 0;
    std::size_t flat = 0;
    std::uint32_t hash = 2166136261u;         // FNV-1a 起始值
    for (unsigned row = 4; row < h; row += 8) {
        const std::uint8_t *line = y + static_cast<std::size_t>(pitch) * row;
        for (unsigned x = 0; x + 8 < w; x += 8) {
            ++total;
            if (line[x] == line[x + 8])
                ++flat;
            hash = (hash ^ line[x]) * 16777619u;
        }
    }
    if (total == 0)
        return p;
    p.flat_percent = static_cast<unsigned>(flat * 100 / total);
    p.hash = hash;
    return p;
}

// libvlc 控制线程。new/play/stop 全都同步阻塞（首次 libvlc_new 扫插件缓存实测
// 5-8 秒，player_stop 要等输入线程收尾），放 UI 线程就是"双击 IP 后软件假死"。
// 全进程共用一条：libvlc 的控制调用本就该串行，多线程反而要自己加锁。
// 控制线程是否已经收掉。**必须有这个标志**：aboutToQuit 在事件循环退出**之前**
// 就把线程 quit+wait 掉了，而 QML 引擎析构 VlcStreamPlayer 发生在那之后 ——
// 析构里的 BlockingQueuedConnection 于是投给一条没有事件循环的死线程，
// 永远等不到返回：进程挂在析构上不退出（2026-08-21 实测：只要开过拉流页面，
// 关窗口必留后台进程）。停了之后一律改走调用线程直接执行。
bool g_controlStopped = false;

QObject *controlHub()
{
    static QThread *thread = [] {
        auto *t = new QThread;
        t->setObjectName(QStringLiteral("vlc-control"));
        t->start();
        // 退出前收线程：线程还在跑就卸 DLL 会崩在 libvlc 内部
        QObject::connect(qApp, &QCoreApplication::aboutToQuit, t, [t] {
            g_controlStopped = true;
            t->quit();
            t->wait(3000);
        });
        return t;
    }();
    static QObject *hub = [] {
        auto *o = new QObject;
        o->moveToThread(thread);
        return o;
    }();
    return hub;
}

template <typename Fn>
void postToControl(Fn &&fn)
{
    // 线程已收：直接在当前线程跑。投过去也没人执行，还会把待办丢掉。
    if (g_controlStopped) {
        fn();
        return;
    }
    QMetaObject::invokeMethod(controlHub(), std::forward<Fn>(fn),
                              Qt::QueuedConnection);
}

} // namespace

// ───────────────────────────────── 播放器 ────────────────────────────────────

VlcStreamPlayer::VlcStreamPlayer(QObject *parent)
    : QObject(parent)
{
    // 预热：把插件扫描（首次 libvlc_new，实测 5-8 秒）挪到程序起来时的后台，
    // 而不是工人双击 IP 的那一刻。页面构造即触发，界面照常可点。
    postToControl([] { LoadRuntime(); });
}

VlcStreamPlayer::~VlcStreamPlayer()
{
    // ⚠️ 控制线程已经收掉时**绝不能**用 BlockingQueuedConnection —— 那条线程没有
    //    事件循环，投过去永远不会被执行，调用方就永久阻塞在这里，进程退不掉
    //    （2026-08-21 实测的"关窗口留后台进程"就是这个死锁）。
    //    此时线程已 join，libvlc 回调不可能再跑，直接同步收尾是安全的。
    if (g_controlStopped) {
        teardownOnControl();
        return;
    }
    // 线程还活着：必须**阻塞**等它收完 —— libvlc 的视频回调把 this 当 opaque 用，
    // player_stop 返回前回调仍可能在跑（碰 frame_mutex_/sink_）。异步收尾
    // 等于让回调打在已析构对象上。此处最多等一次 player_stop 的时长。
    QMetaObject::invokeMethod(controlHub(), [this] { teardownOnControl(); },
                              Qt::BlockingQueuedConnection);
}

QVideoSink *VlcStreamPlayer::videoSink() const
{
    return sink_.data();
}

void VlcStreamPlayer::setVideoSink(QVideoSink *sink)
{
    QMutexLocker lock(&frame_mutex_);
    if (sink_ == sink)
        return;
    sink_ = sink;
    lock.unlock();
    emit videoSinkChanged();
}

// UI 线程。**不做任何 libvlc 调用** —— 只更状态、投任务给控制线程后立即返回，
// 双击 IP 的那一下不再卡住界面（转圈能转起来的前提）。
void VlcStreamPlayer::setSource(const QString &url)
{
    if (source_ == url)
        return;
    source_ = url;
    emit sourceChanged();

    const int gen = generation_.fetchAndAddOrdered(1) + 1;

    // 本地状态立刻回到"未播"：旧流的 LIVE 徽标不能跨到新流上
    if (playing_) {
        playing_ = false;
        emit playingChanged();
    }
    error_text_.clear();
    emit errorTextChanged();
    {
        // 预热计数与"已出图"标记归零 —— 解码线程也读它们，改要持锁
        QMutexLocker lock(&frame_mutex_);
        first_frame_seen_ = false;
        shown_ = false;
        warmup_frames_left_ = kWarmupFloorFrames;
        stable_run_ = 0;
        last_hash_valid_ = false;
        last_logged_buffer_ = -1;
    }
    if (!source_.isEmpty())
        StreamLog::append(QStringLiteral("[vlc] 起播 ") + source_);
    status_text_ = source_.isEmpty() ? QString() : QStringLiteral("连接中…");
    emit statusTextChanged();

    const QString target = source_;
    postToControl([this, gen, target] {
        teardownOnControl();               // 旧流先收干净（阻塞在控制线程，不碍 UI）
        if (gen != generation_.loadAcquire())
            return;                        // 期间又换了源，这一代作废
        if (!target.isEmpty())
            startOnControl(gen, target);
    });
}

// 三个 post* 都带代次：投递到 UI 线程时若已换源就丢弃
void VlcStreamPlayer::postStatus(const int generation, const QString &text)
{
    QMetaObject::invokeMethod(this, [this, generation, text]() {
        if (generation != generation_.loadAcquire() || status_text_ == text)
            return;
        status_text_ = text;
        emit statusTextChanged();
    }, Qt::QueuedConnection);
}

void VlcStreamPlayer::postError(const int generation, const QString &text)
{
    QMetaObject::invokeMethod(this, [this, generation, text]() {
        if (generation != generation_.loadAcquire())
            return;
        error_text_ = text;
        emit errorTextChanged();
    }, Qt::QueuedConnection);
}

void VlcStreamPlayer::setPlayingQueued(const int generation, const bool value)
{
    QMetaObject::invokeMethod(this, [this, generation, value]() {
        if (generation != generation_.loadAcquire() || playing_ == value)
            return;
        playing_ = value;
        emit playingChanged();
    }, Qt::QueuedConnection);
}

// ↓↓↓ 以下两个跑在控制线程：libvlc 的阻塞调用全在这里，UI 线程碰不到 ↓↓↓

void VlcStreamPlayer::startOnControl(const int generation, const QString &url)
{
    if (!LoadRuntime()) {
        postError(generation, api().load_error);
        return;
    }
    Api &a = api();

    media_ = a.media_new_location(a.instance, url.toUtf8().constData());
    if (!media_) {
        postError(generation, QStringLiteral("无法创建媒体: ") + url);
        return;
    }
    // 直播缓冲。300→600ms：主码流是 2560x1472 H265，集显机软解本就吃紧，
    // 缓冲太浅时解码赶不上就是"画面一顿一顿"。产线口径是宁可多等也别卡，
    // 所以这里换成加深缓冲。**代价是操作延迟同步变大**：调焦时手转镜头到
    // 画面响应会多约 0.3 秒，若调焦嫌不跟手，把这个数调回 300。
    // RTSP 传输方式保持引擎默认（UDP，与本机 VLC 验证一致）；若产线网络挡
    // UDP，改这里加 ":rtsp-tcp" 一行即可。
    a.media_add_option(media_, ":network-caching=600");

    // ── 云拉流（本机 http-flv 转发）专属两项，抄参考实现
    //    （tendasecuritypc BL_TencentLivePlayControl.cpp:357-359 实测可放 H265）。
    //    只对 http 源加，别动已经调好的 RTSP 路径。
    //
    // clock-jitter=0：关掉 input_clock.c 的抖动护栏。设备侧送进 FLV 的音频
    //   时间戳是**绝对值**（实测 2444148201000），护栏一律判超界并丢弃，报
    //   "Timestamp conversion failed (delay …, bound 3000000)"，音频又是主
    //   时钟，于是永久停在缓冲 100%、一帧不出。
    // clock-synchro=1：让时钟跟着流里的 PCR 走，不自己猜。
    if (url.startsWith(QStringLiteral("http://"), Qt::CaseInsensitive) ||
        url.startsWith(QStringLiteral("https://"), Qt::CaseInsensitive)) {
        a.media_add_option(media_, ":clock-jitter=0");
        a.media_add_option(media_, ":clock-synchro=1");
        StreamLog::append(QStringLiteral(
            "[vlc] 云拉流参数：clock-jitter=0 / clock-synchro=1（容忍设备侧绝对时间戳）"));
    }

    player_ = a.player_new_from_media(media_);
    if (!player_) {
        postError(generation, QStringLiteral("无法创建播放器"));
        a.media_release(media_);
        media_ = nullptr;
        return;
    }

    a.video_set_format_callbacks(player_, SetupCb, CleanupCb);
    a.video_set_callbacks(player_, LockCb, UnlockCb, DisplayCb, this);

    if (vlc_event_manager_t *em = a.player_event_manager(player_)) {
        for (const int type : {kEventPlaying, kEventBuffering, kEventStopped,
                               kEventEndReached, kEventError}) {
            a.event_attach(em, type, EventCb, this);
        }
    }

    // 回调侧的代次闸门：play 之前立，回调据此判自己属于哪一代
    play_generation_.storeRelease(generation);
    if (a.player_play(player_) != 0) {
        postError(generation, QStringLiteral("启动播放失败: ") +
                                 QString::fromUtf8(a.errmsg ? a.errmsg() : ""));
    }
}

void VlcStreamPlayer::teardownOnControl()
{
    // 先作废回调：正在收尾的解码/事件线程读到 -1 就不再往 UI 投状态
    play_generation_.storeRelease(-1);

    Api &a = api();
    if (player_) {
        a.player_stop(player_);      // 同步：返回后回调不再触发（可能耗秒级）
        a.player_release(player_);
        player_ = nullptr;
    }
    if (media_) {
        a.media_release(media_);
        media_ = nullptr;
    }
    QMutexLocker lock(&frame_mutex_);
    frame_buffer_.clear();
    width_ = height_ = 0;
}

// ─────────────────────────── libvlc 线程回调 ────────────────────────────────

unsigned VlcStreamPlayer::SetupCb(void **opaque, char *chroma, unsigned *width,
                                  unsigned *height, unsigned *pitches,
                                  unsigned *lines)
{
    auto *self = static_cast<VlcStreamPlayer *>(*opaque);
    // 统一要 I420：与 QVideoFrame 的 YUV420P 一一对应，拷贝零转换。
    std::memcpy(chroma, "I420", 4);
    const unsigned w = *width;
    const unsigned h = *height;

    QMutexLocker lock(&self->frame_mutex_);
    // 分辨率协商成功 = 真正开始解码，预热窗口从这里重新起算（含计时器：
    // 只重置帧数不清 first_frame_seen_ 的话，elapsed() 早已越过窗口，
    // 时长与上限两道闸门等于失效）。
    // ⚠️ 仅限"还没出过图"。已经在放的流中途再协商（换码流/分辨率变化）时
    // 不能重新预热 —— 那会让画面重新卡住数秒，比一两帧花屏难看得多。
    if (!self->shown_) {
        self->warmup_frames_left_ = kWarmupFloorFrames;
        self->first_frame_seen_ = false;
        self->stable_run_ = 0;
        self->last_hash_valid_ = false;   // 换了尺寸，旧 hash 不可比
    }
    self->width_ = w;
    self->height_ = h;
    self->pitch_y_ = (w + 31) & ~31u;        // 32 对齐，部分滤镜/拷贝路径更快
    self->pitch_uv_ = ((w / 2) + 15) & ~15u;
    pitches[0] = self->pitch_y_;
    pitches[1] = pitches[2] = self->pitch_uv_;
    lines[0] = h;
    lines[1] = lines[2] = h / 2;
    self->frame_buffer_.resize(
        static_cast<std::size_t>(self->pitch_y_) * h +
        static_cast<std::size_t>(self->pitch_uv_) * h);   // uv 两平面各 h/2
    self->postStatus(self->play_generation_.loadAcquire(),
                     QStringLiteral("已协商 %1x%2").arg(w).arg(h));
    return 1;
}

void VlcStreamPlayer::CleanupCb(void *opaque)
{
    auto *self = static_cast<VlcStreamPlayer *>(opaque);
    QMutexLocker lock(&self->frame_mutex_);
    self->frame_buffer_.clear();
}

void *VlcStreamPlayer::LockCb(void *opaque, void **planes)
{
    auto *self = static_cast<VlcStreamPlayer *>(opaque);
    self->frame_mutex_.lock();               // UnlockCb 释放
    std::uint8_t *base = self->frame_buffer_.data();
    planes[0] = base;
    planes[1] = base + static_cast<std::size_t>(self->pitch_y_) * self->height_;
    planes[2] = static_cast<std::uint8_t *>(planes[1]) +
        static_cast<std::size_t>(self->pitch_uv_) * (self->height_ / 2);
    return nullptr;
}

void VlcStreamPlayer::UnlockCb(void *opaque, void *, void *const *)
{
    static_cast<VlcStreamPlayer *>(opaque)->frame_mutex_.unlock();
}

void VlcStreamPlayer::DisplayCb(void *opaque, void *)
{
    auto *self = static_cast<VlcStreamPlayer *>(opaque);

    const int gen = self->play_generation_.loadAcquire();

    QMutexLocker lock(&self->frame_mutex_);
    QVideoSink *sink = self->sink_.data();
    if (!sink || self->frame_buffer_.empty())
        return;
    const unsigned w = self->width_;
    const unsigned h = self->height_;

    // ── 预热丢帧：起播头几帧是灰底彩斑的烂图（缺完整 IDR，见头文件），
    //    这段窗口内一帧不送 sink —— 界面停在转圈上，工人不会看到烂图。
    // ⚠️ 整段**只在"还没出过图"时生效**（`!shown_`）。出图之后必须无条件放行
    //    每一帧：否则判据会继续拦掉后面的帧，画面就卡在第一张不动（实测卡
    //    8~10 秒），而且到上限那一刻又正好把一张灰图放出去 —— "第一帧清晰但
    //    卡住、中途还灰一次"就是这么来的。预热是**起播一次性**的闸门，
    //    不是常驻滤镜。
    if (!self->shown_) {
        if (!self->first_frame_seen_) {
            self->first_frame_seen_ = true;
            self->warmup_timer_.start();
            self->postStatus(gen, QStringLiteral("等待画面稳定…"));
        }
        const qint64 waited =
            self->warmup_timer_.isValid() ? self->warmup_timer_.elapsed() : 0;
        if (self->warmup_frames_left_ > 0) {
            --self->warmup_frames_left_;
            return;                  // 拷都不拷，省掉整帧 memcpy
        }
        if (waited < kWarmupFloorMs)
            return;                  // 帧数够了但时长没到（低帧率流靠这条兜）

        // 正面证据：这一帧既不平坦、又和上一帧不同，才算一次合格连击。
        const LumaProbe probe =
            ProbeLuma(self->frame_buffer_.data(), self->pitch_y_, w, h);
        const bool clean = probe.flat_percent < kFlatPercent;
        const bool moving = self->last_hash_valid_ && probe.hash != self->last_hash_;
        self->last_hash_ = probe.hash;
        self->last_hash_valid_ = true;
        self->stable_run_ = (clean && moving) ? self->stable_run_ + 1 : 0;

        // 三级放行。等不到理想画面时逐级让步，但"放弃等待"不等于"可以放灰图"：
        // 宽限级仍拦住明显灰底，只有死线级才无条件放行。
        if (self->stable_run_ >= kStableRun) {
            self->release_reason_ = "stable run";
        } else if (waited >= kWarmupHardMs) {
            self->release_reason_ = "HARD DEADLINE - 始终没等到干净图";
        } else if (waited >= kWarmupCeilMs
                   && probe.flat_percent < kFlatRelaxPercent) {
            self->release_reason_ = "ceiling (relaxed)";
        } else {
            return;                  // 继续丢
        }
        self->release_flat_percent_ = probe.flat_percent;
    }

    QVideoFrame frame(QVideoFrameFormat(QSize(static_cast<int>(w),
                                              static_cast<int>(h)),
                                        QVideoFrameFormat::Format_YUV420P));
    if (!frame.map(QVideoFrame::WriteOnly))
        return;
    const std::uint8_t *src_y = self->frame_buffer_.data();
    const std::uint8_t *src_u =
        src_y + static_cast<std::size_t>(self->pitch_y_) * h;
    const std::uint8_t *src_v =
        src_u + static_cast<std::size_t>(self->pitch_uv_) * (h / 2);
    const struct { const std::uint8_t *src; unsigned pitch, rows, row_bytes; }
        planes[3] = {
            {src_y, self->pitch_y_, h, w},
            {src_u, self->pitch_uv_, h / 2, w / 2},
            {src_v, self->pitch_uv_, h / 2, w / 2},
        };
    for (int i = 0; i < 3; ++i) {
        std::uint8_t *dst = frame.bits(i);
        const int dst_pitch = frame.bytesPerLine(i);
        for (unsigned row = 0; row < planes[i].rows; ++row) {
            std::memcpy(dst + static_cast<std::size_t>(dst_pitch) * row,
                        planes[i].src +
                            static_cast<std::size_t>(planes[i].pitch) * row,
                        planes[i].row_bytes);
        }
    }
    frame.unmap();
    const bool first_shown = !self->shown_;
    // 预热实际耗时：调 kFlatPercent / kWarmupCeilMs 就看这个数。接近上限说明
    // 是被上限强放的（判据没等到干净图，可能判得太严或该设备 GOP 特别长）。
    const qint64 warmup_ms = first_shown && self->warmup_timer_.isValid()
        ? self->warmup_timer_.elapsed() : 0;
    // 连同放行原因一起在锁内取走：日志在 unlock 之后打，不能再碰成员
    const char *release_reason = self->release_reason_;
    const unsigned release_flat = self->release_flat_percent_;
    self->shown_ = true;
    lock.unlock();

    sink->setVideoFrame(frame);
    // LIVE 徽标/收转圈以"第一帧干净图已送出"为准，不是"连上了"
    if (first_shown) {
        self->setPlayingQueued(gen, true);
        self->postStatus(gen, QStringLiteral("已出图 %1x%2").arg(w).arg(h));
        std::fprintf(stderr,
                     "[vlc] first frame %ux%u after %lldms warmup"
                     " (%s, flat=%u%%)\n",
                     w, h, static_cast<long long>(warmup_ms),
                     release_reason, release_flat);
    }
}

void VlcStreamPlayer::EventCb(const void *event, void *opaque)
{
    auto *self = static_cast<VlcStreamPlayer *>(opaque);
    const auto *ev = static_cast<const VlcEvent *>(event);
    const int gen = self->play_generation_.loadAcquire();
    if (gen < 0)
        return;                  // 已拆流，收尾中的旧事件不许再改 UI
    switch (ev->type) {
    case kEventPlaying:
        StreamLog::append(QStringLiteral("[vlc] 事件 Playing（已连接，等首帧）"));
        self->postStatus(gen, QStringLiteral("已连接，等待首帧…"));
        break;
    case kEventBuffering: {
        const int pct = static_cast<int>(ev->u.buffering.cache);
        // 只记变化点，不然 buffering 事件会把面板刷满。卡 0% 的关键就是
        // "只有 0%、再没有别的数字"，所以 0 也要记第一次。
        if (pct != self->last_logged_buffer_) {
            self->last_logged_buffer_ = pct;
            StreamLog::append(QStringLiteral("[vlc] 缓冲 %1%").arg(pct));
        }
        if (!self->shown_)
            self->postStatus(gen, QStringLiteral("缓冲 %1%").arg(pct));
        break;
    }
    case kEventStopped:
    case kEventEndReached:
        StreamLog::append(QStringLiteral("[vlc] 事件 Stopped/EndReached（流结束）"));
        self->setPlayingQueued(gen, false);
        self->postStatus(gen, QStringLiteral("流已结束"));
        break;
    case kEventError:
        StreamLog::append(QStringLiteral("[vlc] 事件 Error（引擎报错）"));
        self->setPlayingQueued(gen, false);
        self->postError(gen, QStringLiteral("拉流出错（VLC 引擎报告）"));
        break;
    default:
        break;
    }
}
