#include "cloud_client.hpp"

#include <QCoreApplication>
#include <QDateTime>
#include <QFile>
#include <QHash>
#include <QJsonArray>
#include <QJsonDocument>
#include <QTime>

#include "crc32.hpp"
#include "factory_config.hpp"
#include "mock_transport.hpp"
#include "tencent_api_transport.hpp"

namespace {

// 云端盖章时间戳的单位不是契约：腾讯 DescribeDeviceData 见过秒也见过毫秒，
// 猜错一个量级 age 就差出五十多年，恒判离线。两者相差三个数量级，用 1e11
// 一刀切是安全的 —— 该阈值以下的毫秒值早于 1973 年、以上的秒值晚于公元
// 5138 年，产线上都不可能出现。
qint64 NormalizeEpochMs(const qint64 stamp)
{
    if (stamp <= 0) return 0;
    return stamp < 100000000000LL ? stamp * 1000 : stamp;
}

// ProductTestInfo + DeviceInformation + PtestHeartbeat + 阶段4 日志属性
//（PtestLastError/PtestLogTail）合并成给 QML 的一张表。
// 带网口产品(CS7G)调焦走 RTSP 直拉,URL 里的 IP 就取自 DeviceInformation 上报；
// 心跳计数/年龄供调试页与在线诊断直接展示，不必再拆第二条通道。
QVariantMap InfoMapFromData(const QJsonObject &data,
                            const int heartbeatValue,
                            const qint64 heartbeatAgeMs)
{
    QJsonObject info = data.value(QStringLiteral("ProductTestInfo"))
                           .toObject().value(QStringLiteral("Value")).toObject();
    const QJsonObject device = data.value(QStringLiteral("DeviceInformation"))
                                   .toObject().value(QStringLiteral("Value")).toObject();
    if (!device.isEmpty()) {
        info.insert(QStringLiteral("IpAddress"),
                    device.value(QStringLiteral("IpAddress")));
        info.insert(QStringLiteral("SystemVersion"),
                    device.value(QStringLiteral("SystemVersion")));
    }
    // 心跳计数一律取 updateOnline 解析后的值：云侧 Value 形态不稳定（可能套一层
    // 对象、也可能是字符串，见 updateOnline），原样塞进表里 QML 会拿到非数字。
    if (heartbeatValue >= 0)
        info.insert(QStringLiteral("PtestHeartbeat"), heartbeatValue);
    // LastUpdate 保留云端原值、不做单位归一 —— 它是排查"云端发的到底是秒还是
    // 毫秒"的唯一现场证据；在线判定用的是已归一的 PtestHeartbeatAgeMs。
    const QJsonObject heartbeat = data.value(QStringLiteral("PtestHeartbeat")).toObject();
    if (heartbeat.contains(QStringLiteral("LastUpdate")))
        info.insert(QStringLiteral("PtestHeartbeatLastUpdate"),
                    heartbeat.value(QStringLiteral("LastUpdate")));
    if (heartbeatAgeMs >= 0)
        info.insert(QStringLiteral("PtestHeartbeatAgeMs"), heartbeatAgeMs);
    // 阶段4 日志展示（物模型 v3 新增，设备端稍后上报——现在收不到属正常）：
    // PtestLastError = 最近一条非指令类失败摘要（起机 provision/自检这类 PC 没
    // 下发指令时的失败，此前只打设备 stderr，PC 侧完全看不见）；
    // PtestLogTail = 设备 ptest.log 尾部原文。原样塞对象（toVariantMap 会转成
    // QML 可读的嵌套 map），缺键不塞占位——QML 按 undefined 显示"—"。
    const QJsonObject lastError = data.value(QStringLiteral("PtestLastError"))
                                      .toObject().value(QStringLiteral("Value")).toObject();
    if (!lastError.isEmpty())
        info.insert(QStringLiteral("PtestLastError"), lastError);
    const QJsonObject logTail = data.value(QStringLiteral("PtestLogTail"))
                                    .toObject().value(QStringLiteral("Value")).toObject();
    if (!logTail.isEmpty())
        info.insert(QStringLiteral("PtestLogTail"), logTail);
    return info.toVariantMap();
}

} // namespace

