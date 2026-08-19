#include "vlc_stream_player.hpp"

#include <QCoreApplication>
#include <QDir>
#include <QLibrary>
#include <QVideoFrame>
#include <QVideoFrameFormat>

#include <cstdarg>
#include <cstdio>
#include <cstring>

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
    std::fprintf(stderr, "[vlc][%d] %s\n", level, line);
}

// 运行时定位顺序：dist/vlc/（随包发）→ D:\tools\VLC（本机联调兜底）。
// 先手动载入 libvlccore：libvlc.dll 的导入表按模块名解析，core 已在内存
// 就不会再去系统路径找——经典的"同目录私有 DLL"加载法。
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
    const char *args[] = {"--no-video-title-show"};
    a.instance = a.new_(1, args);
    if (!a.instance) {
        a.load_error = QStringLiteral("libvlc_new 失败: ") +
            QString::fromUtf8(a.errmsg ? a.errmsg() : "");
        return false;
    }
    a.log_set(a.instance, LogCb, nullptr);
    std::fprintf(stderr, "[vlc] runtime ready: %s\n", qPrintable(dir));
    return true;
}

} // namespace

// ───────────────────────────────── 播放器 ────────────────────────────────────

VlcStreamPlayer::VlcStreamPlayer(QObject *parent)
    : QObject(parent)
{
}

VlcStreamPlayer::~VlcStreamPlayer()
{
    stop();
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

void VlcStreamPlayer::setSource(const QString &url)
{
    if (source_ == url)
        return;
    source_ = url;
    emit sourceChanged();

    stop();
    error_text_.clear();
    emit errorTextChanged();
    if (!source_.isEmpty())
        start();
}

void VlcStreamPlayer::postStatus(const QString &text)
{
    QMetaObject::invokeMethod(this, [this, text]() {
        if (status_text_ == text)
            return;
        status_text_ = text;
        emit statusTextChanged();
    }, Qt::QueuedConnection);
}

void VlcStreamPlayer::postError(const QString &text)
{
    QMetaObject::invokeMethod(this, [this, text]() {
        error_text_ = text;
        emit errorTextChanged();
    }, Qt::QueuedConnection);
}

void VlcStreamPlayer::setPlayingQueued(const bool value)
{
    QMetaObject::invokeMethod(this, [this, value]() {
        if (playing_ == value)
            return;
        playing_ = value;
        emit playingChanged();
    }, Qt::QueuedConnection);
}

void VlcStreamPlayer::start()
{
    if (!LoadRuntime()) {
        error_text_ = api().load_error;
        emit errorTextChanged();
        return;
    }
    Api &a = api();

    media_ = a.media_new_location(a.instance, source_.toUtf8().constData());
    if (!media_) {
        error_text_ = QStringLiteral("无法创建媒体: ") + source_;
        emit errorTextChanged();
        return;
    }
    // 直播低延迟缓冲。RTSP 传输方式保持引擎默认（UDP，与本机 VLC 验证一致）；
    // 若产线网络挡 UDP，改这里加 ":rtsp-tcp" 一行即可。
    a.media_add_option(media_, ":network-caching=300");

    player_ = a.player_new_from_media(media_);
    if (!player_) {
        error_text_ = QStringLiteral("无法创建播放器");
        emit errorTextChanged();
        a.media_release(media_);
        media_ = nullptr;
        return;
    }

    first_frame_seen_ = false;
    a.video_set_format_callbacks(player_, SetupCb, CleanupCb);
    a.video_set_callbacks(player_, LockCb, UnlockCb, DisplayCb, this);

    if (vlc_event_manager_t *em = a.player_event_manager(player_)) {
        for (const int type : {kEventPlaying, kEventBuffering, kEventStopped,
                               kEventEndReached, kEventError}) {
            a.event_attach(em, type, EventCb, this);
        }
    }

    status_text_ = QStringLiteral("连接中…");
    emit statusTextChanged();
    if (a.player_play(player_) != 0) {
        error_text_ = QStringLiteral("启动播放失败: ") +
            QString::fromUtf8(a.errmsg ? a.errmsg() : "");
        emit errorTextChanged();
    }
}

void VlcStreamPlayer::stop()
{
    Api &a = api();
    if (player_) {
        a.player_stop(player_);      // 同步：返回后回调不再触发
        a.player_release(player_);
        player_ = nullptr;
    }
    if (media_) {
        a.media_release(media_);
        media_ = nullptr;
    }
    {
        QMutexLocker lock(&frame_mutex_);
        frame_buffer_.clear();
        width_ = height_ = 0;
    }
    if (playing_) {
        playing_ = false;
        emit playingChanged();
    }
    status_text_.clear();
    emit statusTextChanged();
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
    self->postStatus(QStringLiteral("已协商 %1x%2").arg(w).arg(h));
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

    QMutexLocker lock(&self->frame_mutex_);
    QVideoSink *sink = self->sink_.data();
    if (!sink || self->frame_buffer_.empty())
        return;
    const unsigned w = self->width_;
    const unsigned h = self->height_;

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
    lock.unlock();

    sink->setVideoFrame(frame);
    if (!self->first_frame_seen_) {
        self->first_frame_seen_ = true;
        self->setPlayingQueued(true);
        self->postStatus(QStringLiteral("已出图 %1x%2").arg(w).arg(h));
    }
}

void VlcStreamPlayer::EventCb(const void *event, void *opaque)
{
    auto *self = static_cast<VlcStreamPlayer *>(opaque);
    const auto *ev = static_cast<const VlcEvent *>(event);
    switch (ev->type) {
    case kEventPlaying:
        self->postStatus(QStringLiteral("已连接，等待首帧…"));
        break;
    case kEventBuffering:
        if (!self->first_frame_seen_)
            self->postStatus(QStringLiteral("缓冲 %1%")
                                 .arg(static_cast<int>(ev->u.buffering.cache)));
        break;
    case kEventStopped:
    case kEventEndReached:
        self->setPlayingQueued(false);
        self->postStatus(QStringLiteral("流已结束"));
        break;
    case kEventError:
        self->setPlayingQueued(false);
        self->postError(QStringLiteral("拉流出错（VLC 引擎报告）"));
        break;
    default:
        break;
    }
}
