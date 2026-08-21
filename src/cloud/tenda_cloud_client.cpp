#include "tenda_cloud_client.hpp"

#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDateTime>
#include <QMutex>
#include <QMutexLocker>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QSysInfo>
#include <QUrl>

#include "stream_log.hpp"

namespace {

// 进程级共享的登录 token。工人/工程师登录成功后存进来，取票据一律用它。
// 加锁：登录在主线程，取票据的回调也在主线程，但 Xp2pClient 的 SDK 回调线程也可能
// 间接读到 —— 加锁比"大概不会撞"可靠，成本可忽略。
QString g_sessionToken;
QMutex g_sessionTokenMutex;

// 接口固定盐，参考实现 UIDefine.h:50 原文注释"接口固定的sigsalt，适用于获取
// 主账号，登录"。不是密钥，是全端一致的公开常量。
constexpr char kSigSalt[] = "501c0d9f-58fb-11ed-ba08-525400481a47";
// 接口版本号，服务端按它做兼容分支（参考实现 UIDefine.h:8）
constexpr char kPcVersion[] = "1.0.7";

constexpr char kPathCheck[] = "/td/td-user-api/internal/index/login/check/v2";
constexpr char kPathPwdLogin[] = "/td/td-user-api/internal/login/password/v2";
constexpr char kPathP2pToken[] = "/td/td-device-api/se-device/p2pToken/get/v1";

constexpr int kHttpTimeoutMs = 15000;

// 业务码：token 过期 / token 解析失败 —— 两者都该重登一次再试
constexpr int kCodeTokenExpired = 100410;
constexpr int kCodeTokenBad = 100412;

QString Md5Hex(const QByteArray &data)
{
    return QString::fromLatin1(
        QCryptographicHash::hash(data, QCryptographicHash::Md5).toHex());
}

// 复刻参考实现 EncryptUtil::encryptAccountPassword（BL/utils/EncryptUtil.cpp:124）：
//   salt   = sha1(用户名) 的原始 20 字节
//   缓冲   = 密码按 4 字节对齐补 '\0'，后面接 salt
//   5 轮 MD5：前 4 轮把 16 字节原始摘要喂进下一轮，第 5 轮取 hex 作为结果
// 参考实现里绕了 hex→字节 的来回转换，等价，这里直接用原始摘要。
QByteArray EncryptAccountPassword(const QString &username, const QString &password)
{
    const QByteArray salt =
        QCryptographicHash::hash(username.toUtf8(), QCryptographicHash::Sha1);

    QByteArray padded = password.toUtf8();
    const int aligned = ((padded.size() + 3) / 4) * 4;
    padded.append(aligned - padded.size(), '\0');

    QByteArray buf = padded + salt;
    QByteArray hex;
    for (int i = 0; i < 5; ++i) {
        const QByteArray raw = QCryptographicHash::hash(buf, QCryptographicHash::Md5);
        hex = raw.toHex();
        buf = raw;
    }
    return hex;
}

// 解析统一信封 {code, msg, data}。透传 code 给调用方做重登判断。
QJsonObject ParseEnvelope(const QByteArray &body, int *code, QString *msg)
{
    const QJsonObject root = QJsonDocument::fromJson(body).object();
    if (code)
        *code = root.value(QStringLiteral("code")).toInt(-1);
    if (msg)
        *msg = root.value(QStringLiteral("msg")).toString();
    return root.value(QStringLiteral("data")).toObject();
}

} // namespace

TendaCloudClient::TendaCloudClient(QObject *parent)
    : QObject(parent)
{
    // Terminal 只要本机稳定且登录/取票据两步一致即可（服务端拿它验 sig、
    // 绑会话）。参考实现读的是系统 UUID，这里用 Qt 自带的机器码，省掉 WMI。
    terminal_ = QString::fromLatin1(QSysInfo::machineUniqueId());
    if (terminal_.isEmpty())
        terminal_ = QStringLiteral("defaultid");
    loadConfig();
}