CloudClient::CloudClient(QObject *parent)
    : QObject(parent)
{
    // RequestId 只需「工位内唯一」（物模型注释）。当日秒数*1e4 起步、会话内
    // 自增：同一台 PC 重启也不会与上一会话撞号（秒数在涨），且恒在 int32 内。
    nextRequestId_ =
        static_cast<int>((QDateTime::currentSecsSinceEpoch() % 86400) * 10000 + 1);

    // 轮询节奏走工厂配置（默认 500ms）：产线单工位单设备 + 指令串行足够跟上
    // 节拍；更快只会白烧云 API 配额（真连时每 poll 一次就是一次计费调用）。
    pollTimer_.setInterval(FactoryConfig::instance()->pollIntervalMs());
    connect(&pollTimer_, &QTimer::timeout, this, &CloudClient::pollOnce);

    // 空闲心跳读：指令不在途时定期轻读上报，驱动"在线=心跳新鲜"的判定并给
    // 设备信息保鲜（指令在途时 pollTimer 本来就在读，不重复）。周期取心跳
    // 超时的一半——保证离线能在一个超时窗口内被发现。
    idlePollTimer_.setInterval(
        qMax(3000, FactoryConfig::instance()->heartbeatTimeoutSec() * 1000 / 2));
    connect(&idlePollTimer_, &QTimer::timeout, this, [this]() {
        if (inFlight_ || !transport_) return;
        transport_->readDeviceData(productId_, deviceName_,
                                   [this](const CloudReply &reply) {
            updateOnline(reply);
            if (!reply.ok) return;
            const QJsonObject info =
                reply.data.value(QStringLiteral("ProductTestInfo"))
                    .toObject().value(QStringLiteral("Value")).toObject();
            if (!info.isEmpty() || heartbeatValue_ >= 0)
                emit infoUpdated(InfoMapFromData(reply.data, heartbeatValue_,
                                                 heartbeatAgeMs()));
        });
    });
    idlePollTimer_.start();

    loadConfig();
}

qint64 CloudClient::heartbeatAgeMs() const
{
    if (heartbeatLastMs_ <= 0)
        return -1;
    return QDateTime::currentMSecsSinceEpoch() - heartbeatLastMs_;
}

QString CloudClient::mode() const
{
    return transport_ ? transport_->name() : QStringLiteral("none");
}

void CloudClient::setProductId(const QString &value)
{
    if (productId_ == value) return;
    productId_ = value;
    emit deviceChanged();
}

void CloudClient::setDeviceName(const QString &value)
{
    if (deviceName_ == value) return;
    deviceName_ = value;
    emit deviceChanged();
}

void CloudClient::refreshDevices()
{
    if (!transport_ || productId_.isEmpty())
        return;
    if (devicesInFlight_)          // 名单刷新可能被多个工位页同时触发，去重
        return;
    devicesInFlight_ = true;
    emit devicesChanged();

    const QString asked = productId_;   // 记住本次问的是哪个产品
    log(QStringLiteral("→ 读取设备名单 (DescribeDevices) product=%1").arg(asked));
    transport_->describeDevices(asked, [this, asked](const CloudReply &reply) {
        devicesInFlight_ = false;
        // ⚠️ 期间可能已经切了产品（工人换批次），迟到的应答必须丢掉，
        //    否则名单会是上一个产品的 —— 这就是"按产品过滤"的实现要点：
        //    过滤不是在结果里挑，而是**只认当前 productId 的那次应答**。
        if (asked != productId_) {
            log(QStringLiteral("← 名单应答已过期（产品已切到 %1），丢弃").arg(productId_));
            emit devicesChanged();
            return;
        }
        if (!reply.ok) {
            log(QStringLiteral("✗ 读名单失败: ") + reply.error);
            emit devicesChanged();
            return;
        }

        // 按 deviceName 升序编卡号：卡号要稳定，云端返回顺序不保证。
        QStringList names;
        QHash<QString, bool> onlineOf;
        const QJsonArray arr = reply.data.value(QStringLiteral("devices")).toArray();
        for (const QJsonValue &v : arr) {
            const QJsonObject d = v.toObject();
            const QString n = d.value(QStringLiteral("deviceName")).toString();
            if (n.isEmpty())
                continue;
            names.append(n);
            onlineOf.insert(n, d.value(QStringLiteral("online")).toBool());
        }
        names.sort();

        QVariantList out;
        int card = 1;
        int onlineCount = 0;
        for (const QString &n : names) {
            const bool on = onlineOf.value(n);
            if (on)
                ++onlineCount;
            out.append(QVariantMap{
                {QStringLiteral("card"), card++},
                {QStringLiteral("deviceName"), n},
                {QStringLiteral("online"), on},
            });
        }
        devices_ = out;
        log(QStringLiteral("← 名单 %1 台，在线 %2 台").arg(names.size()).arg(onlineCount));
        emit devicesChanged();
    });
}

