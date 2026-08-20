#include "xp2p_client.hpp"

#include "stream_log.hpp"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLibrary>
#include <QThreadPool>

#include <cstdio>
#include <cstdlib>

// ─────────────────────────── SDK 动态绑定 ────────────────────────────────────
// app_interface.dll 是纯 C 接口（C ABI 跨编译器兼容），用 QLibrary::resolve 手动
// 绑函数指针，绕开 MSVC 导入库与 MinGW 的链接不兼容。缺 DLL / 缺入口都只是
// available()==false，不影响产测其余工位（docs/拉流整合方案.md §2.1/§7.2）。

namespace {

// 与 appWrapper.h 一致的枚举/结构（不引头文件，避免带进 MSVC 专用宏）。
enum {
    kXp2pClose        = 1000,
    kXp2pDisconnect   = 1003,
    kXp2pDetectReady  = 1004,
    kXp2pDetectError  = 1005,
    kXp2pStreamEnd    = 1008,   // 推流结束（原因在事件 msg 里，别猜）
    kXp2pDownloadEnd  = 1009,
    kXp2pStreamRefuse = 1010,   // 请求 devicename 不一致被拒
};

// XP2P_PROTOCOL_AUTO=0：udp 不通自动切 tcp
struct app_config_t {
    const char *server;
    const char *ip;
    std::uint64_t port;
    int type;
    bool cross;
};

using msg_handle_t = const char *(*)(const char *id, int type, const char *msg);
using av_recv_handle_t = void (*)(const char *id, std::uint8_t *buf, std::size_t len);
using device_data_handle_t = char *(*)(const char *id, std::uint8_t *buf, std::size_t len);

struct Api {
    bool loaded {false};
    QString load_error;