void TendaCloudClient::loadConfig()
{
    const QString path =
        QCoreApplication::applicationDirPath() + QStringLiteral("/cloud_config.json");
    QJsonObject cfg;
    QFile file(path);
    if (file.open(QIODevice::ReadOnly))
        cfg = QJsonDocument::fromJson(file.readAll()).object();

    const QJsonObject tenda = cfg.value(QStringLiteral("tenda")).toObject();
    domain_ = tenda.value(QStringLiteral("domain"))
                  .toString(QStringLiteral("https://cn-cloud.tenda.com.cn"));
    account_ = tenda.value(QStringLiteral("account")).toString();
    password_ = tenda.value(QStringLiteral("password")).toString();
    manual_info_ = tenda.value(QStringLiteral("xp2pInfo")).toString().trimmed();
    access_token_.clear();          // 换了配置，旧 token 作废

    // 纪律：只报"有没有"，不报账号密码本身
    StreamLog::append(QStringLiteral("[腾达云] 配置 domain=%1 账号=%2 手工xp2pInfo=%3")
        .arg(domain_)
        .arg(account_.isEmpty() ? QStringLiteral("未配") : QStringLiteral("已配"))
        .arg(manual_info_.isEmpty() ? QStringLiteral("无") : QStringLiteral("有")));
}

bool TendaCloudClient::configured() const
{
    return !manual_info_.isEmpty() || (!account_.isEmpty() && !password_.isEmpty());
}

QString TendaCloudClient::configHint() const
{
    return QStringLiteral(
        "云拉流缺少 xp2p_info 来源：请在 cloud_config.json 的 \"tenda\" 段里，"
        "填 account/password（腾达云账号，软件自动取票据），"
        "或把腾讯云后台/小程序那串 xp2pInfo 直接粘进来先做验证。");
}

void TendaCloudClient::applyHeaders(QNetworkRequest &request, bool withApp,
                                    bool withAuth) const
{
    const QByteArray ts =
        QByteArray::number(QDateTime::currentSecsSinceEpoch());   // 秒，不是毫秒
    const QString sig = Md5Hex(terminal_.toUtf8() + ts + kSigSalt);

    request.setHeader(QNetworkRequest::ContentTypeHeader,
                      QStringLiteral("application/json"));
    request.setRawHeader("pcv", kPcVersion);
    request.setRawHeader("sig", sig.toLatin1());
    request.setRawHeader("Terminal", terminal_.toUtf8());
    request.setRawHeader("Timestamp", ts);
    if (withApp) {
        request.setRawHeader("App-Id", "Tenda");
        request.setRawHeader("Project-Id", "Tenda Security");
        request.setRawHeader("AppSource", "TENDA-SECURITY");
        request.setRawHeader("AppVersion", kPcVersion);
    }
    if (withAuth) {
        // 优先用**登录者**的 token（工人/工程师登录腾达云时存进共享槽）。
        // 这样 cloud_config.json 里不再需要账号密码 —— 实测 p2pToken 不校验设备
        // 归属，登录者的身份一样取得到票据（2026-08-21 用户确认：台面这台设备并没有
        // 绑在配置里那个账号名下）。
        // 退回本实例的 access_token_ 只为兼容"配了固定账号"的老配置。
        const QString token = sessionToken().isEmpty() ? access_token_ : sessionToken();
        if (!token.isEmpty()) {
            request.setRawHeader("Authorization",
                                 QByteArray("Bearer ") + token.toUtf8());
        }
    }
    request.setTransferTimeout(kHttpTimeoutMs);
}

void TendaCloudClient::fetchXp2pInfo(const QString &productKey, const QString &sn,
                                     Handler done)
{
    // 手工粘贴优先：票据是会话级的、几分钟就变，调画面阶段就靠它，不必每次
    // 都去跑一遍登录（账号那条路另算，见 [[cloud-integration-context]]）。
    if (!manual_info_.isEmpty()) {
        StreamLog::append(QStringLiteral("[腾达云] 用 cloud_config.json 里手工粘贴的 "
                                         "xp2pInfo（长度 %1）").arg(manual_info_.size()));
        done(true, manual_info_);
        return;
    }
    // 登录者的 token 就够了 —— 不需要 cloud_config.json 里的账号密码。
    // 这是常态路径：工人一登录软件就有了身份。
    if (!sessionToken().isEmpty()) {
        requestP2pToken(productKey, sn, false, std::move(done));
        return;
    }
    if (account_.isEmpty() || password_.isEmpty()) {
        done(false, QStringLiteral("尚未登录腾达云 —— 退出重新登录即可"
                                   "（或在 cloud_config.json 配 tenda.account/password）"));
        return;
    }
    if (access_token_.isEmpty()) {
        login([this, productKey, sn, done](bool ok, const QString &error) {
            if (!ok) {
                done(false, error);
                return;
            }
            requestP2pToken(productKey, sn, false, done);
        });
        return;
    }
    // 有缓存 token 就直接用，失效再重登（token 有效期未知，不主动猜）
    requestP2pToken(productKey, sn, true, done);
}