int CloudClient::writeStage(int stage, const QString &timestamp17)
{
    // 写阶段落 flash（整块擦写百毫秒级 + 设备单槽 worker），按 flash 类超时
    return enqueue(QStringLiteral("PtestWriteStage"),
                   QJsonObject{{QStringLiteral("Stage"), stage},
                               {QStringLiteral("Timestamp"), timestamp17}},
                   FactoryConfig::instance()->timeoutFlashMs());
}

int CloudClient::clearPartition(int scope)
{
    return enqueue(QStringLiteral("PtestClearPartition"),
                   QJsonObject{{QStringLiteral("Scope"), scope}},
                   FactoryConfig::instance()->timeoutFlashMs());
}

int CloudClient::peripheralTest(int item, int operation, int param1, int param2,
                                const QString &text)
{
    // 4G 项（Item=9）内含 SIM 逐槽检测，设备端最长 30s 网络等待——超时单列
    const int timeoutMs = (item == 9) ? FactoryConfig::instance()->timeoutCellularMs()
                                      : FactoryConfig::instance()->timeoutPeripheralMs();
    return enqueue(QStringLiteral("PtestPeripheralTest"),
                   QJsonObject{{QStringLiteral("Item"), item},
                               {QStringLiteral("Operation"), operation},
                               {QStringLiteral("Param1"), param1},
                               {QStringLiteral("Param2"), param2},
                               {QStringLiteral("Text"), text}},
                   timeoutMs);
}

int CloudClient::writeIdentity(const QVariantMap &fields)
{
    static const char *kKeys[] = {"Sn", "Mac", "ProductKey", "DeviceName",
                                  "DeviceSecret", "ProductSecret", "Uuid", "Language"};
    QJsonObject params;
    for (const char *key : kKeys) {
        QString value = fields.value(QLatin1String(key)).toString();
        if (value.isEmpty()) continue;
        // 物模型硬要求：两个 Secret 必须 base64url 编码下发（调用方传明文）
        if (qstrcmp(key, "DeviceSecret") == 0 || qstrcmp(key, "ProductSecret") == 0)
            value = b64Url(value);
        params.insert(QLatin1String(key), value);
    }
    return enqueue(QStringLiteral("PtestWriteIdentity"), params,
                   FactoryConfig::instance()->timeoutFlashMs());
}

int CloudClient::shutdownDevice(int delaySec)
{
    return enqueue(QStringLiteral("PtestShutdown"),
                   QJsonObject{{QStringLiteral("DelaySec"), delaySec}},
                   FactoryConfig::instance()->timeoutNormalMs());
}