    void (*set_user_callback)(av_recv_handle_t, msg_handle_t, device_data_handle_t) {};
    int (*set_qcloud_cred)(const char *, const char *) {};
    void (*set_log_enable)(bool, bool) ;
    int (*start_service)(const char *, const char *, const char *, app_config_t) {};
    int (*set_device_xp2p_info)(const char *, const char *) {};
    const char *(*delegate_http_flv)(const char *) {};
    void (*stop_service)(const char *) {};
    // 信令通道（同步阻塞，最长按 timeout_us 等）。只用来排障：问设备
    // get_device_st，看它到底认不认我们这个取流请求。recv_buf 由 SDK 内部
    // malloc、调用方 free。
    int (*post_command_sync)(const char *, const unsigned char *, std::size_t,
                             unsigned char **, std::size_t *, std::uint64_t) {};
};

// 空的音视频/设备数据回调：我们只用本机 http-flv 转发（delegateHttpFlv），
// 不从这两个回调里取流，所以留空即可（参考实现也是空实现）。
void avRecvNoop(const char *, std::uint8_t *, std::size_t) {}
char *deviceDataNoop(const char *, std::uint8_t *, std::size_t)
{
    static char empty[] = "";
    return empty;
}

// 兜底凭据：参考实现 InitTencent 里硬编的那对（TencentIotMgr.cpp:73）。
// 只在 cloud_config.json 缺失时用 —— 见下面 loadCloudApiCred 的说明，这对
// 值大概率**不能**用于 SDK 自取 xp2p_info。
constexpr const char *kFallbackAppId = "tXVlRiHkswkCnFgQDtUn";
constexpr const char *kFallbackAppKey = "aEHgtACyEVsEpkowh";

// setQcloudApiCred 要的是**云 API 的 secret_id/secret_key**（appWrapper.h:242
// 原文"云API secrct_id"），SDK 用它调云 API 自取设备的 xp2p_info。
//
// 为什么不能照抄参考实现：参考虽然也调 setQcloudApiCred，但它随后**总是**从
// 腾达后台取到真 xp2p_info 再 setDeviceXp2pInfo（TencentIotMgr.cpp:170-196，
// 取空就直接返回），自取那条路它从没走过 —— 所以它灌的是 app_id/app_key
// 还是云 API 密钥，在它那儿看不出差别。我们没有腾达登录态，只能靠自取，
// 这对值就成了必须正确的东西。
//
// 产测工具本来就有真云 API 密钥（cloud_config.json，CloudClient 在用，
// secretId 是 AKID… 开头的标准 CAM 形态），直接复用同一份。
// 纪律：只读，绝不落日志/不进 git（该文件已 gitignore）。
struct CloudApiCred { QByteArray id; QByteArray key; bool from_config {false}; };

CloudApiCred loadCloudApiCred()
{
    CloudApiCred c;
    const QString path =
        QCoreApplication::applicationDirPath() + QStringLiteral("/cloud_config.json");
    QFile f(path);
    if (f.open(QIODevice::ReadOnly)) {
        const QJsonObject cfg = QJsonDocument::fromJson(f.readAll()).object();
        const QString id = cfg.value(QStringLiteral("secretId")).toString();
        const QString key = cfg.value(QStringLiteral("secretKey")).toString();
        if (!id.isEmpty() && !key.isEmpty()) {
            c.id = id.toUtf8();
            c.key = key.toUtf8();
            c.from_config = true;
            return c;
        }
    }
    c.id = kFallbackAppId;
    c.key = kFallbackAppKey;
    return c;
}

Api &api()
{
    static Api a;
    return a;
}

// 只加载一次。DLL 找 dist/xp2p/（打包时随 app_interface.dll 一起放），
// 联调时也认本机参考工程路径。
bool loadRuntime()
{
    Api &a = api();
    if (a.loaded)
        return true;
    if (!a.load_error.isEmpty())
        return false;                // 上次已失败，不反复试

    const QString appDir = QCoreApplication::applicationDirPath();
    const QStringList candidates = {
        appDir + QStringLiteral("/xp2p"),
        QStringLiteral("D:/tendasecuritypc/3rdpart/p2p_sample/lib/windows/x64/Release"),
    };
    QString dir;
    for (const QString &c : candidates) {
        if (QFile::exists(c + QStringLiteral("/app_interface.dll"))) {
            dir = c;
            break;
        }
    }
    if (dir.isEmpty()) {
        a.load_error = QStringLiteral("未找到 XP2P 运行时（dist/xp2p/app_interface.dll 缺失）");
        return false;
    }

    static QLibrary lib(dir + QStringLiteral("/app_interface.dll"));
    if (!lib.load()) {
        a.load_error = QStringLiteral("app_interface.dll 加载失败：") + lib.errorString();
        return false;
    }

    const auto need = [&](const char *name) {
        void *fn = reinterpret_cast<void *>(lib.resolve(name));
        if (!fn && a.load_error.isEmpty())
            a.load_error = QStringLiteral("app_interface 缺少入口: ") + QLatin1String(name);
        return fn;
    };
    a.set_user_callback = reinterpret_cast<decltype(a.set_user_callback)>(
        need("setUserCallbackToXp2p"));
    a.set_qcloud_cred = reinterpret_cast<decltype(a.set_qcloud_cred)>(
        need("setQcloudApiCred"));
    a.set_log_enable = reinterpret_cast<decltype(a.set_log_enable)>(
        need("setLogEnable"));
    a.start_service = reinterpret_cast<decltype(a.start_service)>(
        need("startService"));
    a.set_device_xp2p_info = reinterpret_cast<decltype(a.set_device_xp2p_info)>(
        need("setDeviceXp2pInfo"));
    a.delegate_http_flv = reinterpret_cast<decltype(a.delegate_http_flv)>(
        need("delegateHttpFlv"));
    a.stop_service = reinterpret_cast<decltype(a.stop_service)>(
        need("stopService"));
    // 排障用，缺了不算致命：不进 need()，解析失败就跳过探测，照常拉流。
    a.post_command_sync = reinterpret_cast<decltype(a.post_command_sync)>(
        reinterpret_cast<void *>(lib.resolve("postCommandRequestSync")));
    if (!a.load_error.isEmpty())
        return false;

    a.loaded = true;
    return true;
}

Xp2pClient *g_instance = nullptr;

constexpr int kReadyTimeoutMs = 10000;

// 事件码 → 人话。日志里只有 1008 这种数字，现场看不懂也不好判断。
QString EventName(int type)
{
    switch (type) {
    case kXp2pClose:        return QStringLiteral(" Close(传输完成)");
    case kXp2pDisconnect:   return QStringLiteral(" Disconnect(P2P链路断开)");
    case kXp2pDetectReady:  return QStringLiteral(" DetectReady(建联成功)");
    case kXp2pDetectError:  return QStringLiteral(" DetectError(建联失败)");
    case kXp2pStreamEnd:    return QStringLiteral(" StreamEnd(推流结束,原因看 msg)");
    case kXp2pDownloadEnd:  return QStringLiteral(" DownloadEnd");
    case kXp2pStreamRefuse: return QStringLiteral(" StreamRefuse(devicename 不一致被拒)");
    case 1001:              return QStringLiteral(" Log");
    case 1002:              return QStringLiteral(" Cmd");
    case 1006:              return QStringLiteral(" DeviceMsgArrived");
    case 1007:              return QStringLiteral(" CmdNoReturn(设备未回自定义信令)");
    default:                return QString();
    }
}

// 排障探测：建联成功后问设备 get_device_st，把回包记到日志。
//
// 为什么值得做：它和取流走**同一条 P2P 隧道**，但是一次有回包的往返。
//   - 设备正常回包  → 隧道和信令都通，卡 0% 的原因只能在媒体侧；
//   - 探测超时/失败 → DetectReady 是"本地代理就绪"而非"隧道到设备可用"，
//     方向完全不同，不用再在 quality 上试第四次。
// 回包字段（参考 BL_TencentLivePlayControl::checkLivePullAllowed）：
//   status 0=可拉流 1=超限，appConnectNum 当前连接数，maxConnectNum 上限。
// 注意字段名是 `qualtity` —— 设备侧的拼写，别"修正"它，改了设备就不认。
//
// 只读、不改任何状态，失败一律忽略：参考实现里这个查询失败也是放行拉流。
// postCommandRequestSync 会阻塞到有回包或超时，绝不能在 UI 线程调。
void ProbeDeviceStatus(const QByteArray &deviceId, const QByteArray &quality)
{
    Api &a = api();
    if (!a.loaded || !a.post_command_sync)
        return;

    const QByteArray cmd = QByteArray("action=inner_define&channel=0"
                                      "&cmd=get_device_st&type=Live&qualtity=")
                           + quality;
    unsigned char *recv = nullptr;
    std::size_t recv_len = 0;
    const int rc = a.post_command_sync(deviceId.constData(),
                                       reinterpret_cast<const unsigned char *>(cmd.constData()),
                                       static_cast<std::size_t>(cmd.size()),
                                       &recv, &recv_len, 5ull * 1000 * 1000);
    if (rc != 0) {
        StreamLog::append(QStringLiteral("[xp2p][探测] get_device_st 失败 rc=%1"
                                         " → 信令都不通，问题不在 quality").arg(rc));
    } else {
        const QString body = (recv && recv_len > 0)
            ? QString::fromUtf8(reinterpret_cast<const char *>(recv),
                                static_cast<int>(recv_len))
            : QStringLiteral("<空>");
        StreamLog::append(QStringLiteral("[xp2p][探测] get_device_st 回包: %1").arg(body));
    }
    if (recv)
        std::free(recv);            // SDK 内部 malloc，调用方释放
}

} // namespace