QString TendaCloudClient::sessionToken()
{
    QMutexLocker lock(&g_sessionTokenMutex);
    return g_sessionToken;
}

void TendaCloudClient::setSessionToken(const QString &token)
{
    QMutexLocker lock(&g_sessionTokenMutex);
    g_sessionToken = token;
}

void TendaCloudClient::clearSessionToken()
{
    QMutexLocker lock(&g_sessionTokenMutex);
    g_sessionToken.clear();
}

void TendaCloudClient::login(std::function<void(bool, const QString &)> done)
{
    // keepAsSession=false：配置里那个固定账号只服务取票据这条链，不该冒充"登录者"
    doLogin(account_, password_, true, false, std::move(done));
}

void TendaCloudClient::verifyCredential(const QString &account, const QString &password,
                                        bool keepAsSession,
                                        std::function<void(bool, const QString &)> done)
{
    // keepToken=false：不存进本实例的 access_token_（那是取票据链自己的缓存）。
    // keepAsSession 决定要不要存进进程级共享槽 —— 两者是不同的东西，别混。
    doLogin(account, password, false, keepAsSession, std::move(done));
}

void TendaCloudClient::doLogin(const QString &account, const QString &password,
                               bool keepToken, bool keepAsSession,
                               std::function<void(bool, const QString &)> done)
{
    // 第一步 check/v2：拿主账号和 encrypt_mode。密码加盐用的是**服务端回的**
    // phone/email，不是用户输入的原文（参考实现 RequestManage.cpp:177-184），
    // 手机号登录而账号库存的是邮箱时，盐必须跟着服务端走。
    const bool isEmail = account.contains(QLatin1Char('@'));
    QJsonObject body;
    body.insert(isEmail ? QStringLiteral("email") : QStringLiteral("phone"), account);

    QNetworkRequest request(QUrl(domain_ + QLatin1String(kPathCheck)));
    applyHeaders(request, false, false);

    QNetworkReply *reply =
        nam_.post(request, QJsonDocument(body).toJson(QJsonDocument::Compact));
    connect(reply, &QNetworkReply::finished, this,
            [this, reply, isEmail, password, keepToken, keepAsSession, done]() {
        reply->deleteLater();
        int code = -1;
        QString msg;
        const QJsonObject data = ParseEnvelope(reply->readAll(), &code, &msg);
        if (code != 0) {
            const QString hint = code == 100421
                ? QStringLiteral("（该账号未在腾达安防云注册，确认是安防 App 的账号）")
                : QString();
            done(false, QStringLiteral("腾达云查账号失败 code=%1 %2%3")
                            .arg(code).arg(msg, hint));
            return;
        }
        const QString phone = data.value(QStringLiteral("phone")).toString();
        const QString email = data.value(QStringLiteral("email")).toString();
        const QString mode = data.value(QStringLiteral("encrypt_mode")).toString();
        const QString saltUser =
            mode == QStringLiteral("ENCRYPT_PHONE") ? phone : email;

        QJsonObject login;
        if (isEmail) {
            login.insert(QStringLiteral("email"), email);
            login.insert(QStringLiteral("phone"), QString());
        } else {
            login.insert(QStringLiteral("phone"), phone);
            login.insert(QStringLiteral("email"), QString());
        }
        const QString encrypted =
            QString::fromLatin1(EncryptAccountPassword(saltUser, password));
        login.insert(QStringLiteral("password"), encrypted);
        login.insert(QStringLiteral("se_password"), encrypted);
        login.insert(QStringLiteral("terminal"), terminal_);
        login.insert(QStringLiteral("terminal_os"), QStringLiteral("Windows"));
        login.insert(QStringLiteral("push_token"), QString());
        login.insert(QStringLiteral("push_OS"), QStringLiteral("ali"));
        login.insert(QStringLiteral("source"), QStringLiteral("TENDA-SECURITY"));
        login.insert(QStringLiteral("language"), QStringLiteral("zh-CN"));
        login.insert(QStringLiteral("timezone"), QStringLiteral("Asia/Shanghai"));
        login.insert(QStringLiteral("country_code"), QStringLiteral("CN"));
        login.insert(QStringLiteral("ip"), QString());
        login.insert(QStringLiteral("phone_code"), QStringLiteral("86"));
        login.insert(QStringLiteral("app_version"), QLatin1String(kPcVersion));
        login.insert(QStringLiteral("phone_model"), QStringLiteral("PC_") + terminal_);

        QNetworkRequest req(QUrl(domain_ + QLatin1String(kPathPwdLogin)));
        applyHeaders(req, true, false);
        QNetworkReply *r2 =
            nam_.post(req, QJsonDocument(login).toJson(QJsonDocument::Compact));
        connect(r2, &QNetworkReply::finished, this,
                [this, r2, keepToken, keepAsSession, done]() {
            r2->deleteLater();
            int c = -1;
            QString m;
            const QJsonObject d = ParseEnvelope(r2->readAll(), &c, &m);
            if (c != 0) {
                // 密码错的业务码要单独给一句人话 —— 工人看 code 看不懂
                const QString hint = (c == 100404 || c == 100405 || c == 100406)
                    ? QStringLiteral("（密码不正确）") : QString();
                done(false, QStringLiteral("腾达云登录失败 code=%1 %2%3")
                                .arg(c).arg(m, hint));
                return;
            }
            const QString token = d.value(QStringLiteral("access_token")).toString();
            if (token.isEmpty()) {
                done(false, QStringLiteral("腾达云登录成功但没回 access_token"));
                return;
            }
            if (keepToken)
                access_token_ = token;
            if (keepAsSession)
                setSessionToken(token);   // 之后取票据一律用登录者的身份
            // 纪律：只报长度，绝不落 token 本身
            StreamLog::append(QStringLiteral("[腾达云] 登录成功，access_token 长度 %1%2")
                                  .arg(token.size())
                                  .arg(keepAsSession ? QStringLiteral("（已作为会话身份）")
                                                     : QString()));
            done(true, QString());
        });
    });
}