void CloudClient::invokeGenericAction(const QString &actionId, const QVariantMap &params)
{
    if (!transport_) return;
    const QJsonObject json = QJsonObject::fromVariantMap(params);
    log(QStringLiteral("→ 下发 %1 %2（通用 action，受理即完成）")
            .arg(actionId, compact(json)));
    transport_->invokeAction(productId_, deviceName_, actionId, json,
                             [this, actionId](const CloudReply &reply) {
        if (reply.ok)
            log(QStringLiteral("✓ %1 云端已受理").arg(actionId));
        else
            log(QStringLiteral("✗ %1 失败: %2").arg(actionId, reply.error));
        emit genericActionDone(actionId, reply.ok, reply.error);
    });
}

QString CloudClient::crc32Hex(const QString &text) const
{
    return PtestCrc32Hex(text);
}

QString CloudClient::b64Url(const QString &text) const
{
    return QString::fromUtf8(text.toUtf8().toBase64(
        QByteArray::Base64UrlEncoding | QByteArray::OmitTrailingEquals));
}

int CloudClient::writeSuid(const QString &suid)
{
    // SUID 落加密分区（整块擦写），与 writeStage/writeIdentity 同一类超时
    return enqueue(QStringLiteral("PtestWriteSuid"),
                   QJsonObject{{QStringLiteral("Suid"), suid}},
                   FactoryConfig::instance()->timeoutFlashMs());
}

void CloudClient::refreshInfo()
{
    if (!transport_) return;
    log(QStringLiteral("→ 读取设备上报 (DescribeDeviceData)"));
    transport_->readDeviceData(productId_, deviceName_, [this](const CloudReply &reply) {
        updateOnline(reply);
        if (!reply.ok) {
            log(QStringLiteral("✗ 读上报失败: ") + reply.error);
            return;
        }
        const QJsonObject info = reply.data.value(QStringLiteral("ProductTestInfo"))
                                     .toObject().value(QStringLiteral("Value")).toObject();
        const QJsonObject result = reply.data.value(QStringLiteral("ProductTestResult"))
                                       .toObject().value(QStringLiteral("Value")).toObject();
        log(QStringLiteral("← ProductTestInfo ") + compact(info));
        if (!result.isEmpty())
            log(QStringLiteral("← ProductTestResult ") + compact(result));
        if (heartbeatValue_ >= 0)
            log(QStringLiteral("← PtestHeartbeat value=%1 ageMs=%2")
                    .arg(heartbeatValue_).arg(heartbeatAgeMs()));
        emit infoUpdated(InfoMapFromData(reply.data, heartbeatValue_, heartbeatAgeMs()));
    });
}

void CloudClient::reloadConfig()
{
    if (inFlight_) {
        pollTimer_.stop();
        inFlight_ = false;
        queue_.clear();
        emit busyChanged();
        log(QStringLiteral("重载配置：已中止在途指令与队列"));
    }
    loadConfig();
}

int CloudClient::enqueue(const QString &actionId, QJsonObject params, int timeoutMs)
{
    const int requestId = nextRequestId_++;
    params.insert(QStringLiteral("RequestId"), requestId);
    queue_.append(PendingCommand{requestId, actionId, params, timeoutMs});
    pump();
    return requestId;
}

void CloudClient::pump()
{
    if (inFlight_ || queue_.isEmpty() || !transport_) return;

    current_ = queue_.takeFirst();
    inFlight_ = true;
    emit busyChanged();
    deadlineMs_ = QDateTime::currentMSecsSinceEpoch() + current_.timeoutMs;
    log(QStringLiteral("→ 下发 %1 %2").arg(current_.actionId, compact(current_.params)));

    transport_->invokeAction(
        productId_, deviceName_, current_.actionId, current_.params,
        [this](const CloudReply &reply) {
            if (!inFlight_) return;  // reloadConfig 已中止
            if (!reply.ok) {
                log(QStringLiteral("✗ 下发失败: ") + reply.error);
                const int id = current_.requestId;
                const QString error = reply.error;
                inFlight_ = false;
                emit busyChanged();
                emit commandFailed(id, error);
                pump();
                return;
            }
            log(QStringLiteral("✓ 云端已受理，等待设备上报…"));
            pollTimer_.start();
            pollOnce();
        });
}