// ───────────────────────────── 建联器 ────────────────────────────────────────

Xp2pClient::Xp2pClient(QObject *parent)
    : QObject(parent)
{
    g_instance = this;

    timeout_timer_.setSingleShot(true);
    timeout_timer_.setInterval(kReadyTimeoutMs);
    connect(&timeout_timer_, &QTimer::timeout, this, [this] {
        fail(QStringLiteral("云拉流建联超时（10s 未就绪，可能设备离线或被其他工位占用）"));
    });

    // 全局初始化只做一次：注册回调 + 灌凭据 + 关 SDK 日志。放构造里（页面
    // 构造即触发），把首次加载的代价挪到开机而不是工人点按钮那一刻。
    if (loadRuntime()) {
        Api &a = api();
        a.set_user_callback(avRecvNoop, &Xp2pClient::msgCallback, deviceDataNoop);
        const CloudApiCred cred = loadCloudApiCred();
        const int credrc = a.set_qcloud_cred(cred.id.constData(), cred.key.constData());
        // 只报来源与返回码，不报密钥本身
        StreamLog::append(QStringLiteral("[xp2p] setQcloudApiCred rc=%1，凭据来源=%2")
            .arg(credrc)
            .arg(cred.from_config ? QStringLiteral("cloud_config.json 的云API密钥")
                                  : QStringLiteral("内置兜底 app_id/app_key")));
        // 默认关 SDK 日志（它很吵）。排障时用 PTEST_STREAM_DEBUG=1 放开 —— 卡在
        // "缓冲 0%" 这类问题只有 SDK 日志能说清设备对取流请求回了什么，
        // 光看我们自己的状态机看不出来。与 libvlc 那边同一个开关。
        const bool debug = !qEnvironmentVariableIsEmpty("PTEST_STREAM_DEBUG");
        a.set_log_enable(debug, false);
    }
}