void TendaCloudClient::requestP2pToken(const QString &productKey, const QString &sn,
                                       bool allowRelogin, Handler done)
{
    // 参数走 query string —— 参考实现把"body"直接拼到 URL 后面
    //（httpsrequest.cpp:322-331 那段 GET 拼接），不是真的请求体
    QUrl url(domain_ + QLatin1String(kPathP2pToken));
    url.setQuery(QStringLiteral("product_key=%1&sn=%2").arg(productKey, sn));

    QNetworkRequest request(url);
    applyHeaders(request, true, true);
    request.setRawHeader("Provider", "C");

    StreamLog::append(QStringLiteral("[腾达云] 取 xp2p_info product_key=%1 sn=%2")
                          .arg(productKey, sn));

    QNetworkReply *reply = nam_.get(request);
    connect(reply, &QNetworkReply::finished, this,
            [this, reply, productKey, sn, allowRelogin, done]() {
        reply->deleteLater();
        int code = -1;
        QString msg;
        const QJsonObject data = ParseEnvelope(reply->readAll(), &code, &msg);

        // 用登录者身份时 token 过期没法自动重登（我们不存工人的密码，这正是这套
        // 方案的意义）。给一句工人能照做的话，而不是抛业务码。
        if ((code == kCodeTokenExpired || code == kCodeTokenBad)
            && !sessionToken().isEmpty()) {
            StreamLog::append(QStringLiteral("[腾达云] 登录身份已过期 code=%1").arg(code));
            clearSessionToken();
            done(false, QStringLiteral("腾达云登录已过期 —— 请退出后重新登录"));
            return;
        }

        // token 过期/无效：清掉重登一次再试，只给一次机会，避免打循环
        if ((code == kCodeTokenExpired || code == kCodeTokenBad) && allowRelogin) {
            StreamLog::append(QStringLiteral("[腾达云] token 失效 code=%1，重登后重试")
                                  .arg(code));
            access_token_.clear();
            login([this, productKey, sn, done](bool ok, const QString &error) {
                if (!ok) {
                    done(false, error);
                    return;
                }
                requestP2pToken(productKey, sn, false, done);
            });
            return;
        }
        if (code != 0) {
            done(false, QStringLiteral("腾达云取 xp2p_info 失败 code=%1 %2")
                            .arg(code).arg(msg));
            return;
        }
        const QString value = data.value(QStringLiteral("value")).toString();
        if (value.isEmpty()) {
            done(false, QStringLiteral("腾达云回了空 xp2p_info（设备可能未绑到该账号）"));
            return;
        }
        // 票据本身是敏感值，只报长度和更新时间
        StreamLog::append(QStringLiteral("[腾达云] xp2p_info 已取到，长度 %1，last_update=%2")
                              .arg(value.size())
                              .arg(data.value(QStringLiteral("last_update")).toString()));
        done(true, value);
    });
}