void CloudClient::pollOnce()
{
    if (!inFlight_ || !transport_) {
        pollTimer_.stop();
        return;
    }
    transport_->readDeviceData(productId_, deviceName_, [this](const CloudReply &reply) {
        updateOnline(reply);
        if (!inFlight_) return;

        if (reply.ok) {
            // ProductTestInfo/心跳顺带带给界面（同一次轮询的免费搭车）
            const QJsonObject info = reply.data.value(QStringLiteral("ProductTestInfo"))
                                         .toObject().value(QStringLiteral("Value")).toObject();
            if (!info.isEmpty() || heartbeatValue_ >= 0)
                emit infoUpdated(InfoMapFromData(reply.data, heartbeatValue_,
                                                 heartbeatAgeMs()));

            const QJsonObject result = reply.data.value(QStringLiteral("ProductTestResult"))
                                           .toObject().value(QStringLiteral("Value")).toObject();
            if (!result.isEmpty() &&
                result.value(QStringLiteral("RequestId")).toInt(-1) == current_.requestId) {
                pollTimer_.stop();
                const int command = result.value(QStringLiteral("Command")).toInt(-1);
                const int item = result.value(QStringLiteral("Item")).toInt(-1);
                const int code = result.value(QStringLiteral("Code")).toInt(-1);
                const QString detail = result.value(QStringLiteral("Detail")).toString();
                // Command=5 是 PtestShutdown：设备端契约=受理即回报成功，
                // 真断电在 DelaySec 之后，PC 以下发成功为完成。
                const QString cmdName =
                    command == 0 ? QStringLiteral("WriteStage")
                    : command == 1 ? QStringLiteral("ClearPartition")
                    : command == 2 ? QStringLiteral("PeripheralTest")
                    : command == 3 ? QStringLiteral("WriteIdentity")
                    : command == 4 ? QStringLiteral("WriteSuid")
                    : command == 5 ? QStringLiteral("Shutdown")
                    : QStringLiteral("?");
                log(QStringLiteral("← 结果 RequestId=%1 Command=%2(%3) Item=%4 Code=%5 %6")
                        .arg(current_.requestId).arg(command).arg(cmdName)
                        .arg(item).arg(code).arg(detail));
                const int id = current_.requestId;
                inFlight_ = false;
                emit busyChanged();
                emit commandFinished(id, command, item, code, detail);
                pump();
                return;
            }
        } else {
            // 单次轮询失败不判死刑（网络抖动/信令毛刺），限期内继续重试
            log(QStringLiteral("… 轮询失败(继续): ") + reply.error);
        }

        if (QDateTime::currentMSecsSinceEpoch() > deadlineMs_) {
            pollTimer_.stop();
            log(QStringLiteral("⏱ 超时: RequestId=%1 未等到设备上报").arg(current_.requestId));
            const int id = current_.requestId;
            inFlight_ = false;
            emit busyChanged();
            emit commandTimeout(id);
            pump();
        }
    });
}

void CloudClient::loadConfig()
{
    const QString path =
        QCoreApplication::applicationDirPath() + QStringLiteral("/cloud_config.json");
    QJsonObject cfg;
    QFile file(path);
    if (file.open(QIODevice::ReadOnly))
        cfg = QJsonDocument::fromJson(file.readAll()).object();

    productId_ = cfg.value(QStringLiteral("productId"))
                     .toString(QStringLiteral("5KHBENFCX2"));
    deviceName_ = cfg.value(QStringLiteral("deviceName"))
                      .toString(QStringLiteral("1000000003"));

    const QString secretId = cfg.value(QStringLiteral("secretId")).toString();
    const QString secretKey = cfg.value(QStringLiteral("secretKey")).toString();
    if (!secretId.isEmpty() && !secretKey.isEmpty()) {
        TencentApiConfig api;
        api.secretId = secretId;
        api.secretKey = secretKey;
        api.region = cfg.value(QStringLiteral("region"))
                         .toString(QStringLiteral("ap-guangzhou"));
        transport_ = std::make_unique<TencentApiTransport>(api);
        // 纪律：日志只报模式与 region，绝不落密钥
        log(QStringLiteral("传输 = 腾讯云直连 (region=%1, 配置=%2)").arg(api.region, path));
    } else {
        transport_ = std::make_unique<MockTransport>();
        log(QStringLiteral("传输 = Mock 假设备（%1 缺失或密钥为空）").arg(path));
    }
    emit modeChanged();
    emit deviceChanged();
}