Xp2pClient::~Xp2pClient()
{
    teardown();
    if (g_instance == this)
        g_instance = nullptr;
}

bool Xp2pClient::available() const
{
    return api().loaded;
}

const char *Xp2pClient::msgCallback(const char *id, int type, const char *msg)
{
    // SDK 线程触发。弹回对象线程再处理（照搬参考实现的线程模型）。
    if (g_instance) {
        const QString deviceId = QString::fromUtf8(id ? id : "");
        const QString message = QString::fromUtf8(msg ? msg : "");
        QMetaObject::invokeMethod(g_instance, [deviceId, type, message] {
            if (g_instance)
                g_instance->onXp2pMessage(deviceId, type, message);
        }, Qt::QueuedConnection);
    }
    return "";
}

void Xp2pClient::start(const QString &productKey, const QString &deviceName,
                       const QString &quality)
{
    if (!loadRuntime()) {
        fail(api().load_error);
        return;
    }
    if (productKey.isEmpty() || deviceName.isEmpty()) {
        fail(QStringLiteral("云拉流缺少设备标识（productKey/deviceName）"));
        return;
    }
    // 已在建/在播同一设备：忽略重复点击
    if (device_id_ == deviceName && (state_ == Connecting || state_ == Playing))
        return;

    teardown();                      // 换设备/重连：旧会话先收干净
    device_id_ = deviceName;
    product_key_ = productKey;
    quality_ = quality.isEmpty() ? QStringLiteral("super") : quality;
    setErrorText(QString());
    setState(Connecting);

    // 先取 xp2p_info 再建联 —— 顺序照参考实现 startXp2pService：票据取不到就
    // 别起服务，否则本机转发服务起得来、但每个请求都被 SDK 以
    // "invalid xp2pinfo parameter" 挡掉，表现是静默卡 0%，最难查。
    tenda_.fetchXp2pInfo(productKey, deviceName,
        [this, deviceName](bool ok, const QString &valueOrError) {
            // 回调可能晚于用户切设备/点停止：认不出当前设备就丢弃
            if (device_id_ != deviceName || state_ != Connecting)
                return;
            if (!ok) {
                fail(valueOrError);
                return;
            }
            beginSession(valueOrError);
        });
}

