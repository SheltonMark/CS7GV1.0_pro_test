#include "cloud_client.hpp"

#include <QCoreApplication>
#include <QDateTime>
#include <QFile>
#include <QJsonDocument>
#include <QTime>

#include "crc32.hpp"
#include "mock_transport.hpp"
#include "tencent_api_transport.hpp"

namespace {

// 轮询节奏：产线单工位单设备 + 指令串行，500ms 足够跟上节拍；
// 更快只会白烧云 API 配额（真连时每 poll 一次就是一次计费调用）。
constexpr int kPollIntervalMs = 500;

} // namespace

CloudClient::CloudClient(QObject *parent)
    : QObject(parent)
{
    // RequestId 只需「工位内唯一」（物模型注释）。当日秒数*1e4 起步、会话内
    // 自增：同一台 PC 重启也不会与上一会话撞号（秒数在涨），且恒在 int32 内。
    nextRequestId_ =
        static_cast<int>((QDateTime::currentSecsSinceEpoch() % 86400) * 10000 + 1);

    pollTimer_.setInterval(kPollIntervalMs);
    connect(&pollTimer_, &QTimer::timeout, this, &CloudClient::pollOnce);

    loadConfig();
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

int CloudClient::writeStage(int stage, const QString &timestamp17)
{
    return enqueue(QStringLiteral("PtestWriteStage"),
                   QJsonObject{{QStringLiteral("Stage"), stage},
                               {QStringLiteral("Timestamp"), timestamp17}},
                   10000);
}

int CloudClient::clearPartition(int scope)
{
    return enqueue(QStringLiteral("PtestClearPartition"),
                   QJsonObject{{QStringLiteral("Scope"), scope}}, 15000);
}

int CloudClient::peripheralTest(int item, int operation, int param1, int param2,
                                const QString &text)
{
    // 4G 项（Item=9）内含 SIM 逐槽检测，设备端最长 30s 网络等待——超时放宽
    const int timeoutMs = (item == 9) ? 40000 : 15000;
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
    return enqueue(QStringLiteral("PtestWriteIdentity"), params, 15000);
}

int CloudClient::shutdownDevice(int delaySec)
{
    return enqueue(QStringLiteral("PtestShutdown"),
                   QJsonObject{{QStringLiteral("DelaySec"), delaySec}}, 10000);
}

void CloudClient::invokeGenericAction(const QString &actionId)
{
    if (!transport_) return;
    log(QStringLiteral("→ 下发 %1（通用 action，受理即完成）").arg(actionId));
    transport_->invokeAction(productId_, deviceName_, actionId, QJsonObject(),
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
    return enqueue(QStringLiteral("PtestWriteSuid"),
                   QJsonObject{{QStringLiteral("Suid"), suid}}, 10000);
}

void CloudClient::refreshInfo()
{
    if (!transport_) return;
    log(QStringLiteral("→ 读取设备上报 (DescribeDeviceData)"));
    transport_->readDeviceData(productId_, deviceName_, [this](const CloudReply &reply) {
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
        emit infoUpdated(info.toVariantMap());
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
        if (!inFlight_) return;

        if (reply.ok) {
            // ProductTestInfo 顺带带给界面（同一次轮询的免费搭车，不另发请求）
            const QJsonObject info = reply.data.value(QStringLiteral("ProductTestInfo"))
                                         .toObject().value(QStringLiteral("Value")).toObject();
            if (!info.isEmpty()) emit infoUpdated(info.toVariantMap());

            const QJsonObject result = reply.data.value(QStringLiteral("ProductTestResult"))
                                           .toObject().value(QStringLiteral("Value")).toObject();
            if (!result.isEmpty() &&
                result.value(QStringLiteral("RequestId")).toInt(-1) == current_.requestId) {
                pollTimer_.stop();
                const int command = result.value(QStringLiteral("Command")).toInt(-1);
                const int item = result.value(QStringLiteral("Item")).toInt(-1);
                const int code = result.value(QStringLiteral("Code")).toInt(-1);
                const QString detail = result.value(QStringLiteral("Detail")).toString();
                log(QStringLiteral("← 结果 RequestId=%1 Command=%2 Item=%3 Code=%4 %5")
                        .arg(current_.requestId).arg(command).arg(item).arg(code)
                        .arg(detail));
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

void CloudClient::log(const QString &line)
{
    emit logLine(QTime::currentTime().toString(QStringLiteral("HH:mm:ss.zzz")) +
                 QStringLiteral("  ") + line);
}

QString CloudClient::compact(const QJsonObject &obj)
{
    return QString::fromUtf8(QJsonDocument(obj).toJson(QJsonDocument::Compact));
}