// 在线判定（2026-08-17 需求）：腾讯云自身的在线状态有延迟，以设备心跳包为准
// —— 设备产测态周期上报 PtestHeartbeat，其 LastUpdate 距今在超时窗口内 = 在线。
// 固件尚未加心跳（或旧物模型）时退化为"本次读取成功即在线"。
// 云端时间戳的单位与有无都不可靠，故新鲜度另留一条兜底证据（计数器自增），
// 两条都走同一个 heartbeatLastMs_，判定口径只有"距今是否在窗口内"这一个。
void CloudClient::updateOnline(const CloudReply &reply)
{
    if (!reply.ok) {
        setOnline(false);
        return;
    }
    const QJsonObject heartbeat =
        reply.data.value(QStringLiteral("PtestHeartbeat")).toObject();
    if (heartbeat.isEmpty()) {
        setOnline(true);
        return;
    }

    // 心跳计数：优先 Value；兼容云侧偶尔把整型直接放在根上的形态
    int value = heartbeatValue_;
    if (heartbeat.contains(QStringLiteral("Value"))) {
        const QJsonValue v = heartbeat.value(QStringLiteral("Value"));
        // DescribeDeviceData 有时把 int 属性包成 {"Value": n}，有时 Value 本身又是对象
        if (v.isDouble())
            value = v.toInt();
        else if (v.isObject() && v.toObject().contains(QStringLiteral("Value")))
            value = v.toObject().value(QStringLiteral("Value")).toInt(value);
        else if (v.isString())
            value = v.toString().toInt();
    }
    const qint64 lastMs = NormalizeEpochMs(
        static_cast<qint64>(heartbeat.value(QStringLiteral("LastUpdate")).toDouble()));
    const bool valueChanged = (value != heartbeatValue_);
    const bool stampChanged = (lastMs > 0 && lastMs != heartbeatLastMs_);
    if (valueChanged)
        heartbeatValue_ = value;

    // 新鲜度有两条独立证据，任一成立就把时间戳推到当下：
    //   ① 云端盖章的 LastUpdate —— 首选，真机口径
    //   ② 计数器变化 —— 固件 5s 自增一拍，值一动就说明来了新上报
    // 少了 ②，云端不给 LastUpdate 时首读之后 heartbeatLastMs_ 再也不会更新，
    // 一个超时窗口后恒判离线 —— 设备明明在正常心跳。计数器回退（设备重启从
    // 0 重数）同样算证据，所以判"变化"而不是"变大"。
    if (stampChanged)
        heartbeatLastMs_ = lastMs;
    else if (valueChanged || heartbeatLastMs_ <= 0)
        heartbeatLastMs_ = QDateTime::currentMSecsSinceEpoch();
    if (valueChanged || stampChanged)
        emit heartbeatChanged();

    const qint64 windowMs =
        qint64(FactoryConfig::instance()->heartbeatTimeoutSec()) * 1000;
    const qint64 age = heartbeatAgeMs();
    setOnline(age >= 0 && age <= windowMs);
}

void CloudClient::setOnline(bool value)
{
    if (online_ == value) return;
    online_ = value;
    emit onlineChanged();
}

void CloudClient::log(const QString &line)
{
    emit logLine(QTime::currentTime().toString(QStringLiteral("HH:mm:ss.zzz")) +
                 QStringLiteral("  ") + line);
}

QString CloudClient::compact(const QJsonObject &obj)
{
    return QString::fromUtf8(QJsonDocument(obj).toJson(QJsonDocument::Compact));
}