void Xp2pClient::beginSession(const QString &xp2pInfo)
{
    Api &a = api();
    const QByteArray id = device_id_.toUtf8();
    const QByteArray pk = product_key_.toUtf8();

    app_config_t config {};
    config.server = "";
    config.ip = "";
    config.port = 20002;
    config.type = 0;                 // XP2P_PROTOCOL_AUTO
    config.cross = false;

    const int rc = a.start_service(id.constData(), pk.constData(),
                                   id.constData(), config);
    if (rc != 0) {
        fail(QStringLiteral("startService 失败 rc=%1").arg(rc));
        return;
    }
    service_started_ = true;   // 只有到这里 teardown() 才该去 stopService

    // 灌真票据。曾经这里传 NULL 想让 SDK 自取，实测 rc=-1001：自取查的是腾讯
    // 「物联网视频服务」，我们的设备在「物联网开发平台」，两边产品空间不重叠。
    // 这一步的返回码必须看 —— 票据不对就没有到设备的路由，取流会**静默**卡
    // 0% 而不报错（连 DetectReady 都照样给，它只代表本机转发服务起来了）。
    StreamLog::append(QStringLiteral("[xp2p] 开始建联 product=%1 device=%2 quality=%3")
                          .arg(product_key_, device_id_, quality_));
    const QByteArray info = xp2pInfo.toUtf8();
    const int inforc = a.set_device_xp2p_info(id.constData(), info.constData());
    StreamLog::append(inforc == 0
        ? QStringLiteral("[xp2p] setDeviceXp2pInfo rc=0，票据已灌入")
        : QStringLiteral("[xp2p] setDeviceXp2pInfo rc=%1 → 票据被拒（-1014 规则不符 / "
                         "-1015 解密失败），取流必然卡 0%").arg(inforc));
    timeout_timer_.start();
}

void Xp2pClient::stop()
{
    teardown();
    setState(Idle);
}

void Xp2pClient::onXp2pMessage(const QString &deviceId, int type, const QString &msg)
{
    // 每条事件都记（含被丢弃的）。卡 0% 这类问题最怕"什么都没发生"：
    // 有没有 1008/1010、1004 之后还有没有别的，光看 UI 是看不出来的。
    StreamLog::append(QStringLiteral("[xp2p] 事件 %1%2%3%4")
        .arg(type)
        .arg(EventName(type))
        .arg(deviceId == device_id_ ? QString() : QStringLiteral(" (非当前设备,丢弃)"))
        .arg(msg.isEmpty() ? QString() : QStringLiteral(" msg=") + msg));

    // 只认当前设备的消息：晚到的旧设备回调直接丢
    if (deviceId != device_id_ || device_id_.isEmpty())
        return;

    switch (type) {
    case kXp2pDetectReady: {
        if (state_ != Connecting)
            return;
        timeout_timer_.stop();
        Api &a = api();
        const QByteArray id = device_id_.toUtf8();
        const char *base = a.delegate_http_flv(id.constData());
        if (!base || base[0] == '\0') {
            fail(QStringLiteral("delegateHttpFlv 返回空（本机转发服务未起）"));
            return;
        }
        // 本机 URL 拼直播参数。**逐字对齐参考实现在服役的 composeLiveUrl**
        //（src/Common/TencentIotMgr.cpp:331）：只有 action=live&quality=xxx，
        // 连 crypto 都 Q_UNUSED 掉了。早先照抄 p2p_sample 的 QcloudRequestLiveUrl
        // 多带了 &channel=0&_crypto=off，已去掉 —— 但要说清：去掉它**并没有**
        // 解决缓冲卡 0%，所以别把这行当成那个 bug 的修复记录。留着对齐参考口径
        // 是为了少一个变量，channel 缺省即 0，不用显式带。
        live_url_ = QString::fromUtf8(base)
            + QStringLiteral("ipc.flv?action=live&quality=") + quality_;
        // 排障锚点：DetectReady 已到（P2P 隧道通了）、代理也出了本机 URL。若这条
        // 记下了但界面还卡 0%，问题在"设备不为这个请求推流"，不在建联/凭据。
        StreamLog::append(QStringLiteral("[xp2p] 本机取流地址 = ") + live_url_);
        emit liveUrlChanged();
        setState(Playing);
        emit liveUrlReady(live_url_);
        // 先把 URL 交给播放器，再异步探测 —— 探测是阻塞调用（最长 5s），放在
        // 后面且丢到线程池，保证它既不推迟起播、也不占住 UI 线程。
        // 必须由 PTEST_STREAM_DEBUG 显式开：产线正常拉流不该为排障多占一个
        // 线程池槽位干等 5 秒。纯排障，不影响拉流本身。
        if (!qEnvironmentVariableIsEmpty("PTEST_STREAM_DEBUG")) {
            const QByteArray probe_id = device_id_.toUtf8();
            const QByteArray probe_quality = quality_.toUtf8();
            QThreadPool::globalInstance()->start([probe_id, probe_quality]() {
                ProbeDeviceStatus(probe_id, probe_quality);
            });
        }
        break;
    }
    case kXp2pDetectError:
        fail(QStringLiteral("云拉流链路初始化失败（DetectError）"));
        break;
    case kXp2pStreamRefuse:
        fail(QStringLiteral("设备拒绝推流（devicename 不一致）"));
        break;
    case kXp2pStreamEnd:
        // ⚠️ 别再自作聪明补"可能被其他工位占用"。1008 的含义就是**推流结束**，
        //    设备会在 msg 里说明原因（实测 {"mode":"device end stream"}）。
        //    早先那句猜测文案把一次"同一 URL 被两个播放器同时打开、设备踢掉先来
        //    的会话"误导成了名额问题，白查一轮。原因照抄设备的话，不加推测。
        teardown();
        setState(Idle);
        emit streamEnded(msg.isEmpty()
            ? QStringLiteral("设备停止推流")
            : QStringLiteral("设备停止推流：%1").arg(msg));
        break;
    case kXp2pDisconnect:
    case kXp2pDownloadEnd:
    case kXp2pClose:
        teardown();
        setState(Idle);
        emit streamEnded(QStringLiteral("云拉流链路已断开"));
        break;
    default:
        break;
    }
}

void Xp2pClient::teardown()
{
    timeout_timer_.stop();
    // 只对"真的 startService 过"的会话收尾。device_id_ 在异步取票据**之前**就已
    // 赋值，若在取票据阶段失败就 stop_service，SDK 只会回一句
    // "p2p service is not running"，把真正的失败原因盖掉（实测踩过）。
    if (service_started_ && !device_id_.isEmpty() && api().loaded) {
        Api &a = api();
        a.stop_service(device_id_.toUtf8().constData());
    }
    service_started_ = false;
    device_id_.clear();
    if (!live_url_.isEmpty()) {
        live_url_.clear();
        emit liveUrlChanged();
    }
}

void Xp2pClient::setState(State s)
{
    if (state_ == s)
        return;
    state_ = s;
    emit stateChanged();
}

void Xp2pClient::setErrorText(const QString &text)
{
    if (error_text_ == text)
        return;
    error_text_ = text;
    emit errorTextChanged();
}

void Xp2pClient::fail(const QString &text)
{
    // 先落日志再 teardown：排障面板要看到的是**原因**，不是收尾时 SDK 那句
    // "p2p service is not running"。
    StreamLog::append(QStringLiteral("[xp2p] 失败：") + text);
    teardown();
    setErrorText(text);
    setState(Error);
}
